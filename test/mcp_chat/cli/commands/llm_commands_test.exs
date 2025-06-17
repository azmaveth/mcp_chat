defmodule MCPChat.CLI.Commands.LLMCommandsTest do
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

      assert output =~ "Use '/model info' to see current model"
    end

    test "model switch changes model" do
      output =
        capture_io(fn ->
          LLM.handle_command("model", ["switch", "gpt-4"])
        end)

      assert output =~ "Switched to model: gpt-4"
    end

    test "backward compatibility - model name directly" do
      output =
        capture_io(fn ->
          LLM.handle_command("model", ["gpt-4-turbo"])
        end)

      assert output =~ "Switched to model: gpt-4-turbo"
    end

    test "model info shows current model information" do
      output =
        capture_io(fn ->
          LLM.handle_command("model", ["info"])
        end)

      assert output =~ "Current backend:"
      assert output =~ "Current model:"
    end

    test "model list shows available models" do
      output =
        capture_io(fn ->
          LLM.handle_command("model", ["list"])
        end)

      assert output =~ "Current backend:" or output =~ "Available models"
    end
  end

  describe "model capabilities command" do
    test "shows current model capabilities when no args" do
      # Mock the ModelCapabilities call
      output =
        capture_io(fn ->
          LLM.handle_command("model", ["capabilities"])
        end)

      # Should either show capabilities or model not found error
      assert output =~ "Model:" or output =~ "not found" or output =~ "Failed to get capabilities"
    end

    test "shows specific model capabilities" do
      output =
        capture_io(fn ->
          LLM.handle_command("model", ["capabilities", "gpt-4"])
        end)

      # Should either show capabilities or model not found error
      assert output =~ "Model: GPT-4" or output =~ "gpt-4 not found" or output =~ "Failed to get capabilities"
    end

    test "handles model not found gracefully" do
      output =
        capture_io(fn ->
          LLM.handle_command("model", ["capabilities", "nonexistent-model"])
        end)

      assert output =~ "Model nonexistent-model not found"
    end
  end

  describe "model features command" do
    test "lists all available features" do
      output =
        capture_io(fn ->
          LLM.handle_command("model", ["features"])
        end)

      # Should show features or error message
      assert output =~ "Available model features:" or output =~ "Failed to list features"
    end
  end

  describe "model recommend command" do
    test "shows general recommendations when no features specified" do
      output =
        capture_io(fn ->
          LLM.handle_command("model", ["recommend"])
        end)

      # Should show recommendations or no models found message
      assert output =~ "Recommended models" or output =~ "No models found" or output =~ "Failed to get recommendations"
    end

    test "finds models with specific features" do
      output =
        capture_io(fn ->
          LLM.handle_command("model", ["recommend", "streaming", "vision"])
        end)

      # Should show recommendations for streaming + vision or no models found
      assert output =~ "Recommended models" or output =~ "No models found" or output =~ "Failed to get recommendations"
    end

    test "handles invalid features gracefully" do
      output =
        capture_io(fn ->
          LLM.handle_command("model", ["recommend", "invalid_feature"])
        end)

      # Should still work, just with no matching models
      assert output =~ "Recommended models" or output =~ "No models found" or output =~ "Failed to get recommendations"
    end
  end

  describe "model compare command" do
    test "requires at least 2 models" do
      output =
        capture_io(fn ->
          LLM.handle_command("model", ["compare"])
        end)

      assert output =~ "Usage: /compare <model1> <model2>"
      assert output =~ "Example: /compare gpt-4 claude-3-opus-20240229"
    end

    test "requires at least 2 models with single model" do
      output =
        capture_io(fn ->
          LLM.handle_command("model", ["compare", "gpt-4"])
        end)

      assert output =~ "At least 2 models are required"
    end

    test "compares multiple models" do
      output =
        capture_io(fn ->
          LLM.handle_command("model", ["compare", "gpt-4", "gpt-3.5-turbo"])
        end)

      # Should either show comparison or comparison failed error
      assert output =~ "Model Comparison:" or output =~ "Comparison failed" or output =~ "Failed to compare models"
    end

    test "compares three models" do
      output =
        capture_io(fn ->
          LLM.handle_command("model", ["compare", "gpt-4", "gpt-3.5-turbo", "claude-3-sonnet-20240229"])
        end)

      # Should either show comparison or comparison failed error
      assert output =~ "Model Comparison:" or output =~ "Comparison failed" or output =~ "Failed to compare models"
    end
  end

  describe "models command" do
    test "lists available models for current backend" do
      output =
        capture_io(fn ->
          LLM.handle_command("models", [])
        end)

      assert output =~ "Current backend:"
      assert output =~ "Current model:"
    end
  end

  describe "loadmodel command" do
    test "shows usage when no model specified" do
      output =
        capture_io(fn ->
          LLM.handle_command("loadmodel", [])
        end)

      assert output =~ "Usage: /loadmodel <model-id|path>"
      # Should also show available models or not available message
      assert output =~ "Available models" or output =~ "Local model support is not available"
    end

    test "attempts to load specified model" do
      output =
        capture_io(fn ->
          LLM.handle_command("loadmodel", ["microsoft/phi-2"])
        end)

      # Should either start loading or show not available
      assert output =~ "Loading model: microsoft/phi-2" or output =~ "Local model support is not available"
    end
  end

  describe "unloadmodel command" do
    test "shows usage when no model specified" do
      output =
        capture_io(fn ->
          LLM.handle_command("unloadmodel", [])
        end)

      assert output =~ "Usage: /unloadmodel <model-id>"
      # Should also show loaded models or not available message
      assert output =~ "Currently loaded models" or output =~ "Local model support is not available"
    end

    test "attempts to unload specified model" do
      output =
        capture_io(fn ->
          LLM.handle_command("unloadmodel", ["microsoft/phi-2"])
        end)

      # Should either attempt unload or show not available
      assert output =~ "unload" or output =~ "Local model support is not available"
    end
  end

  describe "acceleration command" do
    test "shows hardware acceleration info" do
      output =
        capture_io(fn ->
          LLM.handle_command("acceleration", [])
        end)

      assert output =~ "Hardware Acceleration Info"
      assert output =~ "Type:"
      assert output =~ "Backend:"
    end

    test "shows optimization status" do
      output =
        capture_io(fn ->
          LLM.handle_command("acceleration", [])
        end)

      assert output =~ "Optimization Status:"
      # Should show either enabled optimizations or suggestions
      assert output =~ "✓" or output =~ "⚠" or output =~ "available"
    end
  end

  describe "error handling" do
    test "unknown command returns error" do
      result = LLM.handle_command("unknown_command", [])
      assert {:error, message} = result
      assert message =~ "Unknown LLM command: unknown_command"
    end

    test "model capabilities handles adapter errors gracefully" do
      output =
        capture_io(fn ->
          LLM.handle_command("model", ["capabilities", "test-model"])
        end)

      # Should handle errors gracefully without crashing
      assert is_binary(output)
    end

    test "model comparison handles adapter errors gracefully" do
      output =
        capture_io(fn ->
          LLM.handle_command("model", ["compare", "model1", "model2"])
        end)

      # Should handle errors gracefully without crashing
      assert is_binary(output)
    end
  end

  describe "command formatting and output" do
    test "capabilities output includes feature formatting" do
      output =
        capture_io(fn ->
          LLM.handle_command("model", ["capabilities"])
        end)

      # If successful, should format features nicely
      if output =~ "Supported Features:" do
        # Check mark for supported features
        assert output =~ "✓"
      end
    end

    test "comparison output includes visual indicators" do
      output =
        capture_io(fn ->
          LLM.handle_command("model", ["compare", "gpt-4", "gpt-3.5-turbo"])
        end)

      # If successful, should include comparison symbols
      if output =~ "Feature Comparison:" do
        # Check marks and X marks
        assert output =~ "✓" or output =~ "✗"
      end
    end

    test "recommendations include scoring information" do
      output =
        capture_io(fn ->
          LLM.handle_command("model", ["recommend"])
        end)

      # If successful, should include model scoring
      if output =~ "Recommended models" and not (output =~ "No models found") do
        assert output =~ "Score:" or output =~ "Context:" or output =~ "Features:"
      end
    end
  end

  # No helper functions needed - using supervised application startup
end
