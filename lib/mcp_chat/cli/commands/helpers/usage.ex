defmodule MCPChat.CLI.Commands.Helpers.Usage do
  @moduledoc """
  Common usage and help display utilities for CLI commands.

  This module provides consistent help formatting and usage display patterns
  across all CLI command modules.
  """

  alias MCPChat.CLI.Renderer

  @doc """
  Shows standardized command help with description and subcommands.

  ## Examples

      iex> subcommands = [
      ...>   %{name: "list", description: "List all items"},
      ...>   %{name: "add", description: "Add a new item"}
      ...> ]
      iex> show_command_help("mycommand", "Manages items", subcommands)
  """
  def show_command_help(command, description, subcommands \\ []) do
    Renderer.show_info("""
    #{description}

    Usage: /#{command} <subcommand> [options]

    Available subcommands:
    #{format_subcommand_list(subcommands)}

    Use '/#{command} help' for more information.
    """)
  end

  @doc """
  Shows a usage error with the correct usage string.

  ## Examples

      iex> show_usage_error("mycommand <arg1> [arg2]")
  """
  def show_usage_error(usage_string) do
    Renderer.show_error("Usage: #{usage_string}")
  end

  @doc """
  Shows a list of subcommands in a formatted table.

  ## Examples

      iex> subcommands = [
      ...>   %{name: "list", description: "List items"},
      ...>   %{name: "add", description: "Add item", usage: "add <name> [options]"}
      ...> ]
      iex> show_subcommand_list(subcommands)
  """
  def show_subcommand_list(subcommands) when is_list(subcommands) do
    if Enum.empty?(subcommands) do
      Renderer.show_info("No subcommands available.")
    else
      display_subcommands(subcommands)
    end
  end

  defp display_subcommands(subcommands) do
    max_name_width = calculate_max_name_width(subcommands)
    Enum.each(subcommands, &display_single_subcommand(&1, max_name_width))
  end

  defp calculate_max_name_width(subcommands) do
    subcommands
    |> Enum.map(fn sub -> String.length(sub.name) end)
    |> Enum.max()
    |> max(10)
  end

  defp display_single_subcommand(subcommand, max_name_width) do
    name = String.pad_trailing(subcommand.name, max_name_width)
    description = Map.get(subcommand, :description, "")

    IO.puts("  #{name} - #{description}")

    if usage = Map.get(subcommand, :usage) do
      IO.puts("#{String.duplicate(" ", max_name_width + 4)}Usage: #{usage}")
    end
  end

  @doc """
  Formats a single usage line for a command.

  ## Examples

      iex> format_usage_line("list", "List all available items")
      "  list        - List all available items"
  """
  def format_usage_line(command, description, width \\ 15) do
    padded_command = String.pad_trailing(command, width)
    "  #{padded_command} - #{description}"
  end

  @doc """
  Shows standardized help for command flags and options.

  ## Examples

      iex> flags = [
      ...>   %{name: "--verbose", description: "Enable verbose output", type: :boolean},
      ...>   %{name: "--count", description: "Number of items", type: :integer, default: 10}
      ...> ]
      iex> show_flag_help(flags)
  """
  def show_flag_help(flags) when is_list(flags) do
    if Enum.empty?(flags) do
      :ok
    else
      display_flag_help(flags)
    end
  end

  defp display_flag_help(flags) do
    Renderer.show_info("Options:")
    max_flag_width = calculate_max_flag_width(flags)
    Enum.each(flags, &display_single_flag(&1, max_flag_width))
  end

  defp calculate_max_flag_width(flags) do
    flags
    |> Enum.map(fn flag -> String.length(flag.name) end)
    |> Enum.max()
    |> max(15)
  end

  defp display_single_flag(flag, max_flag_width) do
    name = String.pad_trailing(flag.name, max_flag_width)
    description = Map.get(flag, :description, "")

    line = "  #{name} #{description}"
    line = add_flag_type(line, flag)
    line = add_flag_default(line, flag)

    IO.puts(line)
  end

  defp add_flag_type(line, flag) do
    case Map.get(flag, :type) do
      :boolean -> line
      type -> "#{line} (#{type})"
    end
  end

  defp add_flag_default(line, flag) do
    case Map.get(flag, :default) do
      nil -> line
      default -> "#{line} [default: #{default}]"
    end
  end

  @doc """
  Shows examples for command usage.

  ## Examples

      iex> examples = [
      ...>   "mycommand list",
      ...>   "mycommand add item1 --verbose",
      ...>   "mycommand delete item1 item2"
      ...> ]
      iex> show_examples(examples)
  """
  def show_examples(examples) when is_list(examples) do
    if Enum.empty?(examples) do
      :ok
    else
      Renderer.show_info("Examples:")

      Enum.each(examples, fn example ->
        IO.puts("  /#{example}")
      end)
    end
  end

  @doc """
  Shows comprehensive help including description, usage, subcommands, flags, and examples.

  ## Examples

      iex> help_config = %{
      ...>   command: "mycommand",
      ...>   description: "Manages items in the system",
      ...>   usage: "mycommand <subcommand> [options]",
      ...>   subcommands: [...],
      ...>   flags: [...],
      ...>   examples: [...]
      ...> }
      iex> show_comprehensive_help(help_config)
  """
  def show_comprehensive_help(help_config) when is_map(help_config) do
    command = Map.get(help_config, :command, "command")
    description = Map.get(help_config, :description, "No description available")
    usage = Map.get(help_config, :usage, "#{command} [options]")

    # Main description and usage
    Renderer.show_info("""
    #{description}

    Usage: /#{usage}
    """)

    # Subcommands
    if subcommands = Map.get(help_config, :subcommands) do
      IO.puts("\nSubcommands:")
      show_subcommand_list(subcommands)
    end

    # Flags/Options
    if flags = Map.get(help_config, :flags) do
      IO.puts("")
      show_flag_help(flags)
    end

    # Examples
    if examples = Map.get(help_config, :examples) do
      IO.puts("")
      show_examples(examples)
    end

    # Additional notes
    if notes = Map.get(help_config, :notes) do
      IO.puts("")
      Renderer.show_info("Notes:")
      Renderer.show_info(notes)
    end
  end

  @doc """
  Shows a "command not found" error with suggestions.

  ## Examples

      iex> show_command_not_found("lst", ["list", "last", "lost"])
      # Shows error with suggestions
  """
  def show_command_not_found(attempted_command, available_commands \\ []) do
    message = "Unknown subcommand: '#{attempted_command}'"

    # Try to find similar commands using simple string similarity
    suggestions = find_similar_commands(attempted_command, available_commands)

    if Enum.empty?(suggestions) do
      Renderer.show_error("#{message}")
    else
      suggestion_text =
        suggestions
        |> Enum.take(3)
        |> Enum.join(", ")

      Renderer.show_error("#{message}")
      Renderer.show_info("Did you mean: #{suggestion_text}?")
    end

    if not Enum.empty?(available_commands) do
      IO.puts("")
      Renderer.show_info("Available commands: #{Enum.join(available_commands, ", ")}")
    end
  end

  @doc """
  Shows a generic "invalid argument" error with context.
  """
  def show_invalid_argument(argument, context \\ nil) do
    message = "Invalid argument: '#{argument}'"

    if context do
      Renderer.show_error("#{message} (#{context})")
    else
      Renderer.show_error(message)
    end
  end

  @doc """
  Shows a standardized "operation successful" message.
  """
  def show_operation_success(operation, details \\ nil) do
    message = "#{operation} completed successfully"

    if details do
      Renderer.show_success("#{message}: #{details}")
    else
      Renderer.show_success(message)
    end
  end

  @doc """
  Shows a standardized "operation failed" message.
  """
  def show_operation_failure(operation, reason) do
    Renderer.show_error("#{operation} failed: #{reason}")
  end

  # Private helper functions

  defp format_subcommand_list(subcommands) do
    max_width =
      subcommands
      |> Enum.map(fn sub -> String.length(sub.name) end)
      |> Enum.max(fn -> 10 end)
      |> max(12)

    Enum.map_join(subcommands, "\n", fn subcommand ->
      name = String.pad_trailing(subcommand.name, max_width)
      description = Map.get(subcommand, :description, "")
      "  #{name} - #{description}"
    end)
  end

  defp find_similar_commands(target, available_commands) do
    available_commands
    |> Enum.map(fn cmd -> {cmd, string_similarity(target, cmd)} end)
    |> Enum.filter(fn {_cmd, similarity} -> similarity > 0.4 end)
    |> Enum.sort_by(fn {_cmd, similarity} -> -similarity end)
    |> Enum.map(fn {cmd, _similarity} -> cmd end)
  end

  # Simple string similarity using Levenshtein-like algorithm
  defp string_similarity(s1, s2) do
    len1 = String.length(s1)
    len2 = String.length(s2)
    max_len = max(len1, len2)

    if max_len == 0 do
      1.0
    else
      distance = levenshtein_distance(s1, s2)
      (max_len - distance) / max_len
    end
  end

  defp levenshtein_distance(s1, s2) do
    s1_chars = String.graphemes(s1)
    s2_chars = String.graphemes(s2)

    do_levenshtein(s1_chars, s2_chars, length(s1_chars), length(s2_chars), %{})
  end

  defp do_levenshtein(s1, s2, i, j, cache) do
    key = {i, j}

    case Map.get(cache, key) do
      nil ->
        result = calculate_levenshtein(s1, s2, i, j, cache)
        {result, Map.put(cache, key, result)}

      cached_result ->
        {cached_result, cache}
    end
    |> elem(0)
  end

  defp calculate_levenshtein(_s1, _s2, 0, j, _cache), do: j
  defp calculate_levenshtein(_s1, _s2, i, 0, _cache), do: i

  defp calculate_levenshtein(s1, s2, i, j, cache) do
    char1 = Enum.at(s1, i - 1)
    char2 = Enum.at(s2, j - 1)

    if char1 == char2 do
      do_levenshtein(s1, s2, i - 1, j - 1, cache)
    else
      deletion = do_levenshtein(s1, s2, i - 1, j, cache)
      insertion = do_levenshtein(s1, s2, i, j - 1, cache)
      substitution = do_levenshtein(s1, s2, i - 1, j - 1, cache)

      1 + min(deletion, min(insertion, substitution))
    end
  end
end
