defmodule MCPChat do
  @moduledoc """
  MCP Chat Client - A CLI chat interface with MCP server support.
  """

  require Logger
  alias MCPChat.CLI.Chat

  @doc """
  Start the chat client CLI.
  """
  def main(args \\ []) do
    case parse_args(args) do
      {:ok, opts} ->
        start_app(opts)

      {:list_sessions, _opts} ->
        list_sessions_and_exit()

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end

  defp parse_args(args) do
    case OptionParser.parse(args,
           switches: [
             config: :string,
             backend: :string,
             help: :boolean,
             resume: :string,
             continue: :boolean,
             list_sessions: :boolean
           ],
           aliases: [
             c: :continue,
             b: :backend,
             h: :help,
             r: :resume,
             l: :list_sessions
           ]
         ) do
      {opts, [], []} ->
        # Handle conflict between -c for config and -c for continue
        opts = resolve_config_continue_conflict(opts, args)

        cond do
          opts[:help] ->
            show_help()
            System.halt(0)

          opts[:list_sessions] ->
            # Handle list sessions flag
            {:list_sessions, opts}

          true ->
            {:ok, opts}
        end

      {_, _, invalid} ->
        {:error, "Invalid arguments: #{inspect(invalid)}"}
    end
  end

  defp resolve_config_continue_conflict(opts, args) do
    # Check if -c was used (could be either config or continue)
    has_c_flag = Enum.any?(args, &(&1 == "-c"))

    if has_c_flag and opts[:continue] do
      # -c was parsed as continue, but check if it has a value (making it config)
      c_index = Enum.find_index(args, &(&1 == "-c"))
      next_arg = Enum.at(args, c_index + 1)

      if next_arg && !String.starts_with?(next_arg, "-") do
        # -c has a value, so it's config, not continue
        opts
        |> Keyword.put(:config, next_arg)
        |> Keyword.delete(:continue)
      else
        # -c has no value, so it's continue
        opts
      end
    else
      opts
    end
  end

  defp show_help() do
    IO.puts("""
    MCP Chat Client

    Usage: mcp_chat [options]

    Options:
      -h, --help             Show this help message
      -b, --backend NAME     LLM backend to use (anthropic, openai, local)
      -c, --continue         Continue the most recent chat session
      -r, --resume PATH      Resume a specific chat session by file path or ID
      -l, --list-sessions    List all saved chat sessions
      --config PATH          Path to configuration file

    Examples:
      mcp_chat               Start a new chat session
      mcp_chat -c            Continue the most recent session
      mcp_chat -r session_1  Resume session with ID or filename containing 'session_1'
      mcp_chat -l            List all saved sessions
    """)
  end

  defp start_app(opts) do
    configure_logging(opts)
    start_application()
    handle_session_options(opts)
    start_chat_interface()
  end

  defp configure_logging(opts) do
    log_level = determine_log_level(opts)
    Logger.configure(level: log_level)
  end

  defp determine_log_level(opts) do
    if opts[:quiet] || !Code.ensure_loaded?(Mix), do: :error, else: :info
  end

  defp start_application() do
    {:ok, _} = Application.ensure_all_started(:mcp_chat)
  end

  defp handle_session_options(opts) do
    cond do
      opts[:continue] -> continue_recent_session()
      opts[:resume] -> resume_specific_session(opts[:resume])
      true -> start_new_session_with_opts(opts)
    end
  end

  defp continue_recent_session() do
    case MCPChat.SessionManager.continue_most_recent() do
      {:ok, session_info} ->
        Logger.info("Continuing session: #{session_info.name}")

      {:error, :no_sessions} ->
        Logger.info("No previous sessions found, starting new session")
        MCPChat.SessionManager.start_new_session()

      {:error, reason} ->
        handle_session_error("Failed to continue session", reason)
    end
  end

  defp resume_specific_session(session_id) do
    case MCPChat.SessionManager.resume_session(session_id) do
      {:ok, session_info} ->
        Logger.info("Resumed session: #{session_info.name}")

      {:error, :not_found} ->
        IO.puts(:stderr, "Session not found: #{session_id}")
        System.halt(1)

      {:error, reason} ->
        handle_session_error("Failed to resume session", reason)
    end
  end

  defp start_new_session_with_opts(opts) do
    session_opts = build_session_opts(opts)
    MCPChat.SessionManager.start_new_session(session_opts)
  end

  defp build_session_opts(opts) do
    if opts[:backend] do
      [backend: opts[:backend]]
    else
      []
    end
  end

  defp handle_session_error(message, reason) do
    IO.puts(:stderr, "#{message}: #{inspect(reason)}")
    System.halt(1)
  end

  defp start_chat_interface() do
    profile_ui_setup()
    result = Chat.start()
    complete_ui_profiling()
    result
  end

  defp profile_ui_setup() do
    MCPChat.StartupProfiler.start_phase(:ui_setup)
  end

  defp complete_ui_profiling() do
    MCPChat.StartupProfiler.end_phase(:ui_setup)
    MCPChat.StartupProfiler.end_phase(:total)
    MCPChat.StartupProfiler.report()
  end

  defp list_sessions_and_exit() do
    # Start minimal application components needed for session listing
    {:ok, _} = Application.ensure_all_started(:mcp_chat)

    case MCPChat.Persistence.list_sessions() do
      {:ok, []} ->
        IO.puts("No saved sessions found.")

      {:ok, sessions} ->
        IO.puts("\n📂 Saved Sessions:\n")

        sessions
        |> Enum.with_index(1)
        |> Enum.each(fn {session, index} ->
          # Format session info
          name = Path.basename(session.filename, ".json")
          time_ago = format_relative_time(session.updated_at)
          message_count = session.message_count
          size_kb = Float.round(session.size / 1_024, 1)

          # Show session info
          IO.puts("  #{index}. #{name}")
          IO.puts("     📅 #{time_ago} | 💬 #{message_count} messages | 📦 #{size_kb} KB")
          IO.puts("")
        end)

        IO.puts("Use 'mcp_chat -r <session_name>' to resume a session")

      {:error, reason} ->
        IO.puts(:stderr, "Failed to list sessions: #{inspect(reason)}")
    end

    System.halt(0)
  end

  defp format_relative_time(datetime) do
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
        Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
    end
  end
end
