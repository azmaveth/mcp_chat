defmodule MCPChat.ConnectionPool do
  @moduledoc """
  Supervised connection pool for HTTP clients.
  Provides health-checked, reusable connections with automatic recovery.
  """
  use GenServer
  require Logger

  defstruct [
    :name,
    :size,
    :connections,
    :available,
    :in_use,
    :waiting,
    :health_check_interval,
    :connection_timeout,
    :idle_timeout,
    :max_idle_time
  ]

  @default_size 5
  # 30 seconds
  @default_health_check_interval 30_000
  @default_connection_timeout 5_000
  @default_idle_timeout 60_000
  # 5 minutes
  @default_max_idle_time 300_000

  # Client API

  @doc """
  Starts a connection pool with the given options.

  Options:
  - name: Pool name (required)
  - size: Number of connections (default: 5)
  - health_check_interval: Ms between health checks (default: 30_000)
  - connection_timeout: Ms to wait for connection (default: 5_000)
  - idle_timeout: Ms before idle connection check (default: 60_000)
  """
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Checks out a connection from the pool.
  Returns {:ok, conn} or {:error, reason}.
  """
  def checkout(pool, timeout \\ 5_000) do
    GenServer.call(pool, :checkout, timeout)
  end

  @doc """
  Returns a connection to the pool.
  """
  def checkin(pool, conn) do
    GenServer.cast(pool, {:checkin, conn})
  end

  @doc """
  Executes a function with a pooled connection.
  Automatically handles checkout/checkin.
  """
  def with_connection(pool, fun) when is_function(fun, 1) do
    case checkout(pool) do
      {:ok, conn} ->
        try do
          result = fun.(conn)
          checkin(pool, conn)
          {:ok, result}
        catch
          kind, reason ->
            # Don't return bad connections to the pool
            GenServer.cast(pool, {:remove_connection, conn})
            :erlang.raise(kind, reason, __STACKTRACE__)
        end

      error ->
        error
    end
  end

  @doc """
  Gets pool statistics.
  """
  def get_stats(pool) do
    GenServer.call(pool, :get_stats)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      size: opts[:size] || @default_size,
      connections: %{},
      available: :queue.new(),
      in_use: MapSet.new(),
      waiting: :queue.new(),
      health_check_interval: opts[:health_check_interval] || @default_health_check_interval,
      connection_timeout: opts[:connection_timeout] || @default_connection_timeout,
      idle_timeout: opts[:idle_timeout] || @default_idle_timeout,
      max_idle_time: opts[:max_idle_time] || @default_max_idle_time
    }

    # Start initial connections
    send(self(), :init_connections)

    # Schedule health checks
    Process.send_after(self(), :health_check, state.health_check_interval)

    {:ok, state}
  end

  @impl true
  def handle_call(:checkout, from, state) do
    case get_available_connection(state) do
      {:ok, conn, new_state} ->
        {:reply, {:ok, conn}, new_state}

      :none_available ->
        handle_no_available_connections(from, state)
    end
  end

  defp handle_no_available_connections(from, state) do
    if can_create_new_connection?(state) do
      attempt_new_connection(from, state)
    else
      queue_checkout_request(from, state)
    end
  end

  defp can_create_new_connection?(state) do
    map_size(state.connections) < state.size
  end

  defp attempt_new_connection(from, state) do
    case create_connection() do
      {:ok, conn} ->
        handle_new_connection_success(conn, state)

      {:error, _reason} ->
        queue_checkout_request(from, state)
    end
  end

  defp handle_new_connection_success(conn, state) do
    new_state =
      state
      |> add_connection(conn)
      |> mark_in_use(conn)

    {:reply, {:ok, conn}, new_state}
  end

  defp queue_checkout_request(from, state) do
    new_waiting = :queue.in(from, state.waiting)
    {:noreply, %{state | waiting: new_waiting}}
  end

  def handle_call(:get_stats, _from, state) do
    stats = %{
      total: map_size(state.connections),
      available: :queue.len(state.available),
      in_use: MapSet.size(state.in_use),
      waiting: :queue.len(state.waiting),
      healthy: count_healthy_connections(state)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:checkin, conn}, state) do
    new_state =
      if MapSet.member?(state.in_use, conn) do
        state
        |> mark_available(conn)
        |> process_waiting_queue()
      else
        Logger.warning("Attempted to checkin unknown connection: #{inspect(conn)}")
        state
      end

    {:noreply, new_state}
  end

  def handle_cast({:remove_connection, conn}, state) do
    new_state = remove_connection(state, conn)

    # Try to create a replacement if we're below minimum size
    if map_size(new_state.connections) < state.size do
      send(self(), :create_replacement_connection)
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:init_connections, state) do
    # Create initial pool of connections
    new_state =
      Enum.reduce(1..state.size, state, fn _, acc ->
        case create_connection() do
          {:ok, conn} ->
            add_connection(acc, conn)

          {:error, reason} ->
            Logger.error("Failed to create initial connection: #{inspect(reason)}")
            acc
        end
      end)

    {:noreply, new_state}
  end

  def handle_info(:health_check, state) do
    # Check health of all connections
    new_state = perform_health_check(state)

    # Schedule next health check
    Process.send_after(self(), :health_check, state.health_check_interval)

    {:noreply, new_state}
  end

  def handle_info(:create_replacement_connection, state) do
    new_state =
      case create_connection() do
        {:ok, conn} ->
          add_connection(state, conn)

        {:error, reason} ->
          Logger.error("Failed to create replacement connection: #{inspect(reason)}")
          state
      end

    {:noreply, new_state}
  end

  def handle_info({:idle_timeout, conn}, state) do
    # Check if connection has been idle too long
    case Map.get(state.connections, conn) do
      %{last_used: last_used} ->
        if System.monotonic_time(:millisecond) - last_used > state.max_idle_time do
          new_state = remove_connection(state, conn)
          {:noreply, new_state}
        else
          {:noreply, state}
        end

      nil ->
        {:noreply, state}
    end
  end

  # Private Functions

  defp create_connection do
    # This is a placeholder - actual implementation would create
    # HTTP client connections (e.g., Mint, Finch, etc.)
    {:ok, make_ref()}
  end

  defp add_connection(state, conn) do
    conn_info = %{
      conn: conn,
      created_at: System.monotonic_time(:millisecond),
      last_used: System.monotonic_time(:millisecond),
      healthy: true
    }

    new_connections = Map.put(state.connections, conn, conn_info)
    new_available = :queue.in(conn, state.available)

    %{state | connections: new_connections, available: new_available}
  end

  defp remove_connection(state, conn) do
    new_connections = Map.delete(state.connections, conn)
    new_available = :queue.filter(fn c -> c != conn end, state.available)
    new_in_use = MapSet.delete(state.in_use, conn)

    %{state | connections: new_connections, available: new_available, in_use: new_in_use}
  end

  defp get_available_connection(state) do
    case :queue.out(state.available) do
      {{:value, conn}, new_queue} ->
        new_state = %{state | available: new_queue}
        new_state = mark_in_use(new_state, conn)
        {:ok, conn, new_state}

      {:empty, _} ->
        :none_available
    end
  end

  defp mark_in_use(state, conn) do
    new_in_use = MapSet.put(state.in_use, conn)

    # Update last used time
    new_connections =
      Map.update!(state.connections, conn, fn info ->
        %{info | last_used: System.monotonic_time(:millisecond)}
      end)

    %{state | in_use: new_in_use, connections: new_connections}
  end

  defp mark_available(state, conn) do
    new_in_use = MapSet.delete(state.in_use, conn)
    new_available = :queue.in(conn, state.available)

    # Schedule idle timeout check
    Process.send_after(self(), {:idle_timeout, conn}, state.idle_timeout)

    %{state | in_use: new_in_use, available: new_available}
  end

  defp process_waiting_queue(state) do
    case :queue.out(state.waiting) do
      {{:value, from}, new_waiting} ->
        case get_available_connection(%{state | waiting: new_waiting}) do
          {:ok, conn, new_state} ->
            GenServer.reply(from, {:ok, conn})
            new_state

          :none_available ->
            %{state | waiting: new_waiting}
        end

      {:empty, _} ->
        state
    end
  end

  defp perform_health_check(state) do
    # Check each connection's health
    new_connections =
      Map.new(state.connections, fn {conn, info} ->
        healthy = check_connection_health(conn)
        {conn, %{info | healthy: healthy}}
      end)

    # Remove unhealthy connections
    unhealthy_conns =
      new_connections
      |> Enum.filter(fn {_, info} -> not info.healthy end)
      |> Enum.map(fn {conn, _} -> conn end)

    new_state = %{state | connections: new_connections}

    Enum.reduce(unhealthy_conns, new_state, fn conn, acc ->
      Logger.warning("Removing unhealthy connection: #{inspect(conn)}")
      remove_connection(acc, conn)
    end)
  end

  defp check_connection_health(_conn) do
    # Placeholder - actual implementation would ping the connection
    true
  end

  defp count_healthy_connections(state) do
    state.connections
    |> Enum.count(fn {_, info} -> info.healthy end)
  end
end
