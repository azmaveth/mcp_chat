defmodule MCPChat.CLI.Helpers do
  @moduledoc """
  Common utilities for CLI commands.

  This module provides shared functions for argument parsing, display formatting,
  session management, and usage help across the CLI interface.
  """

  # Import all the functions from the individual helper modules
  # This consolidates the scattered helper functionality

  # From Arguments helper
  @doc """
  Parses the first argument as a subcommand, with an optional default.

  ## Examples

      iex> parse_subcommand(["list", "arg1", "arg2"])
      {"list", ["arg1", "arg2"]}

      iex> parse_subcommand([], "help")
      {"help", []}
  """
  def parse_subcommand(args, default \\ nil)
  def parse_subcommand([], default), do: {default, []}
  def parse_subcommand([subcommand | rest], _default), do: {subcommand, rest}

  @doc """
  Validates that required arguments are present.
  """
  def validate_required_args(args, required_count) do
    if length(args) >= required_count do
      :ok
    else
      {:error, "Missing required arguments"}
    end
  end

  # From Display helper
  @doc """
  Formats a DateTime as a human-readable "time ago" string.

  ## Examples

      iex> now = DateTime.utc_now()
      iex> past = DateTime.add(now, -3_600, :second)
      iex> format_time_ago(past)
      "1 hour ago"
  """
  def format_time_ago(%DateTime{} = datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 60 ->
        "#{diff_seconds} seconds ago"

      diff_seconds < 3600 ->
        minutes = div(diff_seconds, 60)
        "#{minutes} minute#{if minutes == 1, do: "", else: "s"} ago"

      diff_seconds < 86_400 ->
        hours = div(diff_seconds, 3600)
        "#{hours} hour#{if hours == 1, do: "", else: "s"} ago"

      true ->
        days = div(diff_seconds, 86_400)
        "#{days} day#{if days == 1, do: "", else: "s"} ago"
    end
  end

  @doc """
  Formats file size in human-readable format.
  """
  def format_file_size(bytes) when is_integer(bytes) do
    cond do
      bytes < 1024 -> "#{bytes} B"
      bytes < 1_048_576 -> "#{Float.round(bytes / 1024, 1)} KB"
      bytes < 1_073_741_824 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      true -> "#{Float.round(bytes / 1_073_741_824, 1)} GB"
    end
  end

  # From Session helper
  @doc """
  Gets session property with fallback to default.
  """
  def get_session_property(property, default \\ nil) do
    # Implementation depends on current session architecture
    # For now, return default or a mock value for testing
    case property do
      :backend -> :anthropic
      _ -> default
    end
  end

  @doc """
  Validates session exists and is active.
  """
  def validate_session(session_id) when is_binary(session_id) do
    # Basic validation - in practice this would check with session manager
    if String.length(session_id) > 0 do
      :ok
    else
      {:error, "Invalid session ID"}
    end
  end

  # From Usage helper
  @doc """
  Shows standardized command usage information.
  """
  def show_usage(command, description, usage_text) do
    IO.puts("#{command} - #{description}")
    IO.puts("")
    IO.puts("Usage:")
    IO.puts("  #{usage_text}")
    IO.puts("")
  end

  @doc """
  Shows standardized help for available subcommands.
  """
  def show_subcommands(subcommands) when is_list(subcommands) do
    IO.puts("Available subcommands:")
    IO.puts("")

    Enum.each(subcommands, fn {name, description} ->
      IO.puts("  #{String.pad_trailing(name, 20)} #{description}")
    end)

    IO.puts("")
  end

  # Additional helper functions needed by CLI commands

  @doc """
  Formats a number with thousands separators.
  """
  def format_number(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  def format_number(number, :percentage) when is_number(number) do
    "#{Float.round(number * 100, 1)}%"
  end

  def format_number(number, :currency) when is_number(number) do
    "$#{Float.round(number, 4)}"
  end

  def format_number(number, :compact) when is_number(number) do
    cond do
      number >= 1_000_000 -> "#{Float.round(number / 1_000_000, 1)}M"
      number >= 1_000 -> "#{Float.round(number / 1_000, 1)}K"
      true -> Integer.to_string(round(number))
    end
  end

  @doc """
  Formats bytes in human-readable format.
  """
  def format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes < 1024 -> "#{bytes} B"
      bytes < 1_048_576 -> "#{Float.round(bytes / 1024, 1)} KB"
      bytes < 1_073_741_824 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      true -> "#{Float.round(bytes / 1_073_741_824, 1)} GB"
    end
  end

  @doc """
  Shows key-value pairs in a formatted table.
  """
  def show_key_value_table(title, pairs) do
    IO.puts(title)
    IO.puts("")

    Enum.each(pairs, fn {key, value} ->
      IO.puts("  #{String.pad_trailing(key, 20)} #{value}")
    end)

    IO.puts("")
  end

  @doc """
  Executes code with a session context.
  """
  def with_session(fun) when is_function(fun, 1) do
    # Placeholder implementation - would need to be adapted to actual session system
    fun.(%{})
  end

  @doc """
  Gets session context value.
  """
  def get_session_context(_key, default \\ nil) do
    # Placeholder implementation - would need to be adapted to actual session system
    default
  end

  @doc """
  Updates session context.
  """
  def update_session(updates) when is_map(updates) do
    # Placeholder implementation - would need to be adapted to actual session system
    {:ok, updates}
  end

  @doc """
  Shows operation success message.
  """
  def show_operation_success(operation, details \\ nil) do
    message = if details, do: "✅ #{operation} #{details}", else: "✅ #{operation}"
    IO.puts(message)
  end

  @doc """
  Shows operation failure message.
  """
  def show_operation_failure(operation, error) do
    IO.puts("❌ #{operation} failed: #{error}")
  end

  @doc """
  Shows command help.
  """
  def show_command_help(command, description, usage) do
    show_usage(command, description, usage)
  end

  @doc """
  Shows usage error.
  """
  def show_usage_error(message) do
    IO.puts("Error: #{message}")
  end
end
