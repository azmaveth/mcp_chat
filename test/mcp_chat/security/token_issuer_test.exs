defmodule MCPChat.Security.TokenIssuerTest do
  @moduledoc """
  Unit tests for the TokenIssuer module.
  """

  use ExUnit.Case, async: true

  alias MCPChat.Security.{TokenIssuer, KeyManager}

  setup do
    # Start required services
    start_supervised!(KeyManager)
    start_supervised!(TokenIssuer)

    {:ok, %{}}
  end

  describe "issue_token/5" do
    test "issues valid JWT tokens with correct claims" do
      {:ok, token, jti} =
        TokenIssuer.issue_token(
          :filesystem,
          [:read, :write],
          "/project/**",
          "test_principal",
          %{max_file_size: 1_000_000}
        )

      assert is_binary(token)
      assert String.starts_with?(jti, "cap_")

      # Token should have three parts (header.payload.signature)
      assert length(String.split(token, ".")) == 3
    end

    test "tokens contain required standard claims" do
      {:ok, token, _jti} =
        TokenIssuer.issue_token(
          :mcp_tool,
          [:execute],
          "github",
          "agent_123",
          %{}
        )

      # Decode token to inspect claims
      {:ok, claims} = peek_token_claims(token)

      assert claims["iss"] == "mcp_chat_security"
      assert claims["sub"] == "agent_123"
      assert claims["aud"] == "mcp_tool"
      assert is_integer(claims["exp"])
      assert is_integer(claims["iat"])
      assert is_binary(claims["jti"])
      assert claims["exp"] > claims["iat"]
    end

    test "tokens contain custom capability claims" do
      constraints = %{
        allowed_tools: ["list_repos", "get_repo"],
        rate_limit: 100
      }

      {:ok, token, _jti} =
        TokenIssuer.issue_token(
          :mcp_tool,
          [:execute],
          "github",
          "agent_456",
          constraints
        )

      {:ok, claims} = peek_token_claims(token)

      assert claims["resource"] == "github"
      assert claims["operations"] == [:execute]
      assert claims["constraints"] == constraints
      assert claims["delegation"]["depth"] == 0
      assert claims["delegation"]["max_depth"] == 3
    end
  end

  describe "issue_delegated_token/3" do
    test "issues delegated tokens with incremented depth" do
      # Create parent token
      {:ok, parent_token, _parent_jti} =
        TokenIssuer.issue_token(
          :filesystem,
          [:read, :write, :execute],
          "/home/**",
          "parent_agent",
          %{max_delegation_depth: 5}
        )

      # Create delegated token
      {:ok, child_token, child_jti} =
        TokenIssuer.issue_delegated_token(
          parent_token,
          "child_agent",
          # More restrictive
          %{operations: [:read]}
        )

      assert is_binary(child_token)
      assert String.starts_with?(child_jti, "cap_")

      # Verify delegation claims
      {:ok, child_claims} = peek_token_claims(child_token)
      assert child_claims["sub"] == "child_agent"
      assert child_claims["delegation"]["depth"] == 1
      assert child_claims["delegation"]["parent_id"] != nil
    end

    test "enforces delegation depth limits" do
      # Create token at max depth
      {:ok, parent_token, _} =
        TokenIssuer.issue_token(
          :network,
          [:read],
          "https://api.example.com/**",
          "agent_1",
          %{max_delegation_depth: 1}
        )

      # First delegation should work
      {:ok, child_token, _} =
        TokenIssuer.issue_delegated_token(
          parent_token,
          "agent_2",
          %{}
        )

      # Second delegation should fail
      assert {:error, :delegation_depth_exceeded} =
               TokenIssuer.issue_delegated_token(
                 child_token,
                 "agent_3",
                 %{}
               )
    end

    test "delegated tokens inherit parent expiration" do
      # Create parent token with short lifetime
      # 5 minutes
      short_lifetime = 300_000

      {:ok, parent_token, _} =
        TokenIssuer.issue_token(
          :database,
          [:read],
          "users_db",
          "parent",
          %{lifetime: short_lifetime}
        )

      # Wait a bit
      Process.sleep(100)

      # Create delegated token
      {:ok, child_token, _} =
        TokenIssuer.issue_delegated_token(
          parent_token,
          "child",
          %{}
        )

      # Check expirations
      {:ok, parent_claims} = peek_token_claims(parent_token)
      {:ok, child_claims} = peek_token_claims(child_token)

      # Child should expire no later than parent
      assert child_claims["exp"] <= parent_claims["exp"]
    end

    test "constraint merging works correctly" do
      # Parent with broad permissions
      {:ok, parent_token, _} =
        TokenIssuer.issue_token(
          :filesystem,
          [:read, :write, :execute],
          "/project/**",
          "parent",
          %{
            paths: ["/project", "/shared"],
            allowed_extensions: [".ex", ".exs", ".txt", ".md"],
            max_file_size: 10_000_000
          }
        )

      # Delegate with restrictions
      {:ok, child_token, _} =
        TokenIssuer.issue_delegated_token(
          parent_token,
          "child",
          %{
            # More restrictive
            paths: ["/project/src"],
            # Subset
            allowed_extensions: [".ex", ".exs"],
            # Smaller
            max_file_size: 1_000_000
          }
        )

      {:ok, child_claims} = peek_token_claims(child_token)
      constraints = child_claims["constraints"]

      # Should have intersection of constraints
      assert constraints["paths"] == ["/project/src"]
      assert constraints["allowed_extensions"] == [".ex", ".exs"]
      assert constraints["max_file_size"] == 1_000_000
    end
  end

  describe "revoke_token/1" do
    test "adds token to revocation tracking" do
      {:ok, _token, jti} =
        TokenIssuer.issue_token(
          :process,
          [:execute],
          "worker_*",
          "test_agent",
          %{}
        )

      # Get initial stats
      {:ok, stats_before} = TokenIssuer.get_stats()
      active_before = stats_before.active_tokens

      # Revoke token
      assert :ok == TokenIssuer.revoke_token(jti)

      # Check updated stats
      {:ok, stats_after} = TokenIssuer.get_stats()
      assert stats_after.active_tokens == active_before - 1
    end
  end

  describe "get_stats/0" do
    test "returns accurate token statistics" do
      # Issue some tokens
      {:ok, _token1, _jti1} = TokenIssuer.issue_token(:filesystem, [:read], "/tmp", "agent1", %{})
      {:ok, _token2, _jti2} = TokenIssuer.issue_token(:network, [:read], "*", "agent2", %{})

      # Get stats
      {:ok, stats} = TokenIssuer.get_stats()

      assert is_integer(stats.tokens_issued)
      assert is_integer(stats.active_tokens)
      assert is_integer(stats.expired_tokens)
      assert stats.tokens_issued >= 2
      assert stats.active_tokens >= 2
    end
  end

  # Helper functions

  defp peek_token_claims(token) do
    # Simple JWT decode without verification for testing
    [_header, payload, _signature] = String.split(token, ".")

    with {:ok, decoded} <- Base.url_decode64(payload, padding: false),
         {:ok, claims} <- Jason.decode(decoded) do
      {:ok, claims}
    end
  end
end
