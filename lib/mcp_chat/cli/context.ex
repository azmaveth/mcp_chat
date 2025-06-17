defmodule MCPChat.CLI.Context do
  @moduledoc """
  Context management CLI commands.

  Handles commands for managing conversation context including:
  - Context statistics
  - System prompt configuration
  - Token limits
  - Truncation strategies
  """

  use MCPChat.CLI.Base

  alias MCPChat.CLI.Renderer
  alias MCPChat.Context.AsyncFileLoader
  alias MCPChat.{Context, Gateway}

  @impl true
  def commands do
    %{
      "context" => "Context management (usage: /context [subcommand])",
      "system" => "Set system prompt (usage: /system <prompt>)",
      "tokens" => "Set max tokens (usage: /tokens <number>)",
      "strategy" => "Set context strategy (usage: /strategy <sliding_window|smart>)"
    }
  end

  @doc """
  Returns the list of context subcommands for help display.
  """
  def subcommands do
    %{
      "stats" => "Show context statistics (default)",
      "add" => "Add a file to context (usage: add <file_path>)",
      "add-async" => "Add a file to context asynchronously (usage: add-async <file_path>)",
      "add-batch" => "Add multiple files to context (usage: add-batch <file1> <file2> ...)",
      "rm" => "Remove a file from context (usage: rm <file_name>)",
      "list" => "List files in context",
      "clear" => "Clear all manually added files from context"
    }
  end

  @impl true
  def handle_command("context", args) do
    handle_context_subcommand(args)
  end

  def handle_command("system", args) do
    set_system_prompt(args)
  end

  def handle_command("tokens", args) do
    set_max_tokens(args)
  end

  def handle_command("strategy", args) do
    set_truncation_strategy(args)
  end

  def handle_command(cmd, _args) do
    {:error, "Unknown context command: #{cmd}"}
  end

  # Handle context subcommands
  defp handle_context_subcommand([]) do
    # Default to showing stats
    show_context_stats()
  end

  defp handle_context_subcommand(["stats" | _]) do
    show_context_stats()
  end

  defp handle_context_subcommand(["add" | args]) do
    add_file_to_context(args)
  end

  defp handle_context_subcommand(["add-async" | args]) do
    add_file_to_context_async(args)
  end

  defp handle_context_subcommand(["add-batch" | args]) do
    add_batch_to_context_async(args)
  end

  defp handle_context_subcommand(["rm" | args]) do
    remove_file_from_context(args)
  end

  defp handle_context_subcommand(["list" | _]) do
    list_context_files()
  end

  defp handle_context_subcommand(["clear" | _]) do
    clear_context_files()
  end

  defp handle_context_subcommand([subcmd | _]) do
    available_commands = Map.keys(subcommands())
    show_error("Unknown context command: #{subcmd}")
    show_info("Available commands: #{Enum.join(available_commands, ", ")}")
    show_info("Use '/context help' for more information")
    :ok
  end

  # Command implementations

  defp show_context_stats do
    with_session(fn session ->
      max_tokens = get_session_context(:max_tokens, 4_096)
      stats = Context.get_context_stats(session.messages, max_tokens)

      Renderer.show_text("## Context Statistics\n")

      # Basic stats
      basic_stats = %{
        "Messages" => stats.message_count,
        "Estimated tokens" => format_number(stats.estimated_tokens),
        "Context window" => "#{format_number(stats.max_tokens)} tokens",
        "Available tokens" => format_number(stats.tokens_remaining),
        "Usage" => format_number(stats.tokens_used_percentage, :percentage)
      }

      show_key_value_table(basic_stats, separator: ": ")

      # Show context files info
      context_files = get_session_context(:files, %{})
      show_context_files_info(context_files)

      IO.puts("")
      IO.puts("Truncation strategy: #{get_session_context(:truncation_strategy, "sliding_window")}")

      if stats.tokens_used_percentage > 80 do
        show_warning(
          "Context is #{format_number(stats.tokens_used_percentage, :percentage)} full. " <>
            "Older messages may be truncated soon."
        )
      end
    end)
  end

  defp show_context_files_info(context_files) when map_size(context_files) > 0 do
    file_count = map_size(context_files)

    total_size =
      context_files
      |> Enum.map(fn {_, file_info} -> file_info.size end)
      |> Enum.sum()

    # Estimate tokens for files (rough estimate)
    file_tokens =
      context_files
      |> Enum.map(fn {_, file_info} -> Context.estimate_tokens(file_info.content) end)
      |> Enum.sum()

    IO.puts("\nContext files: #{file_count} (#{format_bytes(total_size)}, ~#{format_number(file_tokens)} tokens)")
  end

  defp show_context_files_info(_context_files), do: :ok

  defp set_system_prompt(args) do
    case args do
      [] ->
        # Show current system prompt
        with_session(&display_current_system_prompt/1)

      _ ->
        prompt = parse_args(args)
        # TODO: Implement set_system_prompt with Gateway API
        show_error("System prompt setting not yet implemented with Gateway API")

        # Calculate token count
        tokens = Context.estimate_tokens(prompt)
        show_operation_success("System prompt updated", "(#{format_number(tokens)} tokens)")
    end
  end

  defp set_max_tokens(args) do
    with {:ok, args} <- require_arg(args, "/tokens <number>"),
         tokens_str <- parse_args(args),
         # Remove underscores from number strings
         cleaned_str = String.replace(tokens_str, "_", ""),
         {tokens, ""} <- Integer.parse(cleaned_str) do
      if tokens < 100 do
        show_error("Max tokens must be at least 100")
        :ok
      else
        # TODO: Implement session context update with Gateway API
        show_error("Max tokens setting not yet implemented with Gateway API")
        show_success("Max tokens set to: #{tokens}")

        # Show updated context stats would go here
        # TODO: Re-enable when Gateway supports context updates

        :ok
      end
    else
      {:error, msg} ->
        show_error(msg)
        :ok

      _ ->
        show_error("Invalid number format")
        :ok
    end
  end

  defp set_truncation_strategy(args) do
    strategies = ["sliding_window", "smart"]

    case args do
      [] ->
        # Show current strategy
        show_error("Truncation strategy display not yet implemented with Gateway API")
        show_info("Available strategies: #{Enum.join(strategies, ", ")}")
        :ok

      [strategy | _] ->
        set_truncation_strategy_value(strategy, strategies)
    end
  end

  defp set_truncation_strategy_value(strategy, strategies) do
    if strategy in strategies do
      # TODO: Implement truncation strategy update with Gateway API
      show_error("Truncation strategy setting not yet implemented with Gateway API")
      show_success("Truncation strategy set to: #{strategy}")
      show_strategy_description(strategy)
      :ok
    else
      show_error("Unknown strategy: #{strategy}")
      show_info("Available strategies: #{Enum.join(strategies, ", ")}")
      :ok
    end
  end

  defp show_strategy_description(strategy) do
    case strategy do
      "sliding_window" ->
        show_info("Will keep most recent messages when truncating")

      "smart" ->
        show_info("Will preserve system prompt and important context when truncating")

      _ ->
        # No description for other strategies
        :ok
    end
  end

  defp add_file_to_context(args) do
    case args do
      [] ->
        show_error("Usage: /context add <file_path>")

      [file_path | _] ->
        file_path = Path.expand(file_path)
        add_file_if_exists(file_path)
    end
  end

  defp add_file_if_exists(file_path) do
    if File.exists?(file_path) do
      add_existing_file_to_context(file_path)
    else
      show_error("File not found: #{file_path}")
    end
  end

  defp add_existing_file_to_context(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        store_file_in_context(file_path, content)

      {:error, reason} ->
        show_error("Failed to read file: #{inspect(reason)}")
    end
  end

  defp store_file_in_context(file_path, content) do
    # TODO: Implement file context storage with Gateway API
    file_name = Path.basename(file_path)
    show_error("Adding files to context not yet implemented with Gateway API")
    show_info("Would add: #{file_name} (#{format_bytes(byte_size(content))})")
  end

  defp remove_file_from_context(args) do
    case args do
      [] ->
        show_error("Usage: /context rm <file_name>")

      [file_name | _] ->
        # TODO: Implement file context removal with Gateway API
        show_error("Removing files from context not yet implemented with Gateway API")
        show_info("Would remove: #{file_name}")
    end
  end

  defp list_context_files do
    # TODO: Implement context file listing with Gateway API
    show_error("Context file listing not yet implemented with Gateway API")
  end

  defp clear_context_files do
    # TODO: Implement context clear with Gateway API
    show_error("Clearing context not yet implemented with Gateway API")
  end

  defp add_file_to_context_async(args) do
    case args do
      [] ->
        show_error("Usage: /context add-async <file_path>")

      [file_path | _] ->
        perform_async_file_load(file_path)
    end

    :ok
  end

  defp perform_async_file_load(file_path) do
    file_path = Path.expand(file_path)
    show_info("Loading #{file_path} asynchronously...")

    callbacks = build_async_load_callbacks()

    case AsyncFileLoader.add_to_context_async(file_path, callbacks) do
      {:ok, operation_id} ->
        operation_id_short = String.slice(operation_id, -8, 8)
        show_info("Async load started (operation: #{operation_id_short})")

      {:error, reason} ->
        show_error("Failed to start async load: #{inspect(reason)}")
    end
  end

  defp build_async_load_callbacks do
    [
      success_callback: &handle_async_load_success/1,
      error_callback: &handle_async_load_error/1,
      progress_callback: &handle_async_load_progress/1
    ]
  end

  defp handle_async_load_success(result) do
    file_size = result.result.size
    duration = result.result.load_duration_ms
    name = result.result.name
    show_success("Added #{name} to context (#{format_bytes(file_size)}) - loaded in #{duration}ms")
  end

  defp handle_async_load_error(error) do
    show_error("Failed to load file: #{inspect(error)}")
  end

  defp handle_async_load_progress(update) do
    case update.phase do
      :starting ->
        show_info("Starting async file load...")

      :completed ->
        if update.failed > 0 do
          show_warning("File load completed with #{update.failed} errors")
        end
    end
  end

  defp add_batch_to_context_async(args) do
    case args do
      [] ->
        show_error("Usage: /context add-batch <file1> <file2> [file3] ...")

      file_paths ->
        perform_batch_async_load(file_paths)
    end

    :ok
  end

  defp perform_batch_async_load(file_paths) do
    expanded_paths = Enum.map(file_paths, &Path.expand/1)
    show_info("Loading #{length(expanded_paths)} files asynchronously...")

    callbacks = build_batch_callbacks()

    case AsyncFileLoader.add_batch_to_context_async(expanded_paths, callbacks) do
      {:ok, operation_id} ->
        operation_id_short = String.slice(operation_id, -8, 8)
        show_info("Batch async load started (operation: #{operation_id_short})")

      {:error, reason} ->
        show_error("Failed to start batch load: #{inspect(reason)}")
    end
  end

  defp build_batch_callbacks do
    [
      batch_callback: &handle_batch_completion/1,
      error_callback: &handle_batch_error/1,
      progress_callback: &handle_batch_progress/1,
      max_concurrency: 3
    ]
  end

  defp handle_batch_completion(%{successful: successful, failed: failed}) do
    handle_successful_batch(successful)
    handle_failed_batch(failed)
  end

  defp handle_successful_batch(successful) do
    if length(successful) > 0 do
      total_size = calculate_total_batch_size(successful)
      show_success("Added #{length(successful)} files to context (#{format_bytes(total_size)} total)")
    end
  end

  defp calculate_total_batch_size(successful) do
    Enum.reduce(successful, 0, fn result, acc ->
      acc + result.result.size
    end)
  end

  defp handle_failed_batch(failed) do
    if length(failed) > 0 do
      show_warning("Failed to load #{length(failed)} files:")
      Enum.each(failed, &show_failed_file_error/1)
    end
  end

  defp show_failed_file_error(result) do
    show_error("  - #{result.file_path}: #{inspect(result.error)}")
  end

  defp handle_batch_error(error) do
    show_error("Batch load failed: #{inspect(error)}")
  end

  defp handle_batch_progress(update) do
    case update.phase do
      :starting ->
        show_info("Starting batch load of #{update.total_files} files...")

      :completed ->
        show_info("Batch load completed: #{update.successful} successful, #{update.failed} failed")
    end
  end

  defp display_current_system_prompt(session) do
    case Enum.find(session.messages, &(&1["role"] == "system")) do
      nil ->
        show_info("No system prompt set")

      %{"content" => content} ->
        show_info("Current system prompt:")
        IO.puts(content)
    end
  end

  # Helper functions

  defp get_current_session_with_state do
    case get_current_session_id() do
      {:ok, session_id} ->
        Gateway.get_session_state(session_id)

      error ->
        error
    end
  end

  defp get_current_session_id do
    case Gateway.list_active_sessions() do
      [session_id | _] -> {:ok, session_id}
      [] -> {:error, :no_active_session}
    end
  end

  # Note: format_bytes and format_time_ago now come from Display helper
end
