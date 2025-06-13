defmodule MCPChat.MCP.StdioIntegrationTest do
  use ExUnit.Case

  alias MCPChat.MCP.{ServerManager, StdioProcessManager}

  @moduletag :integration

  describe "stdio server integration" do
    @tag :skip
    test "starts and manages stdio MCP server through ServerManager" do
      # This test requires an actual MCP server executable
      # Skip unless we have one available

      config = %{
        name: "test-stdio-server",
        command: "npx",
        args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
        env: %{}
      }

      # Start through ServerManager
      assert {:ok, _pid} = ServerManager.start_server(config)

      # List servers
      servers = ServerManager.list_servers()
      assert Enum.any?(servers, &(&1.name == "test-stdio-server"))

      # Get server info
      assert {:ok, server_info} = ServerManager.get_server("test-stdio-server")
      assert server_info.status == :connected

      # Try to list tools
      assert {:ok, tools} = ServerManager.get_tools("test-stdio-server")
      assert is_list(tools)

      # Stop server
      assert :ok = ServerManager.stop_server("test-stdio-server")

      # Verify it's gone
      servers_after = ServerManager.list_servers()
      refute Enum.any?(servers_after, &(&1.name == "test-stdio-server"))
    end
  end

  describe "stdio process lifecycle" do
    test "handles server crash and restart" do
      # Start the supervisor first
      {:ok, _sup} = MCPChat.MCP.StdioProcessSupervisor.start_link([])

      # Use a command that will exit after a short time
      config = %{
        name: "crash-test-server",
        command: "sh",
        args: ["-c", "sleep 0.2 && exit 1"]
      }

      {:ok, manager} =
        MCPChat.MCP.StdioProcessSupervisor.start_process(
          config,
          max_restarts: 2,
          restart_delay: 100,
          auto_start: true
        )

      # Initial status
      {:ok, initial_status} = StdioProcessManager.get_status(manager)
      assert initial_status.status == :running

      # Wait for the process to exit
      Process.sleep(500)

      # Check status - should show failed or exited
      {:ok, status_after} = StdioProcessManager.get_status(manager)
      assert status_after.status in [:failed, :exited]

      # The process should not be running anymore
      assert status_after.running == false

      # Cleanup
      MCPChat.MCP.StdioProcessSupervisor.stop_process(manager)
    end
  end

  describe "environment handling" do
    test "passes environment variables correctly" do
      test_file = "/tmp/mcp_test_env_#{:rand.uniform(10_000)}.txt"

      config = %{
        name: "env-test-server",
        command: "sh",
        args: ["-c", "echo \"VAR1=$TEST_VAR1 VAR2=$TEST_VAR2\" > #{test_file}"],
        env: %{
          "TEST_VAR1" => "value1",
          "TEST_VAR2" => "value2"
        }
      }

      {:ok, manager} = StdioProcessManager.start_link(config, auto_start: true)

      # Wait for command to complete
      Process.sleep(200)

      # Verify environment variables were passed
      assert {:ok, content} = File.read(test_file)
      assert String.contains?(content, "VAR1=value1")
      assert String.contains?(content, "VAR2=value2")

      # Cleanup
      File.rm(test_file)
      GenServer.stop(manager)
    end
  end

  describe "command parsing variations" do
    test "handles various command formats" do
      test_cases = [
        # Command with args field (proper structured format)
        %{command: "echo", args: ["hello"], expected_running: true},
        # Command with multiple args
        %{command: "echo", args: ["hello", "world"], expected_running: true},
        # Shell command (properly structured)
        %{command: "sh", args: ["-c", "echo hello"], expected_running: true},
        # Simple command without args
        %{command: "echo", args: ["test"], expected_running: true}
      ]

      for test_case <- test_cases do
        config =
          Map.merge(%{name: "test-server"}, test_case)
          |> Map.delete(:expected_running)

        {:ok, manager} = StdioProcessManager.start_link(config, auto_start: true)

        # Brief wait
        Process.sleep(100)

        {:ok, status} = StdioProcessManager.get_status(manager)

        if test_case.expected_running do
          assert status.status in [:running, :exited]
        end

        GenServer.stop(manager)
      end
    end
  end
end
