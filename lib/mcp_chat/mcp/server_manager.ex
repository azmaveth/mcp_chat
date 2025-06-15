defmodule MCPChat.MCP.ServerManager do
  @moduledoc """
  GenServer wrapper for managing multiple MCP server connections.
  Delegates all operations to MCPChat.MCP.ServerManager.Core.
  """
  use GenServer

  alias MCPChat.MCP.ServerManager.Core

  require Logger

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_configured_servers do
    GenServer.call(__MODULE__, :start_configured_servers)
  end

  def start_server(server_config) do
    GenServer.call(__MODULE__, {:start_server, server_config})
  end

  def stop_server(name) do
    GenServer.call(__MODULE__, {:stop_server, name})
  end

  def list_servers do
    GenServer.call(__MODULE__, :list_servers)
  end

  def list_servers_with_status do
    GenServer.call(__MODULE__, :list_servers_with_status)
  end

  def get_server(name) do
    GenServer.call(__MODULE__, {:get_server, name})
  end

  def list_all_tools do
    GenServer.call(__MODULE__, :list_all_tools)
  end

  def call_tool(server_name, tool_name, arguments) do
    GenServer.call(__MODULE__, {:call_tool, server_name, tool_name, arguments})
  end

  def list_all_resources do
    GenServer.call(__MODULE__, :list_all_resources)
  end

  def read_resource(server_name, uri) do
    GenServer.call(__MODULE__, {:read_resource, server_name, uri})
  end

  def list_all_prompts do
    GenServer.call(__MODULE__, :list_all_prompts)
  end

  def get_prompt(server_name, prompt_name, arguments \\ %{}) do
    GenServer.call(__MODULE__, {:get_prompt, server_name, prompt_name, arguments})
  end

  def get_tools(server_name) do
    GenServer.call(__MODULE__, {:get_tools, server_name})
  end

  def get_resources(server_name) do
    GenServer.call(__MODULE__, {:get_resources, server_name})
  end

  def get_prompts(server_name) do
    GenServer.call(__MODULE__, {:get_prompts, server_name})
  end

  # Health monitoring functions

  def record_server_success(server_name, response_time_ms) do
    GenServer.cast(__MODULE__, {:record_success, server_name, response_time_ms})
  end

  def record_server_failure(server_name) do
    GenServer.cast(__MODULE__, {:record_failure, server_name})
  end

  def get_server_info(server_name) do
    GenServer.call(__MODULE__, {:get_server_info, server_name})
  end

  def disable_unhealthy_server(server_name) do
    GenServer.cast(__MODULE__, {:disable_unhealthy_server, server_name})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Start the registry for MCP servers
    # Registry no longer needed - ExMCPAdapter manages its own process references

    state = Core.new_state()

    # Start servers after init
    send(self(), :start_configured_servers)

    {:ok, state}
  end

  @impl true
  def handle_call(:start_configured_servers, _from, state) do
    # Start a supervisor for the servers if needed, or use existing one
    supervisor =
      case DynamicSupervisor.start_link(
             strategy: :one_for_one,
             name: MCPChat.MCP.ServerSupervisor
           ) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    state_with_supervisor = Core.set_supervisor(state, supervisor)
    {new_state, result} = Core.start_configured_servers(state_with_supervisor)

    # Start background connection attempts for servers in connecting state
    send(self(), :connect_pending_servers)

    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:start_server, config}, _from, state) do
    {new_state, result} = Core.start_server(state, config)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:stop_server, name}, _from, state) do
    {new_state, result} = Core.stop_server(state, name)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:list_servers, _from, state) do
    servers = Core.list_servers(state)
    {:reply, servers, state}
  end

  @impl true
  def handle_call(:list_servers_with_status, _from, state) do
    servers = Core.list_servers_with_status(state)
    {:reply, servers, state}
  end

  @impl true
  def handle_call({:get_server, name}, _from, state) do
    result = Core.get_server(state, name)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_all_tools, _from, state) do
    tools = Core.list_all_tools(state)
    {:reply, tools, state}
  end

  @impl true
  def handle_call({:call_tool, server_name, tool_name, arguments}, _from, state) do
    result = Core.call_tool(state, server_name, tool_name, arguments)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_all_resources, _from, state) do
    resources = Core.list_all_resources(state)
    {:reply, resources, state}
  end

  @impl true
  def handle_call({:read_resource, server_name, uri}, _from, state) do
    result = Core.read_resource(state, server_name, uri)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_all_prompts, _from, state) do
    prompts = Core.list_all_prompts(state)
    {:reply, prompts, state}
  end

  @impl true
  def handle_call({:get_prompt, server_name, prompt_name, arguments}, _from, state) do
    result = Core.get_prompt(state, server_name, prompt_name, arguments)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_tools, server_name}, _from, state) do
    case Map.get(state.servers, server_name) do
      nil -> {:reply, {:error, :not_found}, state}
      pid -> {:reply, MCPChat.MCP.ExMCPAdapter.get_tools(pid), state}
    end
  end

  @impl true
  def handle_call({:get_resources, server_name}, _from, state) do
    if server_name == "builtin" do
      resources = MCPChat.MCP.BuiltinResources.list_resources()
      {:reply, {:ok, resources}, state}
    else
      case Map.get(state.servers, server_name) do
        nil -> {:reply, {:error, :not_found}, state}
        pid -> {:reply, MCPChat.MCP.ExMCPAdapter.get_resources(pid), state}
      end
    end
  end

  @impl true
  def handle_call({:get_prompts, server_name}, _from, state) do
    if server_name == "builtin" do
      prompts = MCPChat.MCP.BuiltinResources.list_prompts()
      {:reply, {:ok, prompts}, state}
    else
      case Map.get(state.servers, server_name) do
        nil -> {:reply, {:error, :not_found}, state}
        pid -> {:reply, MCPChat.MCP.ExMCPAdapter.get_prompts(pid), state}
      end
    end
  end

  @impl true
  def handle_call({:get_server_info, server_name}, _from, state) do
    result = Core.get_server_info(state, server_name)
    {:reply, result, state}
  end

  @impl true
  def handle_cast({:record_success, server_name, response_time_ms}, state) do
    new_state = Core.record_server_success(state, server_name, response_time_ms)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:record_failure, server_name}, state) do
    new_state = Core.record_server_failure(state, server_name)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:disable_unhealthy_server, server_name}, state) do
    Logger.warning("Auto-disabling unhealthy server: #{server_name}")
    new_state = Core.mark_server_disconnected(state, server_name)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:start_configured_servers, state) do
    # Start profiling MCP servers phase
    MCPChat.StartupProfiler.start_phase(:mcp_servers)

    # Start servers from config file
    config_state =
      handle_call(:start_configured_servers, nil, state)
      |> elem(2)

    # Also start saved servers with auto_connect enabled
    final_state = Core.start_auto_connect_servers(config_state)

    # End profiling MCP servers phase
    MCPChat.StartupProfiler.end_phase(:mcp_servers)

    {:noreply, final_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    Logger.warning("MCP server process died: #{inspect(reason)}")
    new_state = Core.handle_server_death(state, pid)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:connect_pending_servers, state) do
    # Get servers that need connection attempts
    connecting_servers = Core.get_connecting_servers(state)

    if length(connecting_servers) > 0 do
      Logger.info("Starting background connections for #{length(connecting_servers)} servers")

      # Start connection tasks for each server
      Enum.each(connecting_servers, &start_connection_task/1)
    end

    {:noreply, state}
  end

  defp start_connection_task(server) do
    Task.start(fn -> attempt_server_connection(server) end)
  end

  @impl true
  def handle_info({:server_connected, server_name, pid, capabilities}, state) do
    # Monitor the server process
    monitor_ref = Process.monitor(pid)

    # Update server state to connected
    new_state = Core.mark_server_connected(state, server_name, pid, monitor_ref, capabilities)

    Logger.info("Server '#{server_name}' connected successfully")
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:server_failed, server_name, error}, state) do
    # Update server state to failed
    new_state = Core.mark_server_failed(state, server_name, error)

    Logger.warning("Server '#{server_name}' failed to connect: #{inspect(error)}")
    {:noreply, new_state}
  end

  # Private helper for background connection attempts
  defp attempt_server_connection(server) do
    server_manager_pid = Process.whereis(__MODULE__)

    case Core.build_server_config(server.config, server.name) do
      {:ok, server_config} ->
        handle_server_start(server_manager_pid, server, server_config)

      {:error, reason} ->
        send(server_manager_pid, {:server_failed, server.name, reason})
    end
  end

  defp handle_server_start(server_manager_pid, server, server_config) do
    child_spec = %{
      id: {MCPChat.MCP.ServerWrapper, server.name},
      start: {MCPChat.MCP.ServerWrapper, :start_link, [server_config, []]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(MCPChat.MCP.ServerSupervisor, child_spec) do
      {:ok, pid} ->
        handle_server_capabilities(server_manager_pid, server, pid)

      {:error, reason} ->
        send(server_manager_pid, {:server_failed, server.name, reason})
    end
  end

  defp handle_server_capabilities(server_manager_pid, server, pid) do
    case fetch_server_capabilities(pid) do
      {:ok, capabilities} ->
        send(server_manager_pid, {:server_connected, server.name, pid, capabilities})

      {:error, reason} ->
        DynamicSupervisor.terminate_child(MCPChat.MCP.ServerSupervisor, pid)
        send(server_manager_pid, {:server_failed, server.name, reason})
    end
  end

  defp fetch_server_capabilities(pid) do
    # Give server time to initialize
    Process.sleep(500)

    with {:ok, tools} <- MCPChat.MCP.ServerWrapper.get_tools(pid),
         {:ok, resources} <- MCPChat.MCP.ServerWrapper.get_resources(pid),
         {:ok, prompts} <- MCPChat.MCP.ServerWrapper.get_prompts(pid) do
      {:ok, %{tools: tools, resources: resources, prompts: prompts}}
    else
      error -> error
    end
  end
end
