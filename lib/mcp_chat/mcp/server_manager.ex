defmodule MCPChat.MCP.ServerManager do
  @moduledoc """
  Manages multiple MCP server connections.
  """
  use GenServer

  alias MCPChat.MCP.Server
  alias MCPChat.Config

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

    state = %{
      servers: %{},
      supervisor: nil
    }

    # Start servers after init
    send(self(), :start_configured_servers)

    {:ok, state}
  end

  @impl true
  def handle_call(:start_configured_servers, _from, state) do
    servers = Config.get([:mcp, :servers]) || []

    # Start a supervisor for the servers if needed
    {:ok, supervisor} =
      DynamicSupervisor.start_link(
        strategy: :one_for_one,
        name: MCPChat.MCP.ServerSupervisor
      )

    # Start each configured server
    results = Enum.map(servers, &start_server_supervised(&1, supervisor))

    # Update state with started servers
    new_servers =
      results
      |> Enum.filter(fn {status, _} -> status == :ok end)
      |> Enum.map(fn {:ok, {name, pid}} -> {name, pid} end)
      |> Enum.into(%{})

    new_state = %{state | servers: new_servers, supervisor: supervisor}

    {:reply, {:ok, map_size(new_servers)}, new_state}
  end

  @impl true
  def handle_call({:start_server, config}, _from, state) do
    case start_server_supervised(config, state.supervisor) do
      {:ok, {name, pid}} ->
        new_servers = Map.put(state.servers, name, pid)
        {:reply, {:ok, pid}, %{state | servers: new_servers}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:stop_server, name}, _from, state) do
    case Map.get(state.servers, name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      pid ->
        DynamicSupervisor.terminate_child(state.supervisor, pid)
        new_servers = Map.delete(state.servers, name)
        {:reply, :ok, %{state | servers: new_servers}}
    end
  end

  @impl true
  def handle_call(:list_servers, _from, state) do
    servers =
      state.servers
      |> Enum.map(fn {name, _pid} ->
        case Server.get_status(name) do
          {:error, _} -> nil
          status -> status
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:reply, servers, state}
  end

  @impl true
  def handle_call({:get_server, name}, _from, state) do
    case Map.get(state.servers, name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _pid ->
        case Server.get_status(name) do
          {:error, reason} -> {:reply, {:error, reason}, state}
          status -> {:reply, {:ok, status}, state}
        end
    end
  end

  @impl true
  def handle_call(:list_all_tools, _from, state) do
    # Aggregate tools from all connected servers
    tools =
      state.servers
      |> Enum.map(fn {name, _pid} ->
        case Server.get_tools(name) do
          {:ok, tools} -> Enum.map(tools, &Map.put(&1, :server, name))
          _ -> []
        end
      end)
      |> List.flatten()

    {:reply, tools, state}
  end

  @impl true
  def handle_call({:call_tool, server_name, tool_name, arguments}, _from, state) do
    if Map.has_key?(state.servers, server_name) do
      result = Server.call_tool(server_name, tool_name, arguments)
      {:reply, result, state}
    else
      {:reply, {:error, :server_not_found}, state}
    end
  end

  @impl true
  def handle_call(:list_all_resources, _from, state) do
    # Aggregate resources from all connected servers
    resources =
      state.servers
      |> Enum.map(fn {name, _pid} ->
        case Server.get_resources(name) do
          {:ok, resources} -> Enum.map(resources, &Map.put(&1, :server, name))
          _ -> []
        end
      end)
      |> List.flatten()

    {:reply, resources, state}
  end

  @impl true
  def handle_call({:read_resource, server_name, uri}, _from, state) do
    if Map.has_key?(state.servers, server_name) do
      result = Server.read_resource(server_name, uri)
      {:reply, result, state}
    else
      {:reply, {:error, :server_not_found}, state}
    end
  end

  @impl true
  def handle_call(:list_all_prompts, _from, state) do
    # Aggregate prompts from all connected servers
    prompts =
      state.servers
      |> Enum.map(fn {name, _pid} ->
        case Server.get_prompts(name) do
          {:ok, prompts} -> Enum.map(prompts, &Map.put(&1, :server, name))
          _ -> []
        end
      end)
      |> List.flatten()

    {:reply, prompts, state}
  end

  @impl true
  def handle_call({:get_prompt, server_name, prompt_name, arguments}, _from, state) do
    if Map.has_key?(state.servers, server_name) do
      result = Server.get_prompt(server_name, prompt_name, arguments)
      {:reply, result, state}
    else
      {:reply, {:error, :server_not_found}, state}
    end
  end

  @impl true
  def handle_info(:start_configured_servers, state) do
    # Start servers from config file
    config_state =
      handle_call(:start_configured_servers, nil, state)
      |> elem(2)

    # Also start saved servers with auto_connect enabled
    saved_servers = MCPChat.MCP.ServerPersistence.load_all_servers()
    auto_connect_servers = Enum.filter(saved_servers, &(&1["auto_connect"] == true))

    final_state =
      Enum.reduce(auto_connect_servers, config_state, fn server_config, acc_state ->
        # Check if server is already started
        if Map.has_key?(acc_state.servers, server_config["name"]) do
          acc_state
        else
          Logger.info("Auto-connecting to saved server: #{server_config["name"]}")

          case start_server_supervised(server_config, acc_state.supervisor) do
            {:ok, {name, pid}} ->
              %{acc_state | servers: Map.put(acc_state.servers, name, pid)}

            {:error, reason} ->
              Logger.warning("Failed to auto-connect server #{server_config["name"]}: #{inspect(reason)}")
              acc_state
          end
        end
      end)

    {:noreply, final_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Find which server died
    case Enum.find(state.servers, fn {_name, server_pid} -> server_pid == pid end) do
      {name, _} ->
        Logger.warning("MCP server #{name} died: #{inspect(reason)}")
        new_servers = Map.delete(state.servers, name)
        {:noreply, %{state | servers: new_servers}}

      nil ->
        {:noreply, state}
    end
  end

  # Private Functions

  defp start_server_supervised(config, supervisor) do
    name = config[:name] || config["name"]
    command = config[:command] || config["command"]
    url = config[:url] || config["url"]
    env = config[:env] || config["env"] || %{}

    cond do
      name && command ->
        # Stdio transport
        child_spec = %{
          id: {Server, name},
          start:
            {Server, :start_link,
             [
               [
                 name: name,
                 command: command,
                 env: env,
                 auto_connect: true
               ]
             ]},
          restart: :temporary
        }

        case DynamicSupervisor.start_child(supervisor, child_spec) do
          {:ok, pid} ->
            {:ok, {name, pid}}

          {:error, reason} ->
            Logger.error("Failed to start MCP server #{name}: #{inspect(reason)}")
            {:error, reason}
        end

      name && url ->
        # SSE transport
        child_spec = %{
          id: {Server, name},
          start:
            {Server, :start_link,
             [
               [
                 name: name,
                 url: url,
                 auto_connect: true
               ]
             ]},
          restart: :temporary
        }

        case DynamicSupervisor.start_child(supervisor, child_spec) do
          {:ok, pid} ->
            {:ok, {name, pid}}

          {:error, reason} ->
            Logger.error("Failed to start MCP server #{name}: #{inspect(reason)}")
            {:error, reason}
        end

      true ->
        {:error, :invalid_config}
    end
  end
end
