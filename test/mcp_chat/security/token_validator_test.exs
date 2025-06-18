defmodule MCPChat.Security.TokenValidatorTest do
  @moduledoc """
  Unit tests for the TokenValidator module.
  """

  use ExUnit.Case, async: true

  alias MCPChat.Security.{TokenValidator, TokenIssuer, KeyManager, RevocationCache}

  setup do
    # Start required services
    start_supervised!(KeyManager)
    start_supervised!(TokenIssuer)
    start_supervised!(RevocationCache)
    start_supervised!(TokenValidator.Cache)

    {:ok, %{}}
  end

  describe "validate_token/3" do
    test "validates correctly signed tokens" do
      # Issue a valid token
      {:ok, token, _jti} =
        TokenIssuer.issue_token(
          :filesystem,
          [:read, :write],
          "/tmp/**",
          "test_agent",
          %{}
        )

      # Validate for allowed operation and resource
      assert {:ok, _claims} = TokenValidator.validate_token(token, :read, "/tmp/file.txt")
      assert {:ok, _claims} = TokenValidator.validate_token(token, :write, "/tmp/data/log.txt")
    end

    test "rejects tokens with invalid signatures" do
      # Create a token with tampered signature
      {:ok, valid_token, _} = TokenIssuer.issue_token(:filesystem, [:read], "/tmp", "agent", %{})

      # Tamper with the signature
      [header, payload, _sig] = String.split(valid_token, ".")
      tampered_token = "#{header}.#{payload}.invalid_signature"

      assert {:error, :invalid_signature} = TokenValidator.validate_token(tampered_token, :read, "/tmp")
    end

    test "rejects expired tokens" do
      # Create a token that's already expired
      now = System.system_time(:second)

      expired_claims = %{
        "iss" => "mcp_chat_security",
        "sub" => "test_agent",
        "aud" => "filesystem",
        # Expired 1 hour ago
        "exp" => now - 3600,
        "iat" => now - 7200,
        "jti" => "expired_token",
        "resource" => "/tmp",
        "operations" => [:read]
      }

      # Create a token with expired claims (this is a test hack)
      {:ok, signer} = get_test_signer()
      {:ok, expired_token} = Joken.generate_and_sign(%{}, expired_claims, signer)

      assert {:error, :token_expired} = TokenValidator.validate_token(expired_token, :read, "/tmp")
    end

    test "validates operation permissions correctly" do
      {:ok, token, _} =
        TokenIssuer.issue_token(
          :mcp_tool,
          # Only execute permission
          [:execute],
          "github",
          "agent",
          %{}
        )

      # Allowed operation
      assert {:ok, _} = TokenValidator.validate_token(token, :execute, "github")

      # Disallowed operations
      assert {:error, {:operation_not_permitted, :read}} =
               TokenValidator.validate_token(token, :read, "github")

      assert {:error, {:operation_not_permitted, :write}} =
               TokenValidator.validate_token(token, :write, "github")
    end

    test "validates resource patterns with wildcards" do
      {:ok, token, _} =
        TokenIssuer.issue_token(
          :filesystem,
          [:read],
          "/home/*/documents/**",
          "agent",
          %{}
        )

      # Matching patterns
      assert {:ok, _} = TokenValidator.validate_token(token, :read, "/home/alice/documents/file.txt")
      assert {:ok, _} = TokenValidator.validate_token(token, :read, "/home/bob/documents/work/report.pdf")

      # Non-matching patterns
      assert {:error, {:resource_not_permitted, _}} =
               TokenValidator.validate_token(token, :read, "/home/documents/file.txt")

      assert {:error, {:resource_not_permitted, _}} =
               TokenValidator.validate_token(token, :read, "/etc/passwd")
    end

    test "checks revocation status" do
      {:ok, token, jti} =
        TokenIssuer.issue_token(
          :network,
          [:read],
          "https://api.example.com/**",
          "agent",
          %{}
        )

      # Should work before revocation
      assert {:ok, _} = TokenValidator.validate_token(token, :read, "https://api.example.com/users")

      # Revoke the token
      RevocationCache.revoke(jti)
      # Allow cache update
      Process.sleep(50)

      # Should fail after revocation
      assert {:error, :token_revoked} =
               TokenValidator.validate_token(token, :read, "https://api.example.com/users")
    end
  end

  describe "validate_token_structure/1" do
    test "validates token structure without permission checks" do
      {:ok, token, _} =
        TokenIssuer.issue_token(
          :database,
          [:read],
          "users_db",
          "agent",
          %{}
        )

      # Should validate structure
      assert {:ok, claims} = TokenValidator.validate_token_structure(token)
      assert claims["sub"] == "agent"
      assert claims["resource"] == "users_db"
    end

    test "still checks expiration and revocation" do
      {:ok, token, jti} =
        TokenIssuer.issue_token(
          :process,
          [:execute],
          "worker_*",
          "agent",
          %{}
        )

      # Revoke it
      RevocationCache.revoke(jti)
      Process.sleep(50)

      # Structure validation should fail due to revocation
      assert {:error, :token_revoked} = TokenValidator.validate_token_structure(token)
    end
  end

  describe "constraint validation" do
    test "validates file extension constraints" do
      {:ok, token, _} =
        TokenIssuer.issue_token(
          :filesystem,
          [:read, :write],
          "/project/**",
          "agent",
          %{"allowed_extensions" => [".ex", ".exs", ".md"]}
        )

      # Allowed extensions
      assert {:ok, _} = TokenValidator.validate_token(token, :read, "/project/lib/app.ex")
      assert {:ok, _} = TokenValidator.validate_token(token, :write, "/project/README.md")

      # Disallowed extension
      assert {:error, {:extension_not_allowed, ".sh"}} =
               TokenValidator.validate_token(token, :write, "/project/scripts/deploy.sh")
    end

    test "validates time window constraints" do
      now = System.system_time(:second)

      {:ok, token, _} =
        TokenIssuer.issue_token(
          :network,
          [:read],
          "https://api.example.com/**",
          "agent",
          %{
            "time_window" => %{
              # Started 1 hour ago
              "start" => now - 3600,
              # Ends in 1 hour
              "end" => now + 3600
            }
          }
        )

      # Should work within time window
      assert {:ok, _} = TokenValidator.validate_token(token, :read, "https://api.example.com/data")
    end
  end

  describe "peek_claims/1" do
    test "extracts claims without validation" do
      {:ok, token, _} =
        TokenIssuer.issue_token(
          :filesystem,
          [:read],
          "/tmp",
          "agent",
          %{custom_field: "test_value"}
        )

      # Peek without validation
      assert {:ok, claims} = TokenValidator.peek_claims(token)
      assert claims["sub"] == "agent"
      assert claims["resource"] == "/tmp"
      assert claims["constraints"]["custom_field"] == "test_value"
    end

    test "handles malformed tokens" do
      assert {:error, :invalid_token_format} = TokenValidator.peek_claims("not.a.token")
      assert {:error, :invalid_token_format} = TokenValidator.peek_claims("malformed")
    end
  end

  describe "is_expired?/1" do
    test "checks expiration without full validation" do
      # Create expired token
      now = System.system_time(:second)

      expired_claims = %{
        "exp" => now - 3600,
        "iat" => now - 7200
      }

      {:ok, signer} = get_test_signer()
      {:ok, expired_token} = Joken.generate_and_sign(%{}, expired_claims, signer)

      assert TokenValidator.is_expired?(expired_token) == true

      # Valid token
      {:ok, valid_token, _} = TokenIssuer.issue_token(:filesystem, [:read], "/tmp", "agent", %{})
      assert TokenValidator.is_expired?(valid_token) == false
    end
  end

  describe "validate_delegation_chain/1" do
    test "validates delegation depth" do
      # Create parent token
      {:ok, parent_token, _} =
        TokenIssuer.issue_token(
          :filesystem,
          [:read],
          "/tmp",
          "parent",
          %{max_delegation_depth: 3}
        )

      # Create child token
      {:ok, child_token, _} =
        TokenIssuer.issue_delegated_token(
          parent_token,
          "child",
          %{}
        )

      # Validate delegation chain
      assert {:ok, delegation_info} = TokenValidator.validate_delegation_chain(child_token)
      assert delegation_info.depth == 1
      assert delegation_info.max_depth == 3
      assert delegation_info.parent_id != nil
    end
  end

  describe "caching behavior" do
    test "caches validation results for performance" do
      {:ok, token, _} =
        TokenIssuer.issue_token(
          :filesystem,
          [:read],
          "/tmp/**",
          "agent",
          %{}
        )

      # First validation (cache miss)
      {time1, {:ok, _}} =
        :timer.tc(fn ->
          TokenValidator.validate_token(token, :read, "/tmp/file.txt")
        end)

      # Second validation (should be cached)
      {time2, {:ok, _}} =
        :timer.tc(fn ->
          TokenValidator.validate_token(token, :read, "/tmp/file.txt")
        end)

      # Cached validation should be significantly faster
      # (at least 10x faster, accounting for variance)
      assert time2 < time1 / 10
    end
  end

  # Helper functions

  defp get_test_signer do
    {:ok, private_key, _kid} = KeyManager.get_signing_key()
    pem_entry = :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
    pem = :public_key.pem_encode([pem_entry])
    {:ok, Joken.Signer.create("RS256", %{"pem" => pem})}
  end
end
