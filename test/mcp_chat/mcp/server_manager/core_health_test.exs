defmodule MCPChat.MCP.ServerManager.CoreHealthTest do
  use ExUnit.Case

  alias MCPChat.MCP.ServerManager.Core
  alias MCPChat.MCP.ServerManager.Server

  describe "Core health tracking functions" do
    setup do
      # Create initial state with a connected server
      server = Server.new("test-server", %{command: ["test"]})
      pid = self()
      monitor_ref = make_ref()
      connected_server = Server.mark_connected(server, pid, monitor_ref)

      state = %{
        servers: %{"test-server" => connected_server},
        supervisor: nil
      }

      {:ok, %{state: state, server: connected_server}}
    end

    test "record_server_success/3 updates server health metrics", %{state: state} do
      response_time = 150

      new_state = Core.record_server_success(state, "test-server", response_time)

      updated_server = new_state.servers["test-server"]
      health = updated_server.health

      assert health.total_requests == 1
      assert health.successful_requests == 1
      assert health.avg_response_time == 150.0
      assert health.consecutive_failures == 0
      assert health.is_healthy == true
    end

    test "record_server_success/3 ignores non-existent server", %{state: state} do
      new_state = Core.record_server_success(state, "nonexistent-server", 100)

      # State should remain unchanged
      assert new_state == state
    end

    test "record_server_failure/2 updates server health metrics", %{state: state} do
      new_state = Core.record_server_failure(state, "test-server")

      updated_server = new_state.servers["test-server"]
      health = updated_server.health

      assert health.total_requests == 1
      assert health.failed_requests == 1
      assert health.consecutive_failures == 1
      # Still healthy after 1 failure
      assert health.is_healthy == true
    end

    test "record_server_failure/2 ignores non-existent server", %{state: state} do
      new_state = Core.record_server_failure(state, "nonexistent-server")

      # State should remain unchanged
      assert new_state == state
    end

    test "record_server_success/3 calculates average response time correctly", %{state: state} do
      # Record first success
      state1 = Core.record_server_success(state, "test-server", 100)

      # Record second success
      state2 = Core.record_server_success(state1, "test-server", 200)

      updated_server = state2.servers["test-server"]
      health = updated_server.health

      assert health.total_requests == 2
      assert health.successful_requests == 2
      # (100 + 200) / 2
      assert health.avg_response_time == 150.0
    end

    test "record_server_failure/2 marks server unhealthy after 3 consecutive failures", %{state: state} do
      # Record 3 consecutive failures
      state1 = Core.record_server_failure(state, "test-server")
      state2 = Core.record_server_failure(state1, "test-server")
      state3 = Core.record_server_failure(state2, "test-server")

      updated_server = state3.servers["test-server"]
      health = updated_server.health

      assert health.consecutive_failures == 3
      assert health.is_healthy == false
    end

    test "record_server_success/3 resets consecutive failures", %{state: state} do
      # Record some failures first
      state1 = Core.record_server_failure(state, "test-server")
      state2 = Core.record_server_failure(state1, "test-server")

      # Verify failures are recorded
      server_after_failures = state2.servers["test-server"]
      assert server_after_failures.health.consecutive_failures == 2

      # Record a success
      state3 = Core.record_server_success(state2, "test-server", 100)

      updated_server = state3.servers["test-server"]
      health = updated_server.health

      assert health.consecutive_failures == 0
      assert health.is_healthy == true
      # 2 failures + 1 success
      assert health.total_requests == 3
      assert health.successful_requests == 1
      assert health.failed_requests == 2
    end
  end

  describe "Core health tracking integration with tool calls" do
    setup do
      # Create initial state with a connected server
      server = Server.new("test-server", %{command: ["test"]})
      # Create a real PID for testing
      pid = spawn(fn -> :ok end)
      monitor_ref = make_ref()
      connected_server = Server.mark_connected(server, pid, monitor_ref)

      state = %{
        servers: %{"test-server" => connected_server},
        supervisor: nil
      }

      {:ok, %{state: state, server: connected_server, pid: pid}}
    end

    test "call_tool/4 records success on successful tool call", %{state: state, pid: pid} do
      tool_name = "test_tool"
      arguments = %{"param" => "value"}

      # Mock ServerWrapper.call_tool to return success
      :meck.new(MCPChat.MCP.ServerWrapper, [:passthrough])

      :meck.expect(MCPChat.MCP.ServerWrapper, :call_tool, fn ^pid, ^tool_name, ^arguments ->
        {:ok, %{"result" => "success"}}
      end)

      :meck.new(MCPChat.MCP.HealthMonitor, [:passthrough])

      :meck.expect(MCPChat.MCP.HealthMonitor, :record_success, fn "test-server", response_time
                                                                  when is_number(response_time) ->
        :ok
      end)

      try do
        result = Core.call_tool(state, "test-server", tool_name, arguments)

        assert {:ok, %{"result" => "success"}} = result

        # Verify that health monitoring was called (with any response time)
        history = :meck.history(MCPChat.MCP.HealthMonitor)

        success_calls =
          Enum.filter(history, fn {_pid, {_mod, :record_success, [server, _time]}, _result} ->
            server == "test-server"
          end)

        assert length(success_calls) > 0
      after
        :meck.unload(MCPChat.MCP.ServerWrapper)
        :meck.unload(MCPChat.MCP.HealthMonitor)
      end
    end

    test "call_tool/4 records failure on failed tool call", %{state: state, pid: pid} do
      tool_name = "test_tool"
      arguments = %{"param" => "value"}

      # Mock ServerWrapper.call_tool to return error
      :meck.new(MCPChat.MCP.ServerWrapper, [:passthrough])
      :meck.expect(MCPChat.MCP.ServerWrapper, :call_tool, fn ^pid, ^tool_name, ^arguments -> {:error, :timeout} end)

      :meck.new(MCPChat.MCP.HealthMonitor, [:passthrough])
      :meck.expect(MCPChat.MCP.HealthMonitor, :record_failure, fn "test-server" -> :ok end)

      try do
        result = Core.call_tool(state, "test-server", tool_name, arguments)

        assert {:error, :timeout} = result

        # Verify that health monitoring was called
        assert :meck.num_calls(MCPChat.MCP.HealthMonitor, :record_failure, ["test-server"]) > 0
      after
        :meck.unload(MCPChat.MCP.ServerWrapper)
        :meck.unload(MCPChat.MCP.HealthMonitor)
      end
    end

    test "call_tool/4 returns error for non-existent server", %{state: state} do
      result = Core.call_tool(state, "nonexistent-server", "tool", %{})

      assert {:error, :server_not_found} = result
    end

    test "call_tool/4 returns error for disconnected server", %{state: state} do
      # Update server to disconnected status
      disconnected_server = Server.mark_disconnected(state.servers["test-server"])
      updated_state = %{state | servers: %{"test-server" => disconnected_server}}

      result = Core.call_tool(updated_state, "test-server", "tool", %{})

      assert {:error, :server_not_connected} = result
    end

    test "call_tool/4 measures response time accurately", %{state: state, pid: pid} do
      tool_name = "test_tool"
      arguments = %{}

      # Mock ServerWrapper.call_tool with a delay
      :meck.new(MCPChat.MCP.ServerWrapper, [:passthrough])

      :meck.expect(MCPChat.MCP.ServerWrapper, :call_tool, fn ^pid, ^tool_name, ^arguments ->
        # Simulate 50ms delay
        Process.sleep(50)
        {:ok, %{"result" => "success"}}
      end)

      {:ok, captured_response_time} = Agent.start_link(fn -> nil end)

      :meck.new(MCPChat.MCP.HealthMonitor, [:passthrough])

      :meck.expect(MCPChat.MCP.HealthMonitor, :record_success, fn "test-server", response_time ->
        Agent.update(captured_response_time, fn _ -> response_time end)
        :ok
      end)

      try do
        result = Core.call_tool(state, "test-server", tool_name, arguments)

        assert {:ok, %{"result" => "success"}} = result

        # Check that response time was measured (should be >= 50ms)
        response_time = Agent.get(captured_response_time, & &1)
        assert is_number(response_time)
        # Allow some tolerance for timing
        assert response_time >= 40
      after
        :meck.unload(MCPChat.MCP.ServerWrapper)
        :meck.unload(MCPChat.MCP.HealthMonitor)
        Agent.stop(captured_response_time)
      end
    end
  end

  describe "Core server info retrieval with health data" do
    setup do
      # Create initial state with multiple servers in different states
      server1 =
        Server.new("healthy-server", %{command: ["test"]})
        |> Server.mark_connected(spawn(fn -> :ok end), make_ref())
        |> Server.record_success(100)
        |> Server.record_success(150)

      server2 =
        Server.new("unhealthy-server", %{command: ["test"]})
        |> Server.mark_connected(spawn(fn -> :ok end), make_ref())
        |> Server.record_failure()
        |> Server.record_failure()
        |> Server.record_failure()

      server3 =
        Server.new("failed-server", %{command: ["test"]})
        |> Server.mark_failed(:connection_error)

      state = %{
        servers: %{
          "healthy-server" => server1,
          "unhealthy-server" => server2,
          "failed-server" => server3
        },
        supervisor: nil
      }

      {:ok, %{state: state}}
    end

    test "get_server_info/2 returns server with health data", %{state: state} do
      {:ok, server} = Core.get_server_info(state, "healthy-server")

      assert server.name == "healthy-server"
      assert server.status == :connected
      assert server.health.total_requests == 2
      assert server.health.successful_requests == 2
      assert server.health.is_healthy == true
    end

    test "get_server_info/2 returns error for non-existent server", %{state: state} do
      result = Core.get_server_info(state, "nonexistent-server")

      assert {:error, :not_found} = result
    end

    test "list_servers_with_status/1 includes health information", %{state: state} do
      servers = Core.list_servers_with_status(state)

      # Should include builtin server plus our 3 test servers
      assert length(servers) == 4

      # Find our test servers
      healthy_server = Enum.find(servers, &(&1.name == "healthy-server"))
      unhealthy_server = Enum.find(servers, &(&1.name == "unhealthy-server"))
      failed_server = Enum.find(servers, &(&1.name == "failed-server"))

      assert healthy_server != nil
      assert healthy_server.server.health.is_healthy == true

      assert unhealthy_server != nil
      assert unhealthy_server.server.health.is_healthy == false

      assert failed_server != nil
      assert failed_server.server.status == :failed
    end
  end
end
