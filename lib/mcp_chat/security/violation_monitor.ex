defmodule MCPChat.Security.ViolationMonitor do
  @moduledoc """
  Monitors and alerts on security violations in real-time.
  Tracks patterns, generates alerts, and provides analytics.
  """

  use GenServer
  require Logger

  alias MCPChat.Security.AuditLogger

  # Violations before alert
  @violation_threshold 5
  # Time window for threshold
  @time_window :timer.minutes(5)
  # Cooldown between alerts
  @alert_cooldown :timer.minutes(15)

  defstruct [
    :violations,
    :alerts,
    :thresholds,
    :last_alert_times,
    :subscribers
  ]

  # Violation types
  @violation_types [
    :invalid_capability,
    :expired_token,
    :revoked_token,
    :unauthorized_operation,
    :unauthorized_resource,
    :constraint_violation,
    :delegation_depth_exceeded,
    :suspicious_pattern,
    :rate_limit_exceeded
  ]

  # Client API

  @doc """
  Starts the ViolationMonitor GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records a security violation.
  """
  def record_violation(type, details) when type in @violation_types do
    GenServer.cast(__MODULE__, {:record_violation, type, details})
  end

  @doc """
  Subscribes to security alerts.
  """
  def subscribe(pid \\ self()) do
    GenServer.call(__MODULE__, {:subscribe, pid})
  end

  @doc """
  Unsubscribes from security alerts.
  """
  def unsubscribe(pid \\ self()) do
    GenServer.call(__MODULE__, {:unsubscribe, pid})
  end

  @doc """
  Gets current violation statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Gets recent violations.
  """
  def get_recent_violations(limit \\ 100) do
    GenServer.call(__MODULE__, {:get_recent_violations, limit})
  end

  @doc """
  Sets custom threshold for a violation type.
  """
  def set_threshold(type, count, time_window \\ @time_window) do
    GenServer.call(__MODULE__, {:set_threshold, type, count, time_window})
  end

  @doc """
  Clears violation history.
  """
  def clear_history do
    GenServer.call(__MODULE__, :clear_history)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Subscribe to audit events
    Phoenix.PubSub.subscribe(MCPChat.PubSub, "security:audit")

    state = %__MODULE__{
      violations: %{},
      alerts: [],
      thresholds: default_thresholds(),
      last_alert_times: %{},
      subscribers: []
    }

    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup_old_violations, :timer.minutes(1))

    Logger.info("ViolationMonitor started")

    {:ok, state}
  end

  @impl true
  def handle_cast({:record_violation, type, details}, state) do
    violation = %{
      id: generate_violation_id(),
      type: type,
      details: details,
      timestamp: DateTime.utc_now(),
      principal_id: details[:principal_id],
      resource: details[:resource],
      operation: details[:operation]
    }

    # Store violation
    new_violations =
      Map.update(
        state.violations,
        type,
        [violation],
        &[violation | &1]
      )

    # Log to audit system
    AuditLogger.log_event(
      :security_violation,
      %{
        violation_type: type,
        details: details
      },
      details[:principal_id] || "unknown"
    )

    # Check thresholds
    new_state = %{state | violations: new_violations}
    new_state = check_thresholds(new_state, type)

    # Analyze patterns
    analyze_patterns(new_state, violation)

    {:noreply, new_state}
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    new_subscribers = [pid | state.subscribers] |> Enum.uniq()
    {:reply, :ok, %{state | subscribers: new_subscribers}}
  end

  @impl true
  def handle_call({:unsubscribe, pid}, _from, state) do
    new_subscribers = List.delete(state.subscribers, pid)
    {:reply, :ok, %{state | subscribers: new_subscribers}}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      total_violations: count_all_violations(state.violations),
      violations_by_type: count_by_type(state.violations),
      recent_alerts: Enum.take(state.alerts, 10),
      active_thresholds: map_size(state.thresholds),
      subscriber_count: length(state.subscribers)
    }

    {:reply, {:ok, stats}, state}
  end

  @impl true
  def handle_call({:get_recent_violations, limit}, _from, state) do
    recent =
      state.violations
      |> Enum.flat_map(fn {_type, violations} -> violations end)
      |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
      |> Enum.take(limit)

    {:reply, {:ok, recent}, state}
  end

  @impl true
  def handle_call({:set_threshold, type, count, time_window}, _from, state) do
    new_thresholds = Map.put(state.thresholds, type, {count, time_window})
    {:reply, :ok, %{state | thresholds: new_thresholds}}
  end

  @impl true
  def handle_call(:clear_history, _from, state) do
    {:reply, :ok, %{state | violations: %{}, alerts: []}}
  end

  @impl true
  def handle_info(:cleanup_old_violations, state) do
    # Remove violations older than 24 hours
    cutoff = DateTime.add(DateTime.utc_now(), -86400, :second)

    new_violations =
      state.violations
      |> Enum.map(fn {type, violations} ->
        filtered =
          Enum.filter(violations, fn v ->
            DateTime.compare(v.timestamp, cutoff) == :gt
          end)

        {type, filtered}
      end)
      |> Enum.into(%{})

    # Schedule next cleanup
    Process.send_after(self(), :cleanup_old_violations, :timer.minutes(1))

    {:noreply, %{state | violations: new_violations}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove dead subscriber
    new_subscribers = List.delete(state.subscribers, pid)
    {:noreply, %{state | subscribers: new_subscribers}}
  end

  @impl true
  def handle_info({:audit_event, event}, state) do
    # Handle audit events that might indicate violations
    case analyze_audit_event(event) do
      {:violation, type, details} ->
        handle_cast({:record_violation, type, details}, state)

      _ ->
        {:noreply, state}
    end
  end

  # Private Functions

  defp default_thresholds do
    %{
      invalid_capability: {10, @time_window},
      expired_token: {20, @time_window},
      revoked_token: {5, @time_window},
      unauthorized_operation: {5, @time_window},
      unauthorized_resource: {5, @time_window},
      constraint_violation: {10, @time_window},
      delegation_depth_exceeded: {5, @time_window},
      suspicious_pattern: {3, @time_window},
      rate_limit_exceeded: {5, @time_window}
    }
  end

  defp check_thresholds(state, type) do
    case Map.get(state.thresholds, type) do
      {threshold_count, time_window} ->
        recent_count = count_recent_violations(state.violations[type] || [], time_window)

        if recent_count >= threshold_count do
          maybe_send_alert(state, type, recent_count, threshold_count)
        else
          state
        end

      nil ->
        state
    end
  end

  defp count_recent_violations(violations, time_window) do
    cutoff = DateTime.add(DateTime.utc_now(), -div(time_window, 1000), :second)

    Enum.count(violations, fn v ->
      DateTime.compare(v.timestamp, cutoff) == :gt
    end)
  end

  defp maybe_send_alert(state, type, count, threshold) do
    last_alert = Map.get(state.last_alert_times, type)
    now = System.monotonic_time(:millisecond)

    should_alert =
      case last_alert do
        nil -> true
        time -> now - time > @alert_cooldown
      end

    if should_alert do
      alert = %{
        id: generate_alert_id(),
        type: type,
        severity: calculate_severity(type, count, threshold),
        message: format_alert_message(type, count, threshold),
        timestamp: DateTime.utc_now(),
        violation_count: count,
        threshold: threshold
      }

      # Send alert to subscribers
      Enum.each(state.subscribers, fn pid ->
        send(pid, {:security_alert, alert})
      end)

      # Log critical alerts
      if alert.severity in [:critical, :high] do
        Logger.error("Security Alert: #{alert.message}")
      else
        Logger.warning("Security Alert: #{alert.message}")
      end

      # Update state
      %{
        state
        | alerts: [alert | state.alerts] |> Enum.take(100),
          last_alert_times: Map.put(state.last_alert_times, type, now)
      }
    else
      state
    end
  end

  defp analyze_patterns(state, violation) do
    # Check for suspicious patterns
    case violation.type do
      :unauthorized_resource ->
        check_path_traversal_attempts(state, violation)

      :invalid_capability ->
        check_brute_force_attempts(state, violation)

      :rate_limit_exceeded ->
        check_dos_attempts(state, violation)

      _ ->
        :ok
    end
  end

  defp check_path_traversal_attempts(state, violation) do
    if String.contains?(violation.details[:resource] || "", ["../", "..\\", "%2e%2e"]) do
      record_violation(:suspicious_pattern, %{
        pattern: "path_traversal_attempt",
        original_violation: violation
      })
    end
  end

  defp check_brute_force_attempts(state, violation) do
    # Check if same principal has many invalid capability attempts
    principal_id = violation.principal_id

    if principal_id do
      recent_failures =
        state.violations[:invalid_capability] ||
          []
          |> Enum.filter(&(&1.principal_id == principal_id))
          |> count_recent_violations(@time_window)

      if recent_failures > 20 do
        record_violation(:suspicious_pattern, %{
          pattern: "potential_brute_force",
          principal_id: principal_id,
          failure_count: recent_failures
        })
      end
    end
  end

  defp check_dos_attempts(_state, violation) do
    # Rate limit violations might indicate DoS
    if violation.details[:requests_per_second] > 1000 do
      record_violation(:suspicious_pattern, %{
        pattern: "potential_dos_attack",
        original_violation: violation
      })
    end
  end

  defp analyze_audit_event(event) do
    case event do
      %{type: :capability_denied, details: details} ->
        {:violation, :unauthorized_operation, details}

      %{type: :access_denied, details: details} ->
        {:violation, :unauthorized_resource, details}

      %{type: :constraint_violation, details: details} ->
        {:violation, :constraint_violation, details}

      _ ->
        :ignore
    end
  end

  defp calculate_severity(type, count, threshold) do
    ratio = count / threshold

    cond do
      type in [:suspicious_pattern, :unauthorized_operation] -> :critical
      ratio >= 3.0 -> :critical
      ratio >= 2.0 -> :high
      ratio >= 1.5 -> :medium
      true -> :low
    end
  end

  defp format_alert_message(type, count, threshold) do
    "Security threshold exceeded for #{type}: #{count} violations in time window (threshold: #{threshold})"
  end

  defp count_all_violations(violations) do
    violations
    |> Map.values()
    |> Enum.map(&length/1)
    |> Enum.sum()
  end

  defp count_by_type(violations) do
    Map.new(violations, fn {type, list} -> {type, length(list)} end)
  end

  defp generate_violation_id do
    "vio_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end

  defp generate_alert_id do
    "alert_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end

  @doc """
  Convenience function to record common violation patterns.
  """
  def record_invalid_token(token_id, reason, principal_id) do
    record_violation(:invalid_capability, %{
      token_id: token_id,
      reason: reason,
      principal_id: principal_id,
      timestamp: DateTime.utc_now()
    })
  end

  def record_unauthorized_access(principal_id, resource, operation) do
    record_violation(:unauthorized_resource, %{
      principal_id: principal_id,
      resource: resource,
      operation: operation,
      timestamp: DateTime.utc_now()
    })
  end

  def record_rate_limit_exceeded(principal_id, resource, requests_per_second) do
    record_violation(:rate_limit_exceeded, %{
      principal_id: principal_id,
      resource: resource,
      requests_per_second: requests_per_second,
      timestamp: DateTime.utc_now()
    })
  end
end
