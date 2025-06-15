defmodule Commands.MCPBasicTest do
  @moduledoc """
  Basic tests for MCP CLI commands focusing on the /tools command functionality.
  These tests ensure that the command parsing and display logic continues to work
  as we make changes to the codebase.
  """

  use ExUnit.Case, async: false
  alias Commands.MCP
  alias ServerManager

  import ExUnit.CaptureIO
  import :meck

  alias Commands.MCPBasicTest

  setup do
    # Mock ServerManager to avoid actual server connections
    new(ServerManager, [:passthrough])

    on_exit(fn ->
      unload()
    end)

    :ok
  end

  describe "/tools command" do
    test "shows message when no servers are connected" do
      expect(ServerManager, :list_servers, fn -> [] end)

      output =
        capture_io(fn ->
          MCP.handle_command("mcp", ["tools"])
        end)

      assert output =~ "No MCP servers connected"
    end

    test "shows message when no tools are available from connected servers" do
      expect(ServerManager, :list_servers, fn ->
        [%{name: "test-server", status: :connected}]
      end)

      expect(ServerManager, :get_tools, fn "test-server" ->
        {:ok, %{"tools" => []}}
      end)

      output =
        capture_io(fn ->
          MCP.handle_command("mcp", ["tools"])
        end)

      assert output =~ "No tools available from connected servers"
    end

    test "displays tools from servers returning map format" do
      expect(ServerManager, :list_servers, fn ->
        [%{name: "filesystem", status: :connected}]
      end)

      expect(ServerManager, :get_tools, fn "filesystem" ->
        {:ok,
         %{
           "tools" => [
             %{
               "name" => "read_file",
               "description" => "Read a file from the filesystem"
             },
             %{
               "name" => "write_file",
               "description" => "Write a file to the filesystem"
             }
           ]
         }}
      end)

      output =
        capture_io(fn ->
          MCP.handle_command("mcp", ["tools"])
        end)

      assert output =~ "Available MCP tools:"
      assert output =~ "filesystem:"
      assert output =~ "read_file - Read a file from the filesystem"
      assert output =~ "write_file - Write a file to the filesystem"
    end

    test "displays tools from servers returning list format (backward compatibility)" do
      expect(ServerManager, :list_servers, fn ->
        [%{name: "legacy-server", status: :connected}]
      end)

      expect(ServerManager, :get_tools, fn "legacy-server" ->
        {:ok,
         [
           %{
             "name" => "legacy_tool",
             "description" => "A legacy tool"
           }
         ]}
      end)

      output =
        capture_io(fn ->
          MCP.handle_command("mcp", ["tools"])
        end)

      assert output =~ "legacy_tool - A legacy tool"
    end

    test "handles multiple servers with tools" do
      expect(ServerManager, :list_servers, fn ->
        [
          %{name: "server1", status: :connected},
          %{name: "server2", status: :connected}
        ]
      end)

      expect(ServerManager, :get_tools, fn name ->
        case name do
          "server1" ->
            {:ok,
             %{
               "tools" => [
                 %{"name" => "tool1", "description" => "Tool from server1"}
               ]
             }}

          "server2" ->
            {:ok,
             %{
               "tools" => [
                 %{"name" => "tool2", "description" => "Tool from server2"}
               ]
             }}
        end
      end)

      output =
        capture_io(fn ->
          MCP.handle_command("mcp", ["tools"])
        end)

      assert output =~ "server1:"
      assert output =~ "tool1 - Tool from server1"
      assert output =~ "server2:"
      assert output =~ "tool2 - Tool from server2"
    end

    test "gracefully handles servers that return errors" do
      expect(ServerManager, :list_servers, fn ->
        [
          %{name: "good-server", status: :connected},
          %{name: "bad-server", status: :connected}
        ]
      end)

      expect(ServerManager, :get_tools, fn name ->
        case name do
          "good-server" ->
            {:ok,
             %{
               "tools" => [
                 %{"name" => "working_tool", "description" => "This tool works"}
               ]
             }}

          "bad-server" ->
            {:error, :connection_lost}
        end
      end)

      output =
        capture_io(fn ->
          MCP.handle_command("mcp", ["tools"])
        end)

      # Should still show the working tools
      assert output =~ "working_tool - This tool works"
      # But not error out completely
      refute output =~ "bad-server:"
    end

    test "filters out disconnected servers" do
      expect(ServerManager, :list_servers, fn ->
        [
          %{name: "connected-server", status: :connected},
          %{name: "disconnected-server", status: :disconnected}
        ]
      end)

      # Should only call get_tools for the connected server
      expect(ServerManager, :get_tools, fn "connected-server" ->
        {:ok,
         %{
           "tools" => [
             %{"name" => "available_tool", "description" => "Only from connected server"}
           ]
         }}
      end)

      output =
        capture_io(fn ->
          MCP.handle_command("mcp", ["tools"])
        end)

      assert output =~ "available_tool"
      refute output =~ "disconnected-server"
    end
  end
end
