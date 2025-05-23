defmodule MCPChat.MCP.Server do
  @moduledoc """
  Manages MCP server connections, including starting, stopping, and monitoring servers.
  """
  use GenServer
  
  alias MCPChat.MCP.Client
  
  require Logger

  defstruct [:name, :command, :env, :port, :pid, :client_pid, :status, :capabilities]

  # Client API

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(name))
  end

  def connect(name) do
    GenServer.call(via_tuple(name), :connect)
  end

  def disconnect(name) do
    GenServer.call(via_tuple(name), :disconnect)
  end

  def get_status(name) do
    GenServer.call(via_tuple(name), :get_status)
  end

  def get_tools(name) do
    GenServer.call(via_tuple(name), :get_tools)
  end

  def call_tool(name, tool_name, arguments) do
    GenServer.call(via_tuple(name), {:call_tool, tool_name, arguments})
  end

  def get_resources(name) do
    GenServer.call(via_tuple(name), :get_resources)
  end

  def read_resource(name, uri) do
    GenServer.call(via_tuple(name), {:read_resource, uri})
  end

  def get_prompts(name) do
    GenServer.call(via_tuple(name), :get_prompts)
  end

  def get_prompt(name, prompt_name, arguments \\ %{}) do
    GenServer.call(via_tuple(name), {:get_prompt, prompt_name, arguments})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      command: Keyword.fetch!(opts, :command),
      env: Keyword.get(opts, :env, %{}),
      port: nil,
      pid: nil,
      client_pid: nil,
      status: :disconnected,
      capabilities: %{}
    }
    
    # Auto-connect if requested
    if Keyword.get(opts, :auto_connect, true) do
      send(self(), :connect)
    end
    
    {:ok, state}
  end

  @impl true
  def handle_call(:connect, _from, %{status: :connected} = state) do
    {:reply, {:ok, :already_connected}, state}
  end

  @impl true
  def handle_call(:connect, _from, state) do
    case start_server_process(state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:disconnect, _from, state) do
    new_state = stop_server_process(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      name: state.name,
      status: state.status,
      capabilities: state.capabilities,
      port: state.port
    }
    {:reply, status, state}
  end

  @impl true
  def handle_call(:get_tools, _from, %{status: :connected, client_pid: client} = state) do
    Client.list_tools(client)
    # TODO: Wait for response
    {:reply, {:ok, []}, state}
  end

  @impl true
  def handle_call(:get_tools, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_call({:call_tool, tool_name, arguments}, _from, %{status: :connected, client_pid: client} = state) do
    Client.call_tool(client, tool_name, arguments)
    # TODO: Wait for response
    {:reply, {:ok, %{}}, state}
  end

  @impl true
  def handle_call({:call_tool, _, _}, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_call(:get_resources, _from, %{status: :connected, client_pid: client} = state) do
    Client.list_resources(client)
    # TODO: Wait for response
    {:reply, {:ok, []}, state}
  end

  @impl true
  def handle_call(:get_resources, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_call({:read_resource, uri}, _from, %{status: :connected, client_pid: client} = state) do
    Client.read_resource(client, uri)
    # TODO: Wait for response
    {:reply, {:ok, %{}}, state}
  end

  @impl true
  def handle_call({:read_resource, _}, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_call(:get_prompts, _from, %{status: :connected, client_pid: client} = state) do
    Client.list_prompts(client)
    # TODO: Wait for response
    {:reply, {:ok, []}, state}
  end

  @impl true
  def handle_call(:get_prompts, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_call({:get_prompt, prompt_name, arguments}, _from, %{status: :connected, client_pid: client} = state) do
    Client.get_prompt(client, prompt_name, arguments)
    # TODO: Wait for response
    {:reply, {:ok, %{}}, state}
  end

  @impl true
  def handle_call({:get_prompt, _, _}, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case start_server_process(state) do
      {:ok, new_state} ->
        {:noreply, new_state}
      {:error, reason} ->
        Logger.error("Failed to auto-connect MCP server #{state.name}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:mcp_initialized, client}, %{client_pid: client} = state) do
    Logger.info("MCP server #{state.name} initialized")
    
    # Request initial data
    Client.list_tools(client)
    Client.list_resources(client)
    Client.list_prompts(client)
    
    {:noreply, %{state | status: :connected}}
  end

  @impl true
  def handle_info({:mcp_disconnected, client, reason}, %{client_pid: client} = state) do
    Logger.warning("MCP server #{state.name} disconnected: #{inspect(reason)}")
    new_state = stop_server_process(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:mcp_result, client, result, _id}, %{client_pid: client} = state) do
    # TODO: Handle results based on request type
    Logger.debug("MCP result from #{state.name}: #{inspect(result)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:mcp_notification, client, method, params}, %{client_pid: client} = state) do
    Logger.debug("MCP notification from #{state.name}: #{method} - #{inspect(params)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:mcp_error, client, error, _id}, %{client_pid: client} = state) do
    Logger.error("MCP error from #{state.name}: #{inspect(error)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{pid: pid} = state) do
    Logger.warning("MCP server process #{state.name} died: #{inspect(reason)}")
    new_state = %{state | pid: nil, client_pid: nil, status: :disconnected}
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{client_pid: pid} = state) do
    Logger.warning("MCP client process for #{state.name} died: #{inspect(reason)}")
    new_state = stop_server_process(state)
    {:noreply, new_state}
  end

  # Private Functions

  defp via_tuple(name) do
    {:via, Registry, {MCPChat.MCP.ServerRegistry, name}}
  end

  defp start_server_process(state) do
    # For now, we'll simulate the connection since stdio transport
    # requires a different approach than WebSocket
    # TODO: Implement stdio transport for MCP client
    
    Logger.info("MCP server connections not yet implemented for stdio transport")
    
    # Return a simulated connected state
    new_state = %{state |
      port: nil,
      pid: nil,
      client_pid: nil,
      status: :simulated,
      capabilities: %{
        tools: true,
        resources: true,
        prompts: true
      }
    }
    
    {:ok, new_state}
  end

  defp stop_server_process(state) do
    # Stop the client
    if state.client_pid do
      Process.exit(state.client_pid, :shutdown)
    end
    
    # Stop the server process
    if state.port do
      Port.close(state.port)
    end
    
    %{state |
      port: nil,
      pid: nil,
      client_pid: nil,
      status: :disconnected,
      capabilities: %{}
    }
  end

  defp start_server_command([cmd | args], env) do
    # Convert env map to list of {"KEY", "VALUE"} tuples
    env_list = Enum.map(env, fn {k, v} -> {to_string(k), to_string(v)} end)
    
    # Start the port
    port_opts = [
      :binary,
      :exit_status,
      {:env, env_list},
      {:args, args}
    ]
    
    try do
      port = Port.open({:spawn_executable, System.find_executable(cmd)}, port_opts)
      {:ok, port, nil}  # We don't have OS PID easily accessible
    catch
      :error, reason ->
        {:error, reason}
    end
  end

  defp get_port_number(_port) do
    # For stdio transport, we don't actually use WebSocket
    # This is a placeholder - real implementation would vary by transport
    0
  end
end