defmodule MCPChat.LLM.Local do
  @moduledoc """
  Local LLM adapter using Bumblebee for on-device inference.
  """

  @behaviour MCPChat.LLM.Adapter

  require Logger
  alias MCPChat.LLM.ModelLoader
  alias MCPChat.Context

  @impl true
  def chat(messages, opts \\ []) do
    model = Keyword.get(opts, :model, "microsoft/phi-2")
    stream = Keyword.get(opts, :stream, true)
    max_tokens = Keyword.get(opts, :max_tokens, 2048)
    temperature = Keyword.get(opts, :temperature, 0.7)

    # Format messages for the model
    prompt = format_messages(messages, model)

    # Get or load the model
    case ModelLoader.load_model(model) do
      {:ok, model_data} ->
        generate_response(prompt, model_data, %{
          stream: stream,
          max_tokens: max_tokens,
          temperature: temperature
        })

      {:error, reason} ->
        {:error, "Failed to load model: #{inspect(reason)}"}
    end
  end

  @impl true
  def configured? do
    # Check if at least one model is loaded
    case Process.whereis(MCPChat.LLM.ModelLoader) do
      nil -> false
      _pid -> true
    end
  end

  @impl true
  def list_models() do
    # Return loaded models and available models in a structured format
    loaded = ModelLoader.list_loaded_models()
    available = available_models()
    acceleration = ModelLoader.get_acceleration_info()

    # Convert to map format for consistency
    available_maps =
      Enum.map(available, fn model_id ->
        %{
          id: model_id,
          name: humanize_model_name(model_id),
          status: if(model_id in loaded, do: "loaded", else: "available"),
          acceleration: acceleration.name
        }
      end)

    # Add any loaded models that aren't in the available list
    loaded_only = loaded -- available

    loaded_maps =
      Enum.map(loaded_only, fn model_id ->
        %{
          id: model_id,
          name: humanize_model_name(model_id),
          status: "loaded",
          acceleration: acceleration.name
        }
      end)

    {:ok, available_maps ++ loaded_maps}
  end

  defp humanize_model_name(model_id) do
    case model_id do
      "microsoft/phi-2" -> "Phi-2 (2.7B)"
      "meta-llama/Llama-2-7b-hf" -> "Llama 2 (7B)"
      "mistralai/Mistral-7B-v0.1" -> "Mistral (7B)"
      "EleutherAI/gpt-neo-1.3B" -> "GPT-Neo (1.3B)"
      "google/flan-t5-base" -> "Flan-T5 Base"
      _ -> model_id
    end
  end

  @impl true
  def stream_chat(messages, opts \\ []) do
    # For now, just use the chat function and wrap in a stream
    case chat(messages, opts) do
      {:ok, chunks} when is_list(chunks) ->
        {:ok, chunks}

      {:ok, response} ->
        {:ok, [response]}

      error ->
        error
    end
  end

  def count_tokens(text, opts \\ []) do
    model = Keyword.get(opts, :model, "microsoft/phi-2")

    case ModelLoader.get_model_info(model) do
      {:ok, %{tokenizer: tokenizer}} ->
        # Use Bumblebee tokenizer to count tokens
        {:ok, inputs} = Bumblebee.apply_tokenizer(tokenizer, text)
        token_count = Nx.size(inputs["input_ids"])
        {:ok, token_count}

      {:error, :not_loaded} ->
        # Fallback to estimation if model not loaded
        Context.estimate_tokens(text)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def supports_streaming?, do: true

  @impl true
  def default_model, do: "microsoft/phi-2"

  def available_models() do
    [
      "microsoft/phi-2",
      "meta-llama/Llama-2-7b-hf",
      "mistralai/Mistral-7B-v0.1",
      "EleutherAI/gpt-neo-1.3B",
      "google/flan-t5-base"
    ]
  end

  def model_info(model_name) do
    %{
      name: model_name,
      context_window: get_context_window(model_name),
      supports_functions: false,
      supports_vision: false
    }
  end

  # Private functions

  defp format_messages(messages, model) do
    # Format messages based on model requirements
    case model do
      "meta-llama/Llama-2" <> _ ->
        format_llama2_messages(messages)

      "mistralai/Mistral" <> _ ->
        format_mistral_messages(messages)

      _ ->
        # Generic format
        messages
        |> Enum.map(fn msg ->
          role = String.capitalize(to_string(msg["role"]))
          "#{role}: #{msg["content"]}"
        end)
        |> Enum.join("\n\n")
    end
  end

  defp format_llama2_messages(messages) do
    # Llama 2 specific format
    messages
    |> Enum.map_join(
      fn msg ->
        case msg["role"] do
          "system" -> "<<SYS>>\n#{msg["content"]}\n<</SYS>>\n\n"
          "user" -> "[INST] #{msg["content"]} [/INST]"
          "assistant" -> msg["content"]
          _ -> msg["content"]
        end
      end,
      "\n"
    )
  end

  defp format_mistral_messages(messages) do
    # Mistral specific format
    messages
    |> Enum.map_join(
      fn msg ->
        case msg["role"] do
          "user" -> "[INST] #{msg["content"]} [/INST]"
          "assistant" -> msg["content"]
          _ -> msg["content"]
        end
      end,
      "\n"
    )
  end

  defp generate_response(prompt, model_data, opts) do
    %{serving: serving} = model_data

    if opts.stream do
      # Stream the response
      stream =
        Task.async(fn ->
          try do
            serving
            |> Nx.Serving.run(%{text: prompt})
            |> Stream.map(fn chunk ->
              {:data, %{"content" => chunk.text}}
            end)
            |> Enum.to_list()
          rescue
            e ->
              Logger.error("Error during generation: #{inspect(e)}")
              [{:error, "Generation failed: #{inspect(e)}"}]
          end
        end)

      {:ok, Task.await(stream, :infinity)}
    else
      # Non-streaming response
      try do
        result = Nx.Serving.run(serving, %{text: prompt})
        {:ok, %{"content" => result.text}}
      rescue
        e ->
          Logger.error("Error during generation: #{inspect(e)}")
          {:error, "Generation failed: #{inspect(e)}"}
      end
    end
  end

  defp get_context_window(model) do
    case model do
      "meta-llama/Llama-2" <> _ -> 4_096
      "mistralai/Mistral" <> _ -> 8_192
      "microsoft/phi-2" -> 2048
      "EleutherAI/gpt-neo-1.3B" -> 2048
      "google/flan-t5-base" -> 512
      _ -> 2048
    end
  end
end
