defmodule MCPChat.LLM.OllamaTest do
  use ExUnit.Case
  alias MCPChat.LLM.Ollama

  describe "configured?/0" do
    test "checks if Ollama is running" do
      # This will return false if Ollama is not running locally
      result = Ollama.configured?()
      assert is_boolean(result)
    end
  end

  describe "default_model/0" do
    test "returns default model from config or fallback" do
      model = Ollama.default_model()
      assert is_binary(model)
      assert model != ""
    end
  end

  describe "list_models/0" do
    test "attempts to list models from Ollama" do
      case Ollama.list_models() do
        {:ok, models} ->
          assert is_list(models)

          Enum.each(models, fn model ->
            assert Map.has_key?(model, :id)
            assert Map.has_key?(model, :name)
          end)

        {:error, message} ->
          # Ollama not running or accessible
          assert is_binary(message)
      end
    end
  end

  describe "format_messages/1" do
    test "formats messages for Ollama API" do
      messages = [
        %{"role" => "system", "content" => "You are helpful"},
        %{"role" => "user", "content" => "Hello"}
      ]

      formatted = Ollama.format_messages(messages)

      assert formatted == [
               %{role: "system", content: "You are helpful"},
               %{role: "user", content: "Hello"}
             ]
    end

    test "handles empty messages" do
      assert Ollama.format_messages([]) == []
    end
  end

  describe "format_size/1" do
    test "formats bytes to human readable size" do
      assert Ollama.format_size(500) == "500 B"
      assert Ollama.format_size(1_024) == "1.0 KB"
      assert Ollama.format_size(1_536) == "1.5 KB"
      assert Ollama.format_size(1_048_576) == "1.0 MB"
      assert Ollama.format_size(107_374_182_4) == "1.0 GB"
      assert Ollama.format_size(382_679_347_2) == "3.6 GB"
    end

    test "handles zero bytes" do
      assert Ollama.format_size(0) == "0 B"
    end

    test "handles large sizes" do
      tb = 1_024 * 1_024 * 1_024 * 1_024
      assert Ollama.format_size(tb) == "1.0 TB"
    end
  end

  describe "chat/2" do
    @tag :integration
    test "sends chat request if Ollama is running" do
      # This test will only work if Ollama is actually running
      if Ollama.configured?() do
        messages = [%{"role" => "user", "content" => "Say hello"}]

        case Ollama.chat(messages, model: "llama2", max_tokens: 10) do
          {:ok, response} ->
            assert is_binary(response)

          {:error, _reason} ->
            # Model might not be available
            :ok
        end
      else
        :ok
      end
    end
  end

  describe "stream_chat/2" do
    @tag :integration
    test "returns stream if Ollama is running" do
      if Ollama.configured?() do
        messages = [%{"role" => "user", "content" => "Hi"}]

        case Ollama.stream_chat(messages, model: "llama2", max_tokens: 10) do
          {:ok, stream} ->
            assert is_function(stream) or is_struct(stream, Stream)

          {:error, _reason} ->
            # Model might not be available
            :ok
        end
      else
        :ok
      end
    end
  end
end
