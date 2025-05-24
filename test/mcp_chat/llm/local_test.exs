defmodule MCPChat.LLM.LocalTest do
  use ExUnit.Case
  alias MCPChat.LLM.Local

  describe "chat/2" do
    test "returns error when model not loaded" do
      messages = [
        %{"role" => "user", "content" => "Hello"}
      ]

      # Since no model is loaded, this should fail
      assert {:error, _message} = Local.chat(messages, model: "test-model")
    end
  end

  describe "stream_chat/2" do
    test "wraps chat response in a list" do
      messages = [
        %{"role" => "user", "content" => "Hello"}
      ]

      # stream_chat returns the same as chat but wrapped in a list
      assert {:error, _message} = Local.stream_chat(messages)
    end
  end

  describe "configured?/0" do
    test "returns true when ModelLoader is running" do
      # ModelLoader is started by the application, so this should be true
      assert Local.configured?() == true
    end
  end

  describe "default_model/0" do
    test "returns a default model" do
      model = Local.default_model()
      assert is_binary(model)
      assert model != ""
    end
  end

  describe "list_models/0" do
    test "returns available models from HuggingFace" do
      assert {:ok, models} = Local.list_models()
      assert is_list(models)

      # Check some expected models exist
      model_ids = Enum.map(models, & &1.id)
      assert "microsoft/phi-2" in model_ids
      assert "meta-llama/Llama-2-7b-hf" in model_ids
      assert "mistralai/Mistral-7B-v0.1" in model_ids
    end
  end

  describe "load_model/1" do
    @tag :skip
    test "model loading requires ModelLoader GenServer" do
      # This test is skipped because it requires the ModelLoader to be running
      # and would actually try to download models
    end
  end

  describe "unload_model/1" do
    @tag :skip
    test "model unloading requires ModelLoader GenServer" do
      # This test is skipped because it requires the ModelLoader to be running
    end
  end

  describe "loaded_models/0" do
    test "returns list of loaded models" do
      # Without ModelLoader running, this should return empty list
      models = Local.loaded_models()
      assert is_list(models)
    end
  end

  describe "format_prompt/1" do
    test "formats messages into a prompt string" do
      messages = [
        %{"role" => "system", "content" => "You are helpful"},
        %{"role" => "user", "content" => "Hello"},
        %{"role" => "assistant", "content" => "Hi there"},
        %{"role" => "user", "content" => "How are you?"}
      ]

      expected = """
      System: You are helpful

      Human: Hello

      Assistant: Hi there

      Human: How are you?

      Assistant:
      """

      assert Local.format_prompt(messages) == String.trim(expected)
    end

    test "handles empty messages" do
      assert Local.format_prompt([]) == "Assistant:"
    end

    test "handles single user message" do
      messages = [%{"role" => "user", "content" => "Hi"}]

      expected = """
      Human: Hi

      Assistant:
      """

      assert Local.format_prompt(messages) == String.trim(expected)
    end
  end
end
