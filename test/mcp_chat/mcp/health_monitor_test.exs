defmodule MCPChat.MCP.HealthMonitorTest do
  use ExUnit.Case, async: false

  alias MCPChat.MCP.HealthMonitor
  alias MCPChat.MCP.ServerManager

  # Import test helpers
  import ExUnit.CaptureLog

  describe "HealthMonitor GenServer" do
    setup do
      # The health monitor is already started by the application, so we just get the PID
      pid = Process.whereis(HealthMonitor)
      {:ok, %{monitor_pid: pid}}
    end

    test "starts successfully", %{monitor_pid: pid} do
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "get_health_metrics returns empty list when no servers" do
      # Mock ServerManager to return empty list
      :meck.new(ServerManager, [:passthrough])
      :meck.expect(ServerManager, :list_servers_with_status, fn -> [] end)

      try do
        metrics = HealthMonitor.get_health_metrics()
        assert metrics == []
      after
        :meck.unload(ServerManager)
      end
    end

    test "get_health_metrics returns server metrics" do
      # Create a mock server with health data
      mock_server = %MCPChat.MCP.ServerManager.Server{
        name: "test-server",
        status: :connected,
        health: %{
          uptime_start: DateTime.utc_now(),
          total_requests: 10,
          successful_requests: 8,
          failed_requests: 2,
          avg_response_time: 150.0,
          last_ping: DateTime.utc_now(),
          consecutive_failures: 0,
          is_healthy: true
        }
      }

      mock_servers = [%{name: "test-server", server: mock_server}]

      :meck.new(ServerManager, [:passthrough])
      :meck.expect(ServerManager, :list_servers_with_status, fn -> mock_servers end)

      try do
        metrics = HealthMonitor.get_health_metrics()

        assert length(metrics) == 1
        [metric] = metrics

        assert metric.name == "test-server"
        assert metric.status == :connected
        assert metric.health_status == :healthy
        assert metric.total_requests == 10
        assert metric.consecutive_failures == 0
      after
        :meck.unload(ServerManager)
      end
    end

    test "force_health_check triggers health check" do
      # This is an integration test that verifies the cast is handled
      assert :ok = HealthMonitor.force_health_check()
    end

    test "record_success updates server metrics" do
      # Mock ServerManager to accept the record_success call
      :meck.new(ServerManager, [:passthrough])
      :meck.expect(ServerManager, :record_server_success, fn "test-server", 100 -> :ok end)

      try do
        # Test that the function executes successfully
        assert :ok = HealthMonitor.record_success("test-server", 100)

        # Sleep briefly to allow the GenServer cast to be processed
        Process.sleep(10)

        # Check that the mock was called using meck's history
        assert :meck.num_calls(ServerManager, :record_server_success, ["test-server", 100]) > 0
      after
        :meck.unload(ServerManager)
      end
    end

    test "record_failure updates server metrics and checks health" do
      # Mock ServerManager and server info
      mock_server = %MCPChat.MCP.ServerManager.Server{
        name: "test-server",
        status: :connected,
        health: %{consecutive_failures: 3, is_healthy: false}
      }

      :meck.new(ServerManager, [:passthrough])
      :meck.expect(ServerManager, :record_server_failure, fn "test-server" -> :ok end)
      :meck.expect(ServerManager, :get_server_info, fn "test-server" -> {:ok, mock_server} end)
      :meck.expect(ServerManager, :disable_unhealthy_server, fn "test-server" -> :ok end)

      try do
        # Capture logs to verify warning is logged
        log =
          capture_log(fn ->
            assert :ok = HealthMonitor.record_failure("test-server")
            # Give the GenServer time to process the cast
            Process.sleep(50)
          end)

        # Verify the mocks were called
        assert :meck.num_calls(ServerManager, :record_server_failure, ["test-server"]) > 0
        assert :meck.num_calls(ServerManager, :get_server_info, ["test-server"]) > 0
        assert :meck.num_calls(ServerManager, :disable_unhealthy_server, ["test-server"]) > 0

        # Verify warning was logged
        assert log =~ "Server 'test-server' marked as unhealthy, auto-disabling"
      after
        :meck.unload(ServerManager)
      end
    end
  end

  describe "HealthMonitor ping operations" do
    setup do
      # The health monitor is already started by the application, so we just get the PID
      pid = Process.whereis(HealthMonitor)
      {:ok, %{monitor_pid: pid}}
    end

    test "ping_server with successful response records success" do
      # Create a mock server with a valid PID
      mock_pid = spawn(fn -> :ok end)

      mock_server_info = %{
        name: "test-server",
        server: %MCPChat.MCP.ServerManager.Server{
          name: "test-server",
          pid: mock_pid,
          status: :connected
        }
      }

      :meck.new(MCPChat.MCP.ServerWrapper, [:passthrough])
      :meck.expect(MCPChat.MCP.ServerWrapper, :get_tools, fn ^mock_pid -> {:ok, []} end)

      :meck.new(HealthMonitor, [:passthrough])
      :meck.expect(HealthMonitor, :record_success, fn "test-server", _response_time -> :ok end)

      :meck.new(ServerManager, [:passthrough])
      :meck.expect(ServerManager, :list_servers_with_status, fn -> [mock_server_info] end)

      try do
        # Call the private ping_server function via the public interface
        # We'll test this indirectly through perform_health_checks
        HealthMonitor.force_health_check()
        # Give time for async processing
        Process.sleep(50)

        # Verify that get_tools was called
        assert :meck.num_calls(MCPChat.MCP.ServerWrapper, :get_tools, [mock_pid]) > 0
      after
        :meck.unload(MCPChat.MCP.ServerWrapper)
        :meck.unload(HealthMonitor)
        :meck.unload(ServerManager)
      end
    end

    test "ping_server with failed response records failure" do
      # Create a mock server with a valid PID
      mock_pid = spawn(fn -> :ok end)

      mock_server_info = %{
        name: "test-server",
        server: %MCPChat.MCP.ServerManager.Server{
          name: "test-server",
          pid: mock_pid,
          status: :connected
        }
      }

      :meck.new(MCPChat.MCP.ServerWrapper, [:passthrough])
      :meck.expect(MCPChat.MCP.ServerWrapper, :get_tools, fn ^mock_pid -> {:error, :timeout} end)

      :meck.new(HealthMonitor, [:passthrough])
      :meck.expect(HealthMonitor, :record_failure, fn "test-server" -> :ok end)

      :meck.new(ServerManager, [:passthrough])
      :meck.expect(ServerManager, :list_servers_with_status, fn -> [mock_server_info] end)

      try do
        # Capture the warning log
        log =
          capture_log(fn ->
            HealthMonitor.force_health_check()
            # Give time for async processing
            Process.sleep(50)
          end)

        # Verify that get_tools was called and failure was logged
        assert :meck.num_calls(MCPChat.MCP.ServerWrapper, :get_tools, [mock_pid]) > 0
        assert log =~ "Health check failed for server 'test-server'"
      after
        :meck.unload(MCPChat.MCP.ServerWrapper)
        :meck.unload(HealthMonitor)
        :meck.unload(ServerManager)
      end
    end
  end
end
