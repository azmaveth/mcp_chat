#!/usr/bin/env elixir

# Example of using MCPChat with stdio MCP servers
# 
# This example demonstrates:
# 1. Starting an MCP server as an OS process
# 2. Connecting to it via stdio transport
# 3. Using the server's capabilities
# 4. Proper cleanup

# Ensure we're in the right directory
File.cd!(__DIR__ <> "/..")

# Start the application
{:ok, _} = Application.ensure_all_started(:mcp_chat)

defmodule StdioServerExample do
  alias MCPChat.MCP.{ServerManager, StdioProcessManager}
  
  def run do
    IO.puts("=== MCP Stdio Server Example ===\n")
    
    # Example 1: Direct StdioProcessManager usage
    direct_process_example()
    
    # Example 2: Using ServerManager (recommended)
    server_manager_example()
  end
  
  defp direct_process_example do
    IO.puts("1. Direct StdioProcessManager Usage")
    IO.puts("-----------------------------------")
    
    config = %{
      name: "echo-server",
      command: "sh",
      args: ["-c", "while read line; do echo \"Server received: $line\"; done"],
      env: %{"SERVER_NAME" => "Echo Server"}
    }
    
    IO.puts("Starting echo server process...")
    {:ok, manager} = StdioProcessManager.start_link(config)
    
    # Check status
    {:ok, status} = StdioProcessManager.get_status(manager)
    IO.puts("Status: #{inspect(status.status)}")
    IO.puts("OS PID: #{inspect(status.os_pid)}")
    
    # Let it run for a bit
    Process.sleep(1000)
    
    # Stop the process
    IO.puts("Stopping server...")
    :ok = StdioProcessManager.stop_process(manager)
    
    # Cleanup
    GenServer.stop(manager)
    IO.puts("Done!\n")
  end
  
  defp server_manager_example do
    IO.puts("2. ServerManager Integration")
    IO.puts("----------------------------")
    
    # Start ServerManager if not already running
    case GenServer.whereis(ServerManager) do
      nil -> 
        {:ok, _} = ServerManager.start_link()
      _pid -> 
        :ok
    end
    
    # Example with a filesystem MCP server (if available)
    config = %{
      name: "fs-server",
      command: "npx",
      args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
      env: %{}
    }
    
    IO.puts("Starting filesystem MCP server...")
    
    case ServerManager.start_server(config) do
      {:ok, _pid} ->
        IO.puts("Server started successfully!")
        
        # List servers
        servers = ServerManager.list_servers()
        IO.puts("\nActive servers:")
        for server <- servers do
          IO.puts("  - #{server.name}: #{server.status}")
        end
        
        # Try to get tools
        IO.puts("\nGetting tools...")
        case ServerManager.get_tools("fs-server") do
          {:ok, tools} ->
            IO.puts("Available tools: #{length(tools)}")
            for tool <- Enum.take(tools, 3) do
              IO.puts("  - #{tool["name"]}: #{tool["description"]}")
            end
            
          {:error, reason} ->
            IO.puts("Failed to get tools: #{inspect(reason)}")
        end
        
        # Stop the server
        IO.puts("\nStopping server...")
        :ok = ServerManager.stop_server("fs-server")
        IO.puts("Server stopped.")
        
      {:error, reason} ->
        IO.puts("Failed to start server: #{inspect(reason)}")
        IO.puts("Note: This example requires npx and @modelcontextprotocol/server-filesystem")
    end
    
    IO.puts("\nDone!")
  end
end

# Run the example
StdioServerExample.run()

# Give some time for async operations to complete
Process.sleep(500)