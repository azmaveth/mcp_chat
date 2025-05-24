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

  def start_configured_servers() do
    GenServer.call(__MODULE__, :start_configured_servers)
  end

  def start_server(server_config) do
    GenServer.call(__MODULE__, {:start_server, server_config})
  end

  def stop_server(name) do
    GenServer.call(__MODULE__, {:stop_server, name})
  end

  def list_servers() do
    GenServer.call(__MODULE__, :list_servers)
  end

  def get_server(name) do
    GenServer.call(__MODULE__, {:get_server, name})
  end

  def list_all_tools() do
    GenServer.call(__MODULE__, :list_all_tools)
  end

  def call_tool(server_name, tool_name, arguments) do
    GenServer.call(__MODULE__, {:call_tool, server_name, tool_name, arguments})
  end

  def list_all_resources() do
    GenServer.call(__MODULE__, :list_all_resources)
  end

  def read_resource(server_name, uri) do
    GenServer.call(__MODULE__, {:read_resource, server_name, uri})
  end

  def list_all_prompts() do
    GenServer.call(__MODULE__, :list_all_prompts)
  end

  def get_prompt(server_name, prompt_name, arguments \\ %{}) do
    GenServer.call(__MODULE__, {:get_prompt, server_name, prompt_name, arguments})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Start the registry for MCP servers
    {:ok, _} = Registry.start_link(keys: :unique, name: MCPChat.MCP.ServerRegistry)

    state = Core.new_state()

    # Start servers after init
    send(self(), :start_configured_servers)

    {:ok, state}
  end

  @impl true
  def handle_call(:start_configured_servers, _from, state) do
    # Start a supervisor for the servers if needed
    {:ok, supervisor} =
      DynamicSupervisor.start_link(
        strategy: :one_for_one,
        name: MCPChat.MCP.ServerSupervisor
      )

    state_with_supervisor = Core.set_supervisor(state, supervisor)
    {new_state, result} = Core.start_configured_servers(state_with_supervisor)

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
  def handle_info(:start_configured_servers, state) do
    # Start servers from config file
    config_state =
      handle_call(:start_configured_servers, nil, state)
      |> elem(2)

    # Also start saved servers with auto_connect enabled
    final_state = Core.start_auto_connect_servers(config_state)

    {:noreply, final_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    Logger.warning("MCP server process died: #{inspect(reason)}")
    new_state = Core.handle_server_death(state, pid)
    {:noreply, new_state}
  end
end
