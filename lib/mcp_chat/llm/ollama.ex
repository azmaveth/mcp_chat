defmodule MCPChat.LLM.Ollama do
  @moduledoc """
  Ollama LLM adapter for local model inference via Ollama server.
  """

  @behaviour MCPChat.LLM.Adapter

  require Logger

  @default_base_url "http://localhost:11_434"
  @default_model "llama2"

  @impl true
  def chat(messages, opts \\ []) do
    model = Keyword.get(opts, :model, get_default_model())
    stream = Keyword.get(opts, :stream, false)

    body = %{
      model: model,
      messages: format_messages(messages),
      stream: stream
    }

    headers = [{"Content-Type", "application/json"}]
    base_url = get_base_url()

    if stream do
      stream_chat(messages, opts)
    else
      case Req.post("#{base_url}/api/chat", json: body, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          {:ok, parse_response(response)}

        {:ok, %{status: status, body: body}} ->
          {:error, "Ollama API error (#{status}): #{inspect(body)}"}

        {:error, reason} ->
          {:error, "Failed to connect to Ollama: #{inspect(reason)}"}
      end
    end
  end

  @impl true
  def stream_chat(messages, opts \\ []) do
    model = Keyword.get(opts, :model, get_default_model())

    body = %{
      model: model,
      messages: format_messages(messages),
      stream: true
    }

    headers = [{"Content-Type", "application/json"}]
    base_url = get_base_url()

    parent = self()

    Task.start(fn ->
      case Req.post("#{base_url}/api/chat",
             json: body,
             headers: headers,
             into: :self
           ) do
        {:ok, response} ->
          ref = make_ref()
          send(parent, {:stream_start, ref})

          receive_loop(parent, ref, response)

        {:error, reason} ->
          send(parent, {:error, "Failed to connect to Ollama: #{inspect(reason)}"})
      end
    end)

    receive do
      {:stream_start, ref} ->
        {:ok, stream_receiver(ref)}

      {:error, reason} ->
        {:error, reason}
    after
      5_000 -> {:error, "Stream start timeout"}
    end
  end

  @impl true
  def configured? do
    # Check if Ollama is running
    case check_ollama_status() do
      :ok -> true
      _ -> false
    end
  end

  @impl true
  def default_model() do
    get_config()[:model] || @default_model
  end

  @impl true
  def list_models() do
    base_url = get_base_url()

    case Req.get("#{base_url}/api/tags") do
      {:ok, %{status: 200, body: body}} ->
        models =
          body["models"]
          |> Enum.map(fn model ->
            %{
              id: model["name"],
              name: model["name"],
              size: format_size(model["size"]),
              modified_at: model["modified_at"]
            }
          end)

        {:ok, models}

      {:error, reason} ->
        {:error, "Failed to fetch models: #{inspect(reason)}"}
    end
  end

  def format_messages(messages) do
    Enum.map(messages, fn msg ->
      %{
        role: msg["role"] || "user",
        content: msg["content"] || ""
      }
    end)
  end

  def format_size(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_099_511_627_776 -> "#{Float.round(bytes / 1_099_511_627_776, 1)} TB"
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 1)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      bytes >= 1_024 -> "#{Float.round(bytes / 1_024, 1)} KB"
      true -> "#{bytes} B"
    end
  end

  def format_size(_), do: "Unknown"

  # Private functions

  defp get_config() do
    MCPChat.Config.get([:llm, :ollama]) || %{}
  end

  defp get_base_url() do
    config = get_config()

    # Check environment variable first
    case System.get_env("OLLAMA_API_BASE") do
      nil -> config[:base_url] || @default_base_url
      url -> url
    end
  end

  defp get_default_model() do
    config = get_config()
    config[:model] || @default_model
  end

  defp check_ollama_status() do
    base_url = get_base_url()

    case Req.get("#{base_url}/api/tags", receive_timeout: 2000) do
      {:ok, %{status: 200}} -> :ok
      _ -> :error
    end
  end

  # Removed - now public function above

  defp parse_response(response) do
    %{
      content: response["message"]["content"] || "",
      finish_reason: if(response["done"], do: "stop", else: nil),
      usage: %{
        prompt_tokens: response["prompt_eval_count"],
        completion_tokens: response["eval_count"],
        total_tokens: (response["prompt_eval_count"] || 0) + (response["eval_count"] || 0)
      }
    }
  end

  defp receive_loop(parent, ref, %{status: 200} = response) do
    receive do
      {:data, data} ->
        # Parse each line of the streaming response
        data
        |> String.split("\n", trim: true)
        |> Enum.each(fn line ->
          case Jason.decode(line) do
            {:ok, chunk} ->
              if chunk["done"] do
                send(parent, {:stream_end, ref})
              else
                message = chunk["message"]["content"] || ""
                send(parent, {:stream_chunk, ref, {:data, %{"content" => message}}})
              end

            {:error, _} ->
              # Skip invalid JSON lines
              :ok
          end
        end)

        receive_loop(parent, ref, response)

      :done ->
        send(parent, {:stream_end, ref})

      other ->
        Logger.warning("Unexpected message in Ollama stream: #{inspect(other)}")
        receive_loop(parent, ref, response)
    end
  end

  defp receive_loop(parent, _ref, response) do
    send(parent, {:error, "Ollama returned status #{response.status}"})
  end

  defp stream_receiver(ref) do
    Stream.resource(
      fn -> ref end,
      fn ref ->
        receive do
          {:stream_chunk, ^ref, chunk} -> {[chunk], ref}
          {:stream_end, ^ref} -> {:halt, ref}
          {:error, reason} -> {[{:error, reason}], ref}
        after
          30_000 -> {:halt, ref}
        end
      end,
      fn _ref -> :ok end
    )
  end

  # Removed - now public function above
end
