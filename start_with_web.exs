#!/usr/bin/env elixir

# Script to start MCP Chat with Web Dashboard
# This handles the configuration and startup more gracefully

IO.puts """
🚀 Starting MCP Chat with Web Dashboard
=======================================

This will start:
- MCP Chat application
- Phoenix web server on http://localhost:4000
- All agent supervisors and services

"""

# First ensure configs are loaded
Mix.Task.run("loadconfig")

# Start the application with server enabled
Application.put_env(:mcp_chat, MCPChatWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  server: true,
  url: [host: "localhost"],
  secret_key_base: String.duplicate("a", 64),
  render_errors: [
    formats: [html: MCPChatWeb.ErrorHTML, json: MCPChatWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MCPChat.PubSub,
  live_view: [signing_salt: "mcp_chat_lv_salt"]
)

# Configure Phoenix
Application.put_env(:phoenix, :json_library, Jason)

# Start all applications
{:ok, _} = Application.ensure_all_started(:mcp_chat)

IO.puts """
✅ Application started successfully!

Web Dashboard URLs:
- Dashboard: http://localhost:4000/
- Sessions:  http://localhost:4000/sessions  
- Agents:    http://localhost:4000/agents
- Health:    http://localhost:4000/health

To start the CLI in IEx, run:
  MCPChat.main()

Press Ctrl+C twice to exit.
"""

# Keep the script running
Process.sleep(:infinity)