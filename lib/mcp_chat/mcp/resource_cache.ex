defmodule MCPChat.MCP.ResourceCache do
  @moduledoc """
  Local caching layer for MCP resources with automatic invalidation via subscriptions.
  Stores frequently accessed resources to reduce server load and improve response times.
  """

  use GenServer
  require Logger

  alias MCPChat.MCP.ServerManager
  alias ExMCP.Client

  @table_name :mcp_resource_cache
  @stats_table :mcp_resource_cache_stats
  @default_ttl :timer.hours(1)
  # 100MB
  @max_cache_size 100 * 1_024 * 1_024
  @cleanup_interval :timer.minutes(5)

  defstruct [
    :cache_dir,
    :max_size,
    :ttl,
    :cleanup_timer,
    :subscriptions
  ]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get a resource from cache or fetch from server.
  Returns {:ok, resource} or {:error, reason}.
  """
  def get_resource(server_name, uri, opts \\ []) do
    GenServer.call(__MODULE__, {:get_resource, server_name, uri, opts})
  end

  @doc """
  Invalidate a cached resource.
  """
  def invalidate(server_name, uri) do
    GenServer.cast(__MODULE__, {:invalidate, server_name, uri})
  end

  @doc """
  Clear all cached resources for a server.
  """
  def clear_server_cache(server_name) do
    GenServer.cast(__MODULE__, {:clear_server, server_name})
  end

  @doc """
  Clear the entire cache.
  """
  def clear_all() do
    GenServer.cast(__MODULE__, :clear_all)
  end

  @doc """
  Get cache statistics.
  """
  def get_stats() do
    try do
      [{_, stats}] = :ets.lookup(@stats_table, :global)
      stats
    rescue
      _ ->
        %{
          total_resources: 0,
          total_size: 0,
          hit_rate: 0.0,
          avg_response_time: 0,
          memory_usage: 0,
          last_cleanup: nil
        }
    end
  end

  @doc """
  List all cached resources.
  """
  def list_resources() do
    try do
      :ets.tab2list(@table_name)
      |> Enum.map(fn {{server, uri}, resource} ->
        Map.merge(resource, %{server_name: server, uri: uri})
      end)
    rescue
      _ -> []
    end
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    # Create ETS tables
    :ets.new(@table_name, [:named_table, :public, :set])
    :ets.new(@stats_table, [:named_table, :public, :set])

    # Initialize stats
    :ets.insert(
      @stats_table,
      {:global,
       %{
         total_resources: 0,
         total_size: 0,
         hits: 0,
         misses: 0,
         hit_rate: 0.0,
         avg_response_time: 0,
         memory_usage: 0,
         last_cleanup: nil
       }}
    )

    # Set up cache directory
    cache_dir = opts[:cache_dir] || Path.join(System.tmp_dir!(), "mcp_chat_cache")
    File.mkdir_p!(cache_dir)

    state = %__MODULE__{
      cache_dir: cache_dir,
      max_size: opts[:max_size] || @max_cache_size,
      ttl: opts[:ttl] || @default_ttl,
      subscriptions: %{}
    }

    # Schedule periodic cleanup
    cleanup_timer = :timer.send_interval(@cleanup_interval, :cleanup)

    {:ok, %{state | cleanup_timer: cleanup_timer}}
  end

  @impl true
  def handle_call({:get_resource, server_name, uri, opts}, _from, state) do
    start_time = System.monotonic_time(:millisecond)

    case lookup_cache(server_name, uri) do
      {:ok, resource} ->
        # Cache hit
        update_stats(:hit, System.monotonic_time(:millisecond) - start_time)
        update_access_time(server_name, uri)
        {:reply, {:ok, resource}, state}

      :not_found ->
        # Cache miss - fetch from server
        case fetch_and_cache(server_name, uri, opts, state) do
          {:ok, resource} = result ->
            update_stats(:miss, System.monotonic_time(:millisecond) - start_time)

            # Subscribe to resource changes if not already subscribed
            new_state = maybe_subscribe(state, server_name, uri)

            {:reply, result, new_state}

          error ->
            update_stats(:miss, System.monotonic_time(:millisecond) - start_time)
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_cast({:invalidate, server_name, uri}, state) do
    Logger.debug("Invalidating cached resource: #{server_name} - #{uri}")

    # Remove from ETS
    :ets.delete(@table_name, {server_name, uri})

    # Remove file cache
    cache_file = get_cache_file_path(state.cache_dir, server_name, uri)
    File.rm(cache_file)

    update_cache_size()

    {:noreply, state}
  end

  @impl true
  def handle_cast({:clear_server, server_name}, state) do
    Logger.info("Clearing cache for server: #{server_name}")

    # Find and remove all entries for this server
    :ets.match_delete(@table_name, {{server_name, :_}, :_})

    # Remove server cache directory
    server_dir = Path.join(state.cache_dir, server_name)
    File.rm_rf(server_dir)

    update_cache_size()

    # Unsubscribe from all resources for this server
    new_subscriptions = Map.reject(state.subscriptions, fn {{srv, _}, _} -> srv == server_name end)

    {:noreply, %{state | subscriptions: new_subscriptions}}
  end

  @impl true
  def handle_cast(:clear_all, state) do
    Logger.info("Clearing entire resource cache")

    # Clear ETS
    :ets.delete_all_objects(@table_name)

    # Clear file cache
    File.rm_rf(state.cache_dir)
    File.mkdir_p!(state.cache_dir)

    # Reset stats
    :ets.insert(
      @stats_table,
      {:global,
       %{
         total_resources: 0,
         total_size: 0,
         hits: 0,
         misses: 0,
         hit_rate: 0.0,
         avg_response_time: 0,
         memory_usage: 0,
         last_cleanup: DateTime.utc_now()
       }}
    )

    # Unsubscribe from all resources
    Enum.each(state.subscriptions, fn {_, sub_ref} ->
      # TODO: Implement unsubscribe when ex_mcp supports it
      _ = sub_ref
    end)

    {:noreply, %{state | subscriptions: %{}}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    Logger.debug("Running cache cleanup")

    now = System.os_time(:second)

    # Remove expired entries
    expired =
      :ets.select(@table_name, [
        {
          {{:"$1", :"$2"}, %{expires_at: :"$3", size: :"$4"}},
          [{:<, :"$3", now}],
          [{{:"$1", :"$2", :"$4"}}]
        }
      ])

    expired_count =
      Enum.reduce(expired, 0, fn {server, uri, _size}, count ->
        :ets.delete(@table_name, {server, uri})

        # Remove file
        cache_file = get_cache_file_path(state.cache_dir, server, uri)
        File.rm(cache_file)

        count + 1
      end)

    if expired_count > 0 do
      Logger.info("Cleaned up #{expired_count} expired cache entries")
    end

    # Update stats
    update_cache_size()
    update_cleanup_time()

    # Check if cache size exceeds limit
    enforce_size_limit(state)

    {:noreply, state}
  end

  @impl true
  def handle_info({:resource_changed, server_name, uri}, state) do
    Logger.info("Resource changed notification received: #{server_name} - #{uri}")

    # Invalidate the cached resource
    handle_cast({:invalidate, server_name, uri}, state)
  end

  # Private Functions

  defp lookup_cache(server_name, uri) do
    case :ets.lookup(@table_name, {server_name, uri}) do
      [{_, resource}] ->
        # Check if expired
        if resource.expires_at > System.os_time(:second) do
          {:ok, resource.data}
        else
          :ets.delete(@table_name, {server_name, uri})
          :not_found
        end

      [] ->
        :not_found
    end
  end

  defp fetch_and_cache(server_name, uri, _opts, state) do
    with {:ok, client} <- ServerManager.get_server(server_name),
         {:ok, resource} <- Client.read_resource(client, uri) do
      # Cache the resource
      cache_entry = %{
        data: resource,
        size: estimate_size(resource),
        cached_at: DateTime.utc_now(),
        last_accessed: DateTime.utc_now(),
        expires_at: System.os_time(:second) + div(state.ttl, 1_000),
        hit_count: 0
      }

      # Store in ETS
      :ets.insert(@table_name, {{server_name, uri}, cache_entry})

      # Store to disk for larger resources
      # 10KB threshold
      if cache_entry.size > 1_024 * 10 do
        Task.start(fn ->
          write_to_disk_cache(state.cache_dir, server_name, uri, resource)
        end)
      end

      update_cache_size()

      {:ok, resource}
    end
  end

  defp maybe_subscribe(state, server_name, uri) do
    key = {server_name, uri}

    if Map.has_key?(state.subscriptions, key) do
      state
    else
      # Try to subscribe to resource changes
      case ServerManager.get_server(server_name) do
        {:ok, client} ->
          case Client.subscribe_resource(client, uri) do
            {:ok, subscription_ref} ->
              Logger.debug("Subscribed to resource changes: #{server_name} - #{uri}")
              %{state | subscriptions: Map.put(state.subscriptions, key, subscription_ref)}

            {:error, :not_supported} ->
              # Server doesn't support subscriptions
              state

            {:error, reason} ->
              Logger.warning("Failed to subscribe to resource: #{inspect(reason)}")
              state
          end

        _ ->
          state
      end
    end
  end

  defp write_to_disk_cache(cache_dir, server_name, uri, resource) do
    file_path = get_cache_file_path(cache_dir, server_name, uri)
    dir_path = Path.dirname(file_path)

    File.mkdir_p!(dir_path)

    # Serialize and write
    binary = :erlang.term_to_binary(resource, [:compressed])
    File.write!(file_path, binary)
  end

  defp get_cache_file_path(cache_dir, server_name, uri) do
    # Create a safe filename from the URI
    safe_name =
      uri
      |> String.replace(["/", "\\", ":", "*", "?", "\"", "<", ">", "|"], "_")
      |> String.slice(0, 200)

    hash = :crypto.hash(:md5, uri) |> Base.encode16(case: :lower)

    Path.join([cache_dir, server_name, "#{safe_name}_#{hash}.cache"])
  end

  defp estimate_size(resource) do
    # Rough estimation of memory size
    :erlang.external_size(resource)
  end

  defp update_stats(type, response_time) do
    [{_, stats}] = :ets.lookup(@stats_table, :global)

    new_stats =
      case type do
        :hit ->
          hits = stats.hits + 1
          total = hits + stats.misses
          %{stats | hits: hits, hit_rate: if(total > 0, do: hits / total, else: 0.0)}

        :miss ->
          %{stats | misses: stats.misses + 1}
      end

    # Update average response time
    total_requests = new_stats.hits + new_stats.misses

    avg_time =
      if total_requests > 1 do
        (stats.avg_response_time * (total_requests - 1) + response_time) / total_requests
      else
        response_time
      end

    new_stats = %{new_stats | avg_response_time: avg_time}

    :ets.insert(@stats_table, {:global, new_stats})
  end

  defp update_access_time(server_name, uri) do
    case :ets.lookup(@table_name, {server_name, uri}) do
      [{key, resource}] ->
        updated = %{resource | last_accessed: DateTime.utc_now(), hit_count: resource.hit_count + 1}
        :ets.insert(@table_name, {key, updated})

      _ ->
        :ok
    end
  end

  defp update_cache_size() do
    # Calculate total size
    total_size =
      :ets.foldl(
        fn {_, resource}, acc ->
          acc + resource.size
        end,
        0,
        @table_name
      )

    total_resources = :ets.info(@table_name, :size)

    [{_, stats}] = :ets.lookup(@stats_table, :global)

    new_stats = %{
      stats
      | total_size: total_size,
        total_resources: total_resources,
        memory_usage: :ets.info(@table_name, :memory) * :erlang.system_info(:wordsize)
    }

    :ets.insert(@stats_table, {:global, new_stats})
  end

  defp update_cleanup_time() do
    [{_, stats}] = :ets.lookup(@stats_table, :global)
    :ets.insert(@stats_table, {:global, %{stats | last_cleanup: DateTime.utc_now()}})
  end

  defp enforce_size_limit(state) do
    [{_, stats}] = :ets.lookup(@stats_table, :global)

    if stats.total_size > state.max_size do
      # Remove least recently accessed items
      entries =
        :ets.tab2list(@table_name)
        |> Enum.sort_by(fn {_, resource} -> resource.last_accessed end)

      size_to_remove = stats.total_size - state.max_size
      removed_size = 0

      _ =
        Enum.reduce_while(entries, removed_size, fn {{server, uri}, resource}, acc ->
          if acc >= size_to_remove do
            {:halt, acc}
          else
            :ets.delete(@table_name, {server, uri})

            # Remove file
            cache_file = get_cache_file_path(state.cache_dir, server, uri)
            File.rm(cache_file)

            {:cont, acc + resource.size}
          end
        end)

      update_cache_size()
    end
  end
end
