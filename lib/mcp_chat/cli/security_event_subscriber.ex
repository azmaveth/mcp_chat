defmodule MCPChat.CLI.SecurityEventSubscriber do
  @moduledoc """
  Subscribes to security events and displays them in the CLI.

  This module handles real-time security notifications, violations,
  and audit events, providing immediate feedback to users about
  security-related activities in their CLI session.
  """

  use GenServer
  require Logger

  # State structure
  defstruct [:ui_mode, :session_id, :display_settings, :violation_count]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Set the UI mode for event display.
  """
  def set_ui_mode(mode) when mode in [:cli, :tui, :silent] do
    GenServer.cast(__MODULE__, {:set_ui_mode, mode})
  end

  @doc """
  Update display settings for security events.
  """
  def set_display_settings(settings) do
    GenServer.cast(__MODULE__, {:set_display_settings, settings})
  end

  @doc """
  Get current violation statistics.
  """
  def get_violation_stats do
    GenServer.call(__MODULE__, :get_violation_stats)
  end

  # GenServer callbacks

  def init(opts) do
    # Subscribe to security events
    Phoenix.PubSub.subscribe(MCPChat.PubSub, "security:violations")
    Phoenix.PubSub.subscribe(MCPChat.PubSub, "security:alerts")
    Phoenix.PubSub.subscribe(MCPChat.PubSub, "security:audit")

    # Subscribe to global security events
    Phoenix.PubSub.subscribe(MCPChat.PubSub, "security:policy_updates")
    Phoenix.PubSub.subscribe(MCPChat.PubSub, "security:capability_revoked")

    ui_mode = Keyword.get(opts, :ui_mode, :cli)
    session_id = Keyword.get(opts, :session_id, "default")

    display_settings = %{
      show_audit_events: Application.get_env(:mcp_chat, :security_audit_display, false),
      show_debug_events: Application.get_env(:mcp_chat, :debug_security, false),
      violation_threshold: :medium,
      alert_sound: false
    }

    state = %__MODULE__{
      ui_mode: ui_mode,
      session_id: session_id,
      display_settings: display_settings,
      violation_count: 0
    }

    {:ok, state}
  end

  def handle_cast({:set_ui_mode, mode}, state) do
    {:noreply, %{state | ui_mode: mode}}
  end

  def handle_cast({:set_display_settings, settings}, state) do
    new_settings = Map.merge(state.display_settings, settings)
    {:noreply, %{state | display_settings: new_settings}}
  end

  def handle_call(:get_violation_stats, _from, state) do
    stats = %{
      total_violations: state.violation_count,
      session_id: state.session_id,
      ui_mode: state.ui_mode
    }

    {:reply, stats, state}
  end

  # Handle security violations
  def handle_info({:security_violation, violation}, state) do
    new_state = %{state | violation_count: state.violation_count + 1}

    case violation.severity do
      :critical ->
        render_critical_violation(violation, state)
        maybe_terminate_session(violation)

      :high ->
        render_high_violation(violation, state)

      :medium ->
        if should_display_violation?(violation, state) do
          render_medium_violation(violation, state)
        end

      :low ->
        if state.display_settings.show_debug_events do
          render_low_violation(violation, state)
        end
    end

    {:noreply, new_state}
  end

  # Handle security alerts
  def handle_info({:security_alert, alert}, state) do
    case state.ui_mode do
      :silent ->
        # Log but don't display
        Logger.info("Security alert: #{alert.type}")

      _ ->
        render_security_alert(alert, state)

        if alert[:action_required] do
          prompt_security_action(alert)
        end
    end

    {:noreply, state}
  end

  # Handle audit events (debug mode only)
  def handle_info({:audit_event, event}, state) do
    if state.display_settings.show_audit_events do
      render_audit_event(event, state)
    end

    {:noreply, state}
  end

  # Handle policy updates
  def handle_info({:security_policy_updated, policy}, state) do
    if state.display_settings.show_debug_events do
      render_info("🔄 Security policy updated: #{policy.name}")
    end

    {:noreply, state}
  end

  # Handle capability revocation
  def handle_info({:capability_revoked, capability_id}, state) do
    if state.display_settings.show_debug_events do
      render_warning("🔒 Capability revoked: #{capability_id}")
    end

    {:noreply, state}
  end

  # Catch-all for other events
  def handle_info(_event, state) do
    {:noreply, state}
  end

  # Private rendering functions

  defp render_critical_violation(violation, state) do
    case state.ui_mode do
      :silent ->
        :ok

      _ ->
        render_error("🚨 CRITICAL SECURITY VIOLATION: #{violation.message}")

        if violation[:details] do
          render_error("   Details: #{violation.details}")
        end

        if violation[:principal_id] do
          render_error("   Principal: #{violation.principal_id}")
        end
    end
  end

  defp render_high_violation(violation, state) do
    case state.ui_mode do
      :silent ->
        :ok

      _ ->
        render_warning("⚠️  Security Warning: #{violation.message}")

        if violation[:details] do
          render_info("   Details: #{violation.details}")
        end
    end
  end

  defp render_medium_violation(violation, state) do
    case state.ui_mode do
      :silent ->
        :ok

      :cli ->
        render_info("🔒 Security Notice: #{violation.message}")

      :tui ->
        # For TUI, could send to a dedicated security panel
        render_info("🔒 Security Notice: #{violation.message}")
    end
  end

  defp render_low_violation(violation, state) do
    case state.ui_mode do
      :silent ->
        :ok

      _ ->
        render_debug("🔍 Security Debug: #{violation.message}")
    end
  end

  defp render_security_alert(alert, state) do
    case state.ui_mode do
      :silent ->
        :ok

      _ ->
        render_warning("🔔 Security Alert: #{alert.type}")
        render_info("   #{alert.message}")

        if alert[:recommended_action] do
          render_info("   Recommended: #{alert.recommended_action}")
        end
    end
  end

  defp render_audit_event(event, state) do
    case state.ui_mode do
      :silent ->
        :ok

      _ ->
        principal = event[:principal_id] || "unknown"
        action = event[:action] || "unknown"
        render_debug("📝 Audit: #{action} by #{principal}")
    end
  end

  defp should_display_violation?(violation, state) do
    severity_level =
      case violation.severity do
        :critical -> 4
        :high -> 3
        :medium -> 2
        :low -> 1
      end

    threshold_level =
      case state.display_settings.violation_threshold do
        :critical -> 4
        :high -> 3
        :medium -> 2
        :low -> 1
      end

    severity_level >= threshold_level
  end

  defp maybe_terminate_session(violation) do
    if violation[:terminate_session] do
      render_error("Session terminated due to security violation.")

      # Send termination signal to CLI
      Task.start(fn ->
        # Give time for message to display
        Process.sleep(1000)
        Process.send(MCPChat.CLI, :security_termination, [])
      end)
    end
  end

  defp prompt_security_action(alert) do
    Task.start(fn ->
      try do
        response = prompt_user_for_action(alert)

        # Send response back to security system
        if function_exported?(MCPChat.Security, :respond_to_alert, 2) do
          MCPChat.Security.respond_to_alert(alert.id, response)
        else
          Logger.warning("Security alert response handler not available")
        end
      rescue
        error ->
          Logger.error("Failed to handle security action prompt: #{inspect(error)}")
      end
    end)
  end

  defp prompt_user_for_action(alert) do
    options = alert[:options] || ["allow", "deny"]

    render_warning("Security action required:")
    render_info("  #{alert.prompt}")
    render_info("  Options: #{Enum.join(options, ", ")}")

    # Simple input prompt (would be enhanced in real TUI)
    case IO.gets("Your choice: ") do
      # Default to deny on error
      {:error, _} ->
        "deny"

      response ->
        response
        |> String.trim()
        |> String.downcase()
        |> then(fn choice ->
          if choice in options, do: choice, else: "deny"
        end)
    end
  end

  # Output rendering helpers

  defp render_error(message) do
    IO.puts(:stderr, message)
  end

  defp render_warning(message) do
    IO.puts(:stderr, message)
  end

  defp render_info(message) do
    IO.puts(message)
  end

  defp render_debug(message) do
    if Application.get_env(:mcp_chat, :debug_security, false) do
      IO.puts(message)
    end
  end
end
