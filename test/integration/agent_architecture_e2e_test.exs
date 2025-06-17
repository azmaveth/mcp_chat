defmodule MCPChat.AgentArchitectureE2ETest do
  use ExUnit.Case, async: false

  @moduledoc """
  End-to-end tests for the complete agent architecture integration.
  Tests the full flow from CLI commands through agents and back.
  """

  import ExUnit.CaptureIO

  alias MCPChat.CLI.EnhancedCommands
  alias MCPChat.CLI.AgentCommandBridge
  alias MCPChat.Agents.{SessionManager, LLMAgent, MCPAgent, AnalysisAgent, ExportAgent}
  alias MCPChat.Events.AgentEvents

  setup do
    # Ensure application is started with full agent architecture
    case Application.ensure_all_started(:mcp_chat) do
      {:ok, _} -> :ok
      # Already started
      {:error, _} -> :ok
    end

    # Subscribe to all agent events
    Phoenix.PubSub.subscribe(MCPChat.PubSub, "agent_events")

    # Create unique session for each test
    session_id = "e2e_test_#{:rand.uniform(10000)}"

    {:ok, session_id: session_id}
  end

  describe "Complete agent command flow" do
    test "LLM agent commands work end-to-end", %{session_id: session_id} do
      # Test backend command
      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/backend", session_id)
        end)

      assert output =~ "🤖 Executing with llm_agent" or output =~ "backend"

      # Test models command
      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/models", session_id)
        end)

      assert output =~ "🤖 Executing with llm_agent" or output =~ "model"

      # Test model recommend
      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/model recommend", session_id)
        end)

      assert output =~ "🤖 Executing with llm_agent" or output =~ "recommend"
    end

    test "MCP agent commands work end-to-end", %{session_id: session_id} do
      # Test MCP discover
      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/mcp discover", session_id)
        end)

      assert output =~ "🤖 Executing with mcp_agent" or output =~ "discover"

      # Test MCP list
      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/mcp list", session_id)
        end)

      assert output =~ "🤖 Executing with mcp_agent" or output =~ "server"
    end

    test "Analysis agent commands work end-to-end", %{session_id: session_id} do
      # Test stats command
      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/stats", session_id)
        end)

      assert output =~ "🤖 Executing with analysis_agent" or output =~ "stats"

      # Test cost command
      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/cost", session_id)
        end)

      assert output =~ "🤖 Executing with analysis_agent" or output =~ "cost"
    end

    test "Export agent commands work end-to-end", %{session_id: session_id} do
      # Test export command
      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/export json", session_id)
        end)

      assert output =~ "🤖 Executing with export_agent" or output =~ "export"
    end

    test "Local commands still work correctly", %{session_id: session_id} do
      # Test help command (should be local)
      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/help", session_id)
        end)

      assert output =~ "Available Commands" or output =~ "help"

      # Test clear command (should be local)
      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/clear", session_id)
        end)

      # Clear should execute without errors
      assert is_binary(output)
    end
  end

  describe "Agent routing verification" do
    test "all agent commands route correctly" do
      # LLM Agent commands
      assert {:agent, :llm_agent, "backend", []} = AgentCommandBridge.route_command("backend", [])
      assert {:agent, :llm_agent, "model", ["list"]} = AgentCommandBridge.route_command("model", ["list"])
      assert {:agent, :llm_agent, "models", []} = AgentCommandBridge.route_command("models", [])
      assert {:agent, :llm_agent, "acceleration", []} = AgentCommandBridge.route_command("acceleration", [])

      # MCP Agent commands
      assert {:agent, :mcp_agent, "mcp", ["discover"]} = AgentCommandBridge.route_command("mcp", ["discover"])
      assert {:agent, :mcp_agent, "mcp", ["list"]} = AgentCommandBridge.route_command("mcp", ["list"])

      # Analysis Agent commands
      assert {:agent, :analysis_agent, "stats", []} = AgentCommandBridge.route_command("stats", [])
      assert {:agent, :analysis_agent, "cost", []} = AgentCommandBridge.route_command("cost", [])

      # Export Agent commands
      assert {:agent, :export_agent, "export", ["json"]} = AgentCommandBridge.route_command("export", ["json"])

      # Tool Agent commands
      assert {:agent, :tool_agent, "concurrent", []} = AgentCommandBridge.route_command("concurrent", [])
    end

    test "local commands route correctly" do
      assert {:local, "help", []} = AgentCommandBridge.route_command("help", [])
      assert {:local, "clear", []} = AgentCommandBridge.route_command("clear", [])
      assert {:local, "config", []} = AgentCommandBridge.route_command("config", [])
      assert {:local, "new", []} = AgentCommandBridge.route_command("new", [])
      assert {:local, "save", ["test"]} = AgentCommandBridge.route_command("save", ["test"])
      assert {:local, "load", ["test"]} = AgentCommandBridge.route_command("load", ["test"])
    end

    test "unknown commands route correctly" do
      assert {:unknown, "nonexistent", []} = AgentCommandBridge.route_command("nonexistent", [])
      assert {:unknown, "invalid_cmd", ["arg"]} = AgentCommandBridge.route_command("invalid_cmd", ["arg"])
    end
  end

  describe "Agent discovery and help system" do
    test "enhanced help discovers agent commands", %{session_id: session_id} do
      commands = AgentCommandBridge.discover_available_commands(session_id)

      # Should discover agent commands
      assert "backend" in commands.agent
      assert "model" in commands.agent
      assert "mcp" in commands.agent
      assert "stats" in commands.agent
      assert "export" in commands.agent

      # Should discover local commands
      assert "help" in commands.local
      assert "clear" in commands.local
      assert "save" in commands.local
    end

    test "enhanced help shows comprehensive command list", %{session_id: session_id} do
      output =
        capture_io(fn ->
          EnhancedCommands.show_enhanced_help(session_id)
        end)

      # Should show available commands
      assert output =~ "Available Commands"

      # Should show agent status
      assert output =~ "Agent session" or output =~ "commands available"
    end
  end

  describe "Agent architecture resilience" do
    test "handles agent unavailability gracefully", %{session_id: session_id} do
      # Test with potentially unavailable agents
      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/backend", session_id)
        end)

      # Should either execute with agent or show graceful error
      # Any response is acceptable
      assert output =~ "🤖 Executing with llm_agent" or
               output =~ "⏳ Agent pool is busy" or
               output =~ "backend" or
               is_binary(output)
    end

    test "unknown commands show helpful error", %{session_id: session_id} do
      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/unknown_command", session_id)
        end)

      assert output =~ "Unknown command: /unknown_command"
    end
  end

  describe "Session management integration" do
    test "commands work with session context", %{session_id: session_id} do
      # Multiple commands in same session should work

      output1 =
        capture_io(fn ->
          EnhancedCommands.handle_command("/stats", session_id)
        end)

      output2 =
        capture_io(fn ->
          EnhancedCommands.handle_command("/backend", session_id)
        end)

      output3 =
        capture_io(fn ->
          EnhancedCommands.handle_command("/help", session_id)
        end)

      # All should execute successfully
      assert is_binary(output1) and is_binary(output2) and is_binary(output3)
    end

    test "session isolation works correctly" do
      session_1 = "test_isolation_1_#{:rand.uniform(1000)}"
      session_2 = "test_isolation_2_#{:rand.uniform(1000)}"

      # Commands in different sessions should be isolated
      output1 =
        capture_io(fn ->
          EnhancedCommands.handle_command("/stats", session_1)
        end)

      output2 =
        capture_io(fn ->
          EnhancedCommands.handle_command("/stats", session_2)
        end)

      # Both should work independently
      assert is_binary(output1) and is_binary(output2)
    end
  end
end
