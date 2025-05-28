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

  alias MCPChat.{Session, Context}
  alias MCPChat.Context.AsyncFileLoader

  @impl true
  def commands() do
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
  def subcommands() do
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
    show_error("Unknown context subcommand: #{subcmd}")
    show_info("Type /context for available subcommands")
    :ok
  end

  # Command implementations

  defp show_context_stats() do
    session = Session.get_current_session()
    stats = Context.get_context_stats(session.messages, session.context[:max_tokens] || 4_096)

    MCPChat.CLI.Renderer.show_text("## Context Statistics\n")

    IO.puts("Messages: #{stats.message_count}")
    IO.puts("Estimated tokens: #{stats.estimated_tokens}")

    # Show context files info
    context_files = session.context[:files] || %{}

    if map_size(context_files) > 0 do
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

      IO.puts("Context files: #{file_count} (#{format_bytes(total_size)}, ~#{file_tokens} tokens)")
    end

    IO.puts("")

    IO.puts("Context window: #{stats.max_tokens} tokens")
    IO.puts("Available tokens: #{stats.tokens_remaining}")
    IO.puts("Usage: #{stats.tokens_used_percentage}%")
    IO.puts("")

    IO.puts("Truncation strategy: #{session.context[:truncation_strategy] || "sliding_window"}")

    if stats.tokens_used_percentage > 80 do
      show_warning(
        "Context is #{stats.tokens_used_percentage}% full. " <>
          "Older messages may be truncated soon."
      )
    end

    :ok
  end

  defp set_system_prompt(args) do
    case args do
      [] ->
        # Show current system prompt
        session = Session.get_current_session()

        case Enum.find(session.messages, &(&1["role"] == "system")) do
          nil ->
            show_info("No system prompt set")

          %{"content" => content} ->
            show_info("Current system prompt:")
            IO.puts(content)
        end

        :ok

      _ ->
        prompt = parse_args(args)
        Session.set_system_prompt(prompt)

        # Calculate token count
        tokens = Context.estimate_tokens(prompt)
        show_success("System prompt updated (#{tokens} tokens)")
        :ok
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
        if strategy in strategies do
          Session.update_session(%{context: %{truncation_strategy: strategy}})
          show_success("Truncation strategy set to: #{strategy}")

          case strategy do
            "sliding_window" ->
              show_info("Will keep most recent messages when truncating")

            "smart" ->
              show_info("Will preserve system prompt and important context when truncating")
          end

          :ok
        else
          show_error("Unknown strategy: #{strategy}")
          show_info("Available strategies: #{Enum.join(strategies, ", ")}")
          :ok
        end
    end
  end

  defp add_file_to_context(args) do
    case args do
      [] ->
        show_error("Usage: /context add <file_path>")

      [file_path | _] ->
        file_path = Path.expand(file_path)

        if File.exists?(file_path) do
          case File.read(file_path) do
            {:ok, content} ->
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

            {:error, reason} ->
              show_error("Failed to read file: #{inspect(reason)}")
          end
        else
          show_error("File not found: #{file_path}")
        end
    end
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

  defp list_context_files() do
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

  defp clear_context_files() do
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
        file_path = Path.expand(file_path)

        show_info("Loading #{file_path} asynchronously...")

        # Set up callbacks
        success_callback = fn result ->
          file_size = result.result.size
          duration = result.result.load_duration_ms
          show_success("Added #{result.result.name} to context (#{format_bytes(file_size)}) - loaded in #{duration}ms")
        end

        error_callback = fn error ->
          show_error("Failed to load file: #{inspect(error)}")
        end

        progress_callback = fn update ->
          case update.phase do
            :starting ->
              show_info("Starting async file load...")

            :completed ->
              if update.failed > 0 do
                show_warning("File load completed with #{update.failed} errors")
              end
          end
        end

        case AsyncFileLoader.add_to_context_async(file_path,
               success_callback: success_callback,
               error_callback: error_callback,
               progress_callback: progress_callback
             ) do
          {:ok, operation_id} ->
            show_info("Async load started (operation: #{String.slice(operation_id, -8, 8)})")

          {:error, reason} ->
            show_error("Failed to start async load: #{inspect(reason)}")
        end
    end

    :ok
  end

  defp add_batch_to_context_async(args) do
    case args do
      [] ->
        show_error("Usage: /context add-batch <file1> <file2> [file3] ...")

      file_paths ->
        expanded_paths = Enum.map(file_paths, &Path.expand/1)

        show_info("Loading #{length(expanded_paths)} files asynchronously...")

        # Set up callbacks
        batch_callback = fn %{successful: successful, failed: failed} ->
          if length(successful) > 0 do
            total_size =
              Enum.reduce(successful, 0, fn result, acc ->
                acc + result.result.size
              end)

            show_success("Added #{length(successful)} files to context (#{format_bytes(total_size)} total)")
          end

          if length(failed) > 0 do
            show_warning("Failed to load #{length(failed)} files:")

            Enum.each(failed, fn result ->
              show_error("  - #{result.file_path}: #{inspect(result.error)}")
            end)
          end
        end

        error_callback = fn error ->
          show_error("Batch load failed: #{inspect(error)}")
        end

        progress_callback = fn update ->
          case update.phase do
            :starting ->
              show_info("Starting batch load of #{update.total_files} files...")

            :completed ->
              show_info("Batch load completed: #{update.successful} successful, #{update.failed} failed")
          end
        end

        case AsyncFileLoader.add_batch_to_context_async(expanded_paths,
               batch_callback: batch_callback,
               error_callback: error_callback,
               progress_callback: progress_callback,
               max_concurrency: 3
             ) do
          {:ok, operation_id} ->
            show_info("Batch async load started (operation: #{String.slice(operation_id, -8, 8)})")

          {:error, reason} ->
            show_error("Failed to start batch load: #{inspect(reason)}")
        end
    end

    :ok
  end

  # Helper functions

  defp format_bytes(bytes) when bytes < 1_024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1_024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_time_ago(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3_600 -> "#{div(diff, 60)} minutes ago"
      diff < 86_400 -> "#{div(diff, 3_600)} hours ago"
      true -> "#{div(diff, 86_400)} days ago"
    end
  end
end
