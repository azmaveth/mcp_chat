defmodule MCPChat.LLM.Anthropic do
  @moduledoc """
  Anthropic Claude API adapter.
  """
  @behaviour MCPChat.LLM.Adapter

  @base_url "https://api.anthropic.com/v1"
  @default_model "claude-sonnet-4-20_250_514"

  @impl true
  def chat(messages, options \\ []) do
    config = get_config()
    model = Keyword.get(options, :model, config.model || @default_model)
    max_tokens = Keyword.get(options, :max_tokens, config.max_tokens || 4_096)

    # Convert messages to Anthropic format
    formatted_messages = format_messages_for_anthropic(messages)

    body =
      %{
        model: model,
        messages: formatted_messages,
        max_tokens: max_tokens
      }
      |> maybe_add_system(options)

    headers = [
      {"x-api-key", get_api_key()},
      {"anthropic-version", "2_023-06-01"},
      {"content-type", "application/json"}
    ]

    case Req.post("#{@base_url}/messages", json: body, headers: headers) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, parse_response(response)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def stream_chat(messages, options \\ []) do
    config = get_config()
    model = Keyword.get(options, :model, config.model || @default_model)
    max_tokens = Keyword.get(options, :max_tokens, config.max_tokens || 4_096)

    # Convert messages to Anthropic format
    formatted_messages = format_messages_for_anthropic(messages)

    body =
      %{
        model: model,
        messages: formatted_messages,
        max_tokens: max_tokens,
        stream: true
      }
      |> maybe_add_system(options)

    headers = [
      {"x-api-key", get_api_key()},
      {"anthropic-version", "2_023-06-01"},
      {"content-type", "application/json"}
    ]

    # Create a simple streaming implementation
    parent = self()

    Task.start(fn ->
      case Req.post("#{@base_url}/messages",
             json: body,
             headers: headers,
             receive_timeout: 60_000,
             into: :self
           ) do
        {:ok, response} ->
          if response.status == 200 do
            handle_stream_response(response, parent, "")
          else
            send(parent, {:stream_error, "HTTP #{response.status}"})
          end

        {:error, reason} ->
          send(parent, {:stream_error, inspect(reason)})
      end
    end)

    # Create stream that receives messages
    stream =
      Stream.resource(
        fn -> :ok end,
        fn state ->
          receive do
            {:chunk, chunk} -> {[chunk], state}
            :stream_done -> {:halt, state}
            {:stream_error, error} -> throw({:error, error})
          after
            100 -> {[], state}
          end
        end,
        fn _ -> :ok end
      )

    {:ok, stream}
  end

  @impl true
  def configured? do
    api_key = get_api_key()
    api_key != nil and api_key != ""
  end

  @impl true
  def default_model() do
    config = get_config()
    config.model || @default_model
  end

  def available_models() do
    [
      "claude-sonnet-4-20250514",
      "claude-opus-3-20240229",
      "claude-sonnet-3.5-20241022",
      "claude-sonnet-3.5-20240620",
      "claude-3-5-haiku-20241022",
      "claude-haiku-3-20240307"
    ]
  end

  @impl true
  def list_models() do
    {:ok,
     [
       "claude-sonnet-4-20_250_514",
       "claude-opus-4-20_250_514",
       "claude-3-5-sonnet-20_241_022",
       "claude-3-5-haiku-20_241_022",
       "claude-3-opus-20_240_229",
       "claude-3-sonnet-20_240_229",
       "claude-3-haiku-20_240_307"
     ]}
  end

  # Private Functions

  defp get_config() do
    MCPChat.Config.get([:llm, :anthropic]) || %{}
  end

  defp get_api_key() do
    config = get_config()

    # First try config file
    case Map.get(config, :api_key) do
      nil -> System.get_env("ANTHROPIC_API_KEY")
      "" -> System.get_env("ANTHROPIC_API_KEY")
      key -> key
    end
  end

  defp maybe_add_system(body, options) do
    case Keyword.get(options, :system) do
      nil -> body
      system -> Map.put(body, :system, system)
    end
  end

  defp parse_response(response) do
    %{
      content: get_in(response, ["content", Access.at(0), "text"]) || "",
      finish_reason: response["stop_reason"],
      usage: response["usage"]
    }
  end

  defp parse_sse_event("data: [DONE]"), do: nil

  defp parse_sse_event("data: " <> json) do
    case Jason.decode(json) do
      {:ok, %{"type" => "content_block_delta", "delta" => %{"text" => text}}} ->
        %{delta: text, finish_reason: nil}

      {:ok, %{"type" => "message_stop"}} ->
        %{delta: "", finish_reason: "stop"}

      {:ok, %{"type" => "error", "error" => error}} ->
        # Log error and skip
        IO.inspect(error, label: "Anthropic API Error")
        nil

      _ ->
        nil
    end
  end

  defp format_messages_for_anthropic(messages) do
    messages
    |> Enum.map(fn msg ->
      # Ensure we have string keys and proper format
      %{
        "role" => to_string(msg.role || msg["role"]),
        "content" => to_string(msg.content || msg["content"])
      }
    end)
  end

  defp process_sse_chunks(data) do
    lines = String.split(data, "\n")

    {complete_lines, rest} =
      case List.last(lines) do
        "" -> {lines, ""}
        last_line -> {Enum.drop(lines, -1), last_line}
      end

    chunks =
      complete_lines
      |> Enum.filter(&String.starts_with?(&1, "data: "))
      |> Enum.map(&parse_sse_event/1)
      |> Enum.reject(&is_nil/1)

    {rest, chunks}
  end

  defp handle_stream_response(response, parent, buffer) do
    # The async ref is in the body when using into: :self
    %Req.Response.Async{ref: ref} = response.body

    receive do
      {^ref, {:data, data}} ->
        {new_buffer, chunks} = process_sse_chunks(buffer <> data)
        Enum.each(chunks, &send(parent, {:chunk, &1}))
        handle_stream_response(response, parent, new_buffer)

      {^ref, :done} ->
        send(parent, :stream_done)

      {^ref, {:error, reason}} ->
        send(parent, {:stream_error, inspect(reason)})
    after
      30_000 ->
        send(parent, {:stream_error, "Stream timeout"})
    end
  end
end
