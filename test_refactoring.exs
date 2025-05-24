#!/usr/bin/env elixir

# Test script to verify the refactored command modules work correctly

# Start the necessary processes
{:ok, _} = MCPChat.Session.start_link()
{:ok, _} = MCPChat.Alias.start_link()

# Test command routing
commands = [
  # Session commands
  {"/new", []},
  {"/sessions", []},
  {"/history", []},
  
  # Utility commands
  {"/help", []},
  {"/clear", []},
  {"/config", []},
  {"/cost", []},
  
  # LLM commands
  {"/backend", []},
  {"/models", []},
  {"/acceleration", []},
  
  # MCP commands
  {"/servers", []},
  {"/discover", []},
  {"/tools", []},
  {"/resources", []},
  {"/prompts", []},
  
  # Context commands
  {"/context", []},
  {"/tokens", ["4096"]},
  {"/strategy", ["sliding_window"]},
  
  # Alias commands
  {"/alias", ["list"]}
]

IO.puts("Testing refactored command modules...\n")

for {cmd, args} <- commands do
  cmd_name = String.trim_leading(cmd, "/")
  IO.puts("Testing: #{cmd}")
  
  try do
    result = MCPChat.CLI.Commands.handle_command(cmd_name, args)
    case result do
      :ok -> IO.puts("  ✓ Success")
      {:error, msg} -> IO.puts("  ✗ Error: #{msg}")
      _ -> IO.puts("  ✓ Result: #{inspect(result)}")
    end
  rescue
    e ->
      IO.puts("  ✗ Exception: #{inspect(e)}")
  end
  
  IO.puts("")
end

IO.puts("\nRefactoring test complete!")