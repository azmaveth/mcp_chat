#!/usr/bin/env elixir

# Advanced Credo auto-fixes
# Run with: elixir scripts/credo_advanced_autofix.exs

defmodule CredoAdvancedAutofix do
  @moduledoc """
  Advanced auto-fixes for Credo issues:
  - Removes IO.inspect calls (converts to Logger.debug)
  - Adds missing @moduledoc
  - Fixes module aliasing issues
  - Converts length checks to Enum.empty?
  """

  def run do
    IO.puts("Running advanced Credo auto-fixes...")
    
    files = get_elixir_files()
    
    Enum.each(files, fn file ->
      if File.exists?(file) do
        content = File.read!(file)
        fixed_content = apply_advanced_fixes(content, file)
        
        if content != fixed_content do
          File.write!(file, fixed_content)
          IO.puts("Fixed: #{file}")
        end
      end
    end)
    
    IO.puts("Advanced auto-fix complete!")
  end
  
  defp get_elixir_files do
    Path.wildcard("lib/**/*.{ex,exs}") ++
    Path.wildcard("test/**/*.{ex,exs}")
  end
  
  defp apply_advanced_fixes(content, file) do
    content
    |> fix_io_inspect()
    |> add_missing_moduledoc(file)
    |> fix_length_checks()
    |> fix_module_aliases()
  end
  
  defp fix_io_inspect(content) do
    # Replace IO.inspect with Logger.debug
    if String.contains?(content, "IO.inspect") do
      content = 
        if not String.contains?(content, "require Logger") do
          # Add Logger requirement after moduledoc or at the top
          if String.contains?(content, "@moduledoc") do
            Regex.replace(
              ~r/(@moduledoc\s+"""[\s\S]*?""")/,
              content,
              "\\1\n\n  require Logger",
              global: false
            )
          else
            Regex.replace(
              ~r/(defmodule\s+[\w.]+\s+do\n)/,
              content,
              "\\1  require Logger\n\n",
              global: false
            )
          end
        else
          content
        end
      
      # Replace IO.inspect calls
      content
      |> Regex.replace(~r/IO\.inspect\(([^,)]+)\)/, "Logger.debug(inspect(\\1))")
      |> Regex.replace(~r/IO\.inspect\(([^,]+),\s*label:\s*([^)]+)\)/, "Logger.debug(\"\\2: \#{inspect(\\1)}\")")
    else
      content
    end
  end
  
  defp add_missing_moduledoc(content, file) do
    if String.contains?(file, "test/") do
      # Don't add moduledoc to test files
      content
    else
      if not String.contains?(content, "@moduledoc") and 
         Regex.match?(~r/defmodule\s+[\w.]+\s+do/, content) do
        # Extract module name
        module_name = 
          case Regex.run(~r/defmodule\s+([\w.]+)\s+do/, content) do
            [_, name] -> name
            _ -> "Module"
          end
        
        # Add basic moduledoc
        Regex.replace(
          ~r/(defmodule\s+[\w.]+\s+do)\n/,
          content,
          "\\1\n  @moduledoc \"\"\"\n  #{module_name} implementation.\n  \"\"\"\n\n",
          global: false
        )
      else
        content
      end
    end
  end
  
  defp fix_length_checks(content) do
    # Replace length(list) == 0 with Enum.empty?(list)
    content
    |> Regex.replace(~r/length\(([^)]+)\)\s*==\s*0/, "Enum.empty?(\\1)")
    |> Regex.replace(~r/length\(([^)]+)\)\s*!=\s*0/, "not Enum.empty?(\\1)")
  end
  
  defp fix_module_aliases(content) do
    # Find commonly used nested modules and suggest aliases
    nested_modules = Regex.scan(~r/MCPChat\.[\w.]+/, content)
    |> Enum.map(&List.first/1)
    |> Enum.frequencies()
    |> Enum.filter(fn {_module, count} -> count >= 3 end)
    |> Enum.map(fn {module, _} -> module end)
    
    if Enum.empty?(nested_modules) do
      content
    else
      # Add aliases after the module declaration
      aliases = nested_modules
      |> Enum.map(fn module ->
        short_name = module |> String.split(".") |> List.last()
        "  alias #{module}, as: #{short_name}"
      end)
      |> Enum.join("\n")
      
      # Don't auto-add aliases for now, just suggest
      IO.puts("Consider adding these aliases to reduce nesting:")
      IO.puts(aliases)
      content
    end
  end
end

CredoAdvancedAutofix.run()