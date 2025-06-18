defmodule MCPChat.Events.AgentEvents do
  @moduledoc """
  Event definitions for the agent system.

  These events are broadcast via Phoenix.PubSub to keep UIs updated
  about agent activities, tool executions, and system status.
  """

  # Tool Execution Events

  defmodule ToolExecutionStarted do
    @moduledoc "Emitted when a tool execution agent starts processing"

    defstruct [
      :session_id,
      :execution_id,
      :tool_name,
      :args,
      :agent_pid,
      :started_at,
      :estimated_duration,
      :timestamp,
      event_type: :tool_execution_started
    ]
  end

  defmodule ToolExecutionProgress do
    @moduledoc "Emitted during tool execution to show progress"

    defstruct [
      :session_id,
      :execution_id,
      :tool_name,
      # 0-100 percentage
      :progress,
      # :starting, :processing, :completing, etc.
      :stage,
      :estimated_completion,
      :agent_pid,
      :timestamp,
      event_type: :tool_execution_progress
    ]
  end

  defmodule ToolExecutionCompleted do
    @moduledoc "Emitted when tool execution completes successfully"

    defstruct [
      :session_id,
      :execution_id,
      :tool_name,
      :result,
      :duration_ms,
      :agent_pid,
      :timestamp,
      event_type: :tool_execution_completed
    ]
  end

  defmodule ToolExecutionFailed do
    @moduledoc "Emitted when tool execution fails"

    defstruct [
      :session_id,
      :execution_id,
      :tool_name,
      :error,
      :duration_ms,
      :agent_pid,
      :timestamp,
      event_type: :tool_execution_failed
    ]
  end

  defmodule ToolExecutionCancelled do
    @moduledoc "Emitted when tool execution is cancelled"

    defstruct [
      :session_id,
      :execution_id,
      :tool_name,
      :progress_at_cancellation,
      :agent_pid,
      :timestamp,
      event_type: :tool_execution_cancelled
    ]
  end

  # Export Events

  defmodule ExportStarted do
    @moduledoc "Emitted when an export operation begins"

    defstruct [
      :session_id,
      :export_id,
      :format,
      :started_at,
      event_type: :export_started
    ]
  end

  defmodule ExportProgress do
    @moduledoc "Emitted during export to show progress"

    defstruct [
      :session_id,
      :export_id,
      # 0-100 percentage
      :progress,
      event_type: :export_progress
    ]
  end

  defmodule ExportCompleted do
    @moduledoc "Emitted when export completes successfully"

    defstruct [
      :session_id,
      :export_id,
      :download_url,
      :file_size,
      :duration_ms,
      event_type: :export_completed
    ]
  end

  defmodule ExportFailed do
    @moduledoc "Emitted when export fails"

    defstruct [
      :session_id,
      :export_id,
      :error,
      event_type: :export_failed
    ]
  end

  # Agent Pool Events

  defmodule AgentPoolStatusChanged do
    @moduledoc "Emitted when agent pool status changes significantly"

    defstruct [
      :active_workers,
      :queue_length,
      :max_concurrent,
      :utilization_pct,
      :total_completed,
      :total_failed,
      event_type: :agent_pool_status_changed
    ]
  end

  defmodule AgentPoolWorkerStarted do
    @moduledoc "Emitted when a new worker is started in the pool"

    defstruct [
      :worker_pid,
      :session_id,
      :tool_name,
      :queue_time_ms,
      event_type: :agent_pool_worker_started
    ]
  end

  defmodule AgentPoolWorkerCompleted do
    @moduledoc "Emitted when a pool worker completes"

    defstruct [
      :worker_pid,
      :session_id,
      :tool_name,
      :duration_ms,
      :success,
      event_type: :agent_pool_worker_completed
    ]
  end

  defmodule AgentPoolQueueFull do
    @moduledoc "Emitted when the agent pool queue is full"

    defstruct [
      :queue_length,
      :max_queue_size,
      :rejected_request,
      :timestamp,
      event_type: :agent_pool_queue_full
    ]
  end

  # Maintenance Events

  defmodule MaintenanceStarted do
    @moduledoc "Emitted when maintenance cycle begins"

    defstruct [
      # :scheduled, :forced, :deep_clean
      :maintenance_type,
      :started_at,
      event_type: :maintenance_started
    ]
  end

  defmodule MaintenanceCompleted do
    @moduledoc "Emitted when maintenance cycle completes"

    defstruct [
      :maintenance_type,
      :duration_ms,
      :stats,
      event_type: :maintenance_completed
    ]
  end

  defmodule MaintenanceFailed do
    @moduledoc "Emitted when maintenance encounters errors"

    defstruct [
      :maintenance_type,
      :error,
      :partial_stats,
      event_type: :maintenance_failed
    ]
  end

  # Session Management Events

  defmodule SessionAgentSpawned do
    @moduledoc "Emitted when a subagent is spawned for a session"

    defstruct [
      :session_id,
      :subagent_id,
      :agent_type,
      :agent_pid,
      :task_spec,
      event_type: :session_agent_spawned
    ]
  end

  defmodule SessionAgentTerminated do
    @moduledoc "Emitted when a subagent terminates"

    defstruct [
      :session_id,
      :subagent_id,
      :agent_type,
      :reason,
      :duration_ms,
      event_type: :session_agent_terminated
    ]
  end

  # Multi-Agent Orchestration Events

  defmodule AgentStarted do
    @moduledoc "Emitted when a specialized agent starts"

    defstruct [
      :agent_id,
      :agent_type,
      :capabilities,
      :started_at,
      :pid,
      :timestamp,
      event_type: :agent_started
    ]
  end

  defmodule AgentStopped do
    @moduledoc "Emitted when a specialized agent stops"

    defstruct [
      :agent_id,
      :agent_type,
      :reason,
      :uptime_ms,
      :timestamp,
      event_type: :agent_stopped
    ]
  end

  defmodule TaskCompleted do
    @moduledoc "Emitted when an agent completes a task"

    defstruct [
      :agent_id,
      :task_id,
      :result,
      :duration_ms,
      :timestamp,
      event_type: :task_completed
    ]
  end

  defmodule TaskFailed do
    @moduledoc "Emitted when an agent task fails"

    defstruct [
      :agent_id,
      :task_id,
      :error,
      :duration_ms,
      :timestamp,
      event_type: :task_failed
    ]
  end

  defmodule WorkflowStarted do
    @moduledoc "Emitted when a multi-agent workflow starts"

    defstruct [
      :workflow_id,
      :steps,
      :started_at,
      :timestamp,
      event_type: :workflow_started
    ]
  end

  defmodule WorkflowCompleted do
    @moduledoc "Emitted when a workflow completes successfully"

    defstruct [
      :workflow_id,
      :results,
      :duration_ms,
      :timestamp,
      event_type: :workflow_completed
    ]
  end

  defmodule WorkflowFailed do
    @moduledoc "Emitted when a workflow fails"

    defstruct [
      :workflow_id,
      :error,
      :step_index,
      :duration_ms,
      :timestamp,
      event_type: :workflow_failed
    ]
  end

  defmodule CollaborationStarted do
    @moduledoc "Emitted when agent collaboration begins"

    defstruct [
      :collaboration_id,
      :agent_ids,
      :collaboration_spec,
      :started_at,
      :timestamp,
      event_type: :collaboration_started
    ]
  end

  # System Events

  defmodule SystemHealthUpdate do
    @moduledoc "Emitted periodically with system health information"

    defstruct [
      :timestamp,
      :active_sessions,
      :active_subagents,
      :agent_pool_status,
      :memory_usage,
      :uptime_ms,
      event_type: :system_health_update
    ]
  end

  # Helper functions for working with events

  @doc "Get all event types that can be emitted"
  def event_types do
    [
      :tool_execution_started,
      :tool_execution_progress,
      :tool_execution_completed,
      :tool_execution_failed,
      :tool_execution_cancelled,
      :export_started,
      :export_progress,
      :export_completed,
      :export_failed,
      :agent_pool_status_changed,
      :agent_pool_worker_started,
      :agent_pool_worker_completed,
      :maintenance_started,
      :maintenance_completed,
      :maintenance_failed,
      :session_agent_spawned,
      :session_agent_terminated,
      :agent_started,
      :agent_stopped,
      :task_completed,
      :task_failed,
      :workflow_started,
      :workflow_completed,
      :workflow_failed,
      :collaboration_started,
      :system_health_update
    ]
  end

  @doc "Check if an event is related to a specific session"
  def session_event?(event, session_id) do
    Map.get(event, :session_id) == session_id
  end

  @doc "Check if an event is a tool execution event"
  def tool_execution_event?(event) do
    event.event_type in [
      :tool_execution_started,
      :tool_execution_progress,
      :tool_execution_completed,
      :tool_execution_failed,
      :tool_execution_cancelled
    ]
  end

  @doc "Check if an event is an export event"
  def export_event?(event) do
    event.event_type in [
      :export_started,
      :export_progress,
      :export_completed,
      :export_failed
    ]
  end

  @doc "Check if an event indicates completion (success or failure)"
  def completion_event?(event) do
    event.event_type in [
      :tool_execution_completed,
      :tool_execution_failed,
      :tool_execution_cancelled,
      :export_completed,
      :export_failed,
      :maintenance_completed,
      :maintenance_failed
    ]
  end

  @doc "Extract duration from events that have it"
  def get_duration(event) do
    Map.get(event, :duration_ms)
  end

  @doc "Format event for logging"
  def format_for_log(event) do
    base_info = %{
      event_type: event.event_type,
      timestamp: DateTime.utc_now()
    }

    session_info =
      if Map.has_key?(event, :session_id) do
        %{session_id: event.session_id}
      else
        %{}
      end

    agent_info =
      if Map.has_key?(event, :agent_pid) do
        %{agent_pid: inspect(event.agent_pid)}
      else
        %{}
      end

    Map.merge(base_info, Map.merge(session_info, agent_info))
  end
end
