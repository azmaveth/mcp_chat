defmodule MCPChat.StdioProcessIntegrationTest do
  use ExUnit.Case, async: false

  alias MCPChat.MCP.{ServerWrapper, StdioProcessManager}

  @moduletag :integration
  @moduletag :mcp

  describe "stdio MCP server integration" do
    test "connects to demo time server via managed stdio" do
      # Path to our standalone time server
      demo_server_path = Path.join([File.cwd!(), "test", "support", "standalone_mcp_server.exs"])

      # Skip if file doesn't exist
      if File.exists?(demo_server_path) do
        # Start the server wrapper with our demo server
        config = %{
          "name" => "test-time-server",
          "command" => "elixir #{demo_server_path}",
          "env" => %{}
        }

        {:ok, wrapper} = ServerWrapper.start_link(config)

        # Give server more time to initialize
        Process.sleep(2000)

        # Check status
        status = ServerWrapper.get_status(wrapper)
        assert status == :connected

        # Get tools with longer timeout
        {:ok, tools_result} = ServerWrapper.get_tools(wrapper, 15_000)
        tools = tools_result["tools"] || tools_result.tools || tools_result
        assert is_list(tools)
        assert length(tools) > 0

        # Find the get_current_time tool
        time_tool =
          Enum.find(tools, fn tool ->
            tool["name"] == "get_current_time" || tool.name == "get_current_time"
          end)

        assert time_tool != nil
        description = time_tool["description"] || time_tool.description
        assert description =~ "current time"

        # Call the tool
        {:ok, result} = ServerWrapper.call_tool(wrapper, "get_current_time", %{})

        assert is_map(result)
        assert Map.has_key?(result, "content") || Map.has_key?(result, :content)

        content = result["content"] || result[:content]
        assert is_list(content)

        # Find the text content
        text_content =
          Enum.find(content, fn item ->
            item["type"] == "text" || item[:type] == "text"
          end)

        assert text_content != nil
        # Date pattern
        text = text_content["text"] || text_content[:text]
        assert text =~ ~r/\d{4}-\d{2}-\d{2}/

        # Clean up
        GenServer.stop(wrapper)
      else
        IO.puts("Skipping test - demo server not found at: #{demo_server_path}")
        :ok
      end
    end

    test "handles server crash gracefully" do
      # Create a simple script that exits after a delay
      test_script = Path.join(System.tmp_dir!(), "test_crash_server.exs")

      File.write!(test_script, """
      # Simple server that crashes immediately after startup
      # Output a valid JSON-RPC response first, then crash
      IO.puts(~s({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-03-26","capabilities":{},"serverInfo":{"name":"crash-test","version":"1.0.0"}}}))
      Process.sleep(100)  # Brief delay to ensure message is sent
      System.halt(1)  # Exit with error immediately
      """)

      config = %{
        "name" => "crash-test-server",
        "command" => "elixir #{test_script}",
        "env" => %{}
      }

      {:ok, wrapper} = ServerWrapper.start_link(config)

      # Wait for the server to start and then crash
      Process.sleep(500)

      # The ServerWrapper should handle the crash gracefully - it should still be alive
      # but calls to it should fail or return disconnected status
      assert Process.alive?(wrapper)

      # Try to call get_tools - this should fail since the underlying server crashed
      result =
        try do
          ServerWrapper.get_tools(wrapper, 1_000)
        catch
          _, _ -> {:error, :crashed}
        end

      # Should either return an error or fail with an exception
      assert result == {:error, :crashed} || match?({:error, _}, result)

      # The wrapper should still be alive (graceful handling)
      # but further operations should continue to fail
      assert Process.alive?(wrapper)

      # Clean up
      GenServer.stop(wrapper)
      File.rm!(test_script)
    end
  end
end
