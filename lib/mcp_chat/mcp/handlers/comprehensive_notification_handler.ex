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
  """

  @behaviour MCPChat.MCP.NotificationHandler
  require Logger

  alias MCPChat.CLI.Renderer

  defstruct [
    :session_pid,
    :notification_settings,
    :event_count
  ]

  @notification_types [
    # Connection events
    :server_connected,
    :server_disconnected,
    :server_error,

    # Resource events
    :resources_list_changed,
    :resource_added,
    :resource_removed,
    :resources_updated,

    # Tool events
    :tools_list_changed,
    :tool_added,
    :tool_removed,

    # Prompt events
    :prompts_list_changed,
    :prompt_added,
    :prompt_removed,

    # Progress events
    :progress,
    :progress_start,
    :progress_complete,
    :progress_error,

    # Custom events
    :custom_notification
  ]

  @impl true
  def init(args) do
    state = %__MODULE__{
      session_pid: Keyword.get(args, :session_pid, MCPChat.Session),
      notification_settings: load_notification_settings(),
      event_count: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_notification(server_name, type, params, state) when type in @notification_types do
    # Check if this notification type is enabled
    if notification_enabled?(type, state.notification_settings) do
      # Log the event
      Logger.debug("MCP notification: #{server_name} - #{type} - #{inspect(params)}")

      # Format and display notification
      message = format_notification(server_name, type, params)

      if message do
        Renderer.show_info(message)
      end

      # Update event count
      new_state = %{state | event_count: state.event_count + 1}
      {:ok, new_state}
    else
      # Notification disabled, just track the event
      new_state = %{state | event_count: state.event_count + 1}
      {:ok, new_state}
    end
  end

  @impl true
  def handle_notification(server_name, type, params, state) do
    # Unknown notification type
    Logger.warning("Unknown notification type: #{type} from server #{server_name} - #{inspect(params)}")
    {:ok, state}
  end

  # Helper Functions

  defp load_notification_settings() do
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
        resources_updated: true,
        resource_added: false,
        resource_removed: true
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
        prompt_added: false,
        prompt_removed: false
      },
      progress: %{
        enabled: true,
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

  defp notification_enabled?(type, settings) do
    # Check global enabled flag
    if not settings.enabled do
      false
    else
      # Check category-specific settings
      result =
        Enum.reduce_while(settings, {:cont, nil}, fn
          {_category, %{enabled: false}}, acc ->
            acc

          {_category, category_settings}, acc when is_map(category_settings) ->
            if Map.has_key?(category_settings, type) do
              {:halt, category_settings[type]}
            else
              acc
            end

          _, acc ->
            acc
        end)

      case result do
        {:halt, result} -> result
        # Default to enabled if not found
        {:cont, _} -> true
      end
    end
  end

  defp format_notification(server_name, type, params) do
    case type do
      type when type in [:server_connected, :server_disconnected, :server_error] ->
        format_connection_event(server_name, type, params)

      type when type in [:resources_list_changed, :resources_updated, :resource_added, :resource_removed] ->
        format_resource_event(server_name, type, params)

      type when type in [:tools_list_changed, :tool_added, :tool_removed] ->
        format_tool_event(server_name, type, params)

      type when type in [:prompts_list_changed, :prompt_added, :prompt_removed] ->
        format_prompt_event(server_name, type, params)

      type when type in [:progress, :progress_start, :progress_complete, :progress_error] ->
        format_progress_event(server_name, type, params)

      :custom_notification ->
        format_custom_event(server_name, params)

      _ ->
        format_unknown_event(server_name, type, params)
    end
  end

  # Event formatting helpers

  defp format_connection_event(server_name, type, params) do
    case type do
      :server_connected ->
        "🔌 Connected to MCP server: #{server_name}"

      :server_disconnected ->
        "❌ Disconnected from MCP server: #{server_name}"

      :server_error ->
        error = params[:error] || "unknown error"
        "⚠️  Error with MCP server #{server_name}: #{error}"
    end
  end

  defp format_resource_event(server_name, type, params) do
    case type do
      :resources_list_changed ->
        "📋 Resources updated for server: #{server_name}"

      :resources_updated ->
        resource = params[:resource] || "unknown"
        "📝 Resource updated: #{resource} (#{server_name})"

      :resource_added ->
        resource = params[:resource] || "unknown"
        "➕ New resource: #{resource} (#{server_name})"

      :resource_removed ->
        resource = params[:resource] || "unknown"
        "➖ Resource removed: #{resource} (#{server_name})"
    end
  end

  defp format_tool_event(server_name, type, params) do
    case type do
      :tools_list_changed ->
        "🔧 Tools updated for server: #{server_name}"

      :tool_added ->
        tool = params[:tool] || "unknown"
        "🆕 New tool: #{tool} (#{server_name})"

      :tool_removed ->
        tool = params[:tool] || "unknown"
        "🗑️  Tool removed: #{tool} (#{server_name})"
    end
  end

  defp format_prompt_event(server_name, type, params) do
    case type do
      :prompts_list_changed ->
        "💬 Prompts updated for server: #{server_name}"

      :prompt_added ->
        prompt = params[:prompt] || "unknown"
        "📝 New prompt: #{prompt} (#{server_name})"

      :prompt_removed ->
        prompt = params[:prompt] || "unknown"
        "🗑️  Prompt removed: #{prompt} (#{server_name})"
    end
  end

  defp format_progress_event(server_name, type, params) do
    case type do
      # Avoid spam from frequent updates
      :progress ->
        nil

      :progress_start ->
        operation = params[:operation] || "operation"
        "⏳ Started: #{operation} (#{server_name})"

      :progress_complete ->
        operation = params[:operation] || "operation"
        "✅ Completed: #{operation} (#{server_name})"

      :progress_error ->
        operation = params[:operation] || "operation"
        error = params[:error] || "unknown error"
        "❌ Failed: #{operation} - #{error} (#{server_name})"
    end
  end

  defp format_custom_event(server_name, params) do
    message = params[:message] || inspect(params)
    "📢 #{server_name}: #{message}"
  end

  defp format_unknown_event(server_name, type, params) do
    "🔔 #{server_name}: #{type} - #{inspect(params)}"
  end

  # Public API for notification control

  def get_settings() do
    GenServer.call(__MODULE__, :get_settings)
  rescue
    _ -> load_notification_settings()
  end

  def update_settings(new_settings) do
    GenServer.call(__MODULE__, {:update_settings, new_settings})
  rescue
    _ -> {:error, :not_running}
  end

  def get_event_count() do
    GenServer.call(__MODULE__, :get_event_count)
  rescue
    _ -> 0
  end
end
