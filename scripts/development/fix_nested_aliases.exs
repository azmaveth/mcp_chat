#!/usr/bin/env elixir

# Script to fix nested module aliasing issues detected by Credo

defmodule NestedAliasFixer do
  @moduledoc """
  Fixes nested module aliasing issues by adding aliases at the top of modules
  for frequently used nested modules.
  """

  def fix_file(file_path) do
    content = File.read!(file_path)
    
    # Find modules that appear multiple times and could be aliased
    nested_modules = find_nested_module_usage(content)
    
    # Only add aliases for modules used 2+ times
    modules_to_alias = 
      nested_modules
      |> Enum.filter(fn {_module, count} -> count >= 2 end)
      |> Enum.map(fn {module, _count} -> module end)
      |> Enum.sort()
    
    if length(modules_to_alias) > 0 do
      fixed_content = add_aliases_and_replace_usage(content, modules_to_alias)
      
      if content != fixed_content do
        File.write!(file_path, fixed_content)
        IO.puts("Fixed: #{file_path} (added #{length(modules_to_alias)} aliases)")
      end
    end
  end
  
  defp find_nested_module_usage(content) do
    # Pattern to match nested module calls like MCPChat.Session.Autosave.something
    pattern = ~r/\b(MCPChat\.[A-Z][A-Za-z0-9]*(?:\.[A-Z][A-Za-z0-9]*)+)\./
    
    Regex.scan(pattern, content, capture: :all_but_first)
    |> List.flatten()
    |> Enum.frequencies()
    |> Enum.filter(fn {module, _count} ->
      # Only consider modules with at least 2 segments after MCPChat
      String.split(module, ".") |> length() >= 3
    end)
  end
  
  defp add_aliases_and_replace_usage(content, modules_to_alias) do
    lines = String.split(content, "\n")
    
    # Find where to insert aliases (after existing aliases/imports/requires)
    insert_index = find_alias_insertion_point(lines)
    
    # Generate alias lines
    alias_lines = generate_alias_lines(modules_to_alias)
    
    # Insert aliases
    content_with_aliases = insert_aliases(lines, insert_index, alias_lines)
    
    # Replace usage throughout the file
    updated_content = replace_module_usage(content_with_aliases, modules_to_alias)
    
    updated_content
  end
  
  defp find_alias_insertion_point(lines) do
    # Find the last line that contains alias, import, require, or use
    last_directive_index = 
      lines
      |> Enum.with_index()
      |> Enum.reverse()
      |> Enum.find_value(fn {line, index} ->
        trimmed = String.trim(line)
        if String.starts_with?(trimmed, "alias ") or 
           String.starts_with?(trimmed, "import ") or
           String.starts_with?(trimmed, "require ") or
           String.starts_with?(trimmed, "use ") do
          index
        end
      end)
    
    case last_directive_index do
      nil ->
        # Find after moduledoc or module declaration
        lines
        |> Enum.with_index()
        |> Enum.find_value(fn {line, index} ->
          if String.contains?(line, "defmodule ") or 
             String.contains?(line, "@moduledoc") do
            index + 1
          end
        end) || 0
      index -> index + 1
    end
  end
  
  defp generate_alias_lines(modules_to_alias) do
    modules_to_alias
    |> Enum.map(fn module ->
      short_name = module |> String.split(".") |> List.last()
      "  alias #{module}, as: #{short_name}"
    end)
  end
  
  defp insert_aliases(lines, insert_index, alias_lines) do
    before = Enum.take(lines, insert_index)
    after_lines = Enum.drop(lines, insert_index)
    
    # Add empty line before and after aliases if not already present
    prefix = if insert_index > 0 and Enum.at(lines, insert_index - 1) != "", do: [""], else: []
    suffix = if length(after_lines) > 0 and hd(after_lines) != "", do: [""], else: []
    
    (before ++ prefix ++ alias_lines ++ suffix ++ after_lines)
    |> Enum.join("\n")
  end
  
  defp replace_module_usage(content, modules_to_alias) do
    modules_to_alias
    |> Enum.reduce(content, fn module, acc ->
      short_name = module |> String.split(".") |> List.last()
      
      # Replace full module names with short aliases
      # Be careful to only replace when followed by a dot (method call)
      String.replace(acc, ~r/\b#{Regex.escape(module)}\./, "#{short_name}.")
    end)
  end
end

# Get files with nested module issues from Credo
IO.puts("Finding files with nested module aliasing issues...")

{output, _exit_code} = System.cmd("mix", ["credo", "--strict"], stderr_to_stdout: true)

nested_module_files = 
  output
  |> String.split("\n")
  |> Enum.filter(&String.contains?(&1, "Nested modules could be aliased"))
  |> Enum.map(fn line ->
    # Extract file path from Credo output
    case Regex.run(~r/\s+([^:]+\.exs?):/, line) do
      [_, file] -> file
      _ -> nil
    end
  end)
  |> Enum.reject(&is_nil/1)
  |> Enum.uniq()

if length(nested_module_files) == 0 do
  IO.puts("No nested module aliasing issues found!")
else
  IO.puts("Found #{length(nested_module_files)} files with nested module issues")
  IO.puts("Fixing nested module aliasing issues...\n")
  
  Enum.each(nested_module_files, fn file ->
    if File.exists?(file) do
      NestedAliasFixer.fix_file(file)
    else
      IO.puts("File not found: #{file}")
    end
  end)
  
  IO.puts("\nDone!")
end