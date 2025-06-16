defmodule MCPChat.CLI.Commands.Context do
  @moduledoc """
  Context management CLI commands.

  Handles commands for managing conversation context including:
  - Context statistics
  - System prompt configuration
  - Token limits
  - Truncation strategies
  """

  use MCPChat.CLI.Commands.Base

  alias MCPChat.CLI.Renderer
  alias MCPChat.Context.AsyncFileLoader
  alias MCPChat.{Context, Session}

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
    Usage.show_command_not_found(subcmd, available_commands)
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
        with_session(fn session ->
          case Enum.find(session.messages, &(&1["role"] == "system")) do
            nil ->
              show_info("No system prompt set")

            %{"content" => content} ->
              show_info("Current system prompt:")
              IO.puts(content)
          end
        end)

      _ ->
        prompt = parse_args(args)
        Session.set_system_prompt(prompt)

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
        Session.update_session(%{context: %{max_tokens: tokens}})
        show_success("Max tokens set to: #{tokens}")

        # Show updated context stats
        session = Session.get_current_session()
        stats = Context.get_context_stats(session.messages, tokens)

        if stats.estimated_tokens > tokens do
          show_warning(
            "Current context (#{stats.estimated_tokens} tokens) exceeds new limit. " <>
              "Messages will be truncated on next request."
          )
        end

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
        session = Session.get_current_session()
        current = session.context[:truncation_strategy] || "sliding_window"

        show_info("Current strategy: #{current}")
        show_info("Available strategies: #{Enum.join(strategies, ", ")}")
        :ok

      [strategy | _] ->
        set_truncation_strategy_value(strategy, strategies)
    end
  end

  defp set_truncation_strategy_value(strategy, strategies) do
    if strategy in strategies do
      Session.update_session(%{context: %{truncation_strategy: strategy}})
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
    # Get current session
    session = Session.get_current_session()

    # Get or initialize context files map
    context_files = session.context[:files] || %{}

    # Add file to context with metadata
    file_name = Path.basename(file_path)

    file_info = %{
      path: file_path,
      name: file_name,
      content: content,
      size: byte_size(content),
      added_at: DateTime.utc_now()
    }

    # Update context files
    updated_files = Map.put(context_files, file_name, file_info)
    updated_context = Map.put(session.context, :files, updated_files)

    # Update session
    Session.update_session(%{context: updated_context})

    show_success("Added #{file_name} to context (#{format_bytes(file_info.size)})")
  end

  defp remove_file_from_context(args) do
    case args do
      [] ->
        show_error("Usage: /context rm <file_name>")

      [file_name | _] ->
        session = Session.get_current_session()
        context_files = session.context[:files] || %{}

        if Map.has_key?(context_files, file_name) do
          updated_files = Map.delete(context_files, file_name)
          updated_context = Map.put(session.context, :files, updated_files)
          Session.update_session(%{context: updated_context})
          show_success("Removed #{file_name} from context")
        else
          show_error("File not found in context: #{file_name}")
          list_context_files()
        end
    end
  end

  defp list_context_files do
    session = Session.get_current_session()
    context_files = session.context[:files] || %{}

    if map_size(context_files) == 0 do
      show_info("No files in context")
    else
      show_info("Files in context:")

      context_files
      |> Enum.sort_by(fn {_, file_info} -> file_info.added_at end)
      |> Enum.each(fn {_name, file_info} ->
        time_ago = format_time_ago(file_info.added_at)
        IO.puts("  • #{file_info.name} (#{format_bytes(file_info.size)}, added #{time_ago})")
        IO.puts("    #{file_info.path}")
      end)

      # Show total size
      total_size =
        context_files
        |> Enum.map(fn {_, file_info} -> file_info.size end)
        |> Enum.sum()

      IO.puts("\nTotal: #{map_size(context_files)} files, #{format_bytes(total_size)}")
    end
  end

  defp clear_context_files do
    session = Session.get_current_session()
    context_files = session.context[:files] || %{}

    if map_size(context_files) == 0 do
      show_info("No files to clear")
    else
      count = map_size(context_files)
      updated_context = Map.put(session.context, :files, %{})
      Session.update_session(%{context: updated_context})
      show_success("Cleared #{count} files from context")
    end
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

  # Helper functions - Note: format_bytes and format_time_ago now come from Display helper
end
