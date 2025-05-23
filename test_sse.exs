#!/usr/bin/env elixir

# Test script for SSE functionality
# This creates two MCP Chat instances - one as server, one as client

Mix.install([
  {:mcp_chat, path: "."}
])

defmodule TestSSE do
  def run do
    IO.puts("Starting SSE test...")
    
    # Start the application
    {:ok, _} = Application.ensure_all_started(:mcp_chat)
    
    # Configure server mode
    Application.put_env(:mcp_chat, :mcp_server, %{
      sse_enabled: true,
      sse_port: 8888
    })
    
    # Wait for server to start
    Process.sleep(2000)
    
    IO.puts("MCP SSE Server should be running on port 8888")
    IO.puts("You can test it with:")
    IO.puts("  curl -N http://localhost:8888/sse")
    IO.puts("")
    IO.puts("Or send a request:")
    IO.puts("  curl -X POST http://localhost:8888/message \\")
    IO.puts("    -H 'Content-Type: application/json' \\")
    IO.puts("    -d '{\"jsonrpc\":\"2.0\",\"method\":\"tools/list\",\"params\":{},\"id\":1}'")
    
    # Keep running
    Process.sleep(:infinity)
  end
end

TestSSE.run()