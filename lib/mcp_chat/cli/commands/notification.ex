defmodule MCPChat.CLI.Commands.Notification do
  @moduledoc """
  Commands for managing MCP notifications.
  """

  use MCPChat.CLI.Commands.Base

  alias MCPChat.MCP.Handlers.ComprehensiveNotificationHandler

  @impl true
  def commands() do
    %{
      "notification" => "Manage MCP server notifications"
    }
  end

  @impl true
  def handle_command("notification", []) do
    show_info("""
    Notification Management Commands:

    /notification status              - Show notification settings and statistics
    /notification enable              - Enable all notifications
    /notification disable             - Disable all notifications
    /notification enable <category>   - Enable specific category
    /notification disable <category>  - Disable specific category
    /notification history [limit]     - Show notification history (default: 20)
    /notification clear               - Clear notification history

    Categories: connection, resource, tool, prompt, progress, custom
    """)
  end

  @impl true
  def handle_command("notification", ["status"]) do
    case ComprehensiveNotificationHandler.get_statistics() do
      {:ok, stats} ->
        show_info("=== Notification Status ===")

        # Overall status
        enabled = get_in(stats.settings, [:enabled])
        status_icon = if enabled, do: "🟢", else: "🔴"
        show_info("#{status_icon} Notifications: #{if enabled, do: "Enabled", else: "Disabled"}")

        # Category status
        show_info("\nCategory Settings:")
        categories = [:connection, :resource, :tool, :prompt, :progress, :custom]

        Enum.each(categories, fn category ->
          cat_settings = get_in(stats.settings, [category]) || %{}
          cat_enabled = Map.get(cat_settings, :enabled, true)
          icon = if cat_enabled, do: "✓", else: "✗"

          # Count events for this category
          event_count =
            stats.event_counts
            |> Enum.filter(fn {type, _count} ->
              category_for_type(type) == category
            end)
            |> Enum.reduce(0, fn {_type, count}, acc -> acc + count end)

          show_info("  #{icon} #{String.capitalize(to_string(category))}: #{event_count} events")
        end)

        # Statistics
        show_info("\nStatistics:")
        show_info("  Total events: #{stats.total_events}")
        show_info("  Buffered notifications: #{stats.buffered_notifications}")

        if stats.last_notification do
          show_info("  Last notification: #{format_time(stats.last_notification)}")
        end

      {:error, reason} ->
        show_error("Failed to get notification status: #{inspect(reason)}")
    end
  end

  @impl true
  def handle_command("notification", ["enable"]) do
    settings = %{enabled: true}

    case ComprehensiveNotificationHandler.update_settings(settings) do
      :ok ->
        show_success("✅ All notifications enabled")

      error ->
        show_error("Failed to enable notifications: #{inspect(error)}")
    end
  end

  @impl true
  def handle_command("notification", ["disable"]) do
    settings = %{enabled: false}

    case ComprehensiveNotificationHandler.update_settings(settings) do
      :ok ->
        show_info("🔕 All notifications disabled")

      error ->
        show_error("Failed to disable notifications: #{inspect(error)}")
    end
  end

  @impl true
  def handle_command("notification", ["enable", category]) do
    if valid_category?(category) do
      cat_atom = String.to_atom(category)
      settings = %{cat_atom => %{enabled: true}}

      case ComprehensiveNotificationHandler.update_settings(settings) do
        :ok ->
          show_success("✅ #{String.capitalize(category)} notifications enabled")

        error ->
          show_error("Failed to enable #{category} notifications: #{inspect(error)}")
      end
    else
      show_error("Invalid category: #{category}")
      show_info("Valid categories: connection, resource, tool, prompt, progress, custom")
    end
  end

  @impl true
  def handle_command("notification", ["disable", category]) do
    if valid_category?(category) do
      cat_atom = String.to_atom(category)
      settings = %{cat_atom => %{enabled: false}}

      case ComprehensiveNotificationHandler.update_settings(settings) do
        :ok ->
          show_info("🔕 #{String.capitalize(category)} notifications disabled")

        error ->
          show_error("Failed to disable #{category} notifications: #{inspect(error)}")
      end
    else
      show_error("Invalid category: #{category}")
      show_info("Valid categories: connection, resource, tool, prompt, progress, custom")
    end
  end

  @impl true
  def handle_command("notification", ["history"]) do
    handle_command("notification", ["history", "20"])
  end

  @impl true
  def handle_command("notification", ["history", limit_str]) do
    case Integer.parse(limit_str) do
      {limit, ""} when limit > 0 ->
        case ComprehensiveNotificationHandler.get_event_history(limit) do
          {:ok, events} ->
            if events == [] do
              show_info("No notification events in history")
            else
              show_info("=== Notification History (last #{limit}) ===")

              events
              |> Enum.reverse()
              |> Enum.each(&display_event/1)
            end

          {:error, reason} ->
            show_error("Failed to get history: #{inspect(reason)}")
        end

      _ ->
        show_error("Invalid limit: #{limit_str}")
    end
  end

  @impl true
  def handle_command("notification", ["clear"]) do
    # Clear by getting empty history (resets the queue)
    case ComprehensiveNotificationHandler.get_event_history(0) do
      {:ok, _} ->
        show_info("Notification history cleared")

      {:error, reason} ->
        show_error("Failed to clear history: #{inspect(reason)}")
    end
  end

  @impl true
  def handle_command("notification", args) do
    show_error("Unknown notification command: #{Enum.join(args, " ")}")
    show_info("Use /notification without arguments to see usage")
  end

  # Private functions

  defp valid_category?(category) do
    category in ~w(connection resource tool prompt progress custom)
  end

  defp category_for_type(type) do
    cond do
      type in [:server_connected, :server_disconnected, :server_error, :server_reconnecting] ->
        :connection

      type in [:resources_list_changed, :resources_updated, :resource_added, :resource_removed] ->
        :resource

      type in [:tools_list_changed, :tool_added, :tool_removed, :tool_updated] ->
        :tool

      type in [:prompts_list_changed, :prompt_added, :prompt_removed, :prompt_updated] ->
        :prompt

      type in [:progress, :progress_start, :progress_complete, :progress_error] ->
        :progress

      type == :custom_notification ->
        :custom

      true ->
        :unknown
    end
  end

  defp display_event(event) do
    time = format_time(event.timestamp)
    icon = type_icon(event.type)
    message = format_event_message(event)

    show_info("[#{time}] #{icon} #{event.server}: #{message}")
  end

  defp format_event_message(event) do
    case event.type do
      type when type in [:resources_updated, :resource_added, :resource_removed] ->
        format_resource_message(event.type, event.params)

      type when type in [:tool_added, :tool_removed] ->
        format_tool_message(event.type, event.params)

      :server_error ->
        format_server_error_message(event.params)

      :progress ->
        format_progress_message(event.params)

      :custom_notification ->
        format_custom_notification_message(event.params)

      _ ->
        format_default_message(event.type)
    end
  end

  defp format_resource_message(type, params) do
    uri = get_in(params, ["uri"]) || "unknown"
    action = type |> to_string() |> String.replace("_", " ") |> String.replace("resource ", "")
    "Resource #{action}: #{uri}"
  end

  defp format_tool_message(type, params) do
    name = get_in(params, ["name"]) || "unknown"
    action = type |> to_string() |> String.replace("_", " ") |> String.replace("tool ", "")
    "Tool #{action}: #{name}"
  end

  defp format_server_error_message(params) do
    error = get_in(params, ["error"]) || "Unknown error"
    "Server error: #{error}"
  end

  defp format_progress_message(params) do
    operation = get_in(params, ["operation"]) || "Operation"
    progress = get_in(params, ["progress"]) || 0
    total = get_in(params, ["total"]) || 100
    "#{operation}: #{progress}/#{total}"
  end

  defp format_custom_notification_message(params) do
    get_in(params, ["message"]) || "Custom notification"
  end

  defp format_default_message(type) do
    type |> to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  # Notification type icon mapping
  @type_icons %{
    server_connected: "🟢",
    server_disconnected: "🔴",
    server_error: "❌",
    server_reconnecting: "🔄",
    resources_list_changed: "📋",
    resources_updated: "📝",
    resource_added: "➕",
    resource_removed: "➖",
    tools_list_changed: "🔧",
    tool_added: "🆕",
    tool_removed: "🗑️",
    tool_updated: "🔄",
    prompts_list_changed: "💬",
    prompt_added: "💡",
    prompt_removed: "🗑️",
    prompt_updated: "✏️",
    progress: "⏳",
    progress_start: "▶️",
    progress_complete: "✅",
    progress_error: "❌",
    custom_notification: "📢"
  }

  defp type_icon(type) do
    Map.get(@type_icons, type, "•")
  end

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end
end
