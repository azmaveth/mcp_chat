defmodule MCPChat.HealthMonitor do
  @moduledoc """
  Monitors health of supervised processes and provides telemetry.
  """
  use GenServer
  require Logger

  defstruct [:checks, :interval, :thresholds, :alerts_enabled]

  # 30 seconds
  @default_interval 30_000
  # 100MB
  @default_memory_threshold 100 * 1_024 * 1_024
  @default_message_queue_threshold 1_000

  # Client API

  @doc """
  Starts the health monitor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a process for health monitoring.
  """
  def register(name, pid, checks \\ [:memory, :message_queue, :alive]) do
    GenServer.call(__MODULE__, {:register, name, pid, checks})
  end

  @doc """
  Unregisters a process from health monitoring.
  """
  def unregister(name) do
    GenServer.call(__MODULE__, {:unregister, name})
  end

  @doc """
  Gets current health status of all monitored processes.
  """
  def get_health_status do
    GenServer.call(__MODULE__, :get_health_status)
  end

  @doc """
  Performs an immediate health check.
  """
  def check_now do
    GenServer.call(__MODULE__, :check_now)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      checks: %{},
      interval: opts[:interval] || @default_interval,
      thresholds: %{
        memory: opts[:memory_threshold] || @default_memory_threshold,
        message_queue: opts[:message_queue_threshold] || @default_message_queue_threshold
      },
      alerts_enabled: opts[:alerts_enabled] || true
    }

    # Schedule first health check
    Process.send_after(self(), :perform_health_check, state.interval)

    # Register telemetry events
    :telemetry.attach_many(
      "mcp-chat-health-monitor",
      [
        [:mcp_chat, :health, :check],
        [:mcp_chat, :health, :alert]
      ],
      &handle_telemetry_event/4,
      nil
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:register, name, pid, check_types}, _from, state) do
    # Monitor the process
    ref = Process.monitor(pid)

    check_info = %{
      pid: pid,
      ref: ref,
      check_types: check_types,
      last_check: nil,
      status: :unknown,
      metrics: %{}
    }

    new_checks = Map.put(state.checks, name, check_info)
    {:reply, :ok, %{state | checks: new_checks}}
  end

  def handle_call({:unregister, name}, _from, state) do
    case Map.get(state.checks, name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{ref: ref} ->
        Process.demonitor(ref, [:flush])
        new_checks = Map.delete(state.checks, name)
        {:reply, :ok, %{state | checks: new_checks}}
    end
  end

  def handle_call(:get_health_status, _from, state) do
    status =
      Map.new(state.checks, fn {name, info} ->
        {name,
         %{
           pid: info.pid,
           status: info.status,
           last_check: info.last_check,
           metrics: info.metrics
         }}
      end)

    {:reply, status, state}
  end

  def handle_call(:check_now, _from, state) do
    new_state = perform_health_checks(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:perform_health_check, state) do
    new_state = perform_health_checks(state)

    # Schedule next check
    Process.send_after(self(), :perform_health_check, state.interval)

    {:noreply, new_state}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    # Find which process died
    case Enum.find(state.checks, fn {_, info} -> info.ref == ref end) do
      {name, _info} ->
        Logger.warning("Monitored process #{name} (#{inspect(pid)}) died: #{inspect(reason)}")

        # Emit telemetry event
        :telemetry.execute(
          [:mcp_chat, :health, :process_down],
          %{count: 1},
          %{name: name, pid: pid, reason: reason}
        )

        # Remove from checks
        new_checks = Map.delete(state.checks, name)
        {:noreply, %{state | checks: new_checks}}

      nil ->
        {:noreply, state}
    end
  end

  # Private Functions

  defp perform_health_checks(state) do
    new_checks =
      Map.new(state.checks, fn {name, info} ->
        new_info = perform_process_health_check(name, info, state.thresholds)

        # Check for alerts
        if state.alerts_enabled do
          check_for_alerts(name, info, new_info, state.thresholds)
        end

        {name, new_info}
      end)

    %{state | checks: new_checks}
  end

  defp perform_process_health_check(name, info, thresholds) do
    start_time = System.monotonic_time(:microsecond)

    # Check if process is alive
    alive = Process.alive?(info.pid)

    if alive do
      metrics = gather_process_metrics(info.pid, info.check_types)
      status = evaluate_health_status(metrics, thresholds)

      # Emit telemetry
      duration = System.monotonic_time(:microsecond) - start_time

      :telemetry.execute(
        [:mcp_chat, :health, :check],
        %{duration: duration},
        %{name: name, status: status, metrics: metrics}
      )

      %{info | last_check: DateTime.utc_now(), status: status, metrics: metrics}
    else
      %{info | last_check: DateTime.utc_now(), status: :dead, metrics: %{}}
    end
  end

  defp gather_process_metrics(pid, check_types) do
    info =
      Process.info(pid, [
        :memory,
        :message_queue_len,
        :reductions,
        :current_function,
        :status
      ])

    base_metrics = %{
      memory: info[:memory],
      message_queue_len: info[:message_queue_len],
      reductions: info[:reductions],
      current_function: info[:current_function],
      status: info[:status]
    }

    # Filter to requested check types
    Map.take(base_metrics, check_types)
  catch
    _, _ ->
      %{}
  end

  defp evaluate_health_status(metrics, thresholds) do
    cond do
      metrics[:memory] && metrics[:memory] > thresholds.memory ->
        :unhealthy

      metrics[:message_queue_len] && metrics[:message_queue_len] > thresholds.message_queue ->
        :unhealthy

      true ->
        :healthy
    end
  end

  defp check_for_alerts(name, old_info, new_info, thresholds) do
    # Check for status changes
    if old_info.status != new_info.status && new_info.status == :unhealthy do
      alert_reason = determine_alert_reason(new_info.metrics, thresholds)

      Logger.warning("Health alert for #{name}: #{alert_reason}")

      :telemetry.execute(
        [:mcp_chat, :health, :alert],
        %{count: 1},
        %{name: name, reason: alert_reason, metrics: new_info.metrics}
      )
    end
  end

  defp determine_alert_reason(metrics, thresholds) do
    cond do
      metrics[:memory] && metrics[:memory] > thresholds.memory ->
        "High memory usage: #{format_bytes(metrics[:memory])}"

      metrics[:message_queue_len] && metrics[:message_queue_len] > thresholds.message_queue ->
        "High message queue: #{metrics[:message_queue_len]} messages"

      true ->
        "Unknown health issue"
    end
  end

  defp format_bytes(bytes) when bytes < 1_024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1_024, 1)} KB"
  defp format_bytes(bytes) when bytes < 1_073_741_824, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"

  # Telemetry handler
  defp handle_telemetry_event(event_name, measurements, metadata, _config) do
    case event_name do
      [:mcp_chat, :health, :check] ->
        Logger.debug("Health check for #{metadata.name}: #{metadata.status} (#{measurements.duration}μs)")

      [:mcp_chat, :health, :alert] ->
        Logger.warning("Health alert: #{metadata.name} - #{metadata.reason}")

      _ ->
        :ok
    end
  end
end
