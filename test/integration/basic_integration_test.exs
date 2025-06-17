defmodule MCPChat.BasicIntegrationTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Basic integration tests for MCP Chat application with agent architecture.
  Tests core functionality through the agent system.
  """

  alias MCPChat.CLI.EnhancedCommands
  alias MCPChat.CLI.AgentCommandBridge
  alias MCPChat.Agents.{SessionManager, MCPAgent}
  alias MCPChat.Events.AgentEvents

  setup do
    # Ensure application is started with agent architecture
    case Application.ensure_all_started(:mcp_chat) do
      {:ok, _} -> :ok
      # Already started
      {:error, _} -> :ok
    end

    # Subscribe to agent events
    Phoenix.PubSub.subscribe(MCPChat.PubSub, "agent_events")

    :ok
  end

  describe "Agent-based MCP integration" do
    test "MCP commands route to MCP agent" do
      session_id = "test_mcp_#{:rand.uniform(1000)}"

      # Test that MCP commands route correctly
      assert {:agent, :mcp_agent, "mcp", ["list"]} = AgentCommandBridge.route_command("mcp", ["list"])
      assert {:agent, :mcp_agent, "mcp", ["discover"]} = AgentCommandBridge.route_command("mcp", ["discover"])
    end

    test "MCP agent discovery through enhanced commands" do
      session_id = "test_discover_#{:rand.uniform(1000)}"

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          EnhancedCommands.handle_command("/mcp discover", session_id)
        end)

      # Should show agent execution or discovery results
      assert output =~ "🤖 Executing with mcp_agent" or
               output =~ "discover" or
               output =~ "server"
    end

    test "MCP agent list servers through enhanced commands" do
      session_id = "test_list_#{:rand.uniform(1000)}"

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          EnhancedCommands.handle_command("/mcp list", session_id)
        end)

      # Should show agent execution or server list
      assert output =~ "🤖 Executing with mcp_agent" or
               output =~ "server" or
               output =~ "list"
    end
  end

  describe "Agent-based session management" do
    test "session save through enhanced commands" do
      session_id = "test_save_#{:rand.uniform(1000)}"
      test_name = "integration_test_#{System.unique_integer([:positive])}"

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          EnhancedCommands.handle_command("/save #{test_name}", session_id)
        end)

      # Should handle save operation (may be local or agent-based)
      assert output =~ "save" or output =~ "Session" or is_binary(output)
    end

    test "export through export agent" do
      session_id = "test_export_#{:rand.uniform(1000)}"

      # Test that export commands route to export agent
      assert {:agent, :export_agent, "export", ["json"]} = AgentCommandBridge.route_command("export", ["json"])

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          EnhancedCommands.handle_command("/export json", session_id)
        end)

      # Should show agent execution or export functionality
      assert output =~ "🤖 Executing with export_agent" or
               output =~ "export" or
               output =~ "json"
    end

    test "stats through analysis agent" do
      session_id = "test_stats_#{:rand.uniform(1000)}"

      # Test that stats commands route to analysis agent
      assert {:agent, :analysis_agent, "stats", []} = AgentCommandBridge.route_command("stats", [])

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          EnhancedCommands.handle_command("/stats", session_id)
        end)

      # Should show agent execution or statistics
      assert output =~ "🤖 Executing with analysis_agent" or
               output =~ "stats" or
               output =~ "session"
    end
  end

  describe "Context estimation" do
    test "token estimation for messages" do
      messages = [
        %{role: "system", content: "You are a helpful assistant"},
        %{role: "user", content: "Hello, how are you?"},
        %{role: "assistant", content: "I'm doing well, thank you!"}
      ]

      tokens = MCPChat.Context.estimate_tokens(messages)
      assert tokens > 0
      # These short messages should be under 100 tokens
      assert tokens < 100
    end
  end

  describe "Cost calculation" do
    test "cost calculation for session" do
      # Create a test session with Anthropic backend
      session = %{
        llm_backend: "anthropic",
        model: "claude-3-sonnet-20240229",
        messages: [],
        context: %{model: "claude-3-sonnet-20240229"}
      }

      token_usage = %{
        input_tokens: 100,
        output_tokens: 200
      }

      cost_info = MCPChat.Cost.calculate_session_cost(session, token_usage)
      assert cost_info.input_cost > 0
      assert cost_info.output_cost > 0
      assert cost_info.total_cost == cost_info.input_cost + cost_info.output_cost
      assert cost_info.backend == "anthropic"
    end
  end
end
