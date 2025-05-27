defmodule MCPChat.MCP.LazyServerManager do
  @moduledoc """
  Manages lazy loading of MCP servers to improve startup time.

  Instead of connecting to all servers at startup, this module:
  - Defers server connections until first use
  - Provides background connection option
  - Caches connection status
  """

  use GenServer
  require Logger

  alias MCPChat.MCP.ServerManager

  defstruct [
    :server_configs,
    :connection_states,
    :connection_mode,
    :background_tasks
  ]

  @connection_modes [:lazy, :eager, :background]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Set the connection mode for server startup.

  Modes:
  - :lazy - Connect on first use (default)
  - :eager - Connect immediately (original behavior)
  - :background - Connect in background after startup
  """
  def set_connection_mode(mode) when mode in @connection_modes do
    GenServer.call(__MODULE__, {:set_mode, mode})
  end

  @doc """
  Get a server connection, connecting lazily if needed.
  """
  def get_server(name) do
    GenServer.call(__MODULE__, {:get_server, name})
  end

  @doc """
  Check if a server is connected without triggering connection.
  """
  def connected?(name) do
    GenServer.call(__MODULE__, {:connected?, name})
  end

  @doc """
  Preload specific servers in the background.
  """
  def preload_servers(names) when is_list(names) do
    GenServer.cast(__MODULE__, {:preload, names})
  end

  @doc """
  Get connection statistics.
  """
  def stats() do
    GenServer.call(__MODULE__, :stats)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    mode = Keyword.get(opts, :connection_mode, :lazy)

    state = %__MODULE__{
      server_configs: %{},
      connection_states: %{},
      connection_mode: mode,
      background_tasks: %{}
    }

    # Load server configurations but don't connect yet
    {:ok, state, {:continue, :load_configs}}
  end

  @impl true
  def handle_continue(:load_configs, state) do
    configs = MCPChat.Config.get([:mcp, :servers]) || []

    server_configs =
      configs
      |> Enum.map(fn config ->
        name = config[:name] || config["name"]
        {name, config}
      end)
      |> Enum.into(%{})

    new_state = %{state | server_configs: server_configs}

    # Handle different connection modes
    case state.connection_mode do
      :eager ->
        # Original behavior - connect all immediately
        connect_all_servers(new_state)

      :background ->
        # Start background connections after a delay
        Process.send_after(self(), :start_background_connections, 100)
        {:noreply, new_state}

      :lazy ->
        # Do nothing, connect on demand
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_call({:set_mode, mode}, _from, state) do
    {:reply, :ok, %{state | connection_mode: mode}}
  end

  def handle_call({:get_server, name}, _from, state) do
    case get_connection_state(state, name) do
      :connected ->
        # Already connected, just return status
        result = ServerManager.get_server(name)
        {:reply, result, state}

      :connecting ->
        # Wait for connection to complete
        wait_for_connection(name, state)

      :disconnected ->
        # Need to connect
        new_state = start_connection(name, state)
        wait_for_connection(name, new_state)

      :not_configured ->
        {:reply, {:error, :not_configured}, state}
    end
  end

  def handle_call({:connected?, name}, _from, state) do
    connected = get_connection_state(state, name) == :connected
    {:reply, connected, state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      total_servers: map_size(state.server_configs),
      connected: count_by_state(state, :connected),
      connecting: count_by_state(state, :connecting),
      disconnected: count_by_state(state, :disconnected),
      mode: state.connection_mode
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:preload, names}, state) do
    new_state =
      names
      |> Enum.reduce(state, fn name, acc_state ->
        if get_connection_state(acc_state, name) == :disconnected do
          start_connection(name, acc_state)
        else
          acc_state
        end
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:start_background_connections, state) do
    Logger.info("Starting background MCP server connections...")

    new_state =
      state.server_configs
      |> Map.keys()
      |> Enum.reduce(state, fn name, acc_state ->
        start_background_connection(name, acc_state)
      end)

    {:noreply, new_state}
  end

  def handle_info({:connection_complete, name, result}, state) do
    new_state =
      case result do
        :ok ->
          Logger.debug("Server #{name} connected successfully")
          update_connection_state(state, name, :connected)

        {:error, reason} ->
          Logger.error("Failed to connect to server #{name}: #{inspect(reason)}")
          update_connection_state(state, name, :disconnected)
      end

    # Clean up background task
    new_state = %{new_state | background_tasks: Map.delete(new_state.background_tasks, name)}

    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Find which task died and clean up
    name =
      state.background_tasks
      |> Enum.find(fn {_name, task} -> task.pid == pid end)
      |> case do
        {name, _task} -> name
        nil -> nil
      end

    if name do
      new_state = %{
        state
        | background_tasks: Map.delete(state.background_tasks, name),
          connection_states: Map.put(state.connection_states, name, :disconnected)
      }

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  # Private Functions

  defp get_connection_state(state, name) do
    cond do
      not Map.has_key?(state.server_configs, name) ->
        :not_configured

      Map.get(state.connection_states, name) == :connected ->
        :connected

      Map.get(state.connection_states, name) == :connecting ->
        :connecting

      true ->
        :disconnected
    end
  end

  defp start_connection(name, state) do
    config = Map.get(state.server_configs, name)

    if config do
      # Mark as connecting
      new_state = update_connection_state(state, name, :connecting)

      # Start connection in background
      task =
        Task.async(fn ->
          try do
            case ServerManager.start_server(config) do
              {:ok, _} -> :ok
              error -> error
            end
          rescue
            e -> {:error, e}
          end
        end)

      send(self(), {:connection_complete, name, Task.await(task, 5_000)})
      new_state
    else
      state
    end
  end

  defp start_background_connection(name, state) do
    if get_connection_state(state, name) == :disconnected do
      config = Map.get(state.server_configs, name)

      task =
        Task.async(fn ->
          # Stagger connections
          Process.sleep(:rand.uniform(1_000))

          try do
            case ServerManager.start_server(config) do
              {:ok, _} -> :ok
              error -> error
            end
          rescue
            e -> {:error, e}
          end
        end)

      # Monitor the task
      Process.monitor(task.pid)

      %{
        state
        | background_tasks: Map.put(state.background_tasks, name, task),
          connection_states: Map.put(state.connection_states, name, :connecting)
      }
    else
      state
    end
  end

  defp wait_for_connection(name, state) do
    # Simple busy wait with timeout
    # In production, this should use proper synchronization
    wait_result =
      Enum.reduce_while(1..50, :timeout, fn _, _ ->
        Process.sleep(100)

        case get_connection_state(state, name) do
          :connected -> {:halt, :ok}
          :disconnected -> {:halt, :error}
          _ -> {:cont, :timeout}
        end
      end)

    case wait_result do
      :ok ->
        result = ServerManager.get_server(name)
        {:reply, result, state}

      _ ->
        {:reply, {:error, :connection_failed}, state}
    end
  end

  defp connect_all_servers(state) do
    results =
      state.server_configs
      |> Enum.map(fn {name, config} ->
        Logger.info("Connecting to MCP server: #{name}")
        result = ServerManager.start_server(config)
        {name, result}
      end)

    # Update connection states based on results
    new_connection_states =
      results
      |> Enum.map(fn
        {name, {:ok, _}} -> {name, :connected}
        {name, _} -> {name, :disconnected}
      end)
      |> Enum.into(%{})

    {:noreply, %{state | connection_states: new_connection_states}}
  end

  defp update_connection_state(state, name, status) do
    %{state | connection_states: Map.put(state.connection_states, name, status)}
  end

  defp count_by_state(state, status) do
    state.connection_states
    |> Enum.count(fn {_, s} -> s == status end)
  end
end
