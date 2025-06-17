defmodule MCPChat.CLI.EnhancedCommandsTest do
  use ExUnit.Case, async: false

  alias MCPChat.CLI.{AgentCommandBridge, EnhancedCommands}

  @moduletag :integration

  setup do
    # Ensure agent architecture is available
    case Application.ensure_all_started(:mcp_chat) do
      {:ok, _} -> :ok
      # Already started
      {:error, _} -> :ok
    end

    # Wait for agent supervisor to be available
    Process.sleep(100)

    :ok
  end

  describe "command routing" do
    test "routes local commands correctly" do
      {type, cmd, args} = AgentCommandBridge.route_command("help", [])
      assert type == :local
      assert cmd == "help"
      assert args == []
    end

    test "routes agent commands correctly" do
      {type, agent_type, cmd, args} = AgentCommandBridge.route_command("model", ["recommend"])
      assert type == :agent
      assert agent_type == :llm_agent
      assert cmd == "model"
      assert args == ["recommend"]
    end

    test "handles unknown commands" do
      {type, cmd, args} = AgentCommandBridge.route_command("unknown", [])
      assert type == :unknown
      assert cmd == "unknown"
      assert args == []
    end
  end

  describe "command discovery" do
    test "discovers available commands" do
      commands = AgentCommandBridge.discover_available_commands()

      assert is_map(commands)
      assert Map.has_key?(commands, :local)
      assert Map.has_key?(commands, :agent)
      assert Map.has_key?(commands, :all)

      # Should include local commands
      assert "help" in commands.local
      assert "config" in commands.local

      # Should include agent commands
      assert "model" in commands.agent
      assert "backend" in commands.agent
    end

    test "generates enhanced help" do
      help_data = AgentCommandBridge.generate_enhanced_help()

      assert is_map(help_data)
      assert Map.has_key?(help_data, :local_commands)
      assert Map.has_key?(help_data, :agent_commands)
      assert Map.has_key?(help_data, :total_count)
      assert Map.has_key?(help_data, :session_active)

      assert help_data.total_count > 0
    end
  end

  describe "command completions" do
    test "provides enhanced completions" do
      completions = EnhancedCommands.get_enhanced_completions("mod")

      assert is_list(completions)
      # Completions may include hints, so check if any completion starts with the command
      assert Enum.any?(completions, &String.starts_with?(&1, "model"))
      assert Enum.any?(completions, &String.starts_with?(&1, "models"))
    end

    test "provides completions for partial commands" do
      completions = EnhancedCommands.get_enhanced_completions("h")

      assert is_list(completions)
      assert "help" in completions
    end

    test "returns empty list for no matches" do
      completions = EnhancedCommands.get_enhanced_completions("xyz")

      assert completions == []
    end
  end

  describe "enhanced help display" do
    test "shows enhanced help without errors" do
      # This test just ensures the help system doesn't crash
      # In a real test environment, we'd capture and verify the output
      assert :ok = EnhancedCommands.show_enhanced_help()
    end
  end

  describe "agent integration" do
    test "detects agent architecture availability" do
      # Check if agent supervisor is running
      agent_supervisor = Process.whereis(MCPChat.Agents.AgentSupervisor)
      assert agent_supervisor != nil

      # Check if agent pool is available
      agent_pool = Process.whereis(MCPChat.Agents.AgentPool)
      assert agent_pool != nil
    end

    test "can start agent command bridge" do
      # The bridge should already be started by the supervision tree
      bridge = Process.whereis(MCPChat.CLI.AgentCommandBridge)
      assert bridge != nil
    end
  end

  describe "backward compatibility" do
    test "legacy command routing still works" do
      # Ensure legacy commands can still be executed
      # This would be tested by checking the original Commands module
      commands = MCPChat.CLI.get_completions("h")
      assert is_list(commands)
      assert "help" in commands
    end
  end
end
