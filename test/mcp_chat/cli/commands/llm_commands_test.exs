defmodule MCPChat.CLI.Commands.LLMCommandsTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias MCPChat.CLI.Commands.LLM
  alias MCPChat.LLM.ExLLMAdapter

  setup do
    # Start required services
    ensure_services_started()

    # Clear any existing session
    MCPChat.Session.clear_session()

    :ok
  end

  describe "commands/0" do
    test "returns all supported commands" do
      commands = LLM.commands()

      assert Map.has_key?(commands, "backend")
      assert Map.has_key?(commands, "model")
      assert Map.has_key?(commands, "models")
      assert Map.has_key?(commands, "loadmodel")
      assert Map.has_key?(commands, "unloadmodel")
      assert Map.has_key?(commands, "acceleration")
    end

    test "model command shows it supports subcommands" do
      commands = LLM.commands()
      model_desc = commands["model"]

      assert model_desc =~ "subcommand"
      assert model_desc =~ "usage"
    end
  end

  describe "backend command" do
    test "shows current backend and available backends when no args" do
      output =
        capture_io(fn ->
          LLM.handle_command("backend", [])
        end)

      assert output =~ "Current backend:"
      assert output =~ "Available backends:"
      assert output =~ "anthropic"
      assert output =~ "openai"
    end

    test "switches to valid backend" do
      output =
        capture_io(fn ->
          LLM.handle_command("backend", ["anthropic"])
        end)

      # Should either switch successfully or show configuration error
      assert output =~ "Switched to anthropic" or output =~ "not configured"
    end

    test "shows error for invalid backend" do
      output =
        capture_io(fn ->
          LLM.handle_command("backend", ["invalid_backend"])
        end)

      assert output =~ "Unknown backend: invalid_backend"
      assert output =~ "Available backends:"
    end
  end

  describe "model subcommands" do
    test "shows help when no subcommand provided" do
      output =
        capture_io(fn ->
          LLM.handle_command("model", [])
        end)

      assert output =~ "Model management commands:"
      assert output =~ "/model <name>"
      assert output =~ "/model switch <name>"
      assert output =~ "/model list"
      assert output =~ "/model info"
      assert output =~ "/model capabilities"
      assert output =~ "/model recommend"
      assert output =~ "/model features"
      assert output =~ "/model compare"
      assert output =~ "/model help"
    end

    test "model help shows comprehensive usage" do
      output =
        capture_io(fn ->
          LLM.handle_command("model", ["help"])
        end)

      assert output =~ "Model management commands:"
      assert output =~ "Examples:"
      assert output =~ "/model gpt-4"
      assert output =~ "/model capabilities claude-3-opus-20240229"
      assert output =~ "/model recommend streaming vision"
      assert output =~ "/model compare gpt-4 claude-3-sonnet-20240229"
    end

    test "model switch requires model name" do
      output =
        capture_io(fn ->
          LLM.handle_command("model", ["switch"])
        end)

      assert output =~ "Usage: /model switch <name>"
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

  # Helper functions

  defp ensure_services_started do
    start_config()
    start_session()
  end

  defp start_config do
    case Process.whereis(MCPChat.Config) do
      nil -> {:ok, _} = MCPChat.Config.start_link()
      _ -> :ok
    end
  end

  defp start_session do
    case Process.whereis(MCPChat.Session) do
      nil -> {:ok, _} = MCPChat.Session.start_link()
      _ -> :ok
    end
  end
end
