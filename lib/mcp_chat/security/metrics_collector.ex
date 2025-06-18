defmodule MCPChat.Security.MetricsCollector do
  @moduledoc """
  Comprehensive security metrics collection and monitoring.

  This module provides real-time collection of security-related metrics for
  monitoring system health, detecting anomalies, and generating alerts.
  """

  use GenServer
  require Logger

  # Metrics collection interval (30 seconds)
  @collection_interval 30_000

  # Metrics retention (24 hours)
  @metrics_retention_ms 24 * 60 * 60 * 1000

  defstruct [
    :metrics_table,
    :collection_timer,
    :start_time,
    :collection_count
  ]

  @doc """
  Start the metrics collector.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get current security metrics snapshot.
  """
  def get_current_metrics do
    GenServer.call(__MODULE__, :get_current_metrics)
  end

  @doc """
  Get historical metrics for a time range.
  """
  def get_historical_metrics(from_time, to_time) do
    GenServer.call(__MODULE__, {:get_historical_metrics, from_time, to_time})
  end

  @doc """
  Record a security event for metrics.
  """
  def record_event(event_type, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:record_event, event_type, metadata})
  end

  @doc """
  Get aggregated metrics for dashboard display.
  """
  def get_dashboard_metrics do
    GenServer.call(__MODULE__, :get_dashboard_metrics)
  end

  @doc """
  Force immediate metrics collection.
  """
  def collect_now do
    GenServer.cast(__MODULE__, :collect_now)
  end

  # GenServer callbacks

  def init(opts) do
    # Create ETS table for metrics storage
    table =
      :ets.new(:security_metrics, [
        :set,
        :public,
        :named_table,
        {:read_concurrency, true}
      ])

    # Schedule first collection
    timer = Process.send_after(self(), :collect_metrics, 1000)

    state = %__MODULE__{
      metrics_table: table,
      collection_timer: timer,
      start_time: System.system_time(:millisecond),
      collection_count: 0
    }

    Logger.info("Security metrics collector started")
    {:ok, state}
  end

  def handle_call(:get_current_metrics, _from, state) do
    metrics = collect_current_metrics_data()
    {:reply, metrics, state}
  end

  def handle_call({:get_historical_metrics, from_time, to_time}, _from, state) do
    metrics = get_metrics_in_range(state.metrics_table, from_time, to_time)
    {:reply, metrics, state}
  end

  def handle_call(:get_dashboard_metrics, _from, state) do
    dashboard_data = build_dashboard_metrics(state)
    {:reply, dashboard_data, state}
  end

  def handle_cast({:record_event, event_type, metadata}, state) do
    timestamp = System.system_time(:millisecond)
    event_key = {:event, event_type, timestamp}

    :ets.insert(state.metrics_table, {event_key, metadata})
    {:noreply, state}
  end

  def handle_cast(:collect_now, state) do
    collect_and_store_metrics(state)
    {:noreply, state}
  end

  def handle_info(:collect_metrics, state) do
    # Collect current metrics
    collect_and_store_metrics(state)

    # Clean up old metrics
    cleanup_old_metrics(state.metrics_table)

    # Schedule next collection
    timer = Process.send_after(self(), :collect_metrics, @collection_interval)

    new_state = %{state | collection_timer: timer, collection_count: state.collection_count + 1}

    {:noreply, new_state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp collect_current_metrics_data do
    timestamp = System.system_time(:millisecond)

    %{
      timestamp: timestamp,
      capabilities: collect_capability_metrics(),
      security_kernel: collect_security_kernel_metrics(),
      violations: collect_violation_metrics(),
      performance: collect_performance_metrics(),
      audit: collect_audit_metrics(),
      agents: collect_agent_metrics()
    }
  end

  defp collect_capability_metrics do
    try do
      # Get capability statistics from SecurityKernel
      case GenServer.call(MCPChat.Security.SecurityKernel, :get_stats, 5000) do
        {:ok, stats} ->
          %{
            active_count: Map.get(stats, :active_capabilities, 0),
            total_issued: Map.get(stats, :total_issued, 0),
            total_revoked: Map.get(stats, :total_revoked, 0),
            delegation_depth_avg: calculate_avg_delegation_depth(stats),
            by_resource_type: Map.get(stats, :by_resource_type, %{}),
            by_principal: count_by_principal(stats),
            expiring_soon: count_expiring_capabilities()
          }

        {:error, _reason} ->
          %{
            active_count: 0,
            total_issued: 0,
            total_revoked: 0,
            error: "SecurityKernel unavailable"
          }
      end
    rescue
      error ->
        Logger.error("Failed to collect capability metrics: #{inspect(error)}")
        %{error: "Collection failed"}
    end
  end

  defp collect_security_kernel_metrics do
    try do
      kernel_pid = Process.whereis(MCPChat.Security.SecurityKernel)

      if kernel_pid do
        info = Process.info(kernel_pid, [:memory, :message_queue_len, :reductions])

        %{
          status: :running,
          memory_bytes: Keyword.get(info, :memory, 0),
          message_queue_length: Keyword.get(info, :message_queue_len, 0),
          reductions: Keyword.get(info, :reductions, 0),
          uptime_ms: get_process_uptime(kernel_pid)
        }
      else
        %{
          status: :stopped,
          error: "SecurityKernel not running"
        }
      end
    rescue
      error ->
        Logger.error("Failed to collect SecurityKernel metrics: #{inspect(error)}")
        %{status: :error, error: inspect(error)}
    end
  end

  defp collect_violation_metrics do
    try do
      case GenServer.call(MCPChat.Security.ViolationMonitor, :get_metrics, 5000) do
        {:ok, metrics} ->
          %{
            total_violations: Map.get(metrics, :total_violations, 0),
            violations_by_severity: Map.get(metrics, :by_severity, %{}),
            violations_by_type: Map.get(metrics, :by_type, %{}),
            recent_violations_1h: Map.get(metrics, :recent_1h, 0),
            recent_violations_24h: Map.get(metrics, :recent_24h, 0),
            top_violators: Map.get(metrics, :top_violators, [])
          }

        {:error, _reason} ->
          %{
            total_violations: 0,
            error: "ViolationMonitor unavailable"
          }
      end
    rescue
      error ->
        Logger.error("Failed to collect violation metrics: #{inspect(error)}")
        %{error: "Collection failed"}
    end
  end

  defp collect_performance_metrics do
    %{
      system: %{
        memory_usage: get_memory_usage(),
        cpu_usage: get_cpu_usage(),
        process_count: get_process_count()
      },
      security: %{
        avg_validation_time_ms: get_avg_validation_time(),
        avg_capability_creation_time_ms: get_avg_capability_creation_time(),
        token_cache_hit_rate: get_token_cache_hit_rate(),
        concurrent_validations: get_concurrent_validations()
      }
    }
  end

  defp collect_audit_metrics do
    try do
      case GenServer.call(MCPChat.Security.AuditLogger, :get_stats, 5000) do
        {:ok, stats} ->
          %{
            events_logged: Map.get(stats, :events_logged, 0),
            events_flushed: Map.get(stats, :events_flushed, 0),
            buffer_size: Map.get(stats, :buffer_size, 0),
            flush_errors: Map.get(stats, :flush_errors, 0),
            avg_flush_time_ms: Map.get(stats, :avg_flush_time_ms, 0)
          }

        {:error, _reason} ->
          %{
            events_logged: 0,
            error: "AuditLogger unavailable"
          }
      end
    rescue
      error ->
        Logger.error("Failed to collect audit metrics: #{inspect(error)}")
        %{error: "Collection failed"}
    end
  end

  defp collect_agent_metrics do
    try do
      agent_registry = Process.whereis(MCPChat.Agents.AgentRegistry)

      if agent_registry do
        case GenServer.call(agent_registry, :get_metrics, 5000) do
          {:ok, metrics} ->
            %{
              active_agents: Map.get(metrics, :active_count, 0),
              total_spawned: Map.get(metrics, :total_spawned, 0),
              by_type: Map.get(metrics, :by_type, %{}),
              avg_task_duration_ms: Map.get(metrics, :avg_task_duration, 0),
              failed_tasks: Map.get(metrics, :failed_tasks, 0)
            }

          {:error, _reason} ->
            %{
              active_agents: 0,
              error: "AgentRegistry unavailable"
            }
        end
      else
        %{
          active_agents: 0,
          error: "AgentRegistry not running"
        }
      end
    rescue
      error ->
        Logger.error("Failed to collect agent metrics: #{inspect(error)}")
        %{error: "Collection failed"}
    end
  end

  defp collect_and_store_metrics(state) do
    timestamp = System.system_time(:millisecond)
    metrics = collect_current_metrics_data()

    # Store in ETS table
    :ets.insert(state.metrics_table, {{:snapshot, timestamp}, metrics})

    # Log key metrics
    log_key_metrics(metrics)

    # Check for alerts
    check_and_trigger_alerts(metrics)
  end

  defp cleanup_old_metrics(table) do
    cutoff_time = System.system_time(:millisecond) - @metrics_retention_ms

    # Find and delete old entries
    patterns = [
      {{:snapshot, :"$1"}, :_, [{"=<", :"$1", cutoff_time}], [true]},
      {{:event, :_, :"$1"}, :_, [{"=<", :"$1", cutoff_time}], [true]}
    ]

    Enum.each(patterns, fn pattern ->
      :ets.select_delete(table, [pattern])
    end)
  end

  defp get_metrics_in_range(table, from_time, to_time) do
    pattern =
      {{:snapshot, :"$1"}, :"$2",
       [
         {">=", :"$1", from_time},
         {"=<", :"$1", to_time}
       ], [%{timestamp: :"$1", data: :"$2"}]}

    :ets.select(table, [pattern])
    |> Enum.sort_by(& &1.timestamp)
  end

  defp build_dashboard_metrics(state) do
    current = collect_current_metrics_data()

    # Get last hour of data for trends
    one_hour_ago = System.system_time(:millisecond) - 60 * 60 * 1000
    historical = get_metrics_in_range(state.metrics_table, one_hour_ago, current.timestamp)

    %{
      overview: %{
        uptime_ms: current.timestamp - state.start_time,
        collections_count: state.collection_count,
        last_collection: current.timestamp
      },
      current: current,
      trends: calculate_trends(historical),
      alerts: get_active_alerts(current),
      health_score: calculate_health_score(current)
    }
  end

  defp calculate_trends(historical_data) do
    if length(historical_data) < 2 do
      %{insufficient_data: true}
    else
      %{
        capability_growth: calculate_capability_trend(historical_data),
        violation_trend: calculate_violation_trend(historical_data),
        performance_trend: calculate_performance_trend(historical_data)
      }
    end
  end

  defp calculate_capability_trend(data) do
    counts =
      Enum.map(data, fn %{data: d} ->
        get_in(d, [:capabilities, :active_count]) || 0
      end)

    if length(counts) >= 2 do
      first = List.first(counts)
      last = List.last(counts)
      %{change: last - first, change_percent: (last - first) / max(first, 1) * 100}
    else
      %{change: 0, change_percent: 0}
    end
  end

  defp calculate_violation_trend(data) do
    counts =
      Enum.map(data, fn %{data: d} ->
        get_in(d, [:violations, :recent_violations_1h]) || 0
      end)

    if length(counts) >= 2 do
      first = List.first(counts)
      last = List.last(counts)
      %{change: last - first, trend: if(last > first, do: :increasing, else: :stable)}
    else
      %{change: 0, trend: :stable}
    end
  end

  defp calculate_performance_trend(data) do
    validation_times =
      Enum.map(data, fn %{data: d} ->
        get_in(d, [:performance, :security, :avg_validation_time_ms]) || 0
      end)

    if length(validation_times) >= 2 do
      avg_time = Enum.sum(validation_times) / length(validation_times)
      %{avg_validation_time_ms: avg_time, trend: :stable}
    else
      %{avg_validation_time_ms: 0, trend: :unknown}
    end
  end

  defp get_active_alerts(current_metrics) do
    alerts = []

    # Check for high violation rate
    alerts =
      if get_in(current_metrics, [:violations, :recent_violations_1h]) > 100 do
        [
          %{
            type: :high_violation_rate,
            severity: :warning,
            message: "High violation rate detected in the last hour"
          }
          | alerts
        ]
      else
        alerts
      end

    # Check for capability exhaustion
    alerts =
      if get_in(current_metrics, [:capabilities, :active_count]) > 10_000 do
        [
          %{
            type: :capability_exhaustion,
            severity: :warning,
            message: "High number of active capabilities"
          }
          | alerts
        ]
      else
        alerts
      end

    # Check SecurityKernel health
    alerts =
      if get_in(current_metrics, [:security_kernel, :status]) != :running do
        [
          %{
            type: :security_kernel_down,
            severity: :critical,
            message: "SecurityKernel is not running"
          }
          | alerts
        ]
      else
        alerts
      end

    alerts
  end

  defp calculate_health_score(metrics) do
    scores = []

    # Security Kernel health (30% weight)
    kernel_score =
      case get_in(metrics, [:security_kernel, :status]) do
        :running -> 100
        :stopped -> 0
        _ -> 50
      end

    scores = [{kernel_score, 0.3} | scores]

    # Violation rate (25% weight)
    violations_1h = get_in(metrics, [:violations, :recent_violations_1h]) || 0
    violation_score = max(0, 100 - violations_1h)
    scores = [{violation_score, 0.25} | scores]

    # Capability health (20% weight)
    active_caps = get_in(metrics, [:capabilities, :active_count]) || 0
    cap_score = if active_caps > 10_000, do: 50, else: 100
    scores = [{cap_score, 0.2} | scores]

    # Performance (15% weight)
    validation_time = get_in(metrics, [:performance, :security, :avg_validation_time_ms]) || 0
    perf_score = if validation_time > 1000, do: 50, else: 100
    scores = [{perf_score, 0.15} | scores]

    # Audit health (10% weight)
    audit_errors = get_in(metrics, [:audit, :flush_errors]) || 0
    audit_score = if audit_errors > 0, do: 70, else: 100
    scores = [{audit_score, 0.1} | scores]

    # Calculate weighted average
    total_score =
      Enum.reduce(scores, 0, fn {score, weight}, acc ->
        acc + score * weight
      end)

    round(total_score)
  end

  defp log_key_metrics(metrics) do
    active_caps = get_in(metrics, [:capabilities, :active_count]) || 0
    violations = get_in(metrics, [:violations, :recent_violations_1h]) || 0

    Logger.info("Security metrics: #{active_caps} active capabilities, #{violations} violations/1h",
      capabilities: active_caps,
      violations_1h: violations,
      timestamp: metrics.timestamp
    )
  end

  defp check_and_trigger_alerts(metrics) do
    alerts = get_active_alerts(metrics)

    Enum.each(alerts, fn alert ->
      # Send alert via PubSub
      Phoenix.PubSub.broadcast(MCPChat.PubSub, "security:alerts", {:security_alert, alert})

      # Log alert
      Logger.warn("Security alert: #{alert.message}",
        alert_type: alert.type,
        severity: alert.severity
      )
    end)
  end

  # Helper functions for metrics collection

  defp calculate_avg_delegation_depth(stats) do
    delegations = Map.get(stats, :delegations, [])

    if length(delegations) > 0 do
      total_depth = Enum.sum(Enum.map(delegations, &Map.get(&1, :depth, 0)))
      total_depth / length(delegations)
    else
      0
    end
  end

  defp count_by_principal(stats) do
    capabilities = Map.get(stats, :capabilities, [])

    Enum.reduce(capabilities, %{}, fn cap, acc ->
      principal = Map.get(cap, :principal_id, "unknown")
      Map.update(acc, principal, 1, &(&1 + 1))
    end)
  end

  defp count_expiring_capabilities do
    # Count capabilities expiring in the next hour
    one_hour_from_now = System.system_time(:second) + 3600

    # This would typically query the capability store
    # For now, return a placeholder
    0
  end

  defp get_memory_usage do
    :erlang.memory(:total)
  end

  defp get_cpu_usage do
    # Simple CPU usage approximation
    case :cpu_sup.util() do
      {:error, _} -> 0
      usage when is_number(usage) -> usage
      _ -> 0
    end
  end

  defp get_process_count do
    length(Process.list())
  end

  defp get_avg_validation_time do
    # This would typically be collected from performance monitoring
    # For now, return a placeholder
    50
  end

  defp get_avg_capability_creation_time do
    # Placeholder for capability creation timing
    25
  end

  defp get_token_cache_hit_rate do
    # Placeholder for token cache statistics
    0.85
  end

  defp get_concurrent_validations do
    # Count of currently running validations
    0
  end

  defp get_process_uptime(pid) do
    case Process.info(pid, :dictionary) do
      nil ->
        0

      dictionary ->
        start_time = Keyword.get(dictionary, :start_time, System.system_time(:millisecond))
        System.system_time(:millisecond) - start_time
    end
  end
end
