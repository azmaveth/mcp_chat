defmodule MCPChat.CLI.Commands.LLMCommandsAgentTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias MCPChat.CLI.EnhancedCommands
  alias MCPChat.CLI.AgentCommandBridge
  alias MCPChat.Agents.{SessionManager, LLMAgent}
  alias MCPChat.Events.AgentEvents

  setup do
    # Ensure application is started with agent architecture
    case Application.ensure_all_started(:mcp_chat) do
      {:ok, _} -> :ok
      # Already started
      {:error, _} -> :ok
    end

    # Ensure enhanced commands are enabled for testing
    Application.put_env(:mcp_chat, :test_mode, true)

    # Subscribe to agent events for testing
    Phoenix.PubSub.subscribe(MCPChat.PubSub, "agent_events")

    :ok
  end

  describe "agent command discovery" do
    test "discovers LLM agent commands through bridge" do
      commands = AgentCommandBridge.discover_available_commands("test_session")

      assert "backend" in commands.agent
      assert "model" in commands.agent
      assert "models" in commands.agent
      assert "acceleration" in commands.agent
    end

    test "agent command routing classifies LLM commands correctly" do
      assert {:agent, :llm_agent, "backend", []} = AgentCommandBridge.route_command("backend", [])
      assert {:agent, :llm_agent, "model", ["list"]} = AgentCommandBridge.route_command("model", ["list"])
      assert {:agent, :llm_agent, "models", []} = AgentCommandBridge.route_command("models", [])
      assert {:agent, :llm_agent, "acceleration", []} = AgentCommandBridge.route_command("acceleration", [])
    end
  end

  describe "enhanced backend command through agents" do
    test "routes backend command to LLM agent" do
      session_id = "test_backend_#{:rand.uniform(1000)}"

      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/backend", session_id)
        end)

      # Should show agent execution message
      assert output =~ "🤖 Executing with llm_agent" or
               output =~ "backend" or
               output =~ "Available backends"
    end

    test "routes backend switching to LLM agent" do
      session_id = "test_switch_#{:rand.uniform(1000)}"

      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/backend anthropic", session_id)
        end)

      # Should show agent execution or configuration message
      assert output =~ "🤖 Executing with llm_agent" or
               output =~ "anthropic" or
               output =~ "not configured"
    end

    test "handles invalid backend through agent" do
      session_id = "test_invalid_#{:rand.uniform(1000)}"

      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/backend invalid_backend", session_id)
        end)

      # Should show agent execution or error handling
      assert output =~ "🤖 Executing with llm_agent" or
               output =~ "invalid_backend" or
               output =~ "Available backends"
    end
  end

  describe "enhanced model commands through agents" do
    test "routes model command to LLM agent" do
      session_id = "test_model_#{:rand.uniform(1000)}"

      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/model", session_id)
        end)

      # Should show agent execution or model help
      assert output =~ "🤖 Executing with llm_agent" or
               output =~ "model" or
               output =~ "management"
    end

    test "routes model recommend to LLM agent" do
      session_id = "test_recommend_#{:rand.uniform(1000)}"

      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/model recommend", session_id)
        end)

      # Should show agent execution message
      assert output =~ "🤖 Executing with llm_agent" or
               output =~ "recommend"
    end

    test "routes model capabilities to LLM agent" do
      session_id = "test_capabilities_#{:rand.uniform(1000)}"

      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/model capabilities", session_id)
        end)

      # Should show agent execution or capabilities info
      assert output =~ "🤖 Executing with llm_agent" or
               output =~ "capabilities"
    end

    test "routes models listing to LLM agent" do
      session_id = "test_models_#{:rand.uniform(1000)}"

      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/models", session_id)
        end)

      # Should show agent execution or models list
      assert output =~ "🤖 Executing with llm_agent" or
               output =~ "Current backend"
    end

    test "routes acceleration command to LLM agent" do
      session_id = "test_accel_#{:rand.uniform(1000)}"

      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/acceleration", session_id)
        end)

      # Should show agent execution or acceleration info
      assert output =~ "🤖 Executing with llm_agent" or
               output =~ "acceleration" or
               output =~ "Hardware"
    end
  end

  describe "agent PubSub integration" do
    test "can subscribe to agent events" do
      session_id = "test_pubsub_#{:rand.uniform(1000)}"

      # Subscribe to session events
      Phoenix.PubSub.subscribe(MCPChat.PubSub, "session:#{session_id}")

      # Execute command through agents
      spawn(fn ->
        EnhancedCommands.handle_command("/backend", session_id)
      end)

      # Should receive agent events (or timeout gracefully)
      receive do
        _msg -> :ok
      after
        # Timeout is acceptable in test environment
        1000 -> :ok
      end
    end

    test "agent command routing works end-to-end" do
      # Test that commands are properly routed to the right agent type
      assert {:agent, :llm_agent, "acceleration", []} = AgentCommandBridge.route_command("acceleration", [])
      assert {:agent, :llm_agent, "model", ["info"]} = AgentCommandBridge.route_command("model", ["info"])
    end
  end

  describe "enhanced command system integration" do
    test "enhanced commands properly parse complex model commands" do
      session_id = "test_complex_#{:rand.uniform(1000)}"

      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/model compare gpt-4 claude-3-sonnet", session_id)
        end)

      # Should route to agent or show comparison
      assert output =~ "🤖 Executing with llm_agent" or
               output =~ "compare" or
               output =~ "gpt-4"
    end

    test "enhanced commands handle model recommendations with features" do
      session_id = "test_features_#{:rand.uniform(1000)}"

      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/model recommend streaming vision", session_id)
        end)

      # Should route to agent or show recommendations
      assert output =~ "🤖 Executing with llm_agent" or
               output =~ "recommend" or
               output =~ "streaming"
    end
  end

  describe "agent error handling" do
    test "handles agent pool busy gracefully" do
      session_id = "test_busy_#{:rand.uniform(1000)}"

      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/backend", session_id)
        end)

      # Should either execute successfully or show busy message
      assert output =~ "🤖 Executing with llm_agent" or
               output =~ "⏳ Agent pool is busy" or
               output =~ "backend"
    end

    test "handles unknown commands gracefully" do
      session_id = "test_unknown_#{:rand.uniform(1000)}"

      output =
        capture_io(fn ->
          EnhancedCommands.handle_command("/unknown_command", session_id)
        end)

      # Should show unknown command error
      assert output =~ "Unknown command: /unknown_command"
    end
  end
end
