defmodule MCPChat.MCPBeamTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Tests MCP integration using BEAM transport for simplicity.
  This avoids stdio complexity while still testing real MCP protocol.
  """

  require Logger
  import MCPChat.MCPTestHelpers

  describe "MCP BEAM Transport Integration" do
    test "basic tool execution with BEAM transport" do
      # Create a simple handler with test tools
      handler =
        create_mock_handler(%{
          tools: [
            %{
              "name" => "echo",
              "description" => "Echoes the input",
              "inputSchema" => %{
                "type" => "object",
                "properties" => %{
                  "message" => %{"type" => "string"}
                },
                "required" => ["message"]
              }
            },
            %{
              "name" => "add",
              "description" => "Adds two numbers",
              "inputSchema" => %{
                "type" => "object",
                "properties" => %{
                  "a" => %{"type" => "number"},
                  "b" => %{"type" => "number"}
                },
                "required" => ["a", "b"]
              }
            }
          ],
          tool_results: %{
            "echo" => fn args ->
              %{"type" => "text", "text" => "Echo: #{args["message"]}"}
            end,
            "add" => fn args ->
              %{"type" => "text", "text" => "Result: #{args["a"] + args["b"]}"}
            end
          }
        })

      # Use BEAM transport for testing
      with_beam_mcp_server("test-server", handler, fn server_name ->
        # List tools
        {:ok, tools} = MCPChat.MCP.ServerManager.get_tools(server_name)
        assert length(tools) == 2
        assert Enum.find(tools, &(&1["name"] == "echo"))
        assert Enum.find(tools, &(&1["name"] == "add"))

        # Test echo tool
        {:ok, result} =
          MCPChat.MCP.ServerManager.call_tool(
            server_name,
            "echo",
            %{"message" => "Hello MCP!"}
          )

        assert result["content"]
        content = hd(result["content"])
        assert content["text"] == "Echo: Hello MCP!"

        # Test add tool
        {:ok, result} =
          MCPChat.MCP.ServerManager.call_tool(
            server_name,
            "add",
            %{"a" => 5, "b" => 3}
          )

        content = hd(result["content"])
        assert content["text"] == "Result: 8"
      end)
    end

    test "error handling with BEAM transport" do
      handler =
        create_mock_handler(%{
          tools: [
            %{
              "name" => "failing_tool",
              "description" => "A tool that always fails",
              "inputSchema" => %{"type" => "object"}
            }
          ],
          tool_results: %{
            "failing_tool" => fn _args ->
              # Return an error
              {:error, %{"code" => -32_603, "message" => "Internal error"}}
            end
          }
        })

      with_beam_mcp_server("error-server", handler, fn server_name ->
        # Try to call failing tool
        result =
          MCPChat.MCP.ServerManager.call_tool(
            server_name,
            "failing_tool",
            %{}
          )

        # Should get an error
        assert {:error, _} = result

        # Try to call non-existent tool
        result =
          MCPChat.MCP.ServerManager.call_tool(
            server_name,
            "does_not_exist",
            %{}
          )

        assert {:error, %{"code" => -32_601}} = result
      end)
    end

    test "multiple servers with BEAM transport" do
      # Create two different handlers
      time_handler =
        create_mock_handler(%{
          tools: [
            %{
              "name" => "get_time",
              "description" => "Gets current time",
              "inputSchema" => %{"type" => "object"}
            }
          ],
          tool_results: %{
            "get_time" => fn _args ->
              %{"type" => "text", "text" => "Current time: #{DateTime.utc_now()}"}
            end
          }
        })

      calc_handler =
        create_mock_handler(%{
          tools: [
            %{
              "name" => "multiply",
              "description" => "Multiplies two numbers",
              "inputSchema" => %{
                "type" => "object",
                "properties" => %{
                  "x" => %{"type" => "number"},
                  "y" => %{"type" => "number"}
                }
              }
            }
          ],
          tool_results: %{
            "multiply" => fn args ->
              %{"type" => "text", "text" => "Product: #{args["x"] * args["y"]}"}
            end
          }
        })

      # Start both servers
      with_beam_mcp_server("time-server", time_handler, fn time_server ->
        with_beam_mcp_server("calc-server", calc_handler, fn calc_server ->
          # List all servers
          servers = MCPChat.MCP.ServerManager.list_servers()
          assert Enum.find(servers, &(&1.name == time_server))
          assert Enum.find(servers, &(&1.name == calc_server))

          # Call tool from first server
          {:ok, result} =
            MCPChat.MCP.ServerManager.call_tool(
              time_server,
              "get_time",
              %{}
            )

          assert result["content"]

          # Call tool from second server
          {:ok, result} =
            MCPChat.MCP.ServerManager.call_tool(
              calc_server,
              "multiply",
              %{"x" => 7, "y" => 6}
            )

          content = hd(result["content"])
          assert content["text"] == "Product: 42"
        end)
      end)
    end
  end
end
