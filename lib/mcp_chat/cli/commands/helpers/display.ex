defmodule MCPChat.CLI.Commands.Helpers.Display do
  @moduledoc """
  Common display and formatting utilities for CLI commands.

  This module extracts duplicated formatting functions from individual command modules
  to provide consistent display behavior across the CLI interface.
  """

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
    diff_seconds = DateTime.diff(now, datetime)

    cond do
      diff_seconds < 60 ->
        "#{diff_seconds} second#{plural(diff_seconds)} ago"

      diff_seconds < 3_600 ->
        minutes = div(diff_seconds, 60)
        "#{minutes} minute#{plural(minutes)} ago"

      diff_seconds < 86_400 ->
        hours = div(diff_seconds, 3_600)
        "#{hours} hour#{plural(hours)} ago"

      diff_seconds < 2_592_000 ->
        days = div(diff_seconds, 86_400)
        "#{days} day#{plural(days)} ago"

      diff_seconds < 31_536_000 ->
        months = div(diff_seconds, 2_592_000)
        "#{months} month#{plural(months)} ago"

      true ->
        years = div(diff_seconds, 31_536_000)
        "#{years} year#{plural(years)} ago"
    end
  end

  def format_time_ago(nil), do: "Never"
  def format_time_ago(_), do: "Unknown"

  @doc """
  Formats a byte count as a human-readable size string.

  ## Examples

      iex> format_bytes(1_024)
      "1.0 KB"

      iex> format_bytes(1_048_576)
      "1.0 MB"
  """
  def format_bytes(bytes) when is_integer(bytes) and bytes >= 0 do
    cond do
      bytes < 1_024 ->
        "#{bytes} B"

      bytes < 1_048_576 ->
        "#{Float.round(bytes / 1_024, 1)} KB"

      bytes < 1_073_741_824 ->
        "#{Float.round(bytes / 1_048_576, 1)} MB"

      bytes < 1_099_511_627_776 ->
        "#{Float.round(bytes / 1_073_741_824, 1)} GB"

      true ->
        "#{Float.round(bytes / 1_099_511_627_776, 1)} TB"
    end
  end

  def format_bytes(nil), do: "0 B"
  def format_bytes(_), do: "Unknown"

  @doc """
  Formats a number with appropriate scale and unit suffixes.

  ## Examples

      iex> format_number(1_234)
      "1,234"

      iex> format_number(1_234_567, :compact)
      "1.2M"
  """
  def format_number(number, scale \\ :default)

  def format_number(number, :default) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.split("", trim: true)
    |> Enum.chunk_every(3)
    |> Enum.map_join(&Enum.join/1, ",")
    |> String.reverse()
  end

  def format_number(number, :compact) when is_integer(number) do
    cond do
      number < 1_000 ->
        Integer.to_string(number)

      number < 1_000_000 ->
        "#{Float.round(number / 1_000, 1)}K"

      number < 1_000_000_000 ->
        "#{Float.round(number / 1_000_000, 1)}M"

      number < 1_000_000_000_000 ->
        "#{Float.round(number / 1_000_000_000, 1)}B"

      true ->
        "#{Float.round(number / 1_000_000_000_000, 1)}T"
    end
  end

  def format_number(number, :percentage) when is_number(number) do
    "#{Float.round(number * 100, 1)}%"
  end

  def format_number(number, _scale) when is_float(number) do
    :erlang.float_to_binary(number, decimals: 2)
  end

  def format_number(nil, _scale), do: "0"
  def format_number(number, _scale), do: inspect(number)

  @doc """
  Formats a duration in seconds as a human-readable string.

  ## Examples

      iex> format_duration(3_661)
      "1h 1m 1s"

      iex> format_duration(90)
      "1m 30s"
  """
  def format_duration(seconds) when is_integer(seconds) and seconds >= 0 do
    hours = div(seconds, 3_600)
    minutes = div(rem(seconds, 3_600), 60)
    secs = rem(seconds, 60)

    parts = []
    parts = if hours > 0, do: ["#{hours}h" | parts], else: parts
    parts = if minutes > 0, do: ["#{minutes}m" | parts], else: parts
    parts = if secs > 0 or Enum.empty?(parts), do: ["#{secs}s" | parts], else: parts

    parts
    |> Enum.reverse()
    |> Enum.join(" ")
  end

  def format_duration(seconds) when is_float(seconds) do
    format_duration(round(seconds))
  end

  def format_duration(_), do: "0s"

  @doc """
  Displays a table with headers and rows.

  ## Options

  - `:separator` - Column separator string (default: " | ")
  - `:padding` - Padding around cells (default: 1)
  - `:max_width` - Maximum column width before truncation
  """
  def show_table(headers, rows, opts \\ []) do
    separator = Keyword.get(opts, :separator, " | ")
    padding = Keyword.get(opts, :padding, 1)
    max_width = Keyword.get(opts, :max_width, 50)

    # Calculate column widths
    all_rows = [headers | rows]
    col_count = length(headers)

    widths =
      for col_idx <- 0..(col_count - 1) do
        all_rows
        |> Enum.map(fn row ->
          row
          |> Enum.at(col_idx, "")
          |> to_string()
          |> String.length()
        end)
        |> Enum.max()
        |> min(max_width)
      end

    # Format and display rows
    format_table_row(headers, widths, separator, padding, max_width)

    # Header separator
    separator_row =
      Enum.map_join(widths, separator, &String.duplicate("-", &1 + 2 * padding))

    IO.puts(separator_row)

    # Data rows
    Enum.each(rows, fn row ->
      format_table_row(row, widths, separator, padding, max_width)
    end)
  end

  @doc """
  Shows a key-value table for displaying structured data.

  ## Options

  - `:key_width` - Width of the key column (default: auto-calculated)
  - `:separator` - Separator between key and value (default: ": ")
  """
  def show_key_value_table(data, opts \\ []) when is_map(data) or is_list(data) do
    separator = Keyword.get(opts, :separator, ": ")

    pairs = if is_map(data), do: Map.to_list(data), else: data

    key_width =
      case Keyword.get(opts, :key_width) do
        nil ->
          pairs
          |> Enum.map(fn {key, _} -> String.length(to_string(key)) end)
          |> Enum.max(fn -> 0 end)

        width ->
          width
      end

    Enum.each(pairs, fn {key, value} ->
      formatted_key =
        key
        |> to_string()
        |> String.pad_trailing(key_width)

      formatted_value = format_table_value(value)

      IO.puts("#{formatted_key}#{separator}#{formatted_value}")
    end)
  end

  @doc """
  Shows a numbered list of items.
  """
  def show_numbered_list(items) when is_list(items) do
    items
    |> Enum.with_index(1)
    |> Enum.each(fn {item, index} ->
      IO.puts("#{index}. #{item}")
    end)
  end

  @doc """
  Shows a bulleted list of items.

  ## Options

  - `:bullet` - Bullet character (default: "•")
  - `:indent` - Indentation spaces (default: 2)
  """
  def show_bulleted_list(items, opts \\ []) when is_list(items) do
    bullet = Keyword.get(opts, :bullet, "•")
    indent = Keyword.get(opts, :indent, 2)
    prefix = String.duplicate(" ", indent) <> bullet <> " "

    Enum.each(items, fn item ->
      IO.puts("#{prefix}#{item}")
    end)
  end

  @doc """
  Shows a progress bar for operations.

  ## Examples

      iex> show_progress_bar(7, 10)
      "[████████▒▒] 70%"
  """
  def show_progress_bar(current, total, width \\ 20) when is_integer(current) and is_integer(total) do
    percentage = if total > 0, do: current / total, else: 0
    filled = round(percentage * width)
    empty = width - filled

    filled_chars = String.duplicate("█", filled)
    empty_chars = String.duplicate("▒", empty)
    percent_text = "#{round(percentage * 100)}%"

    IO.write("\r[#{filled_chars}#{empty_chars}] #{percent_text}")

    if current >= total do
      IO.puts("")
    end
  end

  @doc """
  Shows a status message with an appropriate icon.

  ## Examples

      iex> show_status_with_icon(:success, "Operation completed")
      "✅ Operation completed"

      iex> show_status_with_icon(:error, "Something failed")
      "❌ Something failed"
  """
  def show_status_with_icon(status, message) do
    icon =
      case status do
        :success -> "✅"
        :error -> "❌"
        :warning -> "⚠️"
        :info -> "ℹ️"
        :pending -> "⏳"
        :running -> "🔄"
        _ -> "•"
      end

    IO.puts("#{icon} #{message}")
  end

  # Private helper functions

  defp plural(1), do: ""
  defp plural(_), do: "s"

  defp format_table_row(row, widths, separator, padding, max_width) do
    formatted_cells =
      row
      |> Enum.with_index()
      |> Enum.map(fn {cell, idx} ->
        width = Enum.at(widths, idx, 10)

        cell
        |> to_string()
        |> truncate_text(max_width)
        |> String.pad_trailing(width)
        |> pad_cell(padding)
      end)

    IO.puts(Enum.join(formatted_cells, separator))
  end

  defp format_table_value(value) when is_list(value) do
    case value do
      [] -> "[]"
      list when length(list) <= 3 -> inspect(list)
      list -> "[#{length(list)} items]"
    end
  end

  defp format_table_value(value) when is_map(value) do
    case Map.keys(value) do
      [] -> "{}"
      keys when length(keys) <= 2 -> inspect(value)
      keys -> "{#{length(keys)} keys}"
    end
  end

  defp format_table_value(value), do: to_string(value)

  defp truncate_text(text, max_width) when is_binary(text) do
    if String.length(text) > max_width do
      String.slice(text, 0, max_width - 3) <> "..."
    else
      text
    end
  end

  defp truncate_text(text, _max_width), do: to_string(text)

  defp pad_cell(text, padding) do
    pad = String.duplicate(" ", padding)
    "#{pad}#{text}#{pad}"
  end
end
