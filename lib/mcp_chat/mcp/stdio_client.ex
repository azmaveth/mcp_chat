defmodule MCPChat.MCP.StdioClient do
  @moduledoc """
  MCP client that communicates via stdio (stdin/stdout) with a server process.
  """
  use GenServer
  
  # alias MCPChat.MCP.Protocol
  
  require Logger

  defstruct [
    :port,
    :server_info,
    :capabilities,
    :tools,
    :resources,
    :prompts,
    :pending_requests,
    :callback_pid,
    :buffer,
    :request_id
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def initialize(client, client_info) do
    GenServer.call(client, {:initialize, client_info}, 10_000)
  end

  def list_tools(client) do
    GenServer.call(client, :list_tools, 10_000)
  end

  def call_tool(client, name, arguments) do
    GenServer.call(client, {:call_tool, name, arguments}, 30_000)
  end

  def list_resources(client) do
    GenServer.call(client, :list_resources, 10_000)
  end

  def read_resource(client, uri) do
    GenServer.call(client, {:read_resource, uri}, 30_000)
  end

  def list_prompts(client) do
    GenServer.call(client, :list_prompts, 10_000)
  end

  def get_prompt(client, name, arguments \\ %{}) do
    GenServer.call(client, {:get_prompt, name, arguments}, 10_000)
  end

  def set_port(client, port) do
    GenServer.call(client, {:set_port, port})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      port: nil,
      server_info: nil,
      capabilities: %{},
      tools: [],
      resources: [],
      prompts: [],
      pending_requests: %{},
      callback_pid: Keyword.get(opts, :callback_pid, self()),
      buffer: "",
      request_id: 1
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:set_port, port}, _from, state) do
    {:reply, :ok, %{state | port: port}}
  end

  @impl true
  def handle_call({:initialize, client_info}, from, state) do
    if state.port do
      request_id = state.request_id
      message = %{
        jsonrpc: "2.0",
        method: "initialize",
        params: %{
          protocolVersion: "2024-11-05",
          capabilities: client_info[:capabilities] || %{},
          clientInfo: client_info
        },
        id: request_id
      }
      
      new_state = %{state | 
        pending_requests: Map.put(state.pending_requests, request_id, {:initialize, from}),
        request_id: request_id + 1
      }
      
      send_json_rpc(new_state.port, message)
      {:noreply, new_state}
    else
      {:reply, {:error, :no_port}, state}
    end
  end

  @impl true
  def handle_call(:list_tools, from, state) do
    if state.port do
      request_id = state.request_id
      message = %{
        jsonrpc: "2.0",
        method: "tools/list",
        params: %{},
        id: request_id
      }
      
      new_state = %{state | 
        pending_requests: Map.put(state.pending_requests, request_id, {:list_tools, from}),
        request_id: request_id + 1
      }
      
      send_json_rpc(new_state.port, message)
      {:noreply, new_state}
    else
      {:reply, {:error, :no_port}, state}
    end
  end

  @impl true
  def handle_call({:call_tool, name, arguments}, from, state) do
    if state.port do
      request_id = state.request_id
      message = %{
        jsonrpc: "2.0",
        method: "tools/call",
        params: %{
          name: name,
          arguments: arguments
        },
        id: request_id
      }
      
      new_state = %{state | 
        pending_requests: Map.put(state.pending_requests, request_id, {:call_tool, from}),
        request_id: request_id + 1
      }
      
      send_json_rpc(new_state.port, message)
      {:noreply, new_state}
    else
      {:reply, {:error, :no_port}, state}
    end
  end

  @impl true
  def handle_call(:list_resources, from, state) do
    if state.port do
      request_id = state.request_id
      message = %{
        jsonrpc: "2.0",
        method: "resources/list",
        params: %{},
        id: request_id
      }
      
      new_state = %{state | 
        pending_requests: Map.put(state.pending_requests, request_id, {:list_resources, from}),
        request_id: request_id + 1
      }
      
      send_json_rpc(new_state.port, message)
      {:noreply, new_state}
    else
      {:reply, {:error, :no_port}, state}
    end
  end

  @impl true
  def handle_call({:read_resource, uri}, from, state) do
    if state.port do
      request_id = state.request_id
      message = %{
        jsonrpc: "2.0",
        method: "resources/read",
        params: %{uri: uri},
        id: request_id
      }
      
      new_state = %{state | 
        pending_requests: Map.put(state.pending_requests, request_id, {:read_resource, from}),
        request_id: request_id + 1
      }
      
      send_json_rpc(new_state.port, message)
      {:noreply, new_state}
    else
      {:reply, {:error, :no_port}, state}
    end
  end

  @impl true
  def handle_call(:list_prompts, from, state) do
    if state.port do
      request_id = state.request_id
      message = %{
        jsonrpc: "2.0",
        method: "prompts/list",
        params: %{},
        id: request_id
      }
      
      new_state = %{state | 
        pending_requests: Map.put(state.pending_requests, request_id, {:list_prompts, from}),
        request_id: request_id + 1
      }
      
      send_json_rpc(new_state.port, message)
      {:noreply, new_state}
    else
      {:reply, {:error, :no_port}, state}
    end
  end

  @impl true
  def handle_call({:get_prompt, name, arguments}, from, state) do
    if state.port do
      request_id = state.request_id
      message = %{
        jsonrpc: "2.0",
        method: "prompts/get",
        params: %{
          name: name,
          arguments: arguments
        },
        id: request_id
      }
      
      new_state = %{state | 
        pending_requests: Map.put(state.pending_requests, request_id, {:get_prompt, from}),
        request_id: request_id + 1
      }
      
      send_json_rpc(new_state.port, message)
      {:noreply, new_state}
    else
      {:reply, {:error, :no_port}, state}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    # Accumulate data in buffer
    buffer = state.buffer <> data
    
    # Split by newlines and process complete messages
    {lines, remaining} = split_lines(buffer)
    
    new_state = Enum.reduce(lines, state, &process_line/2)
    
    {:noreply, %{new_state | buffer: remaining}}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("Port exited with status: #{status}")
    if state.callback_pid do
      send(state.callback_pid, {:mcp_disconnected, self(), {:exit_status, status}})
    end
    {:noreply, %{state | port: nil}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :port, port, reason}, %{port: port} = state) do
    Logger.warning("Port died: #{inspect(reason)}")
    if state.callback_pid do
      send(state.callback_pid, {:mcp_disconnected, self(), reason})
    end
    {:noreply, %{state | port: nil}}
  end

  # Private Functions

  defp send_json_rpc(port, message) do
    json = Jason.encode!(message)
    Port.command(port, json <> "\n")
  end

  defp split_lines(data) do
    lines = String.split(data, "\n")
    
    case List.last(lines) do
      "" ->
        # Data ended with newline, all lines are complete
        {Enum.drop(lines, -1), ""}
      
      partial ->
        # Last line is incomplete
        {Enum.drop(lines, -1), partial}
    end
  end

  defp process_line("", state), do: state
  defp process_line(line, state) do
    case Jason.decode(line) do
      {:ok, message} ->
        handle_json_rpc_message(message, state)
      
      {:error, reason} ->
        Logger.error("Failed to decode JSON-RPC message: #{inspect(reason)}")
        Logger.error("Raw line: #{inspect(line)}")
        state
    end
  end

  defp handle_json_rpc_message(%{"id" => id} = message, state) when not is_nil(id) do
    # This is a response to one of our requests
    case Map.pop(state.pending_requests, id) do
      {nil, _} ->
        Logger.warning("Received response for unknown request ID: #{id}")
        state
      
      {{request_type, from}, pending} ->
        result = case message do
          %{"result" => result} ->
            process_result(request_type, result, state)
          
          %{"error" => error} ->
            {:error, error}
        end
        
        GenServer.reply(from, result)
        %{state | pending_requests: pending}
    end
  end

  defp handle_json_rpc_message(%{"method" => method, "params" => params}, state) do
    # This is a notification from the server
    if state.callback_pid do
      send(state.callback_pid, {:mcp_notification, self(), method, params})
    end
    state
  end

  defp handle_json_rpc_message(message, state) do
    Logger.debug("Unhandled JSON-RPC message: #{inspect(message)}")
    state
  end

  defp process_result(:initialize, result, state) do
    server_info = Map.get(result, "serverInfo", %{})
    capabilities = Map.get(result, "capabilities", %{})
    
    _new_state = %{state | 
      server_info: server_info,
      capabilities: capabilities
    }
    
    # Send initialization complete notification
    if state.callback_pid do
      send(state.callback_pid, {:mcp_initialized, self()})
    end
    
    {:ok, %{server_info: server_info, capabilities: capabilities}}
  end

  defp process_result(:list_tools, %{"tools" => tools}, state) do
    _new_state = %{state | tools: tools}
    {:ok, tools}
  end

  defp process_result(:call_tool, result, _state) do
    # Tool call results can have various formats
    case result do
      %{"content" => content} -> {:ok, content}
      %{"text" => text} -> {:ok, text}
      _ -> {:ok, result}
    end
  end

  defp process_result(:list_resources, %{"resources" => resources}, state) do
    _new_state = %{state | resources: resources}
    {:ok, resources}
  end

  defp process_result(:read_resource, %{"contents" => contents}, _state) do
    {:ok, contents}
  end

  defp process_result(:list_prompts, %{"prompts" => prompts}, state) do
    _new_state = %{state | prompts: prompts}
    {:ok, prompts}
  end

  defp process_result(:get_prompt, %{"messages" => messages}, _state) do
    {:ok, messages}
  end

  defp process_result(_, result, _state) do
    {:ok, result}
  end
end