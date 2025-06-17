#!/usr/bin/env elixir

# Test script for background server connections
# This script demonstrates the new background connection functionality

IO.puts("🚀 Testing Background Server Connections")
IO.puts("")

# Start the application
Application.ensure_all_started(:mcp_chat)

# Wait a moment for startup
Process.sleep(1000)

# Check initial server status
IO.puts("📊 Initial server status:")
servers = MCPChat.MCP.ServerManager.list_servers_with_status()

if Enum.empty?(servers) do
  IO.puts("   No servers configured")
else
  Enum.each(servers, fn %{name: name, server: server} ->
    status = case server.status do
      :connecting -> "🔄 CONNECTING"
      :connected -> "✅ CONNECTED"
      :failed -> "❌ FAILED"
      :disconnected -> "⚠️  DISCONNECTED"
      _ -> "❓ UNKNOWN"
    end
    IO.puts("   #{name}: #{status}")
  end)
end

IO.puts("")
IO.puts("⏱️  Waiting 5 seconds for background connections...")
Process.sleep(5000)

# Check status after connections
IO.puts("")
IO.puts("📊 Status after background connection attempts:")
servers = MCPChat.MCP.ServerManager.list_servers_with_status()

Enum.each(servers, fn %{name: name, server: server} ->
  status = case server.status do
    :connecting -> "🔄 CONNECTING"
    :connected -> "✅ CONNECTED (#{length(server.capabilities.tools)} tools)"
    :failed -> "❌ FAILED: #{inspect(server.error)}"
    :disconnected -> "⚠️  DISCONNECTED"
    _ -> "❓ UNKNOWN"
  end
  IO.puts("   #{name}: #{status}")
end)

IO.puts("")
IO.puts("🔧 Testing /mcp servers command output:")
IO.puts("")
MCPChat.CLI.Commands.MCP.handle_command("mcp", ["servers"])

IO.puts("")
IO.puts("✅ Background connection test completed!")