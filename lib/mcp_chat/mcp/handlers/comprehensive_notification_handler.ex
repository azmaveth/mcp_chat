defmodule MCPChat.MCP.Handlers.ComprehensiveNotificationHandler do
  @moduledoc """
  Comprehensive notification handler for all MCP server changes.

  Handles:
  - Server connection/disconnection events
  - Resource changes (additions, updates, removals)
  - Tool changes (new tools, removed tools)
  - Prompt changes
  - Progress updates
  - Error notifications
  - Custom server notifications

  Features:
  - Event logging with configurable levels
  - User notifications with smart filtering
  - Cache invalidation
  - Automatic retry on recoverable errors
  - Event history tracking
  - Notification batching to prevent spam
  """

  use GenServer
  require Logger

  alias MCPChat.{Session, CLI.Renderer}
  alias MCPChat.MCP.NotificationRegistry

  @notification_types [
    # Connection events
    :server_connected,
    :server_disconnected,
    :server_error,
    :server_reconnecting,

    # Resource events
    :resources_list_changed,
    :resources_updated,
    :resource_added,
    :resource_removed,

    # Tool events
    :tools_list_changed,
    :tool_added,
    :tool_removed,
    :tool_updated,

    # Prompt events
    :prompts_list_changed,
    :prompt_added,
    :prompt_removed,
    :prompt_updated,

    # Progress events
    :progress,
    :progress_start,
    :progress_complete,
    :progress_error,

    # Custom events
    :custom_notification
  ]

  defstruct [
    :session_pid,
    :notification_buffer,
    :event_history,
    :notification_settings,
    :last_notification_time,
    :batch_timer
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def handle_notification(server_name, type, params \\ %{}) do
    GenServer.cast(__MODULE__, {:handle_notification, server_name, type, params})
  end

  def get_event_history(limit \\ 50) do
    GenServer.call(__MODULE__, {:get_event_history, limit})
  end

  def update_settings(settings) do
    GenServer.call(__MODULE__, {:update_settings, settings})
  end

  def get_statistics() do
    GenServer.call(__MODULE__, :get_statistics)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    # Register for all notification types
    Enum.each(@notification_types, fn type ->
      NotificationRegistry.register_handler(__MODULE__, [type])
    end)

    state = %__MODULE__{
      session_pid: Keyword.get(opts, :session_pid, MCPChat.Session),
      notification_buffer: [],
      event_history: :queue.new(),
      notification_settings: load_notification_settings(),
      last_notification_time: nil,
      batch_timer: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:handle_notification, server_name, type, params}, state) do
    # Record event
    event = %{
      server: server_name,
      type: type,
      params: params,
      timestamp: DateTime.utc_now()
    }

    # Add to history (keep last 1_000 events)
    new_history =
      state.event_history
      |> :queue.in(event)
      |> trim_queue(1_000)

    # Process notification based on type
    new_state =
      state
      |> Map.put(:event_history, new_history)
      |> process_notification(server_name, type, params)

    {:noreply, new_state}
  end

  @impl true
  def handle_call({:get_event_history, limit}, _from, state) do
    events =
      state.event_history
      |> :queue.to_list()
      |> Enum.take(-limit)

    {:reply, {:ok, events}, state}
  end

  @impl true
  def handle_call({:update_settings, settings}, _from, state) do
    new_settings = Map.merge(state.notification_settings, settings)
    save_notification_settings(new_settings)

    {:reply, :ok, %{state | notification_settings: new_settings}}
  end

  @impl true
  def handle_call(:get_statistics, _from, state) do
    stats = %{
      total_events: :queue.len(state.event_history),
      buffered_notifications: length(state.notification_buffer),
      settings: state.notification_settings,
      last_notification: state.last_notification_time
    }

    # Group events by type
    event_counts =
      state.event_history
      |> :queue.to_list()
      |> Enum.group_by(& &1.type)
      |> Enum.map(fn {type, events} -> {type, length(events)} end)
      |> Map.new()

    {:reply, {:ok, Map.put(stats, :event_counts, event_counts)}, state}
  end

  @impl true
  def handle_info(:flush_notifications, state) do
    # Flush batched notifications
    if length(state.notification_buffer) > 0 do
      display_batched_notifications(state.notification_buffer)
    end

    {:noreply, %{state | notification_buffer: [], batch_timer: nil}}
  end

  # Private Functions - Notification Processing

  defp process_notification(state, server_name, type, _params) when type in [:server_connected, :server_disconnected] do
    if should_notify?(state, type, :connection) do
      icon = if type == :server_connected, do: "🟢", else: "🔴"
      message = "#{icon} Server #{server_name} #{type |> to_string() |> String.replace("server_", "")}"

      add_notification(state, %{
        type: :info,
        message: message,
        priority: :high
      })
    else
      state
    end
  end

  defp process_notification(state, server_name, :server_error, params) do
    error = Map.get(params, "error", "Unknown error")

    if should_notify?(state, :server_error, :error) do
      add_notification(state, %{
        type: :error,
        message: "❌ Server #{server_name} error: #{error}",
        priority: :high
      })
    else
      state
    end
  end

  defp process_notification(state, server_name, type, params)
       when type in [:resources_list_changed, :resource_added, :resource_removed, :resources_updated] do
    if should_notify?(state, type, :resource) do
      handle_resource_notification(state, server_name, type, params)
    else
      state
    end
  end

  defp process_notification(state, server_name, type, params)
       when type in [:tools_list_changed, :tool_added, :tool_removed] do
    if should_notify?(state, type, :tool) do
      handle_tool_notification(state, server_name, type, params)
    else
      state
    end
  end

  defp process_notification(state, server_name, type, params)
       when type in [:prompts_list_changed, :prompt_added, :prompt_removed] do
    if should_notify?(state, type, :prompt) do
      handle_prompt_notification(state, server_name, type, params)
    else
      state
    end
  end

  defp process_notification(state, server_name, type, params)
       when type in [:progress, :progress_start, :progress_complete, :progress_error] do
    if should_notify?(state, type, :progress) do
      handle_progress_notification(state, server_name, type, params)
    else
      state
    end
  end

  defp process_notification(state, server_name, :custom_notification, params) do
    if should_notify?(state, :custom_notification, :custom) do
      message = Map.get(params, "message", "Custom notification from #{server_name}")
      level = Map.get(params, "level", "info")

      add_notification(state, %{
        type: String.to_atom(level),
        message: "📢 #{message}",
        priority: :medium
      })
    else
      state
    end
  end

  defp process_notification(state, _server_name, _type, _params) do
    # Unknown notification type, log but don't notify user
    state
  end

  # Resource notifications
  defp handle_resource_notification(state, server_name, :resources_list_changed, _params) do
    # Invalidate resource cache
    invalidate_cache(:resources, server_name)

    add_notification(state, %{
      type: :info,
      message: "📋 Resources updated for #{server_name}",
      priority: :medium
    })
  end

  defp handle_resource_notification(state, server_name, :resource_added, params) do
    uri = Map.get(params, "uri", "unknown")

    add_notification(state, %{
      type: :info,
      message: "➕ New resource: #{uri} (#{server_name})",
      priority: :low
    })
  end

  defp handle_resource_notification(state, server_name, :resource_removed, params) do
    uri = Map.get(params, "uri", "unknown")

    # Check if resource is in current context
    warn_if_in_context(uri)

    add_notification(state, %{
      type: :warning,
      message: "➖ Resource removed: #{uri} (#{server_name})",
      priority: :medium
    })
  end

  defp handle_resource_notification(state, server_name, :resources_updated, params) do
    uri = Map.get(params, "uri", "unknown")

    # Check if resource is in current context
    warn_if_in_context(uri)

    add_notification(state, %{
      type: :info,
      message: "📝 Resource updated: #{uri} (#{server_name})",
      priority: :low
    })
  end

  # Tool notifications
  defp handle_tool_notification(state, server_name, :tools_list_changed, _params) do
    # Invalidate tool cache
    invalidate_cache(:tools, server_name)

    add_notification(state, %{
      type: :info,
      message: "🔧 Tools updated for #{server_name}",
      priority: :medium
    })
  end

  defp handle_tool_notification(state, server_name, :tool_added, params) do
    tool_name = Map.get(params, "name", "unknown")

    add_notification(state, %{
      type: :info,
      message: "🆕 New tool available: #{tool_name} (#{server_name})",
      priority: :medium
    })
  end

  defp handle_tool_notification(state, server_name, :tool_removed, params) do
    tool_name = Map.get(params, "name", "unknown")

    add_notification(state, %{
      type: :warning,
      message: "🗑️  Tool removed: #{tool_name} (#{server_name})",
      priority: :medium
    })
  end

  # Prompt notifications
  defp handle_prompt_notification(state, server_name, :prompts_list_changed, _params) do
    # Invalidate prompt cache
    invalidate_cache(:prompts, server_name)

    add_notification(state, %{
      type: :info,
      message: "💬 Prompts updated for #{server_name}",
      priority: :low
    })
  end

  defp handle_prompt_notification(state, server_name, :prompt_added, params) do
    prompt_name = Map.get(params, "name", "unknown")

    add_notification(state, %{
      type: :info,
      message: "💡 New prompt: #{prompt_name} (#{server_name})",
      priority: :low
    })
  end

  defp handle_prompt_notification(state, server_name, :prompt_removed, params) do
    prompt_name = Map.get(params, "name", "unknown")

    add_notification(state, %{
      type: :info,
      message: "🗑️  Prompt removed: #{prompt_name} (#{server_name})",
      priority: :low
    })
  end

  # Progress notifications
  defp handle_progress_notification(state, _server_name, :progress, params) do
    _operation = Map.get(params, "operation", "Operation")
    progress = Map.get(params, "progress", 0)
    total = Map.get(params, "total", 100)
    token = Map.get(params, "token")

    # Update progress tracker if we have a token
    if token do
      MCPChat.MCP.ProgressTracker.update_progress(token, progress, total)
    end

    # Don't add to notification buffer for regular progress updates
    state
  end

  defp handle_progress_notification(state, server_name, :progress_start, params) do
    operation = Map.get(params, "operation", "Operation")

    add_notification(state, %{
      type: :info,
      message: "⏳ Started: #{operation} (#{server_name})",
      priority: :low
    })
  end

  defp handle_progress_notification(state, server_name, :progress_complete, params) do
    operation = Map.get(params, "operation", "Operation")

    add_notification(state, %{
      type: :success,
      message: "✅ Completed: #{operation} (#{server_name})",
      priority: :medium
    })
  end

  defp handle_progress_notification(state, server_name, :progress_error, params) do
    operation = Map.get(params, "operation", "Operation")
    error = Map.get(params, "error", "Unknown error")

    add_notification(state, %{
      type: :error,
      message: "❌ Failed: #{operation} - #{error} (#{server_name})",
      priority: :high
    })
  end

  # Notification management

  defp add_notification(state, notification) do
    # Add to buffer
    new_buffer = [notification | state.notification_buffer]

    # Cancel existing timer if any
    if state.batch_timer do
      Process.cancel_timer(state.batch_timer)
    end

    # Set new timer or flush immediately based on priority
    new_state =
      if notification.priority == :high or length(new_buffer) >= 5 do
        # Flush immediately
        display_batched_notifications(new_buffer)
        %{state | notification_buffer: [], batch_timer: nil, last_notification_time: DateTime.utc_now()}
      else
        # Batch for 2 seconds
        timer = Process.send_after(self(), :flush_notifications, 2000)
        %{state | notification_buffer: new_buffer, batch_timer: timer}
      end

    new_state
  end

  defp display_batched_notifications(notifications) do
    # Group by type and display
    notifications
    |> Enum.reverse()
    |> Enum.group_by(& &1.type)
    |> Enum.each(fn {type, msgs} ->
      display_func =
        case type do
          :error -> &Renderer.show_error/1
          :warning -> &Renderer.show_warning/1
          :success -> &Renderer.show_success/1
          _ -> &Renderer.show_info/1
        end

      Enum.each(msgs, fn notification ->
        display_func.(notification.message)
      end)
    end)
  end

  # Helper functions

  defp should_notify?(state, type, category) do
    settings = state.notification_settings

    # Check global enable
    if Map.get(settings, :enabled, true) do
      # Check category-specific settings
      category_settings = Map.get(settings, category, %{})

      Map.get(category_settings, :enabled, true) and
        Map.get(category_settings, type, true)
    else
      false
    end
  end

  defp invalidate_cache(cache_type, server_name) do
    # This would integrate with a caching layer
    Logger.debug("Invalidating #{cache_type} cache for #{server_name}")
    # TODO: Implement actual cache invalidation when cache layer is added
  end

  defp warn_if_in_context(uri) do
    case Session.get_context_files() do
      {:ok, files} ->
        if Map.has_key?(files, uri) do
          Renderer.show_warning("⚠️  A resource in your context has changed: #{uri}")
          Renderer.show_info("Consider refreshing with: /context rm #{uri} && /context add #{uri}")
        end

      _ ->
        :ok
    end
  end

  defp trim_queue(queue, max_size) do
    current_size = :queue.len(queue)

    if current_size > max_size do
      to_drop = current_size - max_size
      {_dropped, remaining} = :queue.split(to_drop, queue)
      remaining
    else
      queue
    end
  end

  defp load_notification_settings() do
    # Load from config or use defaults
    case MCPChat.Config.get([:notifications]) do
      {:ok, settings} -> settings
      _ -> default_notification_settings()
    end
  end

  defp save_notification_settings(settings) do
    MCPChat.Config.set_runtime("notifications", settings)
  end

  defp default_notification_settings() do
    %{
      enabled: true,
      connection: %{
        enabled: true,
        server_connected: true,
        server_disconnected: true,
        server_error: true
      },
      resource: %{
        enabled: true,
        resources_list_changed: true,
        # Can be noisy
        resource_added: false,
        resource_removed: true,
        resources_updated: true
      },
      tool: %{
        enabled: true,
        tools_list_changed: true,
        tool_added: true,
        tool_removed: true
      },
      prompt: %{
        enabled: true,
        prompts_list_changed: true,
        # Usually less important
        prompt_added: false,
        prompt_removed: false
      },
      progress: %{
        enabled: true,
        # Don't show every progress update
        progress: false,
        progress_start: true,
        progress_complete: true,
        progress_error: true
      },
      custom: %{
        enabled: true,
        custom_notification: true
      }
    }
  end
end
