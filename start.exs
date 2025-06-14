#!/usr/bin/env elixir
# Standalone launcher script for MCP Chat

# Ensure we're in the right directory
File.cd!(Path.dirname(__ENV__.file))

# Check if deps are installed
unless File.exists?("_build") do
  IO.puts("Installing dependencies...")
  System.cmd("mix", ["deps.get"])
  System.cmd("mix", ["compile"])
end

# Start the application
{:ok, _} = Application.ensure_all_started(:mcp_chat)

# Run main in a way that keeps the VM alive
MCPChat.main()

# Keep the script running
receive do
  :never -> :ok
end