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

  @impl true
  def commands() do
    %{
      "context" => "Show context statistics",
      "system" => "Set system prompt (usage: /system <prompt>)",
      "tokens" => "Set max tokens (usage: /tokens <number>)",
      "strategy" => "Set context strategy (usage: /strategy <sliding_window|smart>)"
    }
  end

  @impl true
  def handle_command("context", _args) do
    show_context_stats()
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

  # Command implementations

  defp show_context_stats() do
    session = Session.get_current_session()
    stats = Context.get_context_stats(session.messages, session.context[:max_tokens] || 4_096)

    MCPChat.CLI.Renderer.show_text("## Context Statistics\n")

    IO.puts("Messages: #{stats.message_count}")
    IO.puts("Estimated tokens: #{stats.estimated_tokens}")
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

      _ ->
        prompt = parse_args(args)
        Session.set_system_prompt(prompt)

        # Calculate token count
        tokens = Context.estimate_tokens(prompt)
        show_success("System prompt updated (#{tokens} tokens)")
    end
  end

  defp set_max_tokens(args) do
    with {:ok, args} <- require_arg(args, "/tokens <number>"),
         tokens_str <- parse_args(args),
         {tokens, ""} <- Integer.parse(tokens_str) do
      if tokens < 100 do
        show_error("Max tokens must be at least 100")
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
      end
    else
      {:error, msg} ->
        show_error(msg)

      _ ->
        show_error("Invalid number format")
    end
  end

  defp set_truncation_strategy(args) do
    strategies = ["sliding_window", "smart"]

    case args do
      [] ->
        # Show current strategy
        session = Session.get_current_session()
        current = session.truncation_strategy || "sliding_window"

        show_info("Current strategy: #{current}")
        show_info("Available strategies: #{Enum.join(strategies, ", ")}")

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
        else
          show_error("Unknown strategy: #{strategy}")
          show_info("Available strategies: #{Enum.join(strategies, ", ")}")
        end
    end
  end
end
