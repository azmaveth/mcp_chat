defmodule MCPChat.MCPClientIntegrationTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Integration tests for MCP client functionality.
  Tests the MCP client components working together.
  """

  describe "MCP Protocol and Client integration" do
    test "request ID generation and correlation" do
      # Test that IDs are unique and monotonically increasing
      req1 = MCPChat.MCP.Protocol.encode_initialize(%{name: "test", version: "1.0"})
      req2 = MCPChat.MCP.Protocol.encode_list_tools()
      req3 = MCPChat.MCP.Protocol.encode_list_resources()

      assert req1.id < req2.id
      assert req2.id < req3.id
      assert req1.id != req2.id != req3.id
    end

    test "notification vs request handling" do
      # Requests have IDs
      request = MCPChat.MCP.Protocol.encode_list_tools()
      assert Map.has_key?(request, :id)
      assert request.jsonrpc == "2.0"
      assert request.method == "tools/list"

      # Notifications don't have IDs (when we implement them)
      # notification = MCPChat.MCP.Protocol.encode_notification("test", %{})
      # refute Map.has_key?(notification, :id)
    end

    test "response parsing handles all response types" do
      # Success response
      success_response = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "result" => %{"data" => "test"}
      }

      {tag, result, id} = MCPChat.MCP.Protocol.parse_response(success_response)
      assert tag == :result
      assert result["data"] == "test"
      assert id == 1

      # Error response
      error_response = %{
        "jsonrpc" => "2.0",
        "id" => 2,
        "error" => %{"code" => -32_601, "message" => "Method not found"}
      }

      {tag, error, id} = MCPChat.MCP.Protocol.parse_response(error_response)
      assert tag == :error
      assert error["code"] == -32_601
      assert id == 2

      # Notification (no ID)
      notification = %{
        "jsonrpc" => "2.0",
        "method" => "notification/test",
        "params" => %{}
      }

      {tag, method, params} = MCPChat.MCP.Protocol.parse_response(notification)
      assert tag == :notification
      assert method == "notification/test"
      assert params == %{}
    end
  end

  describe "MCP Client state management" do
    test "client request tracking" do
      # Test the client's ability to track pending requests
      client_state = %MCPChat.MCP.Client{
        pending_requests: %{},
        capabilities: %{},
        server_info: nil
      }

      # Simulate adding a request
      request_id = 123

      updated_state = %{
        client_state
        | pending_requests:
            Map.put(client_state.pending_requests, request_id, %{
              method: "tools/list",
              timestamp: DateTime.utc_now()
            })
      }

      assert Map.has_key?(updated_state.pending_requests, request_id)
      assert updated_state.pending_requests[request_id].method == "tools/list"
    end
  end

  describe "MCP ServerManager integration" do
    test "server configuration parsing" do
      # Test different server configuration formats
      configs = [
        %{
          "name" => "test-stdio",
          "command" => ["node", "server.js"],
          "transport" => "stdio"
        },
        %{
          "name" => "test-sse",
          "command" => ["python", "-m", "server"],
          "transport" => "sse",
          "port" => 8_080
        }
      ]

      Enum.each(configs, fn config ->
        assert config["name"] != nil
        assert config["command"] != nil
        assert config["transport"] in ["stdio", "sse", nil]
      end)
    end
  end

  describe "MCP message flow integration" do
    test "complete initialization sequence" do
      # This tests the expected message flow without actual connections

      # 1. Encode initialize request
      init_request =
        MCPChat.MCP.Protocol.encode_initialize(%{
          name: "test-client",
          version: "1.0.0"
        })

      # 2. Simulate server response
      init_response = %{
        "jsonrpc" => "2.0",
        "id" => init_request.id,
        "result" => %{
          "protocolVersion" => "2_024-11-05",
          "serverInfo" => %{
            "name" => "test-server",
            "version" => "1.0.0"
          },
          "capabilities" => %{
            "tools" => %{},
            "resources" => %{}
          }
        }
      }

      # 3. Parse response
      {tag, result, _id} = MCPChat.MCP.Protocol.parse_response(init_response)
      assert tag == :result
      assert result["protocolVersion"] == "2_024-11-05"

      # 4. Follow up with capability discovery
      tools_request = MCPChat.MCP.Protocol.encode_list_tools()
      assert tools_request.method == "tools/list"

      resources_request = MCPChat.MCP.Protocol.encode_list_resources()
      assert resources_request.method == "resources/list"
    end

    test "tool execution flow" do
      # Test encoding a tool call
      tool_call =
        MCPChat.MCP.Protocol.encode_call_tool(
          "test_tool",
          %{"param1" => "value1"}
        )

      assert tool_call.method == "tools/call"
      assert tool_call.params.name == "test_tool"
      assert tool_call.params.arguments["param1"] == "value1"

      # Simulate tool response
      tool_response = %{
        "jsonrpc" => "2.0",
        "id" => tool_call.id,
        "result" => %{
          "content" => [
            %{
              "type" => "text",
              "text" => "Tool executed successfully"
            }
          ]
        }
      }

      {tag, result, _id} = MCPChat.MCP.Protocol.parse_response(tool_response)
      assert tag == :result
      assert length(result["content"]) == 1
      assert Enum.at(result["content"], 0)["text"] == "Tool executed successfully"
    end
  end
end
