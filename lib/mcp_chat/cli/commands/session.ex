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
      "history" => "Show conversation history"
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
    sessions = Persistence.list_sessions()

    if Enum.empty?(sessions) do
      show_info("No saved sessions found")
    else
      show_info("Saved sessions:")

      sessions
      |> Enum.sort_by(& &1.saved_at, {:desc, DateTime})
      |> Enum.each(fn session ->
        # Format the session info
        time_ago = format_time_ago(session.saved_at)
        _name = session.name || "Unnamed"
        messages = "#{session.message_count} msgs"

        # Show session details
        if session.name do
          IO.puts("  • #{session.name} (#{session.id})")
        else
          IO.puts("  • #{session.id}")
        end

        IO.puts("    #{messages}, #{time_ago}, #{format_bytes(session.file_size)}")

        # Show preview if available
        if session.last_message do
          preview = String.slice(session.last_message, 0, 60)
          suffix = if String.length(session.last_message) > 60, do: "...", else: ""
          IO.puts("    \"#{preview}#{suffix}\"")
        end

        IO.puts("")
      end)
    end

    :ok
  end

  defp show_history() do
    session = Session.get_current_session()

    if Enum.empty?(session.messages) do
      show_info("No messages in current conversation")
    else
      MCPChat.CLI.Renderer.show_text("## Conversation History\n")

      Enum.each(session.messages, fn msg ->
        role = msg["role"]
        content = msg["content"]

        case role do
          "system" ->
            MCPChat.CLI.Renderer.show_text("**System:** #{content}\n")

          "user" ->
            MCPChat.CLI.Renderer.show_text("**You:** #{content}\n")

          "assistant" ->
            MCPChat.CLI.Renderer.show_text("**Assistant:** #{content}\n")

          _ ->
            MCPChat.CLI.Renderer.show_text("**#{String.capitalize(role)}:** #{content}\n")
        end
      end)
    end

    :ok
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
end
