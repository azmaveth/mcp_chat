defmodule MCPChat.Security.KeyManagerTest do
  @moduledoc """
  Unit tests for the KeyManager module.
  """

  use ExUnit.Case, async: true

  alias MCPChat.Security.KeyManager

  setup do
    # Start fresh KeyManager for each test
    start_supervised!(KeyManager)

    {:ok, %{}}
  end

  describe "get_signing_key/0" do
    test "returns current signing key and kid" do
      {:ok, private_key, kid} = KeyManager.get_signing_key()

      # Verify it's an RSA private key
      assert is_tuple(private_key)
      assert elem(private_key, 0) == :RSAPrivateKey

      # Verify kid format
      assert is_binary(kid)
      assert byte_size(kid) > 0
    end

    test "returns same key on multiple calls" do
      {:ok, key1, kid1} = KeyManager.get_signing_key()
      {:ok, key2, kid2} = KeyManager.get_signing_key()

      assert key1 == key2
      assert kid1 == kid2
    end
  end

  describe "get_verification_keys/0" do
    test "returns map of public keys" do
      {:ok, keys} = KeyManager.get_verification_keys()

      assert is_map(keys)
      assert map_size(keys) >= 1

      # Verify each key
      Enum.each(keys, fn {kid, public_key} ->
        assert is_binary(kid)
        assert is_tuple(public_key)
        assert elem(public_key, 0) == :RSAPublicKey
      end)
    end

    test "includes current signing key's public key" do
      {:ok, _private_key, current_kid} = KeyManager.get_signing_key()
      {:ok, verification_keys} = KeyManager.get_verification_keys()

      assert Map.has_key?(verification_keys, current_kid)
    end
  end

  describe "get_public_key/1" do
    test "returns specific public key by kid" do
      {:ok, _private_key, kid} = KeyManager.get_signing_key()

      {:ok, public_key} = KeyManager.get_public_key(kid)
      assert is_tuple(public_key)
      assert elem(public_key, 0) == :RSAPublicKey
    end

    test "returns error for non-existent kid" do
      assert {:error, :key_not_found} = KeyManager.get_public_key("non_existent_kid")
    end
  end

  describe "rotate_keys/0" do
    test "generates new signing key" do
      # Get original key
      {:ok, _key1, kid1} = KeyManager.get_signing_key()

      # Rotate
      :ok = KeyManager.rotate_keys()

      # Get new key
      {:ok, _key2, kid2} = KeyManager.get_signing_key()

      # Should have different kid
      assert kid1 != kid2
    end

    test "keeps previous key for verification" do
      # Get original key
      {:ok, _key1, kid1} = KeyManager.get_signing_key()

      # Rotate
      :ok = KeyManager.rotate_keys()

      # Both keys should be available for verification
      {:ok, verification_keys} = KeyManager.get_verification_keys()
      assert Map.has_key?(verification_keys, kid1)

      # Old key should still be retrievable
      assert {:ok, _} = KeyManager.get_public_key(kid1)
    end

    test "maintains maximum of 2 keys during rotation" do
      # Initial state - 1 key
      {:ok, keys1} = KeyManager.get_verification_keys()
      assert map_size(keys1) == 1

      # First rotation - 2 keys
      :ok = KeyManager.rotate_keys()
      {:ok, keys2} = KeyManager.get_verification_keys()
      assert map_size(keys2) == 2

      # Second rotation - still 2 keys (oldest removed)
      :ok = KeyManager.rotate_keys()
      # Allow cleanup
      Process.sleep(100)

      {:ok, keys3} = KeyManager.get_verification_keys()
      assert map_size(keys3) == 2
    end
  end

  describe "export_jwks/0" do
    test "exports keys in JWK format" do
      jwks = KeyManager.export_jwks()

      assert is_map(jwks)
      assert Map.has_key?(jwks, "keys")
      assert is_list(jwks["keys"])
      assert length(jwks["keys"]) >= 1

      # Verify JWK structure
      Enum.each(jwks["keys"], fn jwk ->
        assert jwk["kty"] == "RSA"
        assert jwk["use"] == "sig"
        assert jwk["alg"] == "RS256"
        assert is_binary(jwk["kid"])
        # Modulus
        assert is_binary(jwk["n"])
        # Exponent
        assert is_binary(jwk["e"])
      end)
    end

    test "JWK values are properly encoded" do
      jwks = KeyManager.export_jwks()

      Enum.each(jwks["keys"], fn jwk ->
        # Should be valid base64url without padding
        assert {:ok, _} = Base.url_decode64(jwk["n"], padding: false)
        assert {:ok, _} = Base.url_decode64(jwk["e"], padding: false)
      end)
    end
  end

  describe "automatic rotation" do
    # Skip in regular test runs due to long duration
    @tag :skip
    test "rotates keys automatically after interval" do
      # This test would wait for automatic rotation
      # In practice, we test manual rotation above
    end
  end

  describe "key generation" do
    test "generates keys with correct size" do
      {:ok, private_key, _kid} = KeyManager.get_signing_key()

      # Extract key components
      {:RSAPrivateKey, _version, modulus, _pub_exp, _priv_exp, _prime1, _prime2, _exp1, _exp2, _coeff, _other} =
        private_key

      # Check key size (2048 bits = 256 bytes)
      key_size_bits = byte_size(:binary.encode_unsigned(modulus)) * 8
      assert key_size_bits >= 2048
      # Allow small variance
      assert key_size_bits <= 2048 + 8
    end

    test "generates unique kids" do
      # Collect multiple kids
      kids =
        for _ <- 1..10 do
          :ok = KeyManager.rotate_keys()
          {:ok, _, kid} = KeyManager.get_signing_key()
          kid
        end

      # All should be unique
      assert length(Enum.uniq(kids)) == length(kids)
    end
  end

  describe "concurrent access" do
    test "handles concurrent key requests" do
      # Spawn multiple concurrent requests
      tasks =
        for _ <- 1..50 do
          Task.async(fn ->
            KeyManager.get_signing_key()
          end)
        end

      results = Task.await_many(tasks)

      # All should succeed
      assert Enum.all?(results, fn result ->
               match?({:ok, _, _}, result)
             end)

      # All should get the same key
      kids = Enum.map(results, fn {:ok, _, kid} -> kid end)
      assert length(Enum.uniq(kids)) == 1
    end

    test "handles rotation during concurrent access" do
      # Start concurrent readers
      reader_tasks =
        for _ <- 1..20 do
          Task.async(fn ->
            for _ <- 1..10 do
              KeyManager.get_verification_keys()
              Process.sleep(10)
            end
          end)
        end

      # Rotate keys while readers are active
      for _ <- 1..3 do
        Process.sleep(50)
        KeyManager.rotate_keys()
      end

      # All readers should complete successfully
      results = Task.await_many(reader_tasks, 5000)
      assert Enum.all?(results, &(&1 == :ok))
    end
  end
end
