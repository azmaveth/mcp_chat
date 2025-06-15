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

  alias MCPChat.{Persistence, Session}
  alias MCPChat.CLI.Renderer

  @impl true
  def commands do
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

  defp new_conversation do
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
      display_loaded_session_info(session)
      display_session_metadata(session)
      display_last_message_preview(session)
    else
      {:error, :not_found} ->
        show_error("Session not found")

      {:error, reason} ->
        show_error("Failed to load session: #{reason}")
    end
  end

  defp display_loaded_session_info(session) do
    message_count = length(session.messages)
    show_success("Loaded session: #{session.id}")
    show_info("Messages: #{message_count}")
  end

  defp display_session_metadata(session) do
    if session.llm_backend do
      show_info("Backend: #{session.llm_backend}")
    end

    model = session.context[:model] || Map.get(session, :model)

    if model do
      show_info("Model: #{model}")
    end
  end

  defp display_last_message_preview(session) do
    case List.last(session.messages) do
      nil ->
        :ok

      message ->
        display_message_preview(message)
    end
  end

  defp display_message_preview(%{"role" => role, "content" => content}) do
    show_message_preview(role, content)
  end

  defp display_message_preview(%{role: role, content: content}) do
    show_message_preview(role, content)
  end

  defp display_message_preview(%{"content" => content} = msg) do
    role = msg["role"] || msg[:role] || "unknown"
    show_message_preview(role, content)
  end

  defp display_message_preview(%{content: content} = msg) do
    role = msg[:role] || msg["role"] || "unknown"
    show_message_preview(role, content)
  end

  defp display_message_preview(_other), do: :ok

  defp show_message_preview(role, content) do
    preview = String.slice(content, 0, 100)
    suffix = if String.length(content) > 100, do: "...", else: ""
    show_info("Last #{role}: #{preview}#{suffix}")
  end

  defp list_sessions do
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

  defp show_history do
    session = Session.get_current_session()

    if Enum.empty?(session.messages) do
      show_info("No messages in history")
    else
      Renderer.show_text("## Conversation History\n")
      Enum.each(session.messages, &show_message/1)
    end

    :ok
  end

  defp show_message(msg) do
    # Handle both map and struct access patterns
    role = msg[:role] || msg["role"]
    content = msg[:content] || msg["content"]
    formatted_role = format_role(role)

    Renderer.show_text("**#{formatted_role}:** #{content}\n")
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
end
