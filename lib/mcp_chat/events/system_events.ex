defmodule MCPChat.Events.SystemEvents do
  @moduledoc """
  System-level event definitions for state persistence.

  These events represent system-wide state changes that need to be
  persisted for recovery and audit purposes.
  """

  # Persistence Events

  defmodule EventStoreStarted do
    @moduledoc "Emitted when the event store starts up"

    defstruct [
      :event_count,
      :last_snapshot_id,
      :recovery_mode,
      :timestamp,
      event_type: :event_store_started
    ]
  end

  defmodule EventStoreStopped do
    @moduledoc "Emitted when the event store shuts down"

    defstruct [
      :final_event_count,
      :uptime_ms,
      :reason,
      :timestamp,
      event_type: :event_store_stopped
    ]
  end

  defmodule SnapshotCreated do
    @moduledoc "Emitted when a snapshot is created"

    defstruct [
      :snapshot_id,
      :snapshot_type,
      :event_id_range,
      :file_size,
      :compression_ratio,
      :timestamp,
      event_type: :snapshot_created
    ]
  end

  defmodule SnapshotRestored do
    @moduledoc "Emitted when system state is restored from snapshot"

    defstruct [
      :snapshot_id,
      :restored_event_id,
      :recovery_duration_ms,
      :timestamp,
      event_type: :snapshot_restored
    ]
  end

  # Configuration Events

  defmodule ConfigurationChanged do
    @moduledoc "Emitted when system configuration changes"

    defstruct [
      :section,
      :changed_keys,
      :previous_values,
      :new_values,
      :source,
      :timestamp,
      event_type: :configuration_changed
    ]
  end

  defmodule ConfigurationReloaded do
    @moduledoc "Emitted when configuration is reloaded"

    defstruct [
      :config_source,
      :reload_reason,
      :changes_detected,
      :timestamp,
      event_type: :configuration_reloaded
    ]
  end

  # Session Lifecycle Events

  defmodule SessionStarted do
    @moduledoc "Emitted when a new chat session begins"

    defstruct [
      :session_id,
      :user_id,
      :session_type,
      :initial_context,
      :timestamp,
      event_type: :session_started
    ]
  end

  defmodule SessionEnded do
    @moduledoc "Emitted when a chat session ends"

    defstruct [
      :session_id,
      :end_reason,
      :duration_ms,
      :message_count,
      :final_context,
      :timestamp,
      event_type: :session_ended
    ]
  end

  defmodule SessionRestored do
    @moduledoc "Emitted when a session is restored from persistence"

    defstruct [
      :session_id,
      :restored_from_event_id,
      :message_count,
      :restoration_duration_ms,
      :timestamp,
      event_type: :session_restored
    ]
  end

  # System Performance Events

  defmodule PerformanceMetricsRecorded do
    @moduledoc "Emitted periodically with system performance data"

    defstruct [
      :cpu_usage_percent,
      :memory_usage_bytes,
      :event_store_size_bytes,
      :active_sessions,
      :events_per_second,
      :timestamp,
      event_type: :performance_metrics_recorded
    ]
  end

  defmodule ResourceThresholdExceeded do
    @moduledoc "Emitted when system resource thresholds are exceeded"

    defstruct [
      :resource_type,
      :current_value,
      :threshold_value,
      :severity,
      :recommended_action,
      :timestamp,
      event_type: :resource_threshold_exceeded
    ]
  end

  # Error and Recovery Events

  defmodule SystemErrorOccurred do
    @moduledoc "Emitted when system-level errors occur"

    defstruct [
      :error_type,
      :error_message,
      :component,
      :severity,
      :recovery_attempted,
      :timestamp,
      event_type: :system_error_occurred
    ]
  end

  defmodule SystemRecoveryCompleted do
    @moduledoc "Emitted when system recovery operations complete"

    defstruct [
      :recovery_type,
      :recovery_duration_ms,
      :recovered_components,
      :remaining_issues,
      :timestamp,
      event_type: :system_recovery_completed
    ]
  end

  # Application Lifecycle Events

  defmodule ApplicationStarted do
    @moduledoc "Emitted when MCP Chat application starts"

    defstruct [
      :version,
      :start_mode,
      :configuration_source,
      :enabled_features,
      :timestamp,
      event_type: :application_started
    ]
  end

  defmodule ApplicationStopping do
    @moduledoc "Emitted when MCP Chat application begins shutdown"

    defstruct [
      :shutdown_reason,
      :active_sessions,
      :pending_operations,
      :graceful_shutdown,
      :timestamp,
      event_type: :application_stopping
    ]
  end

  defmodule ApplicationStopped do
    @moduledoc "Emitted when MCP Chat application completes shutdown"

    defstruct [
      :final_uptime_ms,
      :total_sessions,
      :total_events,
      :clean_shutdown,
      :timestamp,
      event_type: :application_stopped
    ]
  end

  # Maintenance Events

  defmodule MaintenanceWindowStarted do
    @moduledoc "Emitted when maintenance operations begin"

    defstruct [
      :maintenance_id,
      :maintenance_type,
      :scheduled_duration_ms,
      :affected_components,
      :timestamp,
      event_type: :maintenance_window_started
    ]
  end

  defmodule MaintenanceWindowCompleted do
    @moduledoc "Emitted when maintenance operations complete"

    defstruct [
      :maintenance_id,
      :actual_duration_ms,
      :operations_completed,
      :operations_failed,
      :system_impact,
      :timestamp,
      event_type: :maintenance_window_completed
    ]
  end

  # Security Events

  defmodule SecurityEventDetected do
    @moduledoc "Emitted when security-related events are detected"

    defstruct [
      :event_category,
      :severity_level,
      :source_component,
      :threat_indicators,
      :response_actions,
      :timestamp,
      event_type: :security_event_detected
    ]
  end

  defmodule AccessControlChange do
    @moduledoc "Emitted when access control settings change"

    defstruct [
      :resource_type,
      :resource_id,
      :permission_changes,
      :changed_by,
      :timestamp,
      event_type: :access_control_change
    ]
  end

  # Helper functions

  @doc "Get all system event types"
  def event_types do
    [
      :event_store_started,
      :event_store_stopped,
      :snapshot_created,
      :snapshot_restored,
      :configuration_changed,
      :configuration_reloaded,
      :session_started,
      :session_ended,
      :session_restored,
      :performance_metrics_recorded,
      :resource_threshold_exceeded,
      :system_error_occurred,
      :system_recovery_completed,
      :application_started,
      :application_stopping,
      :application_stopped,
      :maintenance_window_started,
      :maintenance_window_completed,
      :security_event_detected,
      :access_control_change
    ]
  end

  @doc "Check if an event is related to persistence operations"
  def persistence_event?(event) do
    event.event_type in [
      :event_store_started,
      :event_store_stopped,
      :snapshot_created,
      :snapshot_restored
    ]
  end

  @doc "Check if an event is related to session lifecycle"
  def session_lifecycle_event?(event) do
    event.event_type in [
      :session_started,
      :session_ended,
      :session_restored
    ]
  end

  @doc "Check if an event is security-related"
  def security_event?(event) do
    event.event_type in [
      :security_event_detected,
      :access_control_change
    ]
  end

  @doc "Check if an event indicates a system problem"
  def error_event?(event) do
    event.event_type in [
      :system_error_occurred,
      :resource_threshold_exceeded,
      :security_event_detected
    ]
  end

  @doc "Get event severity level"
  def get_severity(event) do
    case event.event_type do
      :system_error_occurred -> Map.get(event, :severity, :error)
      :resource_threshold_exceeded -> Map.get(event, :severity, :warning)
      :security_event_detected -> Map.get(event, :severity_level, :warning)
      _ -> :info
    end
  end

  @doc "Format system event for logging"
  def format_for_log(event) do
    %{
      event_type: event.event_type,
      severity: get_severity(event),
      timestamp: event.timestamp || DateTime.utc_now(),
      component: Map.get(event, :component, "system"),
      summary: generate_summary(event)
    }
  end

  defp generate_summary(event) do
    case event.event_type do
      :session_started -> "Session #{event.session_id} started"
      :session_ended -> "Session #{event.session_id} ended (#{event.end_reason})"
      :snapshot_created -> "Snapshot #{event.snapshot_id} created"
      :configuration_changed -> "Configuration changed in #{event.section}"
      :system_error_occurred -> "System error in #{event.component}: #{event.error_message}"
      _ -> "System event: #{event.event_type}"
    end
  end
end
