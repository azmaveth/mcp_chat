defmodule MCPChat.CLI.Commands.Utility do
  @moduledoc """
  Utility CLI commands.

  Handles general utility commands including:
  - Help and documentation
  - Screen clearing
  - Configuration display
  - Cost tracking
  - Session export
  """

  use MCPChat.CLI.Commands.Base

  alias MCPChat.{Cost, Persistence, Session}

  @impl true
  def commands do
    %{
      "help" => "Show available commands",
      "clear" => "Clear the screen",
      "config" => "Show current configuration",
      "cost" => "Show session cost",
      "stats" => "Show session statistics",
      "export" => "Export conversation (usage: /export [format] [path])",
      "resume" => "Resume the last interrupted response"
    }
  end

  @impl true
  def handle_command("help", _args) do
    show_help()
  end

  def handle_command("clear", _args) do
    clear_screen()
  end

  def handle_command("config", _args) do
    show_config()
  end

  def handle_command("cost", _args) do
    show_cost()
  end

  def handle_command("stats", _args) do
    show_stats()
  end

  def handle_command("export", args) do
    export_conversation(args)
  end

  def handle_command("resume", args) do
    resume_interrupted_response(args)
  end

  def handle_command(cmd, _args) do
    {:error, "Unknown utility command: #{cmd}"}
  end

  # Command implementations

  defp show_help do
    # Collect commands from all modules
    all_commands = collect_all_commands()

    MCPChat.CLI.Renderer.show_text("## Available Commands\n")

    # Show table header
    IO.puts("Command          | Description")
    IO.puts("---------------- | -----------")

    # Sort and display all commands
    all_commands
    |> Enum.sort_by(fn {cmd, _desc} -> cmd end)
    |> Enum.each(fn {cmd, desc} ->
      IO.puts("/#{String.pad_trailing(cmd, 15)} | #{desc}")
    end)

    IO.puts("\nType /help <command> for detailed help on a specific command.")
    :ok
  end

  defp clear_screen do
    IO.write(IO.ANSI.clear())
    IO.write(IO.ANSI.cursor(0, 0))
    :ok
  end

  defp show_config do
    session = Session.get_current_session()

    MCPChat.CLI.Renderer.show_text("## Current Configuration\n")

    # Show configuration in table format
    IO.puts("Setting              | Value")
    IO.puts("-------------------- | -----")
    IO.puts("LLM Backend          | #{session.llm_backend || "Not set"}")
    IO.puts("Model                | #{session.context[:model] || "Not set"}")

    # Show MCP servers
    servers = MCPChat.MCP.ServerManager.list_servers()
    server_count = length(servers)
    IO.puts("MCP Servers          | #{server_count} connected")

    # Show context settings
    IO.puts("Max Tokens           | #{session.context[:max_tokens] || "4_096"}")
    IO.puts("Truncation Strategy  | #{session.context[:truncation_strategy] || "sliding_window"}")

    :ok
  end

  defp show_cost do
    session = Session.get_current_session()
    cost_info = Cost.calculate_session_cost(session, session.token_usage || %{input_tokens: 0, output_tokens: 0})

    MCPChat.CLI.Renderer.show_text("## Session Cost Summary\n")

    IO.puts("Backend: #{session.llm_backend || "Not set"}")
    IO.puts("Model: #{session.context[:model] || "Not set"}")
    IO.puts("")

    if Map.has_key?(cost_info, :error) do
      IO.puts(cost_info.error)
    else
      if Map.get(cost_info, :total_cost, 0) > 0 do
        IO.puts("Token Usage:")
        IO.puts("  Input tokens:  #{format_number(cost_info.input_tokens)}")
        IO.puts("  Output tokens: #{format_number(cost_info.output_tokens)}")
        IO.puts("  Total tokens:  #{format_number(cost_info.total_tokens)}")
        IO.puts("")

        IO.puts("Cost Breakdown:")
        IO.puts("  Input cost:  $#{format_cost(cost_info.input_cost)}")
        IO.puts("  Output cost: $#{format_cost(cost_info.output_cost)}")
        IO.puts("  Total cost:  $#{format_cost(cost_info.total_cost)}")
      else
        IO.puts("No token usage recorded yet.")
      end
    end

    :ok
  end

  defp show_stats do
    session = Session.get_current_session()

    IO.puts("## Session Statistics")
    IO.puts("")
    IO.puts("Session ID: #{session.id}")
    IO.puts("Messages: #{length(session.messages)}")
    IO.puts("Created: #{session.created_at}")

    show_token_usage(session)
    :ok
  end

  defp show_token_usage(session) do
    if session.token_usage do
      input_tokens = Map.get(session.token_usage, :input_tokens, 0)
      output_tokens = Map.get(session.token_usage, :output_tokens, 0)
      total_tokens = input_tokens + output_tokens

      if total_tokens > 0 do
        show_token_details(input_tokens, output_tokens, total_tokens)
        show_cost_estimate(session.llm_backend, input_tokens, output_tokens)
      end
    end
  end

  defp show_token_details(input_tokens, output_tokens, total_tokens) do
    IO.puts("Input tokens: #{input_tokens}")
    IO.puts("Output tokens: #{output_tokens}")
    IO.puts("Total tokens: #{total_tokens}")
  end

  defp show_cost_estimate(nil, _input_tokens, _output_tokens), do: :ok

  defp show_cost_estimate(backend, input_tokens, output_tokens) do
    cost = estimate_cost(backend, input_tokens, output_tokens)

    if cost > 0 do
      IO.puts("Estimated cost: $#{:erlang.float_to_binary(cost, decimals: 4)}")
    end
  end

  defp export_conversation(args) do
    format =
      case args do
        [] -> :markdown
        [f | _] -> String.to_atom(f)
      end

    session = Session.get_current_session()

    # Generate filename
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)

    extension =
      case format do
        :json -> "json"
        :text -> "txt"
        _ -> "md"
      end

    filename = "chat_export_#{timestamp}.#{extension}"

    case Persistence.export_session(session, format, filename) do
      {:ok, content} ->
        File.write!(filename, content)
        show_success("Conversation exported to: #{filename}")

      {:error, reason} ->
        show_error("Failed to export: #{reason}")
    end

    :ok
  end

  # Helper functions

  defp collect_all_commands do
    # Import commands from all command modules
    modules = [
      MCPChat.CLI.Commands.Session,
      MCPChat.CLI.Commands.Utility,
      MCPChat.CLI.Commands.LLM,
      MCPChat.CLI.Commands.MCP,
      MCPChat.CLI.Commands.Context,
      MCPChat.CLI.Commands.Alias
    ]

    # Merge all command maps
    modules
    |> Enum.filter(&Code.ensure_loaded?/1)
    |> Enum.flat_map(fn mod ->
      if function_exported?(mod, :commands, 0) do
        mod.commands() |> Map.to_list()
      else
        []
      end
    end)
    |> Map.new()
    |> Map.merge(%{
      "exit" => "Exit the application",
      "quit" => "Exit the application"
    })
  end

  defp format_number(n) when n >= 1_000_000 do
    "#{Float.round(n / 1_000_000, 2)}M"
  end

  defp format_number(n) when n >= 1_000 do
    "#{Float.round(n / 1_000, 1)}K"
  end

  defp format_number(n), do: "#{n}"

  defp format_cost(cost) when cost < 0.01, do: "#{Float.round(cost, 4)}"
  defp format_cost(cost), do: "#{Float.round(cost, 2)}"

  defp resume_interrupted_response(_args) do
    alias MCPChat.CLI.Renderer
    alias MCPChat.LLM.ExLLMAdapter

    case Session.get_last_recovery_id() do
      nil ->
        Renderer.show_error("No interrupted response to resume")

      recovery_id ->
        handle_recovery(recovery_id, ExLLMAdapter, Renderer)
    end
  end

  defp handle_recovery(recovery_id, adapter, renderer) do
    recoverable = adapter.list_recoverable_streams()

    case Enum.find(recoverable, &(&1.id == recovery_id)) do
      nil ->
        handle_recovery_not_found(recovery_id, renderer)

      stream_info ->
        handle_recovery_found(recovery_id, stream_info, adapter, renderer)
    end
  end

  defp handle_recovery_not_found(recovery_id, renderer) do
    renderer.show_error("Previous response is no longer recoverable")
    Session.clear_last_recovery_id()
  end

  defp handle_recovery_found(recovery_id, stream_info, adapter, renderer) do
    show_recovery_info(stream_info, renderer)

    case adapter.get_partial_response(recovery_id) do
      {:ok, chunks} ->
        show_partial_content(chunks, renderer)
        attempt_resume_stream(recovery_id, adapter, renderer)

      {:error, reason} ->
        renderer.show_error("Failed to get partial response: #{inspect(reason)}")
    end
  end

  defp show_recovery_info(stream_info, renderer) do
    renderer.show_info("Resuming interrupted response...")
    renderer.show_text("• Provider: #{stream_info.provider}")
    renderer.show_text("• Model: #{stream_info.model}")
    renderer.show_text("• Chunks received: #{stream_info.chunks_received}")
    renderer.show_text("• Tokens processed: #{stream_info.token_count}")
  end

  defp show_partial_content(chunks, renderer) do
    partial_content = Enum.map_join(chunks, "", & &1.content)

    if String.length(partial_content) > 0 do
      renderer.show_text("\n--- Partial response ---")
      renderer.show_text(partial_content)
      renderer.show_text("--- Continuing... ---\n")
    end
  end

  defp attempt_resume_stream(recovery_id, adapter, renderer) do
    case adapter.resume_stream(recovery_id) do
      {:ok, stream} ->
        renderer.show_success("Response resumed successfully")
        Session.clear_last_recovery_id()
        {:resume_stream, stream}

      {:error, reason} ->
        renderer.show_error("Failed to resume: #{inspect(reason)}")
    end
  end

  # Estimate cost based on token usage
  # These are approximate costs per 1M tokens (as of 2024)
  defp estimate_cost(backend, input_tokens, output_tokens) do
    case backend do
      "anthropic" ->
        # Claude 3 Opus pricing
        input_cost = input_tokens * 15.0 / 1_000_000
        output_cost = output_tokens * 75.0 / 1_000_000
        input_cost + output_cost

      "openai" ->
        # GPT-4 pricing
        input_cost = input_tokens * 30.0 / 1_000_000
        output_cost = output_tokens * 60.0 / 1_000_000
        input_cost + output_cost

      _ ->
        0.0
    end
  end
end
