#!/usr/bin/env elixir

# This script auto-fixes some common Credo issues
# Run with: elixir scripts/credo_autofix.exs

defmodule CredoAutofix do
  @moduledoc """
  Auto-fixes common Credo issues:
  - Trailing whitespace
  - Missing trailing blank lines
  - Large numbers without underscores
  - Enum.map |> Enum.join to Enum.map_join
  """

  def run do
    IO.puts("Running Credo auto-fixes...")
    
    files = get_elixir_files()
    
    Enum.each(files, fn file ->
      if File.exists?(file) do
        content = File.read!(file)
        fixed_content = apply_fixes(content, file)
        
        if content != fixed_content do
          File.write!(file, fixed_content)
          IO.puts("Fixed: #{file}")
        end
      end
    end)
    
    IO.puts("Auto-fix complete!")
  end
  
  defp get_elixir_files do
    files = Path.wildcard("lib/**/*.{ex,exs}") ++
    Path.wildcard("test/**/*.{ex,exs}") ++
    Path.wildcard("config/**/*.{ex,exs}")
    
    # Don't process backup files
    files |> Enum.reject(&String.contains?(&1, "_backup"))
  end
  
  defp apply_fixes(content, _file) do
    content
    |> fix_trailing_whitespace()
    |> fix_trailing_blank_line()
    |> fix_large_numbers()
    |> fix_map_join()
    |> fix_parens_on_zero_arity()
  end
  
  defp fix_trailing_whitespace(content) do
    content
    |> String.split("\n")
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.join("\n")
  end
  
  defp fix_trailing_blank_line(content) do
    if String.ends_with?(content, "\n") do
      content
    else
      content <> "\n"
    end
  end
  
  defp fix_large_numbers(content) do
    # Apply number formatting but preserve model names
    content
    |> fix_number_in_content()
  end
  
  defp fix_number_in_content(content) do
    # Patterns to preserve (model names, dates, and protocol versions)
    preserve_regex = ~r/(claude-[\w-]+-\d{8}|gpt-[\d.]+-\d+k|[\w-]+-\d{8}|\b\d{8}\b|\d{4}-\d{2}-\d{2})/
    
    # Split content by patterns to preserve
    parts = Regex.split(preserve_regex, content, include_captures: true)
    
    parts
    |> Enum.map(fn part ->
      # Check if this part should be preserved
      if Regex.match?(preserve_regex, part) do
        # Preserve model names, 8-digit dates, and protocol versions as-is
        part
      else
        # Apply number formatting to other parts
        fix_numbers_in_text(part)
      end
    end)
    |> Enum.join()
  end
  
  defp fix_numbers_in_text(text) do
    # Replace numbers > 9999 with underscored versions
    text
    |> then(fn text ->
      # Handle 7+ digit numbers
      Regex.replace(~r/\b(\d{1,3})(\d{3})(\d{3})(\d+)\b/, text, fn _full, millions, thousands, hundreds, rest ->
        "#{millions}_#{thousands}_#{hundreds}_#{rest}"
      end)
    end)
    |> then(fn text ->
      # Handle 6-digit numbers
      Regex.replace(~r/\b(\d{3})(\d{3})\b/, text, fn _, thousands, hundreds ->
        "#{thousands}_#{hundreds}"
      end)
    end)
    |> then(fn text ->
      # Handle 5-digit numbers
      Regex.replace(~r/\b(\d{2})(\d{3})\b/, text, fn _, tens, ones ->
        "#{tens}_#{ones}"
      end)
    end)
    |> then(fn text ->
      # Handle 4-digit numbers (but not years like 2024, 2025, etc.)
      Regex.replace(~r/\b(?!20[0-9]{2}\b)(\d)(\d{3})\b/, text, fn _, thousands, hundreds ->
        "#{thousands}_#{hundreds}"
      end)
    end)
  end
  
  defp fix_map_join(content) do
    # Replace Enum.map(...) |> Enum.join(...) with Enum.map_join(...)
    Regex.replace(
      ~r/Enum\.map\(([^)]+)\)\s*\|>\s*Enum\.join\(([^)]+)\)/,
      content,
      "Enum.map_join(\\1, \\2)"
    )
  end
  
  defp fix_parens_on_zero_arity(content) do
    # Add parentheses to zero-arity function definitions
    Regex.replace(
      ~r/(\s+def\s+\w+)\s+do/,
      content,
      "\\1() do"
    )
    |> then(fn content ->
      Regex.replace(
        ~r/(\s+defp\s+\w+)\s+do/,
        content,
        "\\1() do"
      )
    end)
  end
end

CredoAutofix.run()