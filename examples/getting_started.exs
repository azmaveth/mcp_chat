#!/usr/bin/env elixir

# Getting Started with MCP Chat
# This example demonstrates basic usage of MCP Chat from Elixir code

# Add mcp_chat to path
Code.append_path("_build/dev/lib/mcp_chat/ebin")
Code.append_path("_build/dev/lib/ex_mcp/ebin")
Code.append_path("_build/dev/lib/ex_llm/ebin")
Code.append_path("_build/dev/lib/ex_alias/ebin")
Code.append_path("_build/dev/lib/ex_readline/ebin")

# Start the application
{:ok, _} = Application.ensure_all_started(:mcp_chat)

# Wait for services to start
Process.sleep(500)

IO.puts("""
=== MCP Chat Getting Started Example ===

This example demonstrates basic MCP Chat usage.
""")

# Example 1: Simple chat interaction
IO.puts("\n1. Simple Chat Interaction")
IO.puts("-------------------------")

# Get current session
session = MCPChat.Session.get_current_session()
IO.puts("Session ID: #{session.id}")

# Add a message and get response
MCPChat.Session.add_message("user", "What is the capital of France?")

# Get LLM response
case MCPChat.LLM.ExLLMAdapter.chat(session.messages) do
  {:ok, response} ->
    IO.puts("Assistant: #{response.content}")
    MCPChat.Session.add_message("assistant", response.content)
    
  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

# Example 2: Using commands programmatically
IO.puts("\n2. Using Commands")
IO.puts("-----------------")

# Show current model
case MCPChat.CLI.Commands.handle_command("/model") do
  :ok -> :ok
  _ -> IO.puts("Command failed")
end

# Show cost
MCPChat.CLI.Commands.handle_command("/cost")

# Example 3: Context management
IO.puts("\n3. Context Management")
IO.puts("--------------------")

# Add a file to context
test_file = Path.join([System.tmp_dir!(), "test_example.txt"])
File.write!(test_file, "This is a test file for the MCP Chat example.")

MCPChat.CLI.Commands.handle_command("/context add #{test_file}")
MCPChat.CLI.Commands.handle_command("/context list")

# Example 4: Using aliases
IO.puts("\n4. Command Aliases")
IO.puts("-----------------")

# Create an alias
MCPChat.CLI.Commands.handle_command("/alias add quick-save /save example_session")
MCPChat.CLI.Commands.handle_command("/alias list")

# Example 5: MCP Resources
IO.puts("\n5. Built-in Resources")
IO.puts("--------------------")

# List built-in resources
resources = MCPChat.MCP.BuiltinResources.list_resources()
IO.puts("Available built-in resources: #{length(resources)}")
Enum.take(resources, 3) |> Enum.each(fn r ->
  IO.puts("  - #{r["name"]}: #{r["description"]}")
end)

# Read a resource
case MCPChat.MCP.BuiltinResources.read_resource("mcp-chat://info/version") do
  {:ok, content} ->
    IO.puts("\nVersion Info:")
    IO.puts(content)
  _ ->
    IO.puts("Failed to read resource")
end

# Example 6: Health monitoring
IO.puts("\n6. Health Monitoring")
IO.puts("-------------------")

health_status = MCPChat.HealthMonitor.get_health_status()
IO.puts("Monitored processes: #{map_size(health_status)}")
Enum.each(health_status, fn {name, info} ->
  IO.puts("  - #{name}: #{info.status}")
end)

IO.puts("""

=== Example Complete ===

This example demonstrated:
- Basic chat interaction
- Using commands programmatically  
- Context management with files
- Command aliases
- Built-in MCP resources
- Health monitoring

For more examples, see the other files in this directory.
""")

# Cleanup
File.rm(test_file)

# Note: In a real application, you would typically keep the app running
# System.halt(0)