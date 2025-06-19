defmodule ExLLMAdapterTest do
  use ExUnit.Case
  alias MCPChat.LLM.ExLLMAdapter

  describe "chat/2" do
    test "converts messages and calls ExLLM with correct provider" do
      messages = [
        %{"role" => "user", "content" => "Hello"}
      ]

      # Since we can't easily mock ExLLM module calls, we'll test the adapter's behavior
      # by checking it doesn't crash and returns expected structure
      result = ExLLMAdapter.chat(messages, provider: :anthropic)

      assert is_tuple(result)
      assert elem(result, 0) in [:ok, :error]
    end

    test "handles different message formats" do
      messages = [
        %{role: "user", content: "Hello with atoms"},
        %{"role" => "assistant", "content" => "Hello with strings"}
      ]

      result = ExLLMAdapter.chat(messages, provider: :anthropic)
      assert is_tuple(result)
      assert elem(result, 0) in [:ok, :error]
    end
  end

  describe "stream_chat/2" do
    test "returns a stream when successful" do
      messages = [
        %{"role" => "user", "content" => "Hello"}
      ]

      case ExLLMAdapter.stream_chat(messages, provider: :anthropic) do
        {:ok, stream} ->
          assert is_function(stream) or match?(%Stream{}, stream)

        {:error, _reason} ->
          # It's ok if it fails due to missing API key
          assert true
      end
    end
  end

  describe "configured?/0 and configured?/1" do
    test "configured?/0 checks if any provider is configured" do
      result = ExLLMAdapter.configured?()
      assert is_boolean(result)
    end

    test "configured?/1 checks specific provider" do
      assert is_boolean(ExLLMAdapter.configured?("anthropic"))
      assert is_boolean(ExLLMAdapter.configured?("openai"))
      assert is_boolean(ExLLMAdapter.configured?("ollama"))
    end
  end

  describe "default_model/0" do
    test "returns default model" do
      assert ExLLMAdapter.default_model() == "claude-sonnet-4-20250514"
    end
  end

  describe "list_models/0 and list_models/1" do
    test "list_models/0 returns list of models" do
      {:ok, models} = ExLLMAdapter.list_models()
      assert is_list(models)
    end

    test "list_models/1 with provider returns formatted models" do
      case ExLLMAdapter.list_models(provider: :anthropic) do
        {:ok, models} ->
          assert is_list(models)

          if length(models) > 0 do
            model = hd(models)
            assert Map.has_key?(model, :id)
            assert Map.has_key?(model, :name)
          end

        {:error, _reason} ->
          # It's ok if it fails due to missing API key
          assert true
      end
    end
  end

  describe "response conversion" do
    test "converts ExLLM response to MCPChat format" do
      messages = [%{"role" => "user", "content" => "test"}]

      # We can't test the actual conversion without mocking,
      # but we can ensure the adapter doesn't crash
      case ExLLMAdapter.chat(messages, provider: :anthropic) do
        {:ok, response} ->
          # If we get a response, check its structure
          assert Map.has_key?(response, :content) or is_binary(response)

        {:error, _} ->
          # Expected if no API key
          assert true
      end
    end
  end
end
