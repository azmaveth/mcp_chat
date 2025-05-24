defmodule MCPChat.LLM.Gemini do
  @moduledoc """
  Google Gemini API adapter.
  Supports Gemini Pro, Pro Vision, and other variants.

  ## Configuration Injection

  The adapter supports configuration injection through the `:config_provider` option:

      # Use default configuration from application config
      MCPChat.LLM.Gemini.chat(messages)

      # Use custom configuration provider
      custom_provider = %{
        get_config: fn [:llm, :gemini] ->
          %{api_key: "custom-key", model: "gemini-pro"}
        end
      }

      MCPChat.LLM.Gemini.chat(messages, config_provider: custom_provider)
  """
  @behaviour MCPChat.LLM.Adapter

  require Logger

  @base_url "https://generativelanguage.googleapis.com"
  @api_version "v1beta"
  @default_model "gemini-pro"

  # Available models
  @models %{
    "gemini-pro" => %{
      name: "Gemini Pro",
      supports_vision: false,
      max_tokens: 2048
    },
    "gemini-pro-vision" => %{
      name: "Gemini Pro Vision",
      supports_vision: true,
      max_tokens: 2048
    },
    "gemini-ultra" => %{
      name: "Gemini Ultra",
      supports_vision: true,
      max_tokens: 8_192
    },
    "gemini-nano" => %{
      name: "Gemini Nano",
      supports_vision: false,
      max_tokens: 1_024
    }
  }

  @impl true
  def chat(messages, options \\ []) do
    config_provider = Keyword.get(options, :config_provider, MCPChat.ConfigProvider.Default)
    config = get_config(config_provider)
    model = Keyword.get(options, :model, config[:model] || @default_model)

    with {:ok, api_key} <- get_api_key(config_provider),
         {:ok, request_body} <- build_request_body(messages, options),
         {:ok, response} <- call_gemini_api(model, request_body, api_key) do
      parse_response(response)
    end
  end

  @impl true
  def stream_chat(messages, options \\ []) do
    config_provider = Keyword.get(options, :config_provider, MCPChat.ConfigProvider.Default)
    config = get_config(config_provider)
    model = Keyword.get(options, :model, config[:model] || @default_model)

    with {:ok, api_key} <- get_api_key(config_provider),
         {:ok, request_body} <- build_request_body(messages, options) do
      stream_gemini_api(model, request_body, api_key)
    end
  end

  @impl true
  def configured? do
    case get_api_key(MCPChat.ConfigProvider.Default) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @impl true
  def default_model() do
    config = get_config(MCPChat.ConfigProvider.Default)
    config[:model] || @default_model
  end

  @impl true
  def list_models() do
    models =
      @models
      |> Enum.map(fn {id, info} ->
        %{
          id: id,
          name: info.name,
          supports_vision: info.supports_vision,
          max_tokens: info.max_tokens
        }
      end)
      |> Enum.sort_by(& &1.id)

    {:ok, models}
  end

  # Private functions

  defp get_config(config_provider) do
    case config_provider do
      MCPChat.ConfigProvider.Default ->
        MCPChat.Config.get([:llm, :gemini]) || %{}

      provider when is_pid(provider) ->
        # Static provider (Agent pid)
        MCPChat.ConfigProvider.Static.get(provider, [:llm, :gemini]) || %{}

      provider ->
        # Custom provider module
        provider.get([:llm, :gemini]) || %{}
    end
  end

  defp get_api_key(config_provider) do
    config = get_config(config_provider)

    case config[:api_key] || System.get_env("GOOGLE_API_KEY") do
      nil -> {:error, "Google API key not configured"}
      "" -> {:error, "Google API key is empty"}
      key -> {:ok, key}
    end
  end

  defp build_request_body(messages, options) do
    contents = format_messages_for_gemini(messages)

    generation_config = %{
      temperature: Keyword.get(options, :temperature, 0.7),
      topP: Keyword.get(options, :top_p, 0.95),
      topK: Keyword.get(options, :top_k, 40),
      maxOutputTokens: Keyword.get(options, :max_tokens, 2048)
    }

    # Safety settings
    safety_settings = get_safety_settings(options)

    body = %{
      contents: contents,
      generationConfig: generation_config
    }

    body = if safety_settings, do: Map.put(body, :safetySettings, safety_settings), else: body

    {:ok, body}
  end

  defp format_messages_for_gemini(messages) do
    messages
    |> Enum.map(fn msg ->
      role =
        case msg["role"] do
          # Gemini doesn't have system role, prepend to first user
          "system" -> "user"
          "assistant" -> "model"
          role -> role
        end

      %{
        role: role,
        parts: format_content_parts(msg["content"])
      }
    end)
    |> merge_system_messages()
  end

  defp format_content_parts(content) when is_binary(content) do
    [%{text: content}]
  end

  defp format_content_parts(content) when is_list(content) do
    # Handle multimodal content
    Enum.map(content, fn part ->
      case part do
        %{"type" => "text", "text" => text} ->
          %{text: text}

        %{"type" => "image", "source" => source} ->
          %{
            inlineData: %{
              mimeType: source["mime_type"] || "image/jpeg",
              # Base64 encoded
              data: source["data"]
            }
          }

        _ ->
          nil
      end
    end)
    |> Enum.filter(& &1)
  end

  defp merge_system_messages(messages) do
    # Merge system messages into the first user message
    case messages do
      [%{role: "user", parts: parts} = first | rest] ->
        system_parts =
          messages
          |> Enum.take_while(&(&1.role == "user"))
          |> Enum.drop(1)
          |> Enum.flat_map(& &1.parts)

        if length(system_parts) > 0 do
          merged_first = %{first | parts: system_parts ++ parts}
          [merged_first | Enum.drop_while(rest, &(&1.role == "user"))]
        else
          messages
        end

      _ ->
        messages
    end
  end

  defp get_safety_settings(options) do
    case Keyword.get(options, :safety_settings) do
      nil ->
        # Default safety settings
        [
          %{
            category: "HARM_CATEGORY_HARASSMENT",
            threshold: "BLOCK_MEDIUM_AND_ABOVE"
          },
          %{
            category: "HARM_CATEGORY_HATE_SPEECH",
            threshold: "BLOCK_MEDIUM_AND_ABOVE"
          },
          %{
            category: "HARM_CATEGORY_SEXUALLY_EXPLICIT",
            threshold: "BLOCK_MEDIUM_AND_ABOVE"
          },
          %{
            category: "HARM_CATEGORY_DANGEROUS_CONTENT",
            threshold: "BLOCK_MEDIUM_AND_ABOVE"
          }
        ]

      settings ->
        settings
    end
  end

  defp call_gemini_api(model, request_body, api_key) do
    url = build_url(model, "generateContent", api_key)

    headers = [
      {"Content-Type", "application/json"}
    ]

    case Req.post(url, json: request_body, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        error_message = extract_error_message(body)
        {:error, "Gemini API error (#{status}): #{error_message}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp stream_gemini_api(model, request_body, api_key) do
    url = build_url(model, "streamGenerateContent", api_key)

    headers = [
      {"Content-Type", "application/json"}
    ]

    # Create a stream that makes the API call
    stream =
      Stream.resource(
        fn -> start_streaming(url, request_body, headers) end,
        fn state -> read_stream_chunk(state) end,
        fn state -> cleanup_stream(state) end
      )

    {:ok, stream}
  end

  defp build_url(model, method, api_key) do
    "#{@base_url}/#{@api_version}/models/#{model}:#{method}?key=#{api_key}"
  end

  defp parse_response(%{"candidates" => [candidate | _]}) do
    case candidate do
      %{"content" => %{"parts" => parts}} ->
        text =
          parts
          |> Enum.map_join(fn %{"text" => text} -> text end, "")

        {:ok, text}

      %{"finishReason" => reason} when reason in ["SAFETY", "RECITATION"] ->
        {:error, "Response blocked: #{reason}"}

      _ ->
        {:error, "Unexpected response format"}
    end
  end

  defp parse_response(%{"error" => error}) do
    {:error, "Gemini API error: #{error["message"]}"}
  end

  defp parse_response(_) do
    {:error, "Invalid response format"}
  end

  defp extract_error_message(%{"error" => %{"message" => message}}) do
    message
  end

  defp extract_error_message(body) when is_map(body) do
    Jason.encode!(body)
  end

  defp extract_error_message(body) do
    inspect(body)
  end

  # Streaming helpers
  defp start_streaming(url, body, headers) do
    # Start SSE streaming request
    {:ok, resp} =
      Req.post(url,
        json: body,
        headers: headers ++ [{"Accept", "text/event-stream"}],
        into: :self,
        receive_timeout: :infinity
      )

    %{
      response: resp,
      buffer: "",
      done: false
    }
  end

  defp read_stream_chunk(%{done: true} = state) do
    {:halt, state}
  end

  defp read_stream_chunk(state) do
    receive do
      {:data, data} ->
        # Parse SSE data
        {chunks, new_buffer} = parse_sse_data(state.buffer <> data)

        response_chunks =
          chunks
          |> Enum.map(&parse_streaming_chunk/1)
          |> Enum.filter(& &1)

        {response_chunks, %{state | buffer: new_buffer}}

      {:done, _ref} ->
        # Final chunk
        final_chunk = %{delta: "", finish_reason: "stop"}
        {[final_chunk], %{state | done: true}}

      {:error, reason} ->
        Logger.error("Streaming error: #{inspect(reason)}")
        {:halt, state}
    after
      30_000 ->
        Logger.error("Streaming timeout")
        {:halt, state}
    end
  end

  defp cleanup_stream(state) do
    # Cleanup any remaining response
    if state.response do
      # Cancel the request if still active
      :ok
    end
  end

  defp parse_sse_data(data) do
    lines = String.split(data, "\n")

    {complete_chunks, remaining} =
      lines
      |> Enum.reduce({[], ""}, fn line, {chunks, buffer} ->
        cond do
          String.starts_with?(line, "data: ") ->
            json_data = String.replace_prefix(line, "data: ", "")

            if json_data != "[DONE]" do
              {[json_data | chunks], buffer}
            else
              {chunks, buffer}
            end

          line == "" ->
            {chunks, buffer}

          true ->
            {chunks, buffer <> line}
        end
      end)

    {Enum.reverse(complete_chunks), remaining}
  end

  defp parse_streaming_chunk(json_data) do
    case Jason.decode(json_data) do
      {:ok, %{"candidates" => [%{"content" => %{"parts" => parts}} | _]}} ->
        text =
          parts
          |> Enum.map_join(fn %{"text" => text} -> text end, "")

        %{delta: text, finish_reason: nil}

      {:ok, %{"candidates" => [%{"finishReason" => reason} | _]}} ->
        %{delta: "", finish_reason: reason}

      _ ->
        nil
    end
  end
end
