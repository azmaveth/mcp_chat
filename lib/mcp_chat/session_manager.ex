defmodule MCPChat.SessionManager do
  @moduledoc """
  Manages chat sessions with automatic saving and directory-based naming.

  Sessions are automatically saved with names based on:
  - Current datetime
  - Directory where mcp_chat was started
  - Sequential numbering if multiple sessions in same directory
  """

  require Logger
  alias MCPChat.{Session, Persistence}

  @doc """
  Start a new chat session with automatic saving.
  """
  def start_new_session(opts \\ []) do
    backend = Keyword.get(opts, :backend, nil)

    # Create new session
    Session.new_session(backend)

    # Generate session name based on datetime and directory
    session_name = generate_session_name()

    # Get the current session and save it immediately
    session = Session.get_current_session()

    # Update session metadata with the filename
    Session.update_session(%{
      metadata: %{
        session_file: session_name,
        start_directory: File.cwd!(),
        started_at: DateTime.utc_now()
      }
    })

    # Save initial session
    case Persistence.save_session(session, session_name) do
      {:ok, path} ->
        Logger.info("Started new session: #{session_name}")
        Logger.debug("Session saved to: #{path}")

        # Configure autosave to save on every message
        configure_autosave_for_immediate_save(session_name)

        {:ok, %{name: session_name, path: path}}

      {:error, reason} ->
        Logger.error("Failed to save initial session: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Continue the most recent session.
  """
  def continue_most_recent() do
    case Persistence.list_sessions() do
      {:ok, []} ->
        {:error, :no_sessions}

      {:ok, [most_recent | _]} ->
        resume_session(most_recent.filename)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Resume a specific session by filename or identifier.
  """
  def resume_session(identifier) do
    case Persistence.load_session(identifier) do
      {:ok, session} ->
        # Restore the session
        Session.restore_session(session)

        # Extract session name from metadata or filename
        session_name = get_session_name(session, identifier)

        # Configure autosave for this session
        configure_autosave_for_immediate_save(session_name)

        # Show session info
        show_session_info(session)

        {:ok, %{name: session_name, session: session}}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Save the current session immediately.
  Called by autosave when a new message is added.
  """
  def save_current_session() do
    session = Session.get_current_session()

    # Get session name from metadata
    session_name =
      case session.metadata do
        %{session_file: name} -> name
        _ -> generate_session_name()
      end

    case Persistence.save_session(session, session_name) do
      {:ok, _path} ->
        Logger.debug("Session auto-saved: #{session_name}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to auto-save session: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp generate_session_name() do
    # Get current directory name (last part of path)
    cwd = File.cwd!()
    dir_name = cwd |> Path.split() |> List.last() |> sanitize_for_filename()

    # Format datetime
    now = DateTime.utc_now()
    date_str = Calendar.strftime(now, "%Y%m%d_%H%M%S")

    # Base name
    base_name = "#{dir_name}_#{date_str}"

    # Check for existing sessions with same base name and add sequence if needed
    sessions_dir = Persistence.get_sessions_dir()

    existing_files =
      case File.ls(sessions_dir) do
        {:ok, files} -> files
        _ -> []
      end

    if Enum.any?(existing_files, &String.starts_with?(&1, base_name)) do
      # Find the highest sequence number
      max_seq =
        existing_files
        |> Enum.filter(&String.starts_with?(&1, base_name))
        |> Enum.map(fn file ->
          case Regex.run(~r/#{Regex.escape(base_name)}_(\d+)/, file) do
            [_, seq] -> String.to_integer(seq)
            _ -> 0
          end
        end)
        |> Enum.max(fn -> 0 end)

      "#{base_name}_#{max_seq + 1}"
    else
      base_name
    end
  end

  defp sanitize_for_filename(str) do
    str
    |> String.replace(~r/[^a-zA-Z0-9_\-]/, "_")
    |> String.slice(0, 30)
  end

  defp configure_autosave_for_immediate_save(session_name) do
    # Configure autosave to trigger on every change
    MCPChat.Session.Autosave.configure(%{
      # 24 hours - effectively disable periodic saves
      interval: 24 * 60 * 60 * 1_000,
      # Very short debounce for immediate saves
      debounce: 100,
      enabled: true,
      session_name_prefix: session_name
    })

    # Set up a hook to save on every message
    # This will be called by the Session module when messages are added
    :ok
  end

  defp get_session_name(session, identifier) do
    case session do
      %{metadata: %{session_file: name}} -> name
      _ -> Path.basename(identifier, ".json")
    end
  end

  defp show_session_info(session) do
    message_count = length(session.messages)

    created_at =
      case session do
        %{metadata: %{started_at: started}} -> started
        _ -> session.created_at
      end

    time_ago = format_time_ago(created_at)

    IO.puts("")
    IO.puts("📂 Resumed session from #{time_ago}")
    IO.puts("   Messages: #{message_count}")
    IO.puts("   Backend: #{session.llm_backend}")

    # Show last few messages for context
    if message_count > 0 do
      IO.puts("\n   Recent conversation:")

      session.messages
      # Last 3 messages
      |> Enum.take(-3)
      |> Enum.each(fn msg ->
        preview =
          msg.content
          |> String.trim()
          |> String.slice(0, 60)
          |> then(fn s -> if String.length(msg.content) > 60, do: s <> "...", else: s end)

        role_emoji = if msg.role == "user", do: "👤", else: "🤖"
        IO.puts("   #{role_emoji} #{preview}")
      end)
    end

    IO.puts("")
  end

  defp format_time_ago(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime)

    cond do
      diff_seconds < 60 ->
        "just now"

      diff_seconds < 3_600 ->
        minutes = div(diff_seconds, 60)
        if minutes == 1, do: "1 minute ago", else: "#{minutes} minutes ago"

      diff_seconds < 86_400 ->
        hours = div(diff_seconds, 3_600)
        if hours == 1, do: "1 hour ago", else: "#{hours} hours ago"

      diff_seconds < 604_800 ->
        days = div(diff_seconds, 86_400)
        if days == 1, do: "yesterday", else: "#{days} days ago"

      true ->
        Calendar.strftime(datetime, "%Y-%m-%d")
    end
  end
end
