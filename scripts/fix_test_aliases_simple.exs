#!/usr/bin/env elixir

# Script to fix nested module aliasing in test files

defmodule TestAliasFixer do
  @moduledoc """
  Fixes nested module aliasing issues in test files
  """

  def run do
    # Get list of test files with nested module issues
    {output, _} = System.cmd("mix", ["credo", "--strict", "--format", "oneline"], stderr_to_stdout: true)
    
    issues = 
      output
      |> String.split("\n")
      |> Enum.filter(&String.contains?(&1, "[D] ↘"))
      |> Enum.filter(&String.contains?(&1, "Nested modules could be aliased"))
      |> Enum.filter(&String.contains?(&1, "test/"))
      |> Enum.map(&parse_issue/1)
      |> Enum.reject(&is_nil/1)
    
    IO.puts("Found #{length(issues)} nested module aliasing issues")
    
    # Group by file
    issues_by_file = Enum.group_by(issues, fn {file, _, _} -> file end)
    
    Enum.each(issues_by_file, fn {file, file_issues} ->
      IO.puts("\nProcessing #{file}...")
      process_file(file, file_issues)
    end)
  end
  
  defp parse_issue(line) do
    case Regex.run(~r/\[D\] ↘ (test\/[^:]+):(\d+):(\d+)/, line) do
      [_, file, line_num, _col] ->
        {file, String.to_integer(line_num), line}
      _ ->
        nil
    end
  end
  
  defp process_file(file, issues) do
    content = File.read!(file)
    lines = String.split(content, "\n")
    
    # Find all MCPChat modules used in the file
    modules_to_alias = 
      content
      |> find_mcp_modules()
      |> Enum.uniq()
      |> Enum.sort()
    
    if modules_to_alias == [] do
      IO.puts("  No modules to alias found")
      return
    end
    
    IO.puts("  Found modules to alias: #{inspect(modules_to_alias)}")
    
    # Add aliases and update references
    updated_content = 
      content
      |> add_aliases(modules_to_alias)
      |> update_references(modules_to_alias)
    
    File.write!(file, updated_content)
    IO.puts("  ✓ Fixed #{length(modules_to_alias)} aliases")
  end
  
  defp find_mcp_modules(content) do
    # Find all MCPChat.Something.Something references
    ~r/MCPChat\.(?:[A-Z][A-Za-z0-9]*\.)+[A-Z][A-Za-z0-9]*/
    |> Regex.scan(content)
    |> Enum.map(&List.first/1)
    |> Enum.filter(fn module ->
      # Only alias modules with at least 2 levels of nesting
      length(String.split(module, ".")) > 2
    end)
  end
  
  defp add_aliases(content, modules) do
    lines = String.split(content, "\n")
    
    # Find insertion point (after defmodule and any existing aliases)
    {before_aliases, after_aliases} = find_alias_insertion_point(lines)
    
    # Generate alias statements
    new_aliases = generate_aliases(modules, before_aliases)
    
    # Combine all parts
    (before_aliases ++ new_aliases ++ after_aliases)
    |> Enum.join("\n")
  end
  
  defp find_alias_insertion_point(lines) do
    {collected, remaining} = 
      Enum.reduce(lines, {:collecting, [], []}, fn line, acc ->
        case acc do
          {:collecting, collected, []} ->
            cond do
              String.trim(line) =~ ~r/^defmodule\s+/ ->
                {:after_module, [line | collected], []}
              true ->
                {:collecting, [line | collected], []}
            end
            
          {:after_module, collected, []} ->
            cond do
              String.trim(line) == "" ->
                {:after_module, [line | collected], []}
              String.trim(line) =~ ~r/^@/ ->
                {:after_module, [line | collected], []}
              String.trim(line) =~ ~r/^use\s+/ ->
                {:after_module, [line | collected], []}
              String.trim(line) =~ ~r/^import\s+/ ->
                {:after_module, [line | collected], []}
              String.trim(line) =~ ~r/^alias\s+/ ->
                {:after_module, [line | collected], []}
              true ->
                # Found the insertion point
                {:done, collected, [line]}
            end
            
          {:done, collected, remaining} ->
            {:done, collected, [line | remaining]}
        end
      end)
    
    case {collected, remaining} do
      {{:done, before, after_lines}} ->
        {Enum.reverse(before), Enum.reverse(after_lines)}
      {{:after_module, before, []}, []} ->
        {Enum.reverse(before), []}
      _ ->
        {lines, []}
    end
  end
  
  defp generate_aliases(modules, existing_lines) do
    # Check if we already have any aliases
    has_aliases = Enum.any?(existing_lines, &(String.trim(&1) =~ ~r/^alias\s+/))
    
    # Filter out modules that are already aliased
    new_modules = Enum.filter(modules, fn module ->
      !Enum.any?(existing_lines, &String.contains?(&1, "alias #{module}"))
    end)
    
    if new_modules == [] do
      []
    else
      alias_lines = Enum.map(new_modules, fn module ->
        parts = String.split(module, ".")
        short_name = List.last(parts)
        "  alias #{module}"
      end)
      
      if has_aliases do
        alias_lines
      else
        [""] ++ alias_lines ++ [""]
      end
    end
  end
  
  defp update_references(content, modules) do
    Enum.reduce(modules, content, fn module, acc ->
      parts = String.split(module, ".")
      short_name = List.last(parts)
      
      # Replace module references, but not in alias statements
      acc
      |> String.replace(~r/(?<!alias )#{Regex.escape(module)}(?!\.)/m, short_name)
    end)
  end
end

TestAliasFixer.run()