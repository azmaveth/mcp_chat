#!/usr/bin/env elixir

# Script to fix nested module aliasing in test files

defmodule TestAliaseFixer do
  @moduledoc """
  Fixes nested module aliasing issues in test files by adding appropriate aliases
  """

  def run do
    # Get all nested module aliasing issues from Credo
    {output, 0} = System.cmd("mix", ["credo", "--strict", "--format", "json"], stderr_to_stdout: true)
    
    issues = 
      output
      |> Jason.decode!()
      |> Map.get("issues", [])
      |> Enum.filter(&(&1["check"] == "Elixir.Credo.Check.Design.AliasUsage"))
      |> Enum.filter(&String.contains?(&1["filename"], "test/"))
    
    IO.puts("Found #{length(issues)} nested module aliasing issues in test files")
    
    # Group issues by file
    issues_by_file = Enum.group_by(issues, & &1["filename"])
    
    Enum.each(issues_by_file, fn {filename, file_issues} ->
      IO.puts("\nProcessing #{filename} (#{length(file_issues)} issues)")
      fix_file(filename, file_issues)
    end)
    
    IO.puts("\nDone! All nested module aliasing issues should be fixed.")
  end
  
  defp fix_file(filename, issues) do
    content = File.read!(filename)
    lines = String.split(content, "\n")
    
    # Extract all nested modules that need aliases
    nested_modules = 
      issues
      |> Enum.map(&extract_module_from_message(&1["message"]))
      |> Enum.uniq()
      |> Enum.sort()
    
    IO.puts("  Modules to alias: #{inspect(nested_modules)}")
    
    # Find where to insert aliases (after the module definition)
    {updated_lines, _} = 
      Enum.reduce(lines, {[], :looking_for_module}, fn line, {acc, state} ->
        case state do
          :looking_for_module ->
            if String.trim(line) =~ ~r/^defmodule\s+/ do
              {[line | acc], :looking_for_aliases}
            else
              {[line | acc], :looking_for_module}
            end
            
          :looking_for_aliases ->
            if String.trim(line) == "" or String.trim(line) =~ ~r/^@/ or String.trim(line) =~ ~r/^use\s+/ or String.trim(line) =~ ~r/^import\s+/ or String.trim(line) =~ ~r/^alias\s+/ do
              {[line | acc], :looking_for_aliases}
            else
              # Insert aliases here
              alias_lines = generate_alias_lines(nested_modules)
              {[line] ++ alias_lines ++ acc, :done}
            end
            
          :done ->
            {[line | acc], :done}
        end
      end)
    
    # Write back the file with updated content
    updated_content = 
      updated_lines
      |> Enum.reverse()
      |> Enum.join("\n")
      |> update_module_references(nested_modules)
    
    File.write!(filename, updated_content)
  end
  
  defp extract_module_from_message(message) do
    # Extract module name from message like "Nested modules could be aliased at the top of the invoking module."
    # The module is usually in the code snippet in the issue
    case Regex.run(~r/MCPChat\.[A-Za-z0-9\.]+/, message) do
      [module] -> module
      _ -> nil
    end
  end
  
  defp generate_alias_lines(modules) do
    modules
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn module ->
      short_name = module |> String.split(".") |> List.last()
      "  alias #{module}, as: #{short_name}"
    end)
    |> then(fn aliases ->
      if aliases == [] do
        []
      else
        [""] ++ aliases ++ [""]
      end
    end)
  end
  
  defp update_module_references(content, modules) do
    Enum.reduce(modules, content, fn module, acc ->
      if module do
        short_name = module |> String.split(".") |> List.last()
        String.replace(acc, module, short_name)
      else
        acc
      end
    end)
  end
end

# Install Jason if not available
Mix.install([{:jason, "~> 1.4"}])

TestAliaseFixer.run()