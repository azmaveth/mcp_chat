defmodule MCPChat.Agents.MaintenanceAgent do
  @moduledoc """
  Singleton agent responsible for system maintenance tasks.

  This agent handles:
  - Scheduled cleanup of inactive sessions
  - Log rotation and archival
  - Temporary file cleanup
  - System health monitoring
  - Resource optimization
  """

  use GenServer
  require Logger

  # Run every hour
  @default_cleanup_interval :timer.hours(1)
  # Deep clean at 2 AM
  @deep_clean_hour 2
  # 24 hours
  @session_inactive_threshold :timer.hours(24)
  # 48 hours
  @temp_file_max_age :timer.hours(48)

  # Public API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Force immediate cleanup (admin function)"
  def force_cleanup(deep_clean \\ false) do
    GenServer.cast(__MODULE__, {:force_cleanup, deep_clean})
  end

  @doc "Schedule a custom maintenance task"
  def schedule_task(task_spec) do
    GenServer.cast(__MODULE__, {:schedule_task, task_spec})
  end

  @doc "Get maintenance statistics and history"
  def get_maintenance_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc "Get current maintenance configuration"
  def get_config do
    GenServer.call(__MODULE__, :get_config)
  end

  @doc "Update maintenance configuration"
  def update_config(new_config) do
    GenServer.call(__MODULE__, {:update_config, new_config})
  end

  # GenServer implementation

  def init(opts) do
    cleanup_interval = Keyword.get(opts, :cleanup_interval, @default_cleanup_interval)
    deep_clean_hour = Keyword.get(opts, :deep_clean_hour, @deep_clean_hour)

    # Schedule first maintenance check
    schedule_next_maintenance(cleanup_interval)

    Logger.info("Starting Maintenance Agent",
      cleanup_interval_ms: cleanup_interval,
      deep_clean_hour: deep_clean_hour
    )

    {:ok,
     %{
       config: %{
         cleanup_interval: cleanup_interval,
         deep_clean_hour: deep_clean_hour,
         session_inactive_threshold: @session_inactive_threshold,
         temp_file_max_age: @temp_file_max_age
       },
       stats: %{
         last_cleanup: nil,
         cleanup_count: 0,
         sessions_cleaned: 0,
         logs_rotated: 0,
         temp_files_deleted: 0,
         total_runtime_ms: 0,
         errors: []
       },
       scheduled_tasks: []
     }}
  end

  def handle_info(:maintenance, state) do
    Logger.info("Starting scheduled maintenance")

    start_time = System.monotonic_time(:millisecond)
    current_hour = DateTime.utc_now().hour
    is_deep_clean = current_hour == state.config.deep_clean_hour

    # Broadcast maintenance started
    broadcast_maintenance_event(%MCPChat.Events.AgentEvents.MaintenanceStarted{
      maintenance_type: if(is_deep_clean, do: :deep_clean, else: :scheduled),
      started_at: DateTime.utc_now()
    })

    try do
      maintenance_stats = perform_maintenance(state.config, is_deep_clean)
      end_time = System.monotonic_time(:millisecond)
      duration_ms = end_time - start_time

      # Update state with results
      new_stats = merge_maintenance_stats(state.stats, maintenance_stats, duration_ms)
      new_state = %{state | stats: new_stats}

      # Broadcast completion
      broadcast_maintenance_event(%MCPChat.Events.AgentEvents.MaintenanceCompleted{
        maintenance_type: if(is_deep_clean, do: :deep_clean, else: :scheduled),
        duration_ms: duration_ms,
        stats: maintenance_stats
      })

      Logger.info("Maintenance completed",
        duration_ms: duration_ms,
        stats: maintenance_stats
      )

      # Schedule next maintenance
      schedule_next_maintenance(state.config.cleanup_interval)

      {:noreply, new_state}
    rescue
      error ->
        end_time = System.monotonic_time(:millisecond)
        duration_ms = end_time - start_time

        error_info = %{
          error: inspect(error),
          timestamp: DateTime.utc_now(),
          duration_ms: duration_ms
        }

        # Keep last 10 errors
        new_errors = [error_info | Enum.take(state.stats.errors, 9)]
        new_stats = %{state.stats | errors: new_errors}

        # Broadcast failure
        broadcast_maintenance_event(%MCPChat.Events.AgentEvents.MaintenanceFailed{
          maintenance_type: if(is_deep_clean, do: :deep_clean, else: :scheduled),
          error: inspect(error),
          partial_stats: %{}
        })

        Logger.error("Maintenance failed",
          error: inspect(error),
          duration_ms: duration_ms
        )

        # Still schedule next maintenance
        schedule_next_maintenance(state.config.cleanup_interval)

        {:noreply, %{state | stats: new_stats}}
    end
  end

  def handle_cast({:force_cleanup, deep_clean}, state) do
    Logger.info("Performing forced maintenance", deep_clean: deep_clean)

    start_time = System.monotonic_time(:millisecond)

    # Broadcast forced maintenance started
    broadcast_maintenance_event(%MCPChat.Events.AgentEvents.MaintenanceStarted{
      maintenance_type: :forced,
      started_at: DateTime.utc_now()
    })

    try do
      maintenance_stats = perform_maintenance(state.config, deep_clean)
      end_time = System.monotonic_time(:millisecond)
      duration_ms = end_time - start_time

      new_stats = merge_maintenance_stats(state.stats, maintenance_stats, duration_ms)

      broadcast_maintenance_event(%MCPChat.Events.AgentEvents.MaintenanceCompleted{
        maintenance_type: :forced,
        duration_ms: duration_ms,
        stats: maintenance_stats
      })

      {:noreply, %{state | stats: new_stats}}
    rescue
      error ->
        Logger.error("Forced maintenance failed", error: inspect(error))

        broadcast_maintenance_event(%MCPChat.Events.AgentEvents.MaintenanceFailed{
          maintenance_type: :forced,
          error: inspect(error),
          partial_stats: %{}
        })

        {:noreply, state}
    end
  end

  def handle_cast({:schedule_task, task_spec}, state) do
    new_tasks = [task_spec | state.scheduled_tasks]
    Logger.info("Scheduled custom maintenance task", task: inspect(task_spec))
    {:noreply, %{state | scheduled_tasks: new_tasks}}
  end

  def handle_call(:get_stats, _from, state) do
    current_stats =
      Map.merge(state.stats, %{
        uptime_ms: get_uptime_ms(),
        next_maintenance: get_next_maintenance_time(state.config.cleanup_interval),
        scheduled_tasks_count: length(state.scheduled_tasks)
      })

    {:reply, current_stats, state}
  end

  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  def handle_call({:update_config, new_config}, _from, state) do
    updated_config = Map.merge(state.config, new_config)

    Logger.info("Updated maintenance configuration",
      old_config: state.config,
      new_config: updated_config
    )

    new_state = %{state | config: updated_config}
    {:reply, :ok, new_state}
  end

  # Private maintenance functions

  defp perform_maintenance(config, is_deep_clean) do
    base_tasks = [
      &cleanup_inactive_sessions/1,
      &cleanup_temp_files/1,
      &cleanup_agent_pool_metrics/1,
      &update_system_metrics/1
    ]

    all_tasks =
      if is_deep_clean do
        [&rotate_logs/1, &cleanup_old_exports/1, (&optimize_memory/1) | base_tasks]
      else
        base_tasks
      end

    Enum.reduce(all_tasks, %{}, fn task, acc_stats ->
      case task.(config) do
        {:ok, task_stats} ->
          Map.merge(acc_stats, task_stats)

        {:error, reason} ->
          Logger.error("Maintenance task failed", task: inspect(task), reason: inspect(reason))
          acc_stats
      end
    end)
  end

  defp cleanup_inactive_sessions(config) do
    cutoff_time = DateTime.utc_now() |> DateTime.add(-config.session_inactive_threshold, :millisecond)

    active_sessions = MCPChat.Agents.SessionManager.list_active_sessions()

    sessions_cleaned =
      active_sessions
      |> Enum.filter(&session_inactive_since?(&1, cutoff_time))
      |> Enum.count(fn session_id ->
        case MCPChat.Agents.SessionManager.stop_session(session_id) do
          :ok ->
            Logger.info("Cleaned up inactive session", session_id: session_id)
            true

          {:error, reason} ->
            Logger.warning("Failed to clean up session",
              session_id: session_id,
              reason: inspect(reason)
            )

            false
        end
      end)

    {:ok, %{sessions_cleaned: sessions_cleaned}}
  end

  defp cleanup_temp_files(config) do
    temp_dirs = [
      System.tmp_dir(),
      Application.get_env(:mcp_chat, :temp_dir, "/tmp/mcp_chat")
    ]

    total_files_deleted =
      Enum.reduce(temp_dirs, 0, fn temp_dir, acc ->
        if File.exists?(temp_dir) do
          pattern = Path.join(temp_dir, "mcp_chat_*")
          cutoff_time = DateTime.utc_now() |> DateTime.add(-config.temp_file_max_age, :millisecond)

          files_deleted =
            Path.wildcard(pattern)
            |> Enum.filter(&file_older_than?(&1, cutoff_time))
            |> Enum.count(fn file ->
              case File.rm_rf(file) do
                {:ok, _} ->
                  Logger.debug("Deleted temp file", file: file)
                  true

                {:error, reason, _file} ->
                  Logger.warning("Failed to delete temp file",
                    file: file,
                    reason: inspect(reason)
                  )

                  false
              end
            end)

          acc + files_deleted
        else
          acc
        end
      end)

    {:ok, %{temp_files_deleted: total_files_deleted}}
  end

  defp cleanup_agent_pool_metrics(_config) do
    # Clean up old entries from agent pool ETS table
    case :ets.info(:agent_pool_workers) do
      :undefined ->
        {:ok, %{pool_metrics_cleaned: 0}}

      _info ->
        # This is a simplified cleanup - in practice you might want more sophisticated logic
        current_workers = :ets.tab2list(:agent_pool_workers)
        active_count = length(current_workers)
        {:ok, %{pool_metrics_cleaned: 0, active_pool_workers: active_count}}
    end
  end

  defp update_system_metrics(_config) do
    # Update various system metrics
    memory_usage = :erlang.memory()
    process_count = :erlang.system_info(:process_count)

    # Store metrics in ETS table or send to monitoring system
    metrics = %{
      memory_total: memory_usage[:total],
      memory_processes: memory_usage[:processes],
      memory_atom: memory_usage[:atom],
      process_count: process_count,
      updated_at: DateTime.utc_now()
    }

    {:ok, %{system_metrics_updated: true, metrics: metrics}}
  end

  defp rotate_logs(_config) do
    # Rotate application logs if configured
    log_dir = Application.get_env(:logger, :file, %{})[:path]

    if log_dir && File.exists?(log_dir) do
      # Simple log rotation logic
      timestamp = DateTime.utc_now() |> DateTime.to_unix()
      archived_name = "#{log_dir}.#{timestamp}"

      case File.rename(log_dir, archived_name) do
        :ok ->
          Logger.info("Rotated log file", old: log_dir, new: archived_name)
          {:ok, %{logs_rotated: 1}}

        {:error, reason} ->
          Logger.error("Failed to rotate log", reason: inspect(reason))
          {:ok, %{logs_rotated: 0}}
      end
    else
      {:ok, %{logs_rotated: 0}}
    end
  end

  defp cleanup_old_exports(_config) do
    # Remove exports older than 7 days
    # 7 days
    export_cleanup_age = :timer.hours(24 * 7)
    cutoff_time = DateTime.utc_now() |> DateTime.add(-export_cleanup_age, :millisecond)

    case :ets.info(:export_registry) do
      :undefined ->
        {:ok, %{old_exports_cleaned: 0}}

      _info ->
        old_exports =
          :ets.tab2list(:export_registry)
          |> Enum.filter(fn {_export_id, _result, created_at} ->
            DateTime.compare(created_at, cutoff_time) == :lt
          end)

        exports_cleaned =
          Enum.count(old_exports, fn {export_id, result, _created_at} ->
            # Delete the file if it exists
            if Map.has_key?(result, :file_path) and File.exists?(result.file_path) do
              File.rm(result.file_path)
            end

            # Remove from registry
            :ets.delete(:export_registry, export_id)
            true
          end)

        {:ok, %{old_exports_cleaned: exports_cleaned}}
    end
  end

  defp optimize_memory(_config) do
    # Force garbage collection on all processes
    :erlang.garbage_collect()

    # Get memory usage after GC
    memory_after = :erlang.memory()

    {:ok,
     %{
       memory_optimized: true,
       memory_after_gc: memory_after[:total]
     }}
  end

  # Helper functions

  defp session_inactive_since?(session_id, _cutoff_time) do
    # This would need to integrate with actual session activity tracking
    # For now, we'll use a simple heuristic based on process message queue
    case MCPChat.Agents.SessionManager.get_session_pid(session_id) do
      {:ok, pid} ->
        case Process.info(pid, :message_queue_len) do
          # No pending messages might indicate inactivity
          {:message_queue_len, 0} -> true
          _ -> false
        end

      {:error, :not_found} ->
        # Session doesn't exist, consider it inactive
        true
    end
  end

  defp file_older_than?(file_path, cutoff_time) do
    case File.stat(file_path, time: :posix) do
      {:ok, %{mtime: mtime}} ->
        file_time = DateTime.from_unix!(mtime)
        DateTime.compare(file_time, cutoff_time) == :lt

      {:error, _} ->
        # If we can't get file info, don't delete it
        false
    end
  end

  defp merge_maintenance_stats(current_stats, new_stats, duration_ms) do
    %{
      current_stats
      | last_cleanup: DateTime.utc_now(),
        cleanup_count: current_stats.cleanup_count + 1,
        sessions_cleaned: current_stats.sessions_cleaned + Map.get(new_stats, :sessions_cleaned, 0),
        logs_rotated: current_stats.logs_rotated + Map.get(new_stats, :logs_rotated, 0),
        temp_files_deleted: current_stats.temp_files_deleted + Map.get(new_stats, :temp_files_deleted, 0),
        total_runtime_ms: current_stats.total_runtime_ms + duration_ms
    }
  end

  defp schedule_next_maintenance(interval) do
    Process.send_after(self(), :maintenance, interval)
  end

  defp get_uptime_ms do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_ms
  end

  defp get_next_maintenance_time(interval) do
    DateTime.utc_now() |> DateTime.add(interval, :millisecond)
  end

  defp broadcast_maintenance_event(event) do
    Phoenix.PubSub.broadcast(MCPChat.PubSub, "system:maintenance", event)
  end
end
