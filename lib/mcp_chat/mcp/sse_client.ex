defmodule MCPChat.MCP.SSEClient do
  @moduledoc """
  MCP client that communicates with servers via Server-Sent Events (SSE) over HTTP.
  """
  use GenServer
  
  # alias MCPChat.MCP.Protocol
  
  require Logger

  defstruct [
    :name,
    :base_url,
    :sse_url,
    :message_url,
    :capabilities,
    :server_info,
    :sse_pid,
    :pending_requests,
    :request_id
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def initialize(pid) do
    GenServer.call(pid, :initialize, 30_000)
  end

  def list_tools(pid) do
    GenServer.call(pid, :list_tools, 10_000)
  end

  def call_tool(pid, name, arguments) do
    GenServer.call(pid, {:call_tool, name, arguments}, 30_000)
  end

  def list_resources(pid) do
    GenServer.call(pid, :list_resources, 10_000)
  end

  def read_resource(pid, uri) do
    GenServer.call(pid, {:read_resource, uri}, 30_000)
  end

  def list_prompts(pid) do
    GenServer.call(pid, :list_prompts, 10_000)
  end

  def get_prompt(pid, name, arguments \\ %{}) do
    GenServer.call(pid, {:get_prompt, name, arguments}, 10_000)
  end

  def shutdown(pid) do
    GenServer.stop(pid)
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    base_url = Keyword.fetch!(opts, :url)
    
    # Ensure base URL doesn't have trailing slash
    base_url = String.trim_trailing(base_url, "/")
    
    state = %__MODULE__{
      name: name,
      base_url: base_url,
      sse_url: "#{base_url}/sse",
      message_url: "#{base_url}/message",
      capabilities: %{},
      pending_requests: %{},
      request_id: 1
    }
    
    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    # Start SSE connection
    case start_sse_connection(state) do
      {:ok, sse_pid} ->
        {:noreply, %{state | sse_pid: sse_pid}}
      
      {:error, reason} ->
        Logger.error("Failed to connect to SSE endpoint: #{inspect(reason)}")
        {:stop, {:connection_failed, reason}, state}
    end
  end

  @impl true
  def handle_call(:initialize, from, state) do
    # Send initialize request
    request_id = state.request_id
    request = %{
      jsonrpc: "2.0",
      method: "initialize",
      params: %{
        protocolVersion: "2024-11-05",
        capabilities: %{
          tools: %{},
          resources: %{},
          prompts: %{}
        },
        clientInfo: %{
          name: "mcp_chat",
          version: "0.1.0"
        }
      },
      id: request_id
    }
    
    case send_message(state, request) do
      :ok ->
        pending = Map.put(state.pending_requests, request_id, {:initialize, from})
        {:noreply, %{state | pending_requests: pending, request_id: request_id + 1}}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:list_tools, from, state) do
    request_id = state.request_id
    request = %{
      jsonrpc: "2.0",
      method: "tools/list",
      params: %{},
      id: request_id
    }
    
    case send_message(state, request) do
      :ok ->
        pending = Map.put(state.pending_requests, request_id, {:list_tools, from})
        {:noreply, %{state | pending_requests: pending, request_id: request_id + 1}}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:call_tool, name, arguments}, from, state) do
    request_id = state.request_id
    request = %{
      jsonrpc: "2.0",
      method: "tools/call",
      params: %{
        name: name,
        arguments: arguments
      },
      id: request_id
    }
    
    case send_message(state, request) do
      :ok ->
        pending = Map.put(state.pending_requests, request_id, {:call_tool, from})
        {:noreply, %{state | pending_requests: pending, request_id: request_id + 1}}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:list_resources, from, state) do
    request_id = state.request_id
    request = %{
      jsonrpc: "2.0",
      method: "resources/list",
      params: %{},
      id: request_id
    }
    
    case send_message(state, request) do
      :ok ->
        pending = Map.put(state.pending_requests, request_id, {:list_resources, from})
        {:noreply, %{state | pending_requests: pending, request_id: request_id + 1}}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:read_resource, uri}, from, state) do
    request_id = state.request_id
    request = %{
      jsonrpc: "2.0",
      method: "resources/read",
      params: %{uri: uri},
      id: request_id
    }
    
    case send_message(state, request) do
      :ok ->
        pending = Map.put(state.pending_requests, request_id, {:read_resource, from})
        {:noreply, %{state | pending_requests: pending, request_id: request_id + 1}}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:list_prompts, from, state) do
    request_id = state.request_id
    request = %{
      jsonrpc: "2.0",
      method: "prompts/list",
      params: %{},
      id: request_id
    }
    
    case send_message(state, request) do
      :ok ->
        pending = Map.put(state.pending_requests, request_id, {:list_prompts, from})
        {:noreply, %{state | pending_requests: pending, request_id: request_id + 1}}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_prompt, name, arguments}, from, state) do
    request_id = state.request_id
    request = %{
      jsonrpc: "2.0",
      method: "prompts/get",
      params: %{
        name: name,
        arguments: arguments
      },
      id: request_id
    }
    
    case send_message(state, request) do
      :ok ->
        pending = Map.put(state.pending_requests, request_id, {:get_prompt, from})
        {:noreply, %{state | pending_requests: pending, request_id: request_id + 1}}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({:sse_event, event, data}, state) do
    Logger.debug("SSE event: #{event}, data: #{inspect(data)}")
    
    case event do
      "message" ->
        handle_sse_message(data, state)
      
      "connected" ->
        Logger.info("Connected to SSE server: #{state.name}")
        {:noreply, state}
      
      "ping" ->
        # Keepalive ping
        {:noreply, state}
      
      _ ->
        Logger.debug("Unknown SSE event: #{event}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:sse_error, reason}, state) do
    Logger.error("SSE connection error: #{inspect(reason)}")
    # TODO: Implement reconnection logic
    {:stop, {:sse_error, reason}, state}
  end

  @impl true
  def handle_info({:sse_closed}, state) do
    Logger.warning("SSE connection closed")
    # TODO: Implement reconnection logic
    {:stop, :sse_closed, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{sse_pid: pid} = state) do
    Logger.error("SSE process died: #{inspect(reason)}")
    {:stop, {:sse_died, reason}, state}
  end

  # Private functions

  defp start_sse_connection(state) do
    parent = self()
    
    {:ok, spawn_link(fn ->
      # Connect to SSE endpoint
      case Req.get(state.sse_url, 
        headers: [
          {"accept", "text/event-stream"},
          {"cache-control", "no-cache"}
        ],
        receive_timeout: :infinity,
        into: :self
      ) do
        {:ok, %{status: 200} = resp} ->
          # Monitor the response to handle connection close
          Process.monitor(resp.body)
          handle_sse_stream(parent, "")
        
        {:ok, %{status: status}} ->
          send(parent, {:sse_error, {:http_error, status}})
        
        {:error, reason} ->
          send(parent, {:sse_error, reason})
      end
    end)}
  end

  defp handle_sse_stream(parent, buffer) do
    receive do
      {_request, {:data, data}} ->
        # Accumulate data and parse SSE events
        new_buffer = buffer <> data
        {events, remaining} = parse_sse_events(new_buffer)
        
        # Send events to parent
        Enum.each(events, fn {event, data} ->
          send(parent, {:sse_event, event, data})
        end)
        
        handle_sse_stream(parent, remaining)
      
      {_request, :done} ->
        send(parent, {:sse_closed})
      
      {:DOWN, _ref, :process, _pid, reason} ->
        send(parent, {:sse_error, {:connection_closed, reason}})
    end
  end

  defp parse_sse_events(data) do
    # Split by double newline
    parts = String.split(data, "\n\n", trim: true)
    
    # Check if last part is incomplete
    {complete_parts, remaining} = case List.last(parts) do
      nil -> {[], ""}
      last ->
        if String.ends_with?(data, "\n\n") do
          {parts, ""}
        else
          {Enum.drop(parts, -1), last}
        end
    end
    
    # Parse each complete event
    events = Enum.map(complete_parts, &parse_sse_event/1)
    |> Enum.filter(&(&1 != nil))
    
    {events, remaining}
  end

  defp parse_sse_event(event_text) do
    lines = String.split(event_text, "\n", trim: true)
    
    event = Enum.find_value(lines, fn line ->
      case String.split(line, ":", parts: 2) do
        ["event", event] -> String.trim(event)
        _ -> nil
      end
    end)
    
    data = Enum.find_value(lines, fn line ->
      case String.split(line, ":", parts: 2) do
        ["data", data] -> 
          case Jason.decode(String.trim(data)) do
            {:ok, decoded} -> decoded
            _ -> String.trim(data)
          end
        _ -> nil
      end
    end)
    
    if event && data do
      {event, data}
    else
      nil
    end
  end

  defp send_message(state, message) do
    body = Jason.encode!(message)
    
    case Req.post(state.message_url,
      headers: [
        {"content-type", "application/json"},
        {"accept", "application/json"}
      ],
      body: body
    ) do
      {:ok, %{status: 200, body: response_body}} ->
        # Handle synchronous response
        case Jason.decode(response_body) do
          {:ok, response} ->
            handle_response(response, state)
          {:error, reason} ->
            {:error, {:decode_error, reason}}
        end
        :ok
      
      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_sse_message(data, state) when is_map(data) do
    handle_response(data, state)
  end

  defp handle_sse_message(data, state) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, decoded} -> handle_response(decoded, state)
      {:error, _} -> {:noreply, state}
    end
  end

  defp handle_response(%{"id" => id} = response, state) do
    case Map.pop(state.pending_requests, id) do
      {nil, _} ->
        Logger.warning("Received response for unknown request ID: #{id}")
        {:noreply, state}
      
      {{request_type, from}, pending} ->
        result = case response do
          %{"result" => result} ->
            process_result(request_type, result, state)
          
          %{"error" => error} ->
            {:error, error}
        end
        
        GenServer.reply(from, result)
        {:noreply, %{state | pending_requests: pending}}
    end
  end

  defp handle_response(response, state) do
    Logger.debug("Received response without ID: #{inspect(response)}")
    {:noreply, state}
  end

  defp process_result(:initialize, result, state) do
    server_info = Map.get(result, "serverInfo", %{})
    capabilities = Map.get(result, "capabilities", %{})
    
    # Update state with server info
    new_state = %{state | 
      server_info: server_info,
      capabilities: capabilities
    }
    
    {:ok, new_state}
  end

  defp process_result(:list_tools, %{"tools" => tools}, _state) do
    {:ok, tools}
  end

  defp process_result(:call_tool, result, _state) do
    {:ok, result}
  end

  defp process_result(:list_resources, %{"resources" => resources}, _state) do
    {:ok, resources}
  end

  defp process_result(:read_resource, %{"contents" => contents}, _state) do
    {:ok, contents}
  end

  defp process_result(:list_prompts, %{"prompts" => prompts}, _state) do
    {:ok, prompts}
  end

  defp process_result(:get_prompt, %{"messages" => messages}, _state) do
    {:ok, messages}
  end

  defp process_result(_type, result, _state) do
    {:ok, result}
  end
end