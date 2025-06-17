#!/usr/bin/env elixir

# Script to convert explicit try blocks to implicit try in rescue/after scenarios

defmodule FixImplicitTry do
  def run do
    IO.puts("Fixing explicit try blocks to implicit try...")
    
    # Find all files with explicit try blocks
    files = find_files_with_explicit_try()
    
    Enum.each(files, fn file ->
      fix_file(file)
    end)
    
    IO.puts("\nDone!")
  end
  
  defp find_files_with_explicit_try do
    {output, 0} = System.cmd("mix", ["credo", "--strict", "--format=flycheck"])
    
    output
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, "Prefer using an implicit `try`"))
    |> Enum.map(fn line ->
      [file | _] = String.split(line, ":")
      file
    end)
    |> Enum.uniq()
  end
  
  defp fix_file(file) do
    IO.puts("Fixing #{file}...")
    
    content = File.read!(file)
    fixed_content = fix_explicit_try(content)
    
    if content != fixed_content do
      File.write!(file, fixed_content)
      IO.puts("  ✓ Fixed")
    else
      IO.puts("  - No changes needed")
    end
  end
  
  defp fix_explicit_try(content) do
    # Pattern to match explicit try blocks with rescue/after
    # This regex handles multiline try blocks
    pattern = ~r/
      (\s*)try\s+do\s*\n          # Match 'try do' with indentation
      ((?:.*\n)*?)                 # Capture the try body (non-greedy)
      (\s*)(rescue|after)\s*\n     # Match rescue or after
      ((?:.*\n)*?)                 # Capture the rescue/after body
      (\s*)end                     # Match the closing end
    /mx
    
    Regex.replace(pattern, content, fn full_match, indent, body, _, keyword, handler_body, _ ->
      # Remove the try do and end, keep the body and rescue/after
      "#{body}#{indent}#{keyword}\n#{handler_body}"
    end)
  end
end

FixImplicitTry.run()