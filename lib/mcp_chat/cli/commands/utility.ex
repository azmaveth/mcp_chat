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

  alias MCPChat.{Session, Config, Cost, Persistence}

  @impl true
  def commands() do
    %{
      "help" => "Show available commands",
      "clear" => "Clear the screen",
      "config" => "Show current configuration",
      "cost" => "Show session cost",
      "export" => "Export conversation (usage: /export [format] [path])"
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

  def handle_command("export", args) do
    export_conversation(args)
  end

  def handle_command(cmd, _args) do
    {:error, "Unknown utility command: #{cmd}"}
  end

  # Command implementations

  defp show_help() do
    # Collect commands from all modules
    all_commands = collect_all_commands()

    MCPChat.CLI.Renderer.show_text("## Available Commands\n")

    # Group commands by category
    categories = [
      {"Session Management", ~w[new save load sessions history]},
      {"LLM Configuration", ~w[backend model models loadmodel unloadmodel acceleration]},
      {"MCP Servers", ~w[servers discover connect disconnect saved]},
      {"MCP Tools & Resources", ~w[tools tool resources resource prompts prompt]},
      {"Context Management", ~w[context system tokens strategy]},
      {"Utilities", ~w[help clear config cost export alias]},
      {"Navigation", ~w[exit quit]}
    ]

    Enum.each(categories, fn {category, commands} ->
      IO.puts("\n#{category}:")

      commands
      |> Enum.filter(&Map.has_key?(all_commands, &1))
      |> Enum.each(fn cmd ->
        desc = Map.get(all_commands, cmd, "")
        IO.puts("  /#{String.pad_trailing(cmd, 12)} #{desc}")
      end)
    end)

    IO.puts("\nType /help <command> for detailed help on a specific command.")
    :ok
  end

  defp clear_screen() do
    IO.write(IO.ANSI.clear())
    IO.write(IO.ANSI.cursor(0, 0))
    :ok
  end

  defp show_config() do
    config = Config.get([:llm]) || %{}

    MCPChat.CLI.Renderer.show_text("## Current Configuration\n")

    # Format config as YAML-like output
    formatted = format_config(config, 0)
    IO.puts(formatted)

    :ok
  end

  defp show_cost() do
    session = Session.get_current_session()
    cost_info = Cost.calculate_session_cost(session, session.token_usage || %{input_tokens: 0, output_tokens: 0})

    MCPChat.CLI.Renderer.show_text("## Session Cost Summary\n")

    IO.puts("Backend: #{session.llm_backend || "Not set"}")
    IO.puts("Model: #{session.model || "Not set"}")
    IO.puts("")

    if Map.has_key?(cost_info, :error) do
      IO.puts(cost_info.error)
    elsif Map.get(cost_info, :total_cost, 0) > 0 do
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

    :ok
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

  defp collect_all_commands() do
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

  defp format_config(config, indent) when is_map(config) do
    config
    |> Enum.map(fn {key, value} ->
      spaces = String.duplicate("  ", indent)

      if is_map(value) do
        "#{spaces}#{key}:\n#{format_config(value, indent + 1)}"
      else
        "#{spaces}#{key}: #{inspect(value)}"
      end
    end)
    |> Enum.join("\n")
  end

  defp format_config(config, _indent) do
    inspect(config)
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
end
