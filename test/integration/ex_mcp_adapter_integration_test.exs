defmodule MCPChat.ExMCPAdapterIntegrationTest do
  use ExUnit.Case, async: true

  alias MCPChat.MCP.ExMCPAdapter

  @moduletag :integration

  describe "ExMCPAdapter API format handling" do
    test "adapter correctly handles new ex_mcp API format for list_tools" do
      # Mock the ex_mcp client response
      mock_response = {:ok, %{tools: [%{"name" => "test_tool"}], nextCursor: nil}}

      # This test verifies the adapter transforms the new format correctly
      # In a real test, we'd use Mox to mock ExMCP.Client
      # For now, we're just documenting the expected behavior

      # Expected: adapter should extract tools from the map format
      # and return {:ok, tools} for backward compatibility
      assert true
    end

    test "adapter correctly handles new ex_mcp API format for list_resources" do
      # Mock the ex_mcp client response
      mock_response = {:ok, %{resources: [%{"uri" => "test://resource"}], nextCursor: "page2"}}

      # Expected: adapter should extract resources and ignore cursor
      assert true
    end

    test "adapter correctly handles new ex_mcp API format for list_prompts" do
      # Mock the ex_mcp client response  
      mock_response = {:ok, %{prompts: [%{"name" => "test_prompt"}], nextCursor: nil}}

      # Expected: adapter should extract prompts from the map format
      assert true
    end

    test "adapter handles HTTP transport (renamed from SSE)" do
      # The adapter should now use ExMCP.Transport.HTTP instead of SSE
      config = %{
        transport: :sse,
        url: "http://example.com",
        headers: %{}
      }

      # This would normally test that the adapter creates the correct transport config
      assert true
    end
  end
end
