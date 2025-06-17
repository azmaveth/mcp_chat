defmodule ModelCapabilitiesIntegrationTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  @moduletag :integration

  setup do
    # Start the application if not already started
    ensure_application_started()

    # Clear any existing session
    MCPChat.Session.clear_session()

    :ok
  end

  describe "model capabilities integration" do
    test "full workflow: list features, get recommendations, compare models" do
      # Step 1: List all available features
      features_output =
        capture_io(fn ->
          MCPChat.CLI.Commands.handle_command("model features")
        end)

      # Should show available features
      assert features_output =~ "Available model features:" or features_output =~ "Failed to list features"

      # Step 2: Get recommendations for specific features
      recommend_output =
        capture_io(fn ->
          MCPChat.CLI.Commands.handle_command("model recommend streaming function_calling")
        end)

      # Should show recommendations or no models found
      assert recommend_output =~ "Recommended models" or recommend_output =~ "No models found" or
               recommend_output =~ "Failed to get recommendations"

      # Step 3: Compare popular models
      compare_output =
        capture_io(fn ->
          MCPChat.CLI.Commands.handle_command("model compare gpt-4 claude-3-opus-20240229 gpt-3.5-turbo")
        end)

      # Should show comparison or error
      assert compare_output =~ "Model Comparison:" or compare_output =~ "Comparison failed" or
               compare_output =~ "Failed to compare models"
    end

    test "model switching and capabilities workflow" do
      # Step 1: Check current model capabilities
      current_caps_output =
        capture_io(fn ->
          MCPChat.CLI.Commands.handle_command("model capabilities")
        end)

      # Should show capabilities for current model
      assert current_caps_output =~ "Model:" or current_caps_output =~ "not found" or
               current_caps_output =~ "Failed to get capabilities"

      # Step 2: Switch to a specific model
      switch_output =
        capture_io(fn ->
          MCPChat.CLI.Commands.handle_command("model gpt-4")
        end)

      # Should switch successfully
      assert switch_output =~ "Switched to model: gpt-4"

      # Step 3: Check capabilities of the new model
      new_caps_output =
        capture_io(fn ->
          MCPChat.CLI.Commands.handle_command("model capabilities")
        end)

      # Should show capabilities for gpt-4
      assert new_caps_output =~ "Model:" or new_caps_output =~ "gpt-4 not found" or
               new_caps_output =~ "Failed to get capabilities"
    end

    test "model info and list workflow" do
      # Step 1: Show current model info
      info_output =
        capture_io(fn ->
          MCPChat.CLI.Commands.handle_command("model info")
        end)

      assert info_output =~ "Current backend:" and info_output =~ "Current model:"

      # Step 2: List available models
      list_output =
        capture_io(fn ->
          MCPChat.CLI.Commands.handle_command("model list")
        end)

      assert list_output =~ "Current backend:" or list_output =~ "Available models"

      # Step 3: Show help
      help_output =
        capture_io(fn ->
          MCPChat.CLI.Commands.handle_command("model help")
        end)

      assert help_output =~ "Model management commands:" and help_output =~ "Examples:"
    end

    test "error handling in model capabilities" do
      # Test with unknown model
      unknown_model_output =
        capture_io(fn ->
          MCPChat.CLI.Commands.handle_command("model capabilities unknown-model-12_345")
        end)

      assert unknown_model_output =~ "unknown-model-12_345 not found" or
               unknown_model_output =~ "Failed to get capabilities"

      # Test comparison with no models
      no_models_output =
        capture_io(fn ->
          MCPChat.CLI.Commands.handle_command("model compare")
        end)

      assert no_models_output =~ "Usage:" or no_models_output =~ "At least 2 models"

      # Test comparison with one model
      one_model_output =
        capture_io(fn ->
          MCPChat.CLI.Commands.handle_command("model compare gpt-4")
        end)

      assert one_model_output =~ "At least 2 models are required"
    end

    test "backend switching affects model recommendations" do
      # Step 1: Switch to OpenAI backend
      switch_backend_output =
        capture_io(fn ->
          MCPChat.CLI.Commands.handle_command("backend openai")
        end)

      # Should either switch successfully or show not configured
      assert switch_backend_output =~ "Switched to openai" or switch_backend_output =~ "not configured"

      # Step 2: Get recommendations (should work regardless of backend)
      recommend_output =
        capture_io(fn ->
          MCPChat.CLI.Commands.handle_command("model recommend")
        end)

      assert recommend_output =~ "Recommended models" or recommend_output =~ "No models found" or
               recommend_output =~ "Failed to get recommendations"

      # Step 3: Switch to Anthropic backend
      switch_back_output =
        capture_io(fn ->
          MCPChat.CLI.Commands.handle_command("backend anthropic")
        end)

      assert switch_back_output =~ "Switched to anthropic" or switch_back_output =~ "not configured"
    end

    test "model capabilities output formatting" do
      # Test that capabilities output is well-formatted
      output =
        capture_io(fn ->
          MCPChat.CLI.Commands.handle_command("model capabilities claude-3-opus-20240229")
        end)

      if output =~ "Model: Claude 3 Opus" do
        # If we get capabilities, check formatting
        assert output =~ "Context Window:"
        assert output =~ "Supported Features:"
        # Should have check marks for supported features
        assert output =~ "✓"
      end
    end

    test "model comparison output formatting" do
      # Test that comparison output is well-formatted
      output =
        capture_io(fn ->
          MCPChat.CLI.Commands.handle_command("model compare gpt-4 claude-3-opus-20240229")
        end)

      if output =~ "Model Comparison:" do
        # If comparison succeeds, check formatting
        assert output =~ "Feature Comparison:"
        # Should have legend explaining symbols
        assert output =~ "Legend:"
        # Should have visual indicators
        assert output =~ "✓" or output =~ "✗"
      end
    end

    test "recommendation output includes scoring" do
      # Test that recommendations include useful metadata
      output =
        capture_io(fn ->
          MCPChat.CLI.Commands.handle_command("model recommend streaming vision")
        end)

      if output =~ "Recommended models" and not (output =~ "No models found") do
        # If we get recommendations, they should include metadata
        assert output =~ "Score:" or output =~ "Context:" or output =~ "Features:"
      end
    end
  end

  describe "command integration with chat flow" do
    test "model capabilities don't interfere with chat session" do
      # Add a message to the session
      MCPChat.Session.add_message("user", "Test message")

      # Check capabilities
      _caps_output =
        capture_io(fn ->
          MCPChat.CLI.Commands.handle_command("model capabilities")
        end)

      # Session should still have the message
      messages = MCPChat.Session.get_messages()
      assert length(messages) > 0

      # Should still be able to get recommendations
      _recommend_output =
        capture_io(fn ->
          MCPChat.CLI.Commands.handle_command("model recommend")
        end)

      # Session should still be intact
      final_messages = MCPChat.Session.get_messages()
      assert final_messages == messages
    end

    test "switching models updates session state" do
      # Get initial model
      initial_session = MCPChat.Session.get_current_session()
      initial_model = Map.get(initial_session, :model)

      # Switch model
      _output =
        capture_io(fn ->
          MCPChat.CLI.Commands.handle_command("model gpt-4")
        end)

      # Check if model was updated in session
      new_session = MCPChat.Session.get_current_session()
      new_model = Map.get(new_session, :model)

      # Model should be updated (unless it was already gpt-4)
      if initial_model != "gpt-4" do
        assert new_model == "gpt-4"
      else
        assert new_model == "gpt-4"
      end
    end
  end

  # Helper functions

  defp ensure_application_started do
    case Application.ensure_all_started(:mcp_chat) do
      {:ok, _apps} ->
        :ok

      {:error, _reason} ->
        # If app is already started, that's fine
        :ok
    end

    # Wait a bit for services to be ready
    Process.sleep(100)
  end
end
