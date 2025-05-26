defmodule MCPChat.StdioProcessIntegrationTest do
  use ExUnit.Case, async: false
  
  alias MCPChat.MCP.{StdioProcessManager, ServerWrapper}
  
  @moduletag :integration
  @moduletag :mcp

  describe "stdio MCP server integration" do
    test "connects to demo time server via managed stdio" do
      # Path to our standalone time server
      demo_server_path = Path.join([File.cwd!(), "test", "support", "standalone_mcp_server.exs"])
      
      # Skip if file doesn't exist
      unless File.exists?(demo_server_path) do
        IO.puts("Skipping test - demo server not found at: #{demo_server_path}")
        :ok
      else
        # Start the server wrapper with our demo server
        config = %{
          "name" => "test-time-server",
          "command" => "elixir #{demo_server_path}",
          "env" => %{}
        }
        
        {:ok, wrapper} = ServerWrapper.start_link(config)
        
        # Give it a moment to initialize
        Process.sleep(500)
        
        # Check status
        status = ServerWrapper.get_status(wrapper)
        assert status == :connected
        
        # Get tools
        {:ok, tools} = ServerWrapper.get_tools(wrapper)
        assert is_list(tools)
        assert length(tools) > 0
        
        # Find the get_current_time tool
        time_tool = Enum.find(tools, fn tool ->
          tool["name"] == "get_current_time"
        end)
        
        assert time_tool != nil
        assert time_tool["description"] =~ "current time"
        
        # Call the tool
        {:ok, result} = ServerWrapper.call_tool(wrapper, "get_current_time", %{})
        
        assert is_map(result)
        assert Map.has_key?(result, "content")
        
        content = result["content"]
        assert is_list(content)
        
        # Find the text content
        text_content = Enum.find(content, fn item ->
          item["type"] == "text"
        end)
        
        assert text_content != nil
        assert text_content["text"] =~ ~r/\d{4}-\d{2}-\d{2}/  # Date pattern
        
        # Clean up
        GenServer.stop(wrapper)
      end
    end

    test "handles server crash gracefully" do
      # Create a simple script that exits after a delay
      test_script = Path.join(System.tmp_dir!(), "test_crash_server.exs")
      
      File.write!(test_script, """
      # Simple server that exits after receiving input
      # Output a valid JSON-RPC response first
      IO.puts(~s({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","capabilities":{},"serverInfo":{"name":"crash-test","version":"1.0.0"}}}))
      IO.gets("")  # Wait for input
      System.halt(1)  # Exit with error
      """)
      
      config = %{
        "name" => "crash-test-server",  
        "command" => "elixir #{test_script}",
        "env" => %{}
      }
      
      {:ok, wrapper} = ServerWrapper.start_link(config)
      
      # Monitor the wrapper
      ref = Process.monitor(wrapper)
      
      # Give it a moment to start
      Process.sleep(200)
      
      # Try to interact (this should trigger the crash)
      ServerWrapper.get_tools(wrapper)
      
      # Should receive DOWN message
      assert_receive {:DOWN, ^ref, :process, ^wrapper, _reason}, 5000
      
      # Clean up
      File.rm!(test_script)
    end
  end
end