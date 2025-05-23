#!/usr/bin/env elixir

# Test script for MCP tool discovery and execution
Mix.install([
  {:mcp_chat, path: "."}
])

defmodule TestMCPTools do
  def run do
    IO.puts("Testing MCP Tool Discovery and Execution...")
    
    # Start the application
    {:ok, _} = Application.ensure_all_started(:mcp_chat)
    
    # Test configuration with a filesystem server
    config = %{
      mcp: %{
        servers: [
          %{
            name: "test-fs",
            command: ["npx", "-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
          }
        ]
      }
    }
    
    # Manually start the server manager
    MCPChat.MCP.ServerManager.start_configured_servers()
    
    # Wait for servers to connect
    Process.sleep(3000)
    
    # List servers
    IO.puts("\n1. Listing MCP servers:")
    servers = MCPChat.MCP.ServerManager.list_servers()
    Enum.each(servers, fn server ->
      IO.puts("   - #{server.name}: #{server.status}")
    end)
    
    # List tools
    IO.puts("\n2. Listing available tools:")
    tools = MCPChat.MCP.ServerManager.list_all_tools()
    Enum.each(tools, fn tool ->
      IO.puts("   - [#{tool.server}] #{tool["name"]}: #{tool["description"]}")
    end)
    
    # Try calling a tool (if any are available)
    if length(tools) > 0 do
      first_tool = hd(tools)
      IO.puts("\n3. Testing tool execution:")
      IO.puts("   Calling tool: #{first_tool["name"]} from server: #{first_tool.server}")
      
      # For filesystem server, try reading directory
      test_args = case first_tool["name"] do
        "read_directory" -> %{"path" => "/tmp"}
        "read_file" -> %{"path" => "/tmp/test.txt"}
        _ -> %{}
      end
      
      case MCPChat.MCP.ServerManager.call_tool(first_tool.server, first_tool["name"], test_args) do
        {:ok, result} ->
          IO.puts("   ✓ Tool executed successfully!")
          IO.puts("   Result: #{inspect(result, limit: 5, pretty: true)}")
        
        {:error, reason} ->
          IO.puts("   ✗ Tool execution failed: #{inspect(reason)}")
      end
    else
      IO.puts("\n3. No tools available to test")
    end
    
    # List resources
    IO.puts("\n4. Listing available resources:")
    resources = MCPChat.MCP.ServerManager.list_all_resources()
    Enum.each(resources, fn resource ->
      IO.puts("   - [#{resource.server}] #{resource["uri"]}: #{resource["name"]}")
    end)
    
    # List prompts
    IO.puts("\n5. Listing available prompts:")
    prompts = MCPChat.MCP.ServerManager.list_all_prompts()
    Enum.each(prompts, fn prompt ->
      IO.puts("   - [#{prompt.server}] #{prompt["name"]}: #{prompt["description"]}")
    end)
    
    IO.puts("\nTest complete!")
  end
end

TestMCPTools.run()