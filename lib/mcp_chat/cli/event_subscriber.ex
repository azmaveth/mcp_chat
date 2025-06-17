defmodule MCPChat.CLI.EventSubscriber do
  @moduledoc """
  Subscribes to Phoenix.PubSub events from the agent architecture
  and handles real-time updates for the CLI.
  """

  use GenServer
  require Logger

  alias MCPChat.CLI.Renderer
  alias MCPChat.Events.AgentEvents

  @pubsub MCPChat.PubSub

  # Progress tracking state
  defstruct [
    :session_id,
    :active_operations,
    :ui_mode,
    :last_update_time
  ]

  # Client API

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(session_id))
  end

  def via_tuple(session_id) do
    {:via, Registry, {MCPChat.CLI.EventRegistry, {__MODULE__, session_id}}}
  end

  @doc "Subscribe to events for a session"
  def subscribe_to_session(session_id) do
    # Subscribe to session-specific events
    Phoenix.PubSub.subscribe(@pubsub, "session:#{session_id}")

    # Subscribe to system-wide events
    Phoenix.PubSub.subscribe(@pubsub, "system:agents")

    # Start the event subscriber process
    case DynamicSupervisor.start_child(
           MCPChat.CLI.EventSupervisor,
           {__MODULE__, session_id: session_id}
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  @doc "Unsubscribe from session events"
  def unsubscribe_from_session(session_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, "session:#{session_id}")
    Phoenix.PubSub.unsubscribe(@pubsub, "system:agents")

    # Stop the subscriber process
    case Registry.lookup(MCPChat.CLI.EventRegistry, {__MODULE__, session_id}) do
      [{pid, _}] -> GenServer.stop(pid)
      _ -> :ok
    end
  end

  @doc "Set UI mode for rendering"
  def set_ui_mode(session_id, mode) when mode in [:interactive, :streaming, :quiet] do
    GenServer.cast(via_tuple(session_id), {:set_ui_mode, mode})
  end

  # Server implementation

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    ui_mode = Keyword.get(opts, :ui_mode, :interactive)

    # Subscribe to events
    Phoenix.PubSub.subscribe(@pubsub, "session:#{session_id}")
    Phoenix.PubSub.subscribe(@pubsub, "system:agents")

    {:ok,
     %__MODULE__{
       session_id: session_id,
       active_operations: %{},
       ui_mode: ui_mode,
       last_update_time: System.monotonic_time(:millisecond)
     }}
  end

  # Handle Phoenix.PubSub events

  @impl true
  def handle_info({:pubsub, event}, state) do
    new_state = handle_agent_event(event, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:set_ui_mode, mode}, state) do
    {:noreply, %{state | ui_mode: mode}}
  end

  # Event handlers

  defp handle_agent_event(%AgentEvents.ToolExecutionStarted{} = event, state) do
    if state.ui_mode != :quiet do
      show_tool_started(event)
    end

    # Track active operation
    operation = %{
      type: :tool_execution,
      tool_name: event.tool_name,
      started_at: event.timestamp,
      session_id: event.session_id,
      execution_id: event.execution_id
    }

    %{state | active_operations: Map.put(state.active_operations, event.execution_id, operation)}
  end

  defp handle_agent_event(%AgentEvents.ToolExecutionProgress{} = event, state) do
    if should_show_progress?(state, event.execution_id) do
      show_tool_progress(event)
    end

    state
  end

  defp handle_agent_event(%AgentEvents.ToolExecutionCompleted{} = event, state) do
    if state.ui_mode != :quiet do
      show_tool_completed(event)
    end

    # Remove from active operations
    %{state | active_operations: Map.delete(state.active_operations, event.execution_id)}
  end

  defp handle_agent_event(%AgentEvents.ToolExecutionFailed{} = event, state) do
    if state.ui_mode != :quiet do
      show_tool_failed(event)
    end

    # Remove from active operations
    %{state | active_operations: Map.delete(state.active_operations, event.execution_id)}
  end

  defp handle_agent_event(%AgentEvents.ExportStarted{} = event, state) do
    if state.ui_mode != :quiet do
      show_export_started(event)
    end

    # Track active operation
    operation = %{
      type: :export,
      format: event.format,
      started_at: event.timestamp,
      session_id: event.session_id,
      export_id: event.export_id
    }

    %{state | active_operations: Map.put(state.active_operations, event.export_id, operation)}
  end

  defp handle_agent_event(%AgentEvents.ExportProgress{} = event, state) do
    if should_show_progress?(state, event.export_id) do
      show_export_progress(event)
    end

    state
  end

  defp handle_agent_event(%AgentEvents.ExportCompleted{} = event, state) do
    if state.ui_mode != :quiet do
      show_export_completed(event)
    end

    # Remove from active operations
    %{state | active_operations: Map.delete(state.active_operations, event.export_id)}
  end

  defp handle_agent_event(%AgentEvents.ExportFailed{} = event, state) do
    if state.ui_mode != :quiet do
      show_export_failed(event)
    end

    # Remove from active operations
    %{state | active_operations: Map.delete(state.active_operations, event.export_id)}
  end

  defp handle_agent_event(%AgentEvents.MaintenanceStarted{} = event, state) do
    if state.ui_mode == :interactive do
      Logger.debug("Maintenance started: #{event.task_type}")
    end

    state
  end

  defp handle_agent_event(%AgentEvents.MaintenanceCompleted{} = event, state) do
    if state.ui_mode == :interactive do
      Logger.debug("Maintenance completed: #{event.task_type}")
    end

    state
  end

  defp handle_agent_event(%AgentEvents.AgentPoolQueueFull{} = event, state) do
    if state.ui_mode != :quiet do
      Renderer.show_warning("⚠️  Agent pool is busy. Your request has been queued (position: #{event.queue_length})")
    end

    state
  end

  defp handle_agent_event(%AgentEvents.AgentPoolWorkerStarted{} = event, state) do
    Logger.debug("Worker started for task: #{event.task_id}")
    state
  end

  defp handle_agent_event(%AgentEvents.AgentPoolWorkerCompleted{} = event, state) do
    Logger.debug("Worker completed task: #{event.task_id}")
    state
  end

  defp handle_agent_event(_event, state) do
    # Ignore unknown events
    state
  end

  # UI display functions

  defp show_tool_started(%{tool_name: tool_name, args: args}) do
    Renderer.show_info("🔧 Starting tool execution: #{tool_name}")

    if args && map_size(args) > 0 do
      args_str = args |> Map.to_list() |> Enum.map(fn {k, v} -> "#{k}=#{inspect(v)}" end) |> Enum.join(", ")
      Renderer.show_info("   Parameters: #{args_str}")
    end
  end

  defp show_tool_progress(%{progress: progress, message: message}) do
    progress_bar = render_progress_bar(progress)
    status = if message, do: " - #{message}", else: ""

    # Use carriage return to update the same line
    IO.write("\r🔧 Progress: #{progress_bar} #{round(progress)}%#{status}")
  end

  defp show_tool_completed(%{tool_name: tool_name, duration_ms: duration}) do
    # Clear the progress line
    IO.write("\r" <> String.duplicate(" ", 80) <> "\r")

    duration_str = format_duration(duration)
    Renderer.show_success("✅ Tool completed: #{tool_name} (#{duration_str})")
  end

  defp show_tool_failed(%{tool_name: tool_name, error: error}) do
    # Clear the progress line
    IO.write("\r" <> String.duplicate(" ", 80) <> "\r")

    Renderer.show_error("❌ Tool failed: #{tool_name}")
    Renderer.show_error("   Error: #{inspect(error)}")
  end

  defp show_export_started(%{format: format}) do
    Renderer.show_info("📦 Starting export to #{format} format...")
  end

  defp show_export_progress(%{progress: progress, stage: stage}) do
    progress_bar = render_progress_bar(progress)

    # Use carriage return to update the same line
    IO.write("\r📦 Export progress: #{progress_bar} #{round(progress)}% - #{stage}")
  end

  defp show_export_completed(%{format: format, file_path: file_path, duration_ms: duration}) do
    # Clear the progress line
    IO.write("\r" <> String.duplicate(" ", 80) <> "\r")

    duration_str = format_duration(duration)
    Renderer.show_success("✅ Export completed: #{format} format (#{duration_str})")
    Renderer.show_info("   Saved to: #{file_path}")
  end

  defp show_export_failed(%{format: format, error: error}) do
    # Clear the progress line
    IO.write("\r" <> String.duplicate(" ", 80) <> "\r")

    Renderer.show_error("❌ Export failed: #{format} format")
    Renderer.show_error("   Error: #{inspect(error)}")
  end

  # Helper functions

  defp should_show_progress?(state, operation_id) do
    case Map.get(state.active_operations, operation_id) do
      nil ->
        false

      _op ->
        # Throttle progress updates to every 100ms
        now = System.monotonic_time(:millisecond)
        now - state.last_update_time > 100
    end
  end

  defp render_progress_bar(progress) do
    width = 20
    filled = round(progress / 100 * width)
    empty = width - filled

    "[" <> String.duplicate("=", filled) <> String.duplicate(" ", empty) <> "]"
  end

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 1)}s"
  defp format_duration(ms), do: "#{div(ms, 60_000)}m #{rem(div(ms, 1000), 60)}s"
end
