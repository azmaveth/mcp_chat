defmodule MCPChat.Security.RevocationCache do
  @moduledoc """
  Distributed cache for token revocation lists.
  Uses ETS for fast local lookups with periodic sync to other nodes via PubSub.
  """

  use GenServer
  require Logger

  @table_name :revocation_cache
  @sync_interval :timer.seconds(10)
  @cleanup_interval :timer.hours(1)
  @pubsub_topic "security:revocations"

  defstruct [
    :table,
    :sync_timer,
    :cleanup_timer
  ]

  # Client API

  @doc """
  Starts the RevocationCache GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Adds a token to the revocation list.
  """
  def revoke(jti, expires_at \\ nil) do
    GenServer.call(__MODULE__, {:revoke, jti, expires_at})
  end

  @doc """
  Checks if a token is revoked.
  """
  def is_revoked?(jti) do
    case :ets.lookup(@table_name, jti) do
      [{^jti, expires_at}] ->
        # Check if revocation is still valid
        if expires_at == :permanent || System.system_time(:second) < expires_at do
          true
        else
          # Clean up expired revocation
          :ets.delete(@table_name, jti)
          false
        end

      [] ->
        false
    end
  end

  @doc """
  Gets statistics about the revocation cache.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Clears all revocations (use with caution).
  """
  def clear_all do
    GenServer.call(__MODULE__, :clear_all)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table
    table =
      :ets.new(@table_name, [
        :set,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])

    # Subscribe to PubSub for distributed sync
    Phoenix.PubSub.subscribe(MCPChat.PubSub, @pubsub_topic)

    # Schedule periodic sync
    sync_timer = Process.send_after(self(), :sync, @sync_interval)

    # Schedule periodic cleanup
    cleanup_timer = Process.send_after(self(), :cleanup, @cleanup_interval)

    state = %__MODULE__{
      table: table,
      sync_timer: sync_timer,
      cleanup_timer: cleanup_timer
    }

    Logger.info("RevocationCache initialized")

    {:ok, state}
  end

  @impl true
  def handle_call({:revoke, jti, expires_at}, _from, state) do
    # Default expiration to 24 hours if not specified
    final_expires_at = expires_at || System.system_time(:second) + 86400

    # Insert into local cache
    :ets.insert(@table_name, {jti, final_expires_at})

    # Broadcast to other nodes
    broadcast_revocation(jti, final_expires_at)

    Logger.info("Token revoked: #{jti}, expires: #{format_expiry(final_expires_at)}")

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    total_revocations = :ets.info(@table_name, :size)

    # Count permanent vs temporary revocations
    {permanent, temporary, expired} =
      :ets.foldl(
        fn {_jti, expires_at}, {perm, temp, exp} ->
          now = System.system_time(:second)

          cond do
            expires_at == :permanent -> {perm + 1, temp, exp}
            expires_at > now -> {perm, temp + 1, exp}
            true -> {perm, temp, exp + 1}
          end
        end,
        {0, 0, 0},
        @table_name
      )

    stats = %{
      total_revocations: total_revocations,
      permanent_revocations: permanent,
      temporary_revocations: temporary,
      expired_revocations: expired,
      node: node(),
      connected_nodes: Node.list()
    }

    {:reply, {:ok, stats}, state}
  end

  @impl true
  def handle_call(:clear_all, _from, state) do
    :ets.delete_all_objects(@table_name)

    # Broadcast clear to other nodes
    Phoenix.PubSub.broadcast(MCPChat.PubSub, @pubsub_topic, {:revocation_cleared, node()})

    Logger.warn("All revocations cleared")

    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:sync, state) do
    # In a real distributed system, this would sync with a central store
    # For now, we'll just log stats
    size = :ets.info(@table_name, :size)
    Logger.debug("RevocationCache sync: #{size} entries")

    # Schedule next sync
    sync_timer = Process.send_after(self(), :sync, @sync_interval)

    {:noreply, %{state | sync_timer: sync_timer}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Remove expired revocations
    now = System.system_time(:second)

    expired =
      :ets.select_delete(@table_name, [
        {
          {:"$1", :"$2"},
          [{:andalso, {:"/=", :"$2", :permanent}, {:<, :"$2", now}}],
          [true]
        }
      ])

    if expired > 0 do
      Logger.info("Cleaned up #{expired} expired revocations")
    end

    # Schedule next cleanup
    cleanup_timer = Process.send_after(self(), :cleanup, @cleanup_interval)

    {:noreply, %{state | cleanup_timer: cleanup_timer}}
  end

  @impl true
  def handle_info({:revocation_broadcast, jti, expires_at, from_node}, state) do
    # Received revocation from another node
    if from_node != node() do
      :ets.insert(@table_name, {jti, expires_at})
      Logger.debug("Received revocation from #{from_node}: #{jti}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:revocation_cleared, from_node}, state) do
    # Another node cleared all revocations
    if from_node != node() do
      :ets.delete_all_objects(@table_name)
      Logger.warn("Revocations cleared by #{from_node}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Cancel timers
    if state.sync_timer, do: Process.cancel_timer(state.sync_timer)
    if state.cleanup_timer, do: Process.cancel_timer(state.cleanup_timer)

    :ok
  end

  # Private Functions

  defp broadcast_revocation(jti, expires_at) do
    Phoenix.PubSub.broadcast(
      MCPChat.PubSub,
      @pubsub_topic,
      {:revocation_broadcast, jti, expires_at, node()}
    )
  end

  defp format_expiry(:permanent), do: "permanent"

  defp format_expiry(timestamp) do
    case DateTime.from_unix(timestamp) do
      {:ok, datetime} -> DateTime.to_string(datetime)
      _ -> "timestamp: #{timestamp}"
    end
  end

  @doc """
  Batch revocation for performance.
  """
  def revoke_batch(revocations) when is_list(revocations) do
    GenServer.call(__MODULE__, {:revoke_batch, revocations})
  end

  @impl true
  def handle_call({:revoke_batch, revocations}, _from, state) do
    now = System.system_time(:second)

    # Prepare batch insert
    objects =
      Enum.map(revocations, fn
        {jti, expires_at} -> {jti, expires_at || now + 86400}
        jti when is_binary(jti) -> {jti, now + 86400}
      end)

    # Insert all at once
    :ets.insert(@table_name, objects)

    # Broadcast batch
    Phoenix.PubSub.broadcast(
      MCPChat.PubSub,
      @pubsub_topic,
      {:revocation_batch_broadcast, objects, node()}
    )

    Logger.info("Batch revoked #{length(objects)} tokens")

    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:revocation_batch_broadcast, objects, from_node}, state) do
    if from_node != node() do
      :ets.insert(@table_name, objects)
      Logger.debug("Received batch revocation from #{from_node}: #{length(objects)} tokens")
    end

    {:noreply, state}
  end
end
