defmodule ServerManager.ServerTest do
  use ExUnit.Case

  alias ServerManager.Server

  alias ServerManager.ServerTest

  describe "Server struct creation and initialization" do
    test "new/2 creates server with initial health metrics" do
      config = %{command: ["test", "command"]}
      server = Server.new("test-server", config)

      assert server.name == "test-server"
      assert server.config == config
      assert server.status == :connecting
      assert server.pid == nil
      assert server.monitor_ref == nil
      assert server.error == nil
      assert server.connected_at == nil
      assert server.last_attempt != nil

      # Check initial health metrics
      health = server.health
      assert health.uptime_start == nil
      assert health.total_requests == 0
      assert health.successful_requests == 0
      assert health.failed_requests == 0
      assert health.avg_response_time == 0.0
      assert health.last_ping == nil
      assert health.consecutive_failures == 0
      assert health.is_healthy == true
    end
  end

  describe "Server status management" do
    setup do
      config = %{command: ["test"]}
      server = Server.new("test-server", config)
      {:ok, %{server: server}}
    end

    test "mark_connected/4 updates status and initializes health tracking", %{server: server} do
      pid = self()
      monitor_ref = make_ref()
      capabilities = %{tools: [], resources: [], prompts: []}

      connected_server = Server.mark_connected(server, pid, monitor_ref, capabilities)

      assert connected_server.status == :connected
      assert connected_server.pid == pid
      assert connected_server.monitor_ref == monitor_ref
      assert connected_server.capabilities == capabilities
      assert connected_server.error == nil
      assert connected_server.connected_at != nil

      # Check health metrics were initialized
      health = connected_server.health
      assert health.uptime_start != nil
      assert health.consecutive_failures == 0
      assert health.is_healthy == true
    end

    test "mark_failed/2 updates status and clears connection info", %{server: server} do
      error = :connection_failed
      failed_server = Server.mark_failed(server, error)

      assert failed_server.status == :failed
      assert failed_server.error == error
      assert failed_server.pid == nil
      assert failed_server.monitor_ref == nil
      assert failed_server.capabilities == %{tools: [], resources: [], prompts: []}
    end

    test "mark_disconnected/1 updates status and clears connection info", %{server: server} do
      disconnected_server = Server.mark_disconnected(server)

      assert disconnected_server.status == :disconnected
      assert disconnected_server.pid == nil
      assert disconnected_server.monitor_ref == nil
      assert disconnected_server.capabilities == %{tools: [], resources: [], prompts: []}
    end
  end

  describe "Server connection status" do
    setup do
      config = %{command: ["test"]}
      server = Server.new("test-server", config)
      {:ok, %{server: server}}
    end

    test "connected?/1 returns true for connected server with PID", %{server: server} do
      pid = self()
      monitor_ref = make_ref()
      connected_server = Server.mark_connected(server, pid, monitor_ref)

      assert Server.connected?(connected_server) == true
    end

    test "connected?/1 returns false for non-connected statuses", %{server: server} do
      # :connecting
      assert Server.connected?(server) == false

      failed_server = Server.mark_failed(server, :error)
      assert Server.connected?(failed_server) == false

      disconnected_server = Server.mark_disconnected(server)
      assert Server.connected?(disconnected_server) == false
    end

    test "connected?/1 returns false for connected status without PID", %{server: server} do
      # Manually create a server with connected status but no PID
      server_without_pid = %{server | status: :connected, pid: nil}
      assert Server.connected?(server_without_pid) == false
    end
  end

  describe "Server health metrics" do
    setup do
      config = %{command: ["test"]}
      server = Server.new("test-server", config)
      pid = self()
      monitor_ref = make_ref()
      connected_server = Server.mark_connected(server, pid, monitor_ref)
      {:ok, %{server: connected_server}}
    end

    test "record_success/2 updates health metrics correctly", %{server: server} do
      # Record first success
      server1 = Server.record_success(server, 100)
      health1 = server1.health

      assert health1.total_requests == 1
      assert health1.successful_requests == 1
      assert health1.failed_requests == 0
      assert health1.avg_response_time == 100.0
      assert health1.consecutive_failures == 0
      assert health1.is_healthy == true
      assert health1.last_ping != nil

      # Record second success with different response time
      server2 = Server.record_success(server1, 200)
      health2 = server2.health

      assert health2.total_requests == 2
      assert health2.successful_requests == 2
      assert health2.failed_requests == 0
      # (100 + 200) / 2
      assert health2.avg_response_time == 150.0
      assert health2.consecutive_failures == 0
      assert health2.is_healthy == true
    end

    test "record_failure/1 updates health metrics correctly", %{server: server} do
      # Record first failure
      server1 = Server.record_failure(server)
      health1 = server1.health

      assert health1.total_requests == 1
      assert health1.successful_requests == 0
      assert health1.failed_requests == 1
      assert health1.consecutive_failures == 1
      # Still healthy after 1 failure
      assert health1.is_healthy == true

      # Record second failure
      server2 = Server.record_failure(server1)
      health2 = server2.health

      assert health2.total_requests == 2
      assert health2.successful_requests == 0
      assert health2.failed_requests == 2
      assert health2.consecutive_failures == 2
      # Still healthy after 2 failures
      assert health2.is_healthy == true

      # Record third failure (should mark as unhealthy)
      server3 = Server.record_failure(server2)
      health3 = server3.health

      assert health3.total_requests == 3
      assert health3.successful_requests == 0
      assert health3.failed_requests == 3
      assert health3.consecutive_failures == 3
      # Unhealthy after 3 consecutive failures
      assert health3.is_healthy == false
    end

    test "record_success/2 resets consecutive failures", %{server: server} do
      # Record failures first
      server1 =
        server
        |> Server.record_failure()
        |> Server.record_failure()

      assert server1.health.consecutive_failures == 2

      # Record success should reset consecutive failures
      server2 = Server.record_success(server1, 100)
      health2 = server2.health

      assert health2.consecutive_failures == 0
      assert health2.is_healthy == true
      assert health2.total_requests == 3
      assert health2.successful_requests == 1
      assert health2.failed_requests == 2
    end
  end

  describe "Server health status" do
    setup do
      config = %{command: ["test"]}
      server = Server.new("test-server", config)
      pid = self()
      monitor_ref = make_ref()
      connected_server = Server.mark_connected(server, pid, monitor_ref)
      {:ok, %{server: connected_server}}
    end

    test "health_status/1 returns :healthy for healthy connected server", %{server: server} do
      assert Server.health_status(server) == :healthy
    end

    test "health_status/1 returns :unhealthy for unhealthy connected server", %{server: server} do
      # Make server unhealthy by recording 3 failures
      unhealthy_server =
        server
        |> Server.record_failure()
        |> Server.record_failure()
        |> Server.record_failure()

      assert Server.health_status(unhealthy_server) == :unhealthy
    end

    test "health_status/1 returns :unknown for non-connected server" do
      config = %{command: ["test"]}
      server = Server.new("test-server", config)

      # :connecting
      assert Server.health_status(server) == :unknown

      failed_server = Server.mark_failed(server, :error)
      assert Server.health_status(failed_server) == :unknown

      disconnected_server = Server.mark_disconnected(server)
      assert Server.health_status(disconnected_server) == :unknown
    end
  end

  describe "Server uptime and metrics" do
    setup do
      config = %{command: ["test"]}
      server = Server.new("test-server", config)
      pid = self()
      monitor_ref = make_ref()
      connected_server = Server.mark_connected(server, pid, monitor_ref)
      {:ok, %{server: connected_server}}
    end

    test "uptime_seconds/1 returns nil for server without uptime_start", %{server: _server} do
      config = %{command: ["test"]}
      new_server = Server.new("test-server", config)

      assert Server.uptime_seconds(new_server) == nil
    end

    test "uptime_seconds/1 returns positive integer for connected server", %{server: server} do
      # Sleep briefly to ensure uptime > 0
      Process.sleep(10)
      uptime = Server.uptime_seconds(server)

      assert is_integer(uptime)
      assert uptime >= 0
    end

    test "success_rate/1 returns 0.0 for server with no requests", %{server: server} do
      assert Server.success_rate(server) == 0.0
    end

    test "success_rate/1 calculates percentage correctly", %{server: server} do
      # Record mixed successes and failures
      server_with_activity =
        server
        |> Server.record_success(100)
        |> Server.record_success(200)
        |> Server.record_failure()
        |> Server.record_success(150)

      # 3 successes out of 4 total = 75%
      assert Server.success_rate(server_with_activity) == 75.0
    end
  end

  describe "Server capabilities and tools" do
    setup do
      config = %{command: ["test"]}
      server = Server.new("test-server", config)
      {:ok, %{server: server}}
    end

    test "get_tools/1 returns tools for connected server with tools", %{server: server} do
      pid = self()
      monitor_ref = make_ref()
      tools = [%{"name" => "test_tool", "description" => "A test tool"}]
      capabilities = %{tools: tools, resources: [], prompts: []}

      connected_server = Server.mark_connected(server, pid, monitor_ref, capabilities)

      assert Server.get_tools(connected_server) == tools
    end

    test "get_tools/1 returns empty list for non-connected server", %{server: server} do
      assert Server.get_tools(server) == []

      failed_server = Server.mark_failed(server, :error)
      assert Server.get_tools(failed_server) == []
    end

    test "get_resources/1 returns resources for connected server", %{server: server} do
      pid = self()
      monitor_ref = make_ref()
      resources = [%{"uri" => "test://resource", "name" => "Test Resource"}]
      capabilities = %{tools: [], resources: resources, prompts: []}

      connected_server = Server.mark_connected(server, pid, monitor_ref, capabilities)

      assert Server.get_resources(connected_server) == resources
    end

    test "get_prompts/1 returns prompts for connected server", %{server: server} do
      pid = self()
      monitor_ref = make_ref()
      prompts = [%{"name" => "test_prompt", "description" => "A test prompt"}]
      capabilities = %{tools: [], resources: [], prompts: prompts}

      connected_server = Server.mark_connected(server, pid, monitor_ref, capabilities)

      assert Server.get_prompts(connected_server) == prompts
    end
  end

  describe "Server status display" do
    setup do
      config = %{command: ["test"]}
      server = Server.new("test-server", config)
      {:ok, %{server: server}}
    end

    test "status_display/1 returns correct strings for each status", %{server: server} do
      assert Server.status_display(server) == "[CONNECTING]"

      pid = self()
      monitor_ref = make_ref()
      connected_server = Server.mark_connected(server, pid, monitor_ref)
      assert Server.status_display(connected_server) == "[CONNECTED]"

      failed_server = Server.mark_failed(server, :timeout)
      assert Server.status_display(failed_server) == "[FAILED: timeout]"

      disconnected_server = Server.mark_disconnected(server)
      assert Server.status_display(disconnected_server) == "[DISCONNECTED]"
    end

    test "status_display/1 handles different error formats", %{server: server} do
      # Test atom error
      failed_server1 = Server.mark_failed(server, :connection_refused)
      assert Server.status_display(failed_server1) == "[FAILED: connection_refused]"

      # Test string error
      failed_server2 = Server.mark_failed(server, "Network timeout")
      assert Server.status_display(failed_server2) == "[FAILED: Network timeout]"

      # Test tuple error
      failed_server3 = Server.mark_failed(server, {:error, :econnrefused})
      assert Server.status_display(failed_server3) == "[FAILED: econnrefused]"
    end
  end
end
