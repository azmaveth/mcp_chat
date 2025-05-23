defmodule MCPChat.LLM.OpenAI do
  @moduledoc """
  OpenAI API adapter for GPT models.
  """
  @behaviour MCPChat.LLM.Adapter

  @base_url "https://api.openai.com/v1"
  @default_model "gpt-4-turbo-preview"

  @impl true
  def chat(messages, options \\ []) do
    config = get_config()
    model = Keyword.get(options, :model, config.model || @default_model)
    max_tokens = Keyword.get(options, :max_tokens, config.max_tokens || 4096)
    temperature = Keyword.get(options, :temperature, config.temperature || 0.7)
    
    body = %{
      model: model,
      messages: format_messages(messages),
      max_tokens: max_tokens,
      temperature: temperature
    }
    |> maybe_add_system(options)
    
    headers = [
      {"authorization", "Bearer #{get_api_key()}"},
      {"content-type", "application/json"}
    ]
    
    case Req.post("#{@base_url}/chat/completions", json: body, headers: headers) do
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
    temperature = Keyword.get(options, :temperature, config.temperature || 0.7)
    
    body = %{
      model: model,
      messages: format_messages(messages),
      max_tokens: max_tokens,
      temperature: temperature,
      stream: true
    }
    |> maybe_add_system(options)
    
    headers = [
      {"authorization", "Bearer #{get_api_key()}"},
      {"content-type", "application/json"}
    ]
    
    # Create a streaming implementation
    parent = self()
    
    Task.start(fn ->
      case Req.post("#{@base_url}/chat/completions",
        json: body,
        headers: headers,
        receive_timeout: 60_000,
        into: :self
      ) do
        {:ok, response} ->
          if response.status == 200 do
            handle_stream_response(response, parent, "")
          else
            send(parent, {:stream_error, "HTTP #{response.status}: #{inspect(response.body)}"})
          end
          
        {:error, reason} ->
          send(parent, {:stream_error, inspect(reason)})
      end
    end)
    
    # Create stream that receives messages
    stream = Stream.resource(
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
  def default_model do
    config = get_config()
    config.model || @default_model
  end

  @impl true
  def list_models do
    # We could fetch this from the API, but for now return common models
    {:ok, [
      "gpt-4-turbo-preview",
      "gpt-4-turbo",
      "gpt-4",
      "gpt-4-32k",
      "gpt-3.5-turbo",
      "gpt-3.5-turbo-16k"
    ]}
  end

  # Private Functions

  defp get_config do
    MCPChat.Config.get([:llm, :openai]) || %{}
  end

  defp get_api_key do
    config = get_config()
    
    # First try config file
    case Map.get(config, :api_key) do
      nil -> System.get_env("OPENAI_API_KEY")
      "" -> System.get_env("OPENAI_API_KEY")
      key -> key
    end
  end

  defp format_messages(messages) do
    messages
    |> Enum.map(fn msg ->
      %{
        "role" => to_string(msg.role || msg["role"]),
        "content" => to_string(msg.content || msg["content"])
      }
    end)
  end

  defp maybe_add_system(body, options) do
    # OpenAI includes system messages in the messages array
    # So this is a no-op for compatibility
    case Keyword.get(options, :system) do
      nil -> body
      system -> 
        # Prepend system message to messages array
        messages = [%{"role" => "system", "content" => system} | body.messages]
        Map.put(body, :messages, messages)
    end
  end

  defp parse_response(response) do
    choice = get_in(response, ["choices", Access.at(0)]) || %{}
    
    %{
      content: get_in(choice, ["message", "content"]) || "",
      finish_reason: choice["finish_reason"],
      usage: response["usage"]
    }
  end

  defp parse_sse_event("data: [DONE]"), do: %{delta: "", finish_reason: "stop"}
  defp parse_sse_event("data: " <> json) do
    case Jason.decode(json) do
      {:ok, data} ->
        choice = get_in(data, ["choices", Access.at(0)]) || %{}
        delta = choice["delta"] || %{}
        
        %{
          delta: delta["content"] || "",
          finish_reason: choice["finish_reason"]
        }
      
      _ -> nil
    end
  end
  defp parse_sse_event(_), do: nil

  defp process_sse_chunks(data) do
    lines = String.split(data, "\n")
    {complete_lines, rest} = 
      case List.last(lines) do
        "" -> {lines, ""}
        last_line -> {Enum.drop(lines, -1), last_line}
      end
    
    chunks = complete_lines
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