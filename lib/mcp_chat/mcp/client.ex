defmodule MCPChat.MCP.Client do
  @moduledoc """
  MCP client that manages WebSocket connections to MCP servers.
  """
  use WebSockex

  alias MCPChat.MCP.Protocol

  require Logger

  defstruct [
    :server_info,
    :capabilities,
    :tools,
    :resources,
    :prompts,
    :pending_requests,
    :callback_pid
  ]

  # Client API

  def start_link(url, opts \\ []) do
    state = %__MODULE__{
      server_info: nil,
      capabilities: %{},
      tools: [],
      resources: [],
      prompts: [],
      pending_requests: %{},
      callback_pid: Keyword.get(opts, :callback_pid, self())
    }
    
    WebSockex.start_link(url, __MODULE__, state, opts)
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

  # WebSockex Callbacks

  @impl true
  def handle_frame({:text, data}, state) do
    case Protocol.parse_response(data) do
      {:notification, method, params} ->
        handle_notification(method, params, state)
      
      {:result, result, id} ->
        handle_result(result, id, state)
      
      {:error, error, id} ->
        handle_error(error, id, state)
      
      {:error, reason} ->
        Logger.error("Failed to parse MCP response: #{inspect(reason)}")
        {:ok, state}
    end
  end

  @impl true
  def handle_frame({:binary, _}, state) do
    Logger.warning("Received unexpected binary frame")
    {:ok, state}
  end

  @impl true
  def handle_cast({:send, message}, state) do
    frame = {:text, Protocol.encode_message(message)}
    
    # Track request if it has an ID
    state = case message do
      %{id: id} -> 
        %{state | pending_requests: Map.put(state.pending_requests, id, message)}
      _ -> 
        state
    end
    
    {:reply, frame, state}
  end

  @impl true
  def handle_disconnect(%{reason: reason}, state) do
    Logger.warning("MCP client disconnected: #{inspect(reason)}")
    send(state.callback_pid, {:mcp_disconnected, self(), reason})
    {:ok, state}
  end

  @impl true
  def handle_info(message, state) do
    Logger.debug("Unhandled message: #{inspect(message)}")
    {:ok, state}
  end

  # Private Functions

  defp send_message(client, message) do
    WebSockex.cast(client, {:send, message})
  end

  defp handle_notification("initialized", _params, state) do
    # Server confirmed initialization
    send(state.callback_pid, {:mcp_initialized, self()})
    {:ok, state}
  end

  defp handle_notification(method, params, state) do
    send(state.callback_pid, {:mcp_notification, self(), method, params})
    {:ok, state}
  end

  defp handle_result(result, id, state) do
    {request, pending} = Map.pop(state.pending_requests, id)
    
    state = %{state | pending_requests: pending}
    
    state = case request do
      %{method: "initialize"} ->
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
    {:ok, state}
  end

  defp handle_error(error, id, state) do
    {_request, pending} = Map.pop(state.pending_requests, id)
    state = %{state | pending_requests: pending}
    
    Logger.error("MCP error response: #{inspect(error)}")
    send(state.callback_pid, {:mcp_error, self(), error, id})
    
    {:ok, state}
  end
end