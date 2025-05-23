defmodule MCPChat.MCP.StdioClient do
  @moduledoc """
  MCP client that communicates via stdio (stdin/stdout) with a server process.
  """
  use GenServer
  
  alias MCPChat.MCP.Protocol
  
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
    :buffer
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def initialize(client, client_info) do
    message = Protocol.encode_initialize(client_info)
    send_message(client, message)
  end

  def list_tools(client) do
    message = Protocol.encode_list_tools()
    send_message(client, message)
  end

  def call_tool(client, name, arguments) do
    message = Protocol.encode_call_tool(name, arguments)
    send_message(client, message)
  end

  def list_resources(client) do
    message = Protocol.encode_list_resources()
    send_message(client, message)
  end

  def read_resource(client, uri) do
    message = Protocol.encode_read_resource(uri)
    send_message(client, message)
  end

  def list_prompts(client) do
    message = Protocol.encode_list_prompts()
    send_message(client, message)
  end

  def get_prompt(client, name, arguments \\ %{}) do
    message = Protocol.encode_get_prompt(name, arguments)
    send_message(client, message)
  end

  def send_message(client, message) do
    GenServer.cast(client, {:send, message})
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
      buffer: ""
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:set_port, port}, _from, state) do
    {:reply, :ok, %{state | port: port}}
  end

  @impl true
  def handle_cast({:send, message}, state) do
    if state.port do
      json = Protocol.encode_message(message)
      # Send JSON-RPC message followed by newline
      data = json <> "\n"
      Port.command(state.port, data)
      
      # Track request if it has an ID
      new_state = case message do
        %{id: id} -> 
          %{state | pending_requests: Map.put(state.pending_requests, id, message)}
        _ -> 
          state
      end
      
      {:noreply, new_state}
    else
      Logger.error("Attempted to send message without port connection")
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    # Append data to buffer
    buffer = state.buffer <> data
    
    # Process complete lines
    {lines, remaining} = split_lines(buffer)
    
    # Process each complete JSON-RPC message
    state = Enum.reduce(lines, state, &process_line/2)
    
    {:noreply, %{state | buffer: remaining}}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("MCP server process exited with status: #{status}")
    send(state.callback_pid, {:mcp_disconnected, self(), {:exit_status, status}})
    {:noreply, %{state | port: nil}}
  end

  @impl true
  def handle_info(:send_initialized, state) do
    # Send initialized notification after successful initialization
    message = Protocol.encode_initialized()
    handle_cast({:send, message}, state)
  end

  # Private Functions

  defp split_lines(data) do
    lines = String.split(data, "\n")
    case List.last(lines) do
      "" ->
        # Data ended with newline, all lines are complete
        {Enum.drop(lines, -1), ""}
      incomplete ->
        # Last line is incomplete
        {Enum.drop(lines, -1), incomplete}
    end
  end

  defp process_line("", state), do: state
  defp process_line(line, state) do
    case Protocol.parse_response(line) do
      {:notification, method, params} ->
        handle_notification(method, params, state)
      
      {:result, result, id} ->
        handle_result(result, id, state)
      
      {:error, error, id} ->
        handle_error(error, id, state)
      
      {:error, reason} ->
        Logger.error("Failed to parse MCP response: #{inspect(reason)}")
        Logger.error("Raw line: #{line}")
        state
    end
  end

  defp handle_notification("initialized", _params, state) do
    # Server confirmed initialization
    send(state.callback_pid, {:mcp_initialized, self()})
    state
  end

  defp handle_notification(method, params, state) do
    send(state.callback_pid, {:mcp_notification, self(), method, params})
    state
  end

  defp handle_result(result, id, state) do
    {request, pending} = Map.pop(state.pending_requests, id)
    
    state = %{state | pending_requests: pending}
    
    state = case request do
      %{method: "initialize"} ->
        # Send initialized notification
        send(self(), :send_initialized)
        
        %{state | 
          server_info: result["serverInfo"],
          capabilities: result["capabilities"] || %{}
        }
      
      %{method: "tools/list"} ->
        %{state | tools: result["tools"] || []}
      
      %{method: "resources/list"} ->
        %{state | resources: result["resources"] || []}
      
      %{method: "prompts/list"} ->
        %{state | prompts: result["prompts"] || []}
      
      _ ->
        state
    end
    
    send(state.callback_pid, {:mcp_result, self(), result, id})
    state
  end

  defp handle_error(error, id, state) do
    {_request, pending} = Map.pop(state.pending_requests, id)
    state = %{state | pending_requests: pending}
    
    Logger.error("MCP error response: #{inspect(error)}")
    send(state.callback_pid, {:mcp_error, self(), error, id})
    
    state
  end
end