#!/usr/bin/env elixir

# Script to fix alias ordering issues in Elixir files

defmodule AliasOrderFixer do
  @moduledoc """
  Fixes alias ordering issues detected by Credo.
  Groups aliases and sorts them alphabetically within each group.
  """

  def fix_file(file_path) do
    content = File.read!(file_path)
    lines = String.split(content, "\n")
    
    fixed_lines = fix_alias_order(lines)
    fixed_content = Enum.join(fixed_lines, "\n")
    
    if content != fixed_content do
      File.write!(file_path, fixed_content)
      IO.puts("Fixed: #{file_path}")
    end
  end
  
  defp fix_alias_order(lines) do
    lines
    |> find_and_fix_alias_blocks()
  end
  
  defp find_and_fix_alias_blocks(lines) do
    lines
    |> Enum.with_index()
    |> find_alias_blocks([])
    |> Enum.reverse()
    |> Enum.reduce(lines, fn {start_idx, end_idx, sorted_aliases}, acc ->
      # Replace the alias block with sorted version
      before = Enum.take(acc, start_idx)
      after_block = Enum.drop(acc, end_idx + 1)
      before ++ sorted_aliases ++ after_block
    end)
  end
  
  defp find_alias_blocks([], blocks), do: blocks
  defp find_alias_blocks([{line, idx} | rest], blocks) do
    if is_alias_line?(line) do
      # Find the end of this alias block
      {block_lines, remaining} = collect_alias_block([{line, idx} | rest])
      
      if length(block_lines) > 1 do
        # Sort the alias block
        sorted_block = sort_alias_block(block_lines)
        start_idx = idx
        end_idx = idx + length(block_lines) - 1
        
        find_alias_blocks(remaining, [{start_idx, end_idx, sorted_block} | blocks])
      else
        find_alias_blocks(rest, blocks)
      end
    else
      find_alias_blocks(rest, blocks)
    end
  end
  
  defp collect_alias_block(lines) do
    collect_alias_block(lines, [])
  end
  
  defp collect_alias_block([], acc), do: {Enum.reverse(acc), []}
  defp collect_alias_block([{line, idx} | rest], acc) do
    cond do
      is_alias_line?(line) or is_import_line?(line) or is_require_line?(line) or is_use_line?(line) ->
        collect_alias_block(rest, [line | acc])
      String.trim(line) == "" and acc != [] ->
        # Empty line might be part of the block if we're already collecting
        collect_alias_block(rest, [line | acc])
      true ->
        # Non-alias line, end of block
        {Enum.reverse(acc), [{line, idx} | rest]}
    end
  end
  
  defp is_alias_line?(line) do
    trimmed = String.trim(line)
    String.starts_with?(trimmed, "alias ")
  end
  
  defp is_import_line?(line) do
    trimmed = String.trim(line)
    String.starts_with?(trimmed, "import ")
  end
  
  defp is_require_line?(line) do
    trimmed = String.trim(line)
    String.starts_with?(trimmed, "require ")
  end
  
  defp is_use_line?(line) do
    trimmed = String.trim(line)
    String.starts_with?(trimmed, "use ")
  end
  
  defp sort_alias_block(lines) do
    # Group lines by type and sort within groups
    grouped = Enum.group_by(lines, &get_line_type/1)
    
    # Order: use, import, require, alias
    order = [:use, :import, :require, :alias, :empty]
    
    Enum.flat_map(order, fn type ->
      case grouped[type] do
        nil -> []
        group_lines -> sort_group(group_lines, type)
      end
    end)
  end
  
  defp get_line_type(line) do
    trimmed = String.trim(line)
    cond do
      trimmed == "" -> :empty
      String.starts_with?(trimmed, "use ") -> :use
      String.starts_with?(trimmed, "import ") -> :import
      String.starts_with?(trimmed, "require ") -> :require
      String.starts_with?(trimmed, "alias ") -> :alias
      true -> :other
    end
  end
  
  defp sort_group(lines, :empty), do: lines
  defp sort_group(lines, _type) do
    lines
    |> Enum.sort_by(fn line ->
      # Extract the module name for sorting
      line
      |> String.trim()
      |> extract_module_name()
      |> String.downcase()
    end)
  end
  
  defp extract_module_name(line) do
    cond do
      String.contains?(line, "alias ") ->
        line
        |> String.replace(~r/^\s*alias\s+/, "")
        |> String.replace(~r/\s*,?\s*as:.*$/, "")
        |> String.trim()
      String.contains?(line, "import ") ->
        line
        |> String.replace(~r/^\s*import\s+/, "")
        |> String.replace(~r/\s*,?\s*only:.*$/, "")
        |> String.replace(~r/\s*,?\s*except:.*$/, "")
        |> String.trim()
      String.contains?(line, "require ") ->
        line
        |> String.replace(~r/^\s*require\s+/, "")
        |> String.trim()
      String.contains?(line, "use ") ->
        line
        |> String.replace(~r/^\s*use\s+/, "")
        |> String.replace(~r/\s*,.*$/, "")
        |> String.trim()
      true ->
        line
    end
  end
end

# Get list of files with alias ordering issues
files_to_fix = [
  "lib/mcp_chat/chat_supervisor.ex",
  "lib/mcp_chat/cli/chat.ex",
  "lib/mcp_chat/cli/commands/context.ex",
  "lib/mcp_chat/cli/commands/mcp.ex",
  "lib/mcp_chat/cli/commands/mcp_extended.ex",
  "lib/mcp_chat/cli/commands/session.ex",
  "lib/mcp_chat/cli/commands/tui.ex",
  "lib/mcp_chat/cli/commands/utility.ex",
  "lib/mcp_chat/context/async_file_loader.ex",
  "lib/mcp_chat/context/at_symbol_resolver.ex",
  "lib/mcp_chat/mcp/concurrent_tool_executor.ex",
  "lib/mcp_chat/mcp/handlers/resource_change_handler.ex",
  "lib/mcp_chat/mcp/lazy_server_manager.ex",
  "lib/mcp_chat/mcp/parallel_connection_manager.ex",
  "lib/mcp_chat/mcp/resource_cache.ex",
  "lib/mcp_chat/mcp_server_handler.ex",
  "lib/mcp_chat/session_manager.ex",
  "lib/mcp_chat/streaming/enhanced_consumer.ex",
  "test/integration/at_symbol_e2e_test.exs",
  "test/integration/stdio_process_integration_test.exs",
  "test/mcp_chat/cli/resume_command_test.exs",
  "test/mcp_chat/context/at_symbol_resolver_test.exs",
  "test/mcp_chat/mcp/notification_integration_test.exs",
  "test/mcp_chat/session/autosave_test.exs"
]

IO.puts("Fixing alias ordering issues...\n")

Enum.each(files_to_fix, fn file ->
  if File.exists?(file) do
    AliasOrderFixer.fix_file(file)
  else
    IO.puts("File not found: #{file}")
  end
end)

IO.puts("\nDone!")