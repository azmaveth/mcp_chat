defmodule MCPChat.Phase2SecurityTest do
  @moduledoc """
  Integration tests for Phase 2 token-based security features.
  Tests JWT token generation, validation, delegation, and revocation.
  """

  use ExUnit.Case, async: false

  alias MCPChat.Security
  alias MCPChat.Security.{TokenIssuer, TokenValidator, RevocationCache, KeyManager}

  setup do
    # Enable token mode for these tests
    original_mode = Security.use_token_mode?()
    Security.set_token_mode(true)

    # Services should already be started by the application
    # Just verify they're running
    assert Process.whereis(KeyManager) != nil
    assert Process.whereis(TokenIssuer) != nil
    assert Process.whereis(RevocationCache) != nil

    on_exit(fn ->
      Security.set_token_mode(original_mode)
    end)

    {:ok, %{}}
  end

  describe "Token-based capability lifecycle" do
    test "can request, validate, and revoke token-based capabilities" do
      principal_id = "test_agent_#{System.unique_integer()}"

      # Request capability with token mode
      {:ok, capability} =
        Security.request_capability(
          :filesystem,
          %{
            operations: [:read, :write],
            resource: "/tmp/test/**",
            paths: ["/tmp/test"],
            max_file_size: 1_048_576
          },
          principal_id
        )

      # Verify it's a token-based capability
      assert Map.get(capability, :is_token) == true
      assert is_binary(capability.token)
      assert String.starts_with?(capability.id, "cap_")

      # Validate for allowed operation
      assert :ok == Security.validate_capability(capability, :read, "/tmp/test/file.txt")
      assert :ok == Security.validate_capability(capability, :write, "/tmp/test/data.log")

      # Validate fails for disallowed path
      assert {:error, _} = Security.validate_capability(capability, :read, "/etc/passwd")

      # Validate fails for disallowed operation
      assert {:error, _} = Security.validate_capability(capability, :delete, "/tmp/test/file.txt")

      # Revoke the capability
      assert :ok == Security.revoke_capability(capability)

      # Validation should fail after revocation
      # Allow revocation to propagate
      Process.sleep(100)
      assert {:error, :token_revoked} = Security.validate_capability(capability, :read, "/tmp/test/file.txt")
    end

    test "token validation is performed locally without SecurityKernel" do
      # Monitor SecurityKernel to ensure it's not called
      kernel_pid = Process.whereis(MCPChat.Security.SecurityKernel)
      assert kernel_pid != nil

      # Trace calls to SecurityKernel
      :erlang.trace(kernel_pid, true, [:call])
      :erlang.trace_pattern({MCPChat.Security.SecurityKernel, :_, :_}, true, [])

      # Request token-based capability
      {:ok, capability} =
        Security.request_capability(
          :mcp_tool,
          %{
            operations: [:execute],
            resource: "github",
            allowed_tools: ["list_repos", "get_repo"]
          },
          "test_principal"
        )

      # Clear trace messages from capability creation
      flush_trace_messages()

      # Validate capability (should be local)
      assert :ok == Security.validate_capability(capability, :execute, "github")

      # Check that SecurityKernel was NOT called for validation
      refute_receive {:trace, ^kernel_pid, :call, {MCPChat.Security.SecurityKernel, :validate_capability, _}}

      # Stop tracing
      :erlang.trace(kernel_pid, false, [:call])
    end
  end

  describe "Token delegation" do
    test "can delegate token-based capabilities with constraint inheritance" do
      # Create parent capability
      {:ok, parent_cap} =
        Security.request_capability(
          :filesystem,
          %{
            operations: [:read, :write, :execute],
            resource: "/project/**",
            paths: ["/project"],
            max_delegation_depth: 3
          },
          "parent_agent"
        )

      # Delegate with more restrictive constraints
      {:ok, child_cap} =
        Security.delegate_capability(
          parent_cap,
          "child_agent",
          %{
            # Only read, not write/execute
            operations: [:read],
            # More specific path
            paths: ["/project/src"]
          }
        )

      assert child_cap.is_token == true
      assert child_cap.parent_id == parent_cap.id

      # Child can read in allowed path
      assert :ok == Security.validate_capability(child_cap, :read, "/project/src/main.ex")

      # Child cannot write (constraint inherited)
      assert {:error, _} = Security.validate_capability(child_cap, :write, "/project/src/main.ex")

      # Child cannot access parent-only paths
      assert {:error, _} = Security.validate_capability(child_cap, :read, "/project/secrets/key.pem")
    end

    test "delegation depth is enforced" do
      # Create capability with limited delegation depth
      {:ok, cap1} =
        Security.request_capability(
          :network,
          %{
            operations: [:read],
            resource: "https://api.example.com/**",
            max_delegation_depth: 2
          },
          "agent_1"
        )

      # First delegation should work
      {:ok, cap2} = Security.delegate_capability(cap1, "agent_2", %{})

      # Second delegation should work (depth = 2)
      {:ok, cap3} = Security.delegate_capability(cap2, "agent_3", %{})

      # Third delegation should fail (would exceed max depth)
      assert {:error, :delegation_depth_exceeded} = Security.delegate_capability(cap3, "agent_4", %{})
    end
  end

  describe "Token expiration and TTL" do
    test "temporary capabilities expire correctly" do
      # Request capability with 2 second TTL
      {:ok, capability} =
        Security.request_temporary_capability(
          :database,
          %{
            operations: [:read],
            resource: "users_db"
          },
          # 2 seconds
          2,
          "temp_agent"
        )

      # Should work immediately
      assert :ok == Security.validate_capability(capability, :read, "users_db")

      # Wait for expiration (3 seconds to ensure we're well past the 2 second TTL)
      Process.sleep(3000)

      # Should fail after expiration
      assert {:error, :token_expired} = Security.validate_capability(capability, :read, "users_db")
    end
  end

  describe "Revocation cache distribution" do
    test "revocations propagate across nodes" do
      # Request capability
      {:ok, capability} =
        Security.request_capability(
          :process,
          %{operations: [:execute], resource: "worker_*"},
          "distributed_agent"
        )

      # Verify it works
      assert :ok == Security.validate_capability(capability, :execute, "worker_123")

      # Simulate revocation from another node
      Phoenix.PubSub.broadcast(
        MCPChat.PubSub,
        "security:revocations",
        {:revocation_broadcast, capability.id, :permanent, :remote_node}
      )

      # Allow propagation
      Process.sleep(100)

      # Should be revoked
      assert {:error, :token_revoked} = Security.validate_capability(capability, :execute, "worker_123")
    end

    test "batch revocation works efficiently" do
      # Create multiple capabilities
      caps =
        for i <- 1..10 do
          {:ok, cap} =
            Security.request_capability(
              :filesystem,
              %{operations: [:read], resource: "/tmp/batch_#{i}"},
              "batch_agent_#{i}"
            )

          cap
        end

      # Extract JTIs
      jtis = Enum.map(caps, & &1.id)

      # Batch revoke
      assert :ok == RevocationCache.revoke_batch(jtis)

      # Allow propagation
      Process.sleep(100)

      # All should be revoked
      for cap <- caps do
        assert {:error, :token_revoked} = Security.validate_capability(cap, :read, cap.constraints.resource)
      end
    end
  end

  describe "Token validation edge cases" do
    test "handles malformed tokens gracefully" do
      malformed_cap = %{
        __struct__: MCPChat.Security.Capability,
        id: "fake_id",
        token: "not.a.valid.jwt",
        is_token: true,
        resource_type: :filesystem
      }

      assert {:error, :invalid_signature} = Security.validate_capability(malformed_cap, :read, "/tmp")
    end

    test "validates resource patterns correctly" do
      {:ok, cap} =
        Security.request_capability(
          :filesystem,
          %{
            operations: [:read, :write],
            resource: "/home/*/documents/**",
            allowed_extensions: [".txt", ".md", ".ex"]
          },
          "pattern_agent"
        )

      # Valid patterns - These should pass
      assert :ok == Security.validate_capability(cap, :read, "/home/user/documents/notes.txt")
      assert :ok == Security.validate_capability(cap, :read, "/home/alice/documents/code/main.ex")
      assert :ok == Security.validate_capability(cap, :write, "/home/bob/documents/readme.md")

      # Invalid patterns
      assert {:error, _} = Security.validate_capability(cap, :read, "/home/documents/file.txt")
      assert {:error, _} = Security.validate_capability(cap, :read, "/etc/passwd")

      # Invalid extensions
      assert {:error, _} = Security.validate_capability(cap, :write, "/home/user/documents/script.sh")
    end
  end

  describe "Performance characteristics" do
    test "token validation is fast with caching" do
      {:ok, cap} =
        Security.request_capability(
          :network,
          %{operations: [:read], resource: "https://api.github.com/**"},
          "perf_agent"
        )

      # Warm up
      Security.validate_capability(cap, :read, "https://api.github.com/repos")

      # Measure validation time
      {time, _results} =
        :timer.tc(fn ->
          for _ <- 1..1000 do
            Security.validate_capability(cap, :read, "https://api.github.com/repos")
          end
        end)

      # microseconds per validation
      avg_time = time / 1000

      # Should be less than 1ms (1000 microseconds)
      assert avg_time < 1000, "Average validation time #{avg_time}μs exceeds 1ms target"
    end
  end

  describe "Key rotation" do
    test "tokens remain valid during key rotation overlap period" do
      # Get current signing key
      {:ok, _key, kid1} = KeyManager.get_signing_key()

      # Request capability
      {:ok, cap} =
        Security.request_capability(
          :filesystem,
          %{operations: [:read], resource: "/tmp/**"},
          "rotation_agent"
        )

      # Force key rotation
      :ok = KeyManager.rotate_keys()

      # Get new signing key
      {:ok, _key, kid2} = KeyManager.get_signing_key()
      assert kid1 != kid2

      # Old token should still validate (overlap period)
      assert :ok == Security.validate_capability(cap, :read, "/tmp/file.txt")

      # New tokens should use new key
      {:ok, new_cap} =
        Security.request_capability(
          :filesystem,
          %{operations: [:write], resource: "/tmp/**"},
          "rotation_agent_2"
        )

      assert :ok == Security.validate_capability(new_cap, :write, "/tmp/new.txt")
    end
  end

  # Helper functions

  defp flush_trace_messages do
    receive do
      {:trace, _, _, _} -> flush_trace_messages()
    after
      10 -> :ok
    end
  end
end
