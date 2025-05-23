defmodule MCPChat.LLM.Anthropic do
  @moduledoc """
  Anthropic Claude API adapter.
  """
  @behaviour MCPChat.LLM.Adapter

  @base_url "https://api.anthropic.com/v1"
  @default_model "claude-3-sonnet-20240229"

  @impl true
  def chat(messages, options \\ []) do
    config = get_config()
    model = Keyword.get(options, :model, config.model || @default_model)
    max_tokens = Keyword.get(options, :max_tokens, config.max_tokens || 4096)
    
    body = %{
      model: model,
      messages: messages,
      max_tokens: max_tokens
    }
    |> maybe_add_system(options)
    
    headers = [
      {"x-api-key", config.api_key},
      {"anthropic-version", "2023-06-01"},
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
    max_tokens = Keyword.get(options, :max_tokens, config.max_tokens || 4096)
    
    body = %{
      model: model,
      messages: messages,
      max_tokens: max_tokens,
      stream: true
    }
    |> maybe_add_system(options)
    
    headers = [
      {"x-api-key", config.api_key},
      {"anthropic-version", "2023-06-01"},
      {"content-type", "application/json"}
    ]
    
    stream = Stream.resource(
      fn -> start_stream(body, headers) end,
      &stream_next/1,
      &close_stream/1
    )
    
    {:ok, stream}
  end

  @impl true
  def configured? do
    config = get_config()
    config.api_key != nil and config.api_key != ""
  end

  @impl true
  def default_model do
    config = get_config()
    config.model || @default_model
  end

  @impl true
  def list_models do
    {:ok, [
      "claude-3-opus-20240229",
      "claude-3-sonnet-20240229",
      "claude-3-haiku-20240307",
      "claude-2.1",
      "claude-2.0"
    ]}
  end

  # Private Functions

  defp get_config do
    MCPChat.Config.get([:llm, :anthropic]) || %{}
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

  defp start_stream(body, headers) do
    case Req.post("#{@base_url}/messages", json: body, headers: headers, into: :self) do
      {:ok, resp} -> {:ok, resp, ""}
      {:error, reason} -> {:error, reason}
    end
  end

  defp stream_next({:error, _reason} = error), do: {:halt, error}
  defp stream_next({:ok, %{status: status}, _buffer}) when status != 200 do
    {:halt, {:error, {:api_error, status}}}
  end
  defp stream_next({:ok, resp, buffer}) do
    receive do
      {ref, {:data, data}} when ref == resp.async.ref ->
        lines = (buffer <> data)
        |> String.split("\n")
        
        {complete_lines, [last_line]} = Enum.split(lines, -1)
        
        events = complete_lines
        |> Enum.filter(&String.starts_with?(&1, "data: "))
        |> Enum.map(&parse_sse_event/1)
        |> Enum.reject(&is_nil/1)
        
        {events, {:ok, resp, last_line}}
      
      {ref, :done} when ref == resp.async.ref ->
        {:halt, {:ok, resp, buffer}}
    after
      30_000 -> {:halt, {:error, :timeout}}
    end
  end

  defp parse_sse_event("data: [DONE]"), do: nil
  defp parse_sse_event("data: " <> json) do
    case Jason.decode(json) do
      {:ok, %{"type" => "content_block_delta", "delta" => %{"text" => text}}} ->
        %{delta: text, finish_reason: nil}
      
      {:ok, %{"type" => "message_stop"}} ->
        %{delta: "", finish_reason: "stop"}
      
      _ -> nil
    end
  end

  defp close_stream({:ok, _resp, _buffer}), do: :ok
  defp close_stream(_), do: :ok
end