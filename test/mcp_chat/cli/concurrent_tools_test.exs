defmodule MCPChat.CLI.ConcurrentToolsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias MCPChat.CLI.ConcurrentTools

  @moduletag :unit

  describe "commands/0" do
    test "returns map of available commands" do
      commands = ConcurrentTools.commands()

      assert is_map(commands)
      assert Map.size(commands) == 1

      assert Map.has_key?(commands, "concurrent")
      assert commands["concurrent"] =~ "Execute tools concurrently"
    end
  end

  describe "handle_command/1 for concurrent commands" do
    test "shows help for empty args" do
      output =
        capture_io(fn ->
          ConcurrentTools.handle_command("concurrent", [])
        end)

      assert output =~ "Concurrent Tool Execution Commands"
      assert output =~ "/concurrent test"
      assert output =~ "/concurrent execute"
    end

    test "shows help for help subcommand" do
      output =
        capture_io(fn ->
          ConcurrentTools.handle_command("concurrent", ["help"])
        end)

      assert output =~ "Concurrent Tool Execution Commands"
      assert output =~ "Tool Specification Format"
    end

    test "shows error for unknown subcommand" do
      output =
        capture_io(fn ->
          ConcurrentTools.handle_command("concurrent", ["unknown"])
        end)

      assert output =~ "Unknown concurrent command"
      assert output =~ "/concurrent help"
    end
  end

  describe "handle_command/1 for non-concurrent commands" do
    test "returns :not_handled for non-concurrent commands" do
      assert ConcurrentTools.handle_command("other", ["command"]) == :not_handled
      assert ConcurrentTools.handle_command(["help"]) == :not_handled
      assert ConcurrentTools.handle_command([]) == :not_handled
    end
  end

  # Note: Testing private functions indirectly through public interface
  # since we cannot directly test private functions

  describe "test command" do
    test "shows error when no connected servers available" do
      # Mock ServerManager to return no connected servers
      :meck.new(MCPChat.MCP.ServerManager, [:passthrough])
      :meck.expect(MCPChat.MCP.ServerManager, :list_servers, 0, [])

      output =
        capture_io(fn ->
          ConcurrentTools.handle_command("concurrent", ["test"])
        end)

      assert output =~ "No connected MCP servers available for testing"

      :meck.unload(MCPChat.MCP.ServerManager)
    end

    test "shows error when no suitable tools found" do
      # Mock ServerManager to return servers without tools
      :meck.new(MCPChat.MCP.ServerManager, [:passthrough])

      :meck.expect(MCPChat.MCP.ServerManager, :list_servers, 0, [
        %{name: "test_server", status: :connected}
      ])

      :meck.expect(MCPChat.MCP.ServerManager, :get_tools, 1, {:ok, []})

      output =
        capture_io(fn ->
          ConcurrentTools.handle_command("concurrent", ["test"])
        end)

      assert output =~ "No suitable tools found for concurrent execution test"

      :meck.unload(MCPChat.MCP.ServerManager)
    end
  end

  describe "execute command" do
    test "shows error for empty tool specifications" do
      output =
        capture_io(fn ->
          ConcurrentTools.handle_command("concurrent", ["execute"])
        end)

      assert output =~ "No tool specifications provided"
    end

    test "shows error for invalid tool specification format" do
      output =
        capture_io(fn ->
          ConcurrentTools.handle_command("concurrent", ["execute", "invalid_format"])
        end)

      assert output =~ "Invalid tool specification"
      assert output =~ "Invalid format for 'invalid_format'"
    end
  end

  describe "safety command" do
    test "reports safe tools" do
      output =
        capture_io(fn ->
          ConcurrentTools.handle_command("concurrent", ["safety", "read_file"])
        end)

      assert output =~ "Tool 'read_file' is SAFE for concurrent execution"
    end

    test "reports unsafe tools" do
      output =
        capture_io(fn ->
          ConcurrentTools.handle_command("concurrent", ["safety", "write_file"])
        end)

      assert output =~ "Tool 'write_file' is UNSAFE for concurrent execution"
      assert output =~ "modify state or have side effects"
    end
  end

  describe "stats command" do
    test "displays execution statistics" do
      # Mock ConcurrentToolExecutor to return stats
      :meck.new(MCPChat.MCP.ConcurrentToolExecutor, [:passthrough])

      :meck.expect(MCPChat.MCP.ConcurrentToolExecutor, :get_execution_stats, 0, %{
        total_executions: 10,
        concurrent_executions: 5,
        average_duration: 150,
        success_rate: 90.0
      })

      output =
        capture_io(fn ->
          ConcurrentTools.handle_command("concurrent", ["stats"])
        end)

      assert output =~ "Concurrent Tool Execution Statistics"
      assert output =~ "Total executions: 10"
      assert output =~ "Concurrent executions: 5"
      assert output =~ "Average duration: 150ms"
      assert output =~ "Success rate: 90.0%"

      :meck.unload(MCPChat.MCP.ConcurrentToolExecutor)
    end
  end
end
