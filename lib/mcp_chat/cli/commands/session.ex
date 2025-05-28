defmodule MCPChat.CLI.Commands.Session do
  @moduledoc """
  Session-related CLI commands.

  Handles commands for managing chat sessions including:
  - Creating new sessions
  - Saving and loading sessions
  - Viewing session history
  - Listing available sessions
  """

  use MCPChat.CLI.Commands.Base

  alias MCPChat.{Session, Persistence}

  @impl true
  def commands() do
    %{
      "new" => "Start a new conversation",
      "save" => "Save current session (usage: /save [name])",
      "load" => "Load a saved session (usage: /load <name|id>)",
      "sessions" => "List saved sessions",
      "history" => "Show conversation history",
      "autosave" => "Manage automatic session saving"
    }
  end

  @impl true
  def handle_command("new", _args) do
    new_conversation()
  end

  def handle_command("save", args) do
    save_session(args)
  end

  def handle_command("load", args) do
    load_session(args)
  end

  def handle_command("sessions", _args) do
    list_sessions()
  end

  def handle_command("history", _args) do
    show_history()
  end

  def handle_command("autosave", args) do
    handle_autosave_command(args)
  end

  def handle_command(cmd, _args) do
    {:error, "Unknown session command: #{cmd}"}
  end

  # Command implementations

  defp new_conversation() do
    Session.clear_session()
    show_success("Started new conversation")
  end

  defp save_session(args) do
    session_name = parse_args(args)

    case Persistence.save_session(Session.get_current_session(), session_name) do
      {:ok, path} ->
        show_success("Session saved to: #{path}")

      {:error, reason} ->
        show_error("Failed to save session: #{reason}")
    end
  end

  defp load_session(args) do
    with {:ok, args} <- require_arg(args, "/load <name|id>"),
         session_identifier <- parse_args(args),
         {:ok, session} <- Persistence.load_session(session_identifier) do
      Session.set_current_session(session)

      message_count = length(session.messages)
      show_success("Loaded session: #{session.id}")
      show_info("Messages: #{message_count}")

      if session.llm_backend do
        show_info("Backend: #{session.llm_backend}")
      end

      if session.model do
        show_info("Model: #{session.model}")
      end

      # Show last message preview
      case List.last(session.messages) do
        nil ->
          :ok

        %{"role" => role, "content" => content} ->
          preview = String.slice(content, 0, 100)
          suffix = if String.length(content) > 100, do: "...", else: ""
          show_info("Last #{role}: #{preview}#{suffix}")
      end
    else
      {:error, :not_found} ->
        show_error("Session not found")

      {:error, reason} ->
        show_error("Failed to load session: #{reason}")
    end
  end

  defp list_sessions() do
    case Persistence.list_sessions() do
      {:ok, sessions} when sessions == [] ->
        show_info("No saved sessions")

      {:ok, sessions} ->
        show_info("Saved sessions:")

        sessions
        |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
        |> Enum.each(&show_session_details/1)

      {:error, reason} ->
        show_error("Failed to list sessions: #{reason}")
    end

    :ok
  end

  defp show_history() do
    session = Session.get_current_session()

    if Enum.empty?(session.messages) do
      show_info("No messages in history")
    else
      MCPChat.CLI.Renderer.show_text("## Conversation History\n")
      Enum.each(session.messages, &show_message/1)
    end

    :ok
  end

  defp show_message(msg) do
    # Handle both map and struct access patterns
    role = msg[:role] || msg["role"]
    content = msg[:content] || msg["content"]
    formatted_role = format_role(role)

    MCPChat.CLI.Renderer.show_text("**#{formatted_role}:** #{content}\n")
  end

  defp format_role(nil), do: "Unknown"
  defp format_role("system"), do: "System"
  defp format_role("user"), do: "User"
  defp format_role("assistant"), do: "Assistant"
  defp format_role(role), do: String.capitalize(role)

  defp show_session_details(session) do
    # Format the session info
    time_ago = session.relative_time || format_time_ago(session.updated_at)
    messages = "#{session.message_count} msgs"

    # Extract name from filename if available
    name = extract_session_name(session.filename)

    # Show session details
    if name do
      IO.puts("  • #{name} (#{session.id})")
    else
      IO.puts("  • #{session.id}")
    end

    IO.puts("    #{messages}, #{time_ago}, #{format_bytes(session.size)}")

    # Backend info if available
    if session.llm_backend do
      IO.puts("    Backend: #{session.llm_backend}")
    end

    IO.puts("")
  end

  # Helper functions

  defp format_time_ago(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3_600 -> "#{div(diff, 60)} minutes ago"
      diff < 86_400 -> "#{div(diff, 3_600)} hours ago"
      diff < 604_800 -> "#{div(diff, 86_400)} days ago"
      true -> "#{div(diff, 604_800)} weeks ago"
    end
  end

  defp format_bytes(bytes) when bytes < 1_024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1_024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp extract_session_name(filename) do
    # Extract custom name from filename like "my-session_id.json"
    case Regex.run(~r/^(.+?)_[a-f0-9]{32}\.json$/, filename) do
      [_, name] when name not in ["session", "chat_session"] -> name
      _ -> nil
    end
  end

  # Autosave commands
  defp handle_autosave_command(args) do
    alias MCPChat.Session.Autosave

    case args do
      [] ->
        show_autosave_status()

      ["on"] ->
        Autosave.set_enabled(true)
        show_success("Autosave enabled")

      ["off"] ->
        Autosave.set_enabled(false)
        show_success("Autosave disabled")

      ["now"] ->
        case Autosave.force_save() do
          {:ok, :no_changes} ->
            show_info("No changes to save")

          {:ok, save_info} ->
            show_success("Session autosaved to: #{save_info.path}")

          {:error, reason} ->
            show_error("Autosave failed: #{inspect(reason)}")
        end

      ["interval", interval_str] ->
        case Integer.parse(interval_str) do
          {minutes, ""} when minutes > 0 ->
            Autosave.configure(%{interval: minutes * 60 * 1_000})
            show_success("Autosave interval set to #{minutes} minutes")

          _ ->
            show_error("Invalid interval. Please specify minutes as a positive integer.")
        end

      ["status"] ->
        show_autosave_status()

      _ ->
        show_autosave_help()
    end
  end

  defp show_autosave_status() do
    alias MCPChat.Session.Autosave

    stats = Autosave.get_stats()

    show_info("Autosave Status:")
    IO.puts("  • Enabled: #{if stats.enabled, do: "Yes", else: "No"}")
    IO.puts("  • Currently saving: #{if stats.saving, do: "Yes", else: "No"}")
    IO.puts("  • Save count: #{stats.save_count}")
    IO.puts("  • Failure count: #{stats.failure_count}")

    if stats.last_save_time do
      time_ago = format_time_ago(stats.last_save_time)
      IO.puts("  • Last save: #{time_ago}")
    else
      IO.puts("  • Last save: Never")
    end

    if stats.enabled and stats.next_save_in do
      next_save_minutes = div(stats.next_save_in, 60_000)
      next_save_seconds = rem(div(stats.next_save_in, 1_000), 60)
      IO.puts("  • Next save in: #{next_save_minutes}m #{next_save_seconds}s")
    end

    interval_minutes = div(stats.config.interval, 60_000)
    IO.puts("  • Interval: #{interval_minutes} minutes")
  end

  defp show_autosave_help() do
    show_info("""
    Autosave Commands:

    /autosave             - Show autosave status
    /autosave on          - Enable autosave
    /autosave off         - Disable autosave
    /autosave now         - Save immediately
    /autosave interval N  - Set interval to N minutes
    /autosave status      - Show detailed status
    """)
  end

  defp format_time_ago(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime)

    cond do
      diff < 60 -> "#{diff} seconds ago"
      diff < 3_600 -> "#{div(diff, 60)} minutes ago"
      diff < 86_400 -> "#{div(diff, 3_600)} hours ago"
      true -> "#{div(diff, 86_400)} days ago"
    end
  end
end
