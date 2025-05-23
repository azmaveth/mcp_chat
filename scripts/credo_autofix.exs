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
    Path.wildcard("lib/**/*.{ex,exs}") ++
    Path.wildcard("test/**/*.{ex,exs}") ++
    Path.wildcard("config/**/*.{ex,exs}")
  end
  
  defp apply_fixes(content, file) do
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
    # Replace numbers > 9999 with underscored versions
    Regex.replace(~r/\b(\d{1,3})(\d{3})\b/, content, fn _, thousands, hundreds ->
      "#{thousands}_#{hundreds}"
    end)
    |> then(fn content ->
      # Handle 6-digit numbers
      Regex.replace(~r/\b(\d{1,3})(\d{3})(\d{3})\b/, content, fn _, millions, thousands, hundreds ->
        "#{millions}_#{thousands}_#{hundreds}"
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