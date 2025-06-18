defmodule MCPChat.Persistence.SnapshotManager do
  @moduledoc """
  Manages periodic snapshots of system state for efficient recovery.

  This module handles creating, storing, and retrieving snapshots
  of the entire MCP Chat system state to enable fast recovery
  without replaying all events from the beginning.
  """

  use GenServer
  require Logger

  alias MCPChat.Persistence.{EventStore, EventJournal}

  @snapshot_dir "~/.mcp_chat/snapshots"
  # 5 minutes
  @snapshot_interval_ms 60_000 * 5
  @max_snapshots_to_keep 10
  @snapshot_compression_level 6

  # Snapshot state
  defstruct [
    :snapshot_dir,
    :timer,
    :last_snapshot_event_id,
    :snapshot_interval_ms,
    :compression_enabled
  ]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Create a snapshot immediately.
  """
  def create_snapshot(description \\ "Manual snapshot") do
    GenServer.call(__MODULE__, {:create_snapshot, description})
  end

  @doc """
  Get the most recent snapshot information.
  """
  def get_latest_snapshot do
    GenServer.call(__MODULE__, :get_latest_snapshot)
  end

  @doc """
  List all available snapshots.
  """
  def list_snapshots do
    GenServer.call(__MODULE__, :list_snapshots)
  end

  @doc """
  Restore system state from a specific snapshot.
  """
  def restore_from_snapshot(snapshot_id) do
    GenServer.call(__MODULE__, {:restore_from_snapshot, snapshot_id}, :infinity)
  end

  @doc """
  Delete old snapshots to free up disk space.
  """
  def cleanup_snapshots(keep_count \\ @max_snapshots_to_keep) do
    GenServer.call(__MODULE__, {:cleanup_snapshots, keep_count})
  end

  @doc """
  Get snapshot statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    snapshot_dir = expand_snapshot_dir(opts[:snapshot_dir] || @snapshot_dir)
    interval = opts[:snapshot_interval_ms] || @snapshot_interval_ms
    compression = Keyword.get(opts, :compression_enabled, true)

    Logger.info("Starting Snapshot Manager",
      snapshot_dir: snapshot_dir,
      interval_ms: interval,
      compression: compression
    )

    # Ensure directory exists
    File.mkdir_p!(snapshot_dir)

    state = %__MODULE__{
      snapshot_dir: snapshot_dir,
      snapshot_interval_ms: interval,
      compression_enabled: compression,
      last_snapshot_event_id: 0
    }

    case initialize_snapshot_manager(state) do
      {:ok, initialized_state} ->
        # Start periodic snapshot timer
        timer = Process.send_after(self(), :create_periodic_snapshot, interval)
        final_state = %{initialized_state | timer: timer}

        Logger.info("Snapshot Manager initialized",
          last_snapshot: final_state.last_snapshot_event_id
        )

        {:ok, final_state}

      {:error, reason} ->
        Logger.error("Failed to initialize Snapshot Manager", reason: inspect(reason))
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:create_snapshot, description}, _from, state) do
    case create_snapshot_impl(description, state) do
      {:ok, snapshot_info, new_state} ->
        {:reply, {:ok, snapshot_info}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_latest_snapshot, _from, state) do
    result = get_latest_snapshot_impl(state)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_snapshots, _from, state) do
    result = list_snapshots_impl(state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:restore_from_snapshot, snapshot_id}, _from, state) do
    result = restore_from_snapshot_impl(snapshot_id, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:cleanup_snapshots, keep_count}, _from, state) do
    case cleanup_snapshots_impl(keep_count, state) do
      {:ok, cleanup_stats} ->
        {:reply, {:ok, cleanup_stats}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = get_stats_impl(state)
    {:reply, stats, state}
  end

  @impl true
  def handle_info(:create_periodic_snapshot, state) do
    # Create periodic snapshot
    case create_snapshot_impl("Periodic snapshot", state) do
      {:ok, _snapshot_info, new_state} ->
        Logger.debug("Periodic snapshot created successfully")
        schedule_next_snapshot(new_state)

      {:error, reason} ->
        Logger.error("Periodic snapshot failed", reason: inspect(reason))
        schedule_next_snapshot(state)
    end
  end

  # Private functions

  defp initialize_snapshot_manager(state) do
    # Find the most recent snapshot
    case find_latest_snapshot_event_id(state) do
      {:ok, event_id} ->
        {:ok, %{state | last_snapshot_event_id: event_id}}

      {:error, :not_found} ->
        {:ok, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_snapshot_impl(description, state) do
    snapshot_id = generate_snapshot_id()
    snapshot_path = Path.join(state.snapshot_dir, "#{snapshot_id}.snapshot")

    Logger.info("Creating snapshot", id: snapshot_id, description: description)

    try do
      # Get current system state
      system_state = capture_system_state()

      # Get current event store stats for correlation
      event_stats = EventStore.get_stats()

      snapshot_data = %{
        snapshot_id: snapshot_id,
        description: description,
        created_at: DateTime.utc_now(),
        format_version: 1,
        last_event_id: event_stats.total_events,
        system_state: system_state,
        metadata: %{
          mcp_chat_version: get_version(),
          elixir_version: System.version(),
          otp_version: System.otp_release()
        }
      }

      # Serialize and optionally compress
      serialized = :erlang.term_to_binary(snapshot_data)

      final_data =
        if state.compression_enabled do
          :zlib.compress(serialized)
        else
          serialized
        end

      # Write to file
      File.write!(snapshot_path, final_data)

      # Create snapshot marker event
      EventStore.create_snapshot_marker(%{
        snapshot_id: snapshot_id,
        snapshot_path: snapshot_path,
        description: description,
        snapshot_size: byte_size(final_data),
        compressed: state.compression_enabled
      })

      snapshot_info = %{
        snapshot_id: snapshot_id,
        description: description,
        created_at: snapshot_data.created_at,
        last_event_id: snapshot_data.last_event_id,
        file_size: byte_size(final_data),
        compressed: state.compression_enabled
      }

      new_state = %{state | last_snapshot_event_id: snapshot_data.last_event_id}

      Logger.info("Snapshot created successfully",
        id: snapshot_id,
        size_bytes: byte_size(final_data),
        last_event_id: snapshot_data.last_event_id
      )

      {:ok, snapshot_info, new_state}
    rescue
      error ->
        Logger.error("Snapshot creation failed",
          id: snapshot_id,
          error: inspect(error)
        )

        {:error, {:snapshot_creation_failed, error}}
    end
  end

  defp get_latest_snapshot_impl(state) do
    case list_snapshot_files(state.snapshot_dir) do
      [] ->
        {:error, :no_snapshots}

      files ->
        latest_file = Enum.max_by(files, &File.stat!(&1).mtime)
        load_snapshot_info(latest_file, state)
    end
  end

  defp list_snapshots_impl(state) do
    case list_snapshot_files(state.snapshot_dir) do
      [] ->
        {:ok, []}

      files ->
        snapshots =
          Enum.map(files, fn file ->
            case load_snapshot_info(file, state) do
              {:ok, info} -> info
              {:error, _} -> nil
            end
          end)
          |> Enum.filter(& &1)
          |> Enum.sort_by(& &1.created_at, {:desc, DateTime})

        {:ok, snapshots}
    end
  end

  defp restore_from_snapshot_impl(snapshot_id, state) do
    snapshot_path = Path.join(state.snapshot_dir, "#{snapshot_id}.snapshot")

    if File.exists?(snapshot_path) do
      Logger.info("Restoring from snapshot", id: snapshot_id)

      try do
        # Load snapshot data
        case load_snapshot_data(snapshot_path, state) do
          {:ok, snapshot_data} ->
            # Apply the system state
            apply_system_state(snapshot_data.system_state)

            Logger.info("Snapshot restore completed",
              id: snapshot_id,
              last_event_id: snapshot_data.last_event_id
            )

            {:ok,
             %{
               snapshot_id: snapshot_id,
               restored_event_id: snapshot_data.last_event_id,
               created_at: snapshot_data.created_at
             }}

          {:error, reason} ->
            {:error, reason}
        end
      rescue
        error ->
          Logger.error("Snapshot restore failed",
            id: snapshot_id,
            error: inspect(error)
          )

          {:error, {:restore_failed, error}}
      end
    else
      {:error, {:snapshot_not_found, snapshot_id}}
    end
  end

  defp cleanup_snapshots_impl(keep_count, state) do
    Logger.info("Cleaning up snapshots", keep_count: keep_count)

    snapshot_files = list_snapshot_files(state.snapshot_dir)

    if length(snapshot_files) > keep_count do
      # Sort by modification time and keep the newest ones
      sorted_files = Enum.sort_by(snapshot_files, &File.stat!(&1).mtime, {:desc, DateTime})
      files_to_delete = Enum.drop(sorted_files, keep_count)

      deleted_count =
        Enum.reduce(files_to_delete, 0, fn file, acc ->
          case File.rm(file) do
            :ok ->
              Logger.debug("Deleted snapshot", file: Path.basename(file))
              acc + 1

            {:error, reason} ->
              Logger.warning("Failed to delete snapshot",
                file: Path.basename(file),
                reason: inspect(reason)
              )

              acc
          end
        end)

      Logger.info("Snapshot cleanup completed",
        deleted: deleted_count,
        remaining: length(snapshot_files) - deleted_count
      )

      {:ok,
       %{
         deleted_count: deleted_count,
         remaining_count: length(snapshot_files) - deleted_count
       }}
    else
      {:ok, %{deleted_count: 0, remaining_count: length(snapshot_files)}}
    end
  end

  defp get_stats_impl(state) do
    snapshot_files = list_snapshot_files(state.snapshot_dir)

    total_size =
      Enum.reduce(snapshot_files, 0, fn file, acc ->
        acc + File.stat!(file).size
      end)

    %{
      total_snapshots: length(snapshot_files),
      total_size_bytes: total_size,
      last_snapshot_event_id: state.last_snapshot_event_id,
      snapshot_directory: state.snapshot_dir,
      compression_enabled: state.compression_enabled,
      snapshot_interval_ms: state.snapshot_interval_ms
    }
  end

  defp capture_system_state do
    # Capture current system state from various managers
    %{
      # Session state would be captured from SessionManager
      sessions: %{},

      # Agent state would be captured from AgentManager
      agents: %{},

      # MCP server connections
      mcp_servers: %{},

      # Configuration snapshot
      config: %{},

      # Statistics and counters
      statistics: %{
        uptime_ms: System.monotonic_time(:millisecond),
        total_messages: 0,
        total_tool_calls: 0
      }
    }
  end

  defp apply_system_state(_system_state) do
    # In a full implementation, this would restore:
    # - Session state
    # - Agent state
    # - MCP connections
    # - Configuration
    Logger.info("System state restoration - placeholder implementation")
  end

  defp load_snapshot_info(snapshot_path, state) do
    case load_snapshot_data(snapshot_path, state) do
      {:ok, snapshot_data} ->
        file_stat = File.stat!(snapshot_path)

        {:ok,
         %{
           snapshot_id: snapshot_data.snapshot_id,
           description: snapshot_data.description,
           created_at: snapshot_data.created_at,
           last_event_id: snapshot_data.last_event_id,
           file_size: file_stat.size,
           compressed: state.compression_enabled
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_snapshot_data(snapshot_path, state) do
    try do
      file_data = File.read!(snapshot_path)

      # Decompress if needed
      serialized_data =
        if state.compression_enabled do
          :zlib.uncompress(file_data)
        else
          file_data
        end

      snapshot_data = :erlang.binary_to_term(serialized_data)
      {:ok, snapshot_data}
    rescue
      error ->
        Logger.error("Failed to load snapshot",
          path: snapshot_path,
          error: inspect(error)
        )

        {:error, {:load_failed, error}}
    end
  end

  defp list_snapshot_files(snapshot_dir) do
    case File.ls(snapshot_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".snapshot"))
        |> Enum.map(&Path.join(snapshot_dir, &1))

      {:error, _} ->
        []
    end
  end

  defp find_latest_snapshot_event_id(state) do
    case get_latest_snapshot_impl(state) do
      {:ok, snapshot_info} -> {:ok, snapshot_info.last_event_id}
      {:error, :no_snapshots} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp schedule_next_snapshot(state) do
    if state.timer do
      Process.cancel_timer(state.timer)
    end

    timer = Process.send_after(self(), :create_periodic_snapshot, state.snapshot_interval_ms)
    %{state | timer: timer}
  end

  defp generate_snapshot_id do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{timestamp}_#{random}"
  end

  defp get_version do
    case Application.spec(:mcp_chat, :vsn) do
      nil -> "unknown"
      version -> to_string(version)
    end
  end

  defp expand_snapshot_dir(path) do
    Path.expand(path)
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("Snapshot Manager shutting down")

    if state.timer do
      Process.cancel_timer(state.timer)
    end

    :ok
  end
end
