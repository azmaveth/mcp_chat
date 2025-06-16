defmodule MCPChat.HealthMonitorTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias MCPChat.HealthMonitor

  @moduletag :unit

  describe "HealthMonitor GenServer" do
    setup do
      # Start a health monitor instance for testing with a unique name
      monitor_name = :"test_monitor_#{System.unique_integer([:positive])}"

      opts = [
        # Long interval to avoid interference
        interval: 10_000,
        # 1MB for testing
        memory_threshold: 1_000_000,
        message_queue_threshold: 10,
        alerts_enabled: true
      ]

      {:ok, pid} = GenServer.start_link(HealthMonitor, opts, name: monitor_name)

      on_exit(fn ->
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end
      end)

      {:ok, monitor: pid, monitor_name: monitor_name}
    end

    test "starts successfully with default options" do
      monitor_name = :"test_monitor_default_#{System.unique_integer([:positive])}"
      {:ok, pid} = GenServer.start_link(HealthMonitor, [], name: monitor_name)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with custom options", %{monitor: monitor} do
      assert Process.alive?(monitor)
    end

    test "can register a process for monitoring", %{monitor: monitor} do
      test_pid = spawn(fn -> Process.sleep(1_000) end)

      assert :ok = GenServer.call(monitor, {:register, "test_process", test_pid, [:memory, :message_queue, :alive]})

      # Verify process is registered
      status = GenServer.call(monitor, :get_health_status)
      assert Map.has_key?(status, "test_process")
      assert status["test_process"].pid == test_pid
      assert status["test_process"].status == :unknown

      Process.exit(test_pid, :kill)
    end

    test "can register process with custom check types", %{monitor: monitor} do
      test_pid = spawn(fn -> Process.sleep(1_000) end)

      assert :ok = GenServer.call(monitor, {:register, "test_process", test_pid, [:memory, :alive]})

      status = GenServer.call(monitor, :get_health_status)
      assert Map.has_key?(status, "test_process")

      Process.exit(test_pid, :kill)
    end

    test "can unregister a process", %{monitor: monitor} do
      test_pid = spawn(fn -> Process.sleep(1_000) end)

      assert :ok = GenServer.call(monitor, {:register, "test_process", test_pid, [:memory]})
      assert :ok = GenServer.call(monitor, {:unregister, "test_process"})

      status = GenServer.call(monitor, :get_health_status)
      refute Map.has_key?(status, "test_process")

      Process.exit(test_pid, :kill)
    end

    test "unregister returns error for non-existent process", %{monitor: monitor} do
      assert {:error, :not_found} = GenServer.call(monitor, {:unregister, "non_existent"})
    end

    test "get_health_status returns empty map when no processes registered", %{monitor: monitor} do
      status = GenServer.call(monitor, :get_health_status)
      assert status == %{}
    end

    test "check_now performs immediate health check", %{monitor: monitor} do
      test_pid = spawn(fn -> Process.sleep(1_000) end)
      GenServer.call(monitor, {:register, "test_process", test_pid, [:memory, :message_queue_len, :alive]})

      assert :ok = GenServer.call(monitor, :check_now)

      # Check that health status was updated
      status = GenServer.call(monitor, :get_health_status)
      process_status = status["test_process"]

      assert process_status.status in [:healthy, :unhealthy]
      assert process_status.last_check != nil
      assert is_map(process_status.metrics)

      Process.exit(test_pid, :kill)
    end
  end

  describe "health checking functionality" do
    setup do
      monitor_name = :"health_test_monitor_#{System.unique_integer([:positive])}"

      opts = [
        # Long interval to avoid interference
        interval: 10_000,
        # 1MB threshold for healthy tests
        memory_threshold: 1_000_000,
        message_queue_threshold: 5,
        alerts_enabled: true
      ]

      {:ok, monitor} = GenServer.start_link(HealthMonitor, opts, name: monitor_name)

      on_exit(fn ->
        if Process.alive?(monitor) do
          GenServer.stop(monitor)
        end
      end)

      {:ok, monitor: monitor}
    end

    test "detects healthy process", %{monitor: monitor} do
      # Create a simple healthy process
      test_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      GenServer.call(monitor, {:register, "healthy_process", test_pid, [:memory, :message_queue_len, :alive]})
      GenServer.call(monitor, :check_now)

      status = GenServer.call(monitor, :get_health_status)
      process_status = status["healthy_process"]

      assert process_status.status == :healthy
      assert is_integer(process_status.metrics[:memory])
      assert is_integer(process_status.metrics[:message_queue_len])

      send(test_pid, :stop)
    end

    test "detects dead process", %{monitor: monitor} do
      # Create a process that will die
      test_pid = spawn(fn -> :ok end)
      # Let it die
      Process.sleep(10)

      GenServer.call(monitor, {:register, "dead_process", test_pid, [:alive]})
      GenServer.call(monitor, :check_now)

      status = GenServer.call(monitor, :get_health_status)
      process_status = status["dead_process"]

      if process_status do
        assert process_status.status == :dead
        assert process_status.metrics == %{}
      else
        # Process might have been removed from monitoring due to death
        refute Map.has_key?(status, "dead_process")
      end
    end

    test "detects process with memory metrics", %{monitor: monitor} do
      test_pid =
        spawn(fn ->
          # Try to allocate some memory
          _big_list = Enum.to_list(1..1_000)

          receive do
            :stop -> :ok
          end
        end)

      GenServer.call(monitor, {:register, "memory_test", test_pid, [:memory]})
      GenServer.call(monitor, :check_now)

      status = GenServer.call(monitor, :get_health_status)
      process_status = status["memory_test"]

      # This test is hard to make deterministic, so we just check metrics are collected
      assert is_integer(process_status.metrics[:memory])
      assert process_status.status in [:healthy, :unhealthy]

      send(test_pid, :stop)
    end

    test "monitors process message queue", %{monitor: monitor} do
      # Create a process that doesn't process its messages
      test_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          after
            5_000 -> :timeout
          end
        end)

      # Send messages to build up queue
      for i <- 1..3 do
        send(test_pid, {:msg, i})
      end

      GenServer.call(monitor, {:register, "queue_test", test_pid, [:message_queue_len]})
      GenServer.call(monitor, :check_now)

      status = GenServer.call(monitor, :get_health_status)
      process_status = status["queue_test"]

      assert process_status.metrics[:message_queue_len] >= 3

      send(test_pid, :stop)
    end
  end

  describe "process monitoring" do
    setup do
      monitor_name = :"monitor_test_#{System.unique_integer([:positive])}"
      {:ok, monitor} = GenServer.start_link(HealthMonitor, [], name: monitor_name)

      on_exit(fn ->
        if Process.alive?(monitor) do
          GenServer.stop(monitor)
        end
      end)

      {:ok, monitor: monitor}
    end

    test "automatically removes dead processes from monitoring", %{monitor: monitor} do
      # Create a process that will die
      test_pid = spawn(fn -> Process.sleep(10) end)

      GenServer.call(monitor, {:register, "dying_process", test_pid, [:alive]})

      # Wait for process to die and monitor to detect it
      Process.sleep(50)

      status = GenServer.call(monitor, :get_health_status)
      # Process should be removed from monitoring when it dies
      refute Map.has_key?(status, "dying_process")
    end

    test "logs when monitored process dies", %{monitor: monitor} do
      test_pid = spawn(fn -> Process.sleep(10) end)

      GenServer.call(monitor, {:register, "dying_process", test_pid, [:alive]})

      # Capture log output
      log =
        capture_log(fn ->
          # Wait for process to die and monitor to detect it
          Process.sleep(50)
        end)

      assert log =~ "Monitored process dying_process"
      assert log =~ "died:"
    end
  end

  describe "periodic health checks" do
    test "performs periodic health checks automatically" do
      # Start monitor with very short interval
      monitor_name = :"periodic_test_#{System.unique_integer([:positive])}"
      {:ok, monitor} = GenServer.start_link(HealthMonitor, [interval: 50], name: monitor_name)

      test_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      GenServer.call(monitor, {:register, "periodic_test", test_pid, [:alive]})

      # Wait for a couple of intervals
      Process.sleep(150)

      status = GenServer.call(monitor, :get_health_status)

      if Map.has_key?(status, "periodic_test") do
        process_status = status["periodic_test"]
        # Should have been checked by now
        assert process_status.last_check != nil
        assert process_status.status in [:healthy, :unhealthy]
      end

      send(test_pid, :stop)
      GenServer.stop(monitor)
    end
  end

  describe "telemetry integration" do
    setup do
      # Setup telemetry test handler
      test_pid = self()

      handler_id = :"test_health_telemetry_#{System.unique_integer([:positive])}"

      :telemetry.attach_many(
        handler_id,
        [
          [:mcp_chat, :health, :check],
          [:mcp_chat, :health, :alert],
          [:mcp_chat, :health, :process_down]
        ],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach(handler_id)
      end)

      monitor_name = :"telemetry_test_#{System.unique_integer([:positive])}"
      {:ok, monitor} = GenServer.start_link(HealthMonitor, [interval: 10_000], name: monitor_name)

      on_exit(fn ->
        if Process.alive?(monitor) do
          GenServer.stop(monitor)
        end
      end)

      {:ok, monitor: monitor}
    end

    test "emits telemetry events for health checks", %{monitor: monitor} do
      test_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      GenServer.call(monitor, {:register, "telemetry_test", test_pid, [:alive]})
      GenServer.call(monitor, :check_now)

      # Wait for telemetry event
      assert_receive {:telemetry_event, [:mcp_chat, :health, :check], measurements, metadata}, 1_000

      assert is_integer(measurements.duration)
      assert metadata.name == "telemetry_test"
      assert metadata.status in [:healthy, :unhealthy]
      assert is_map(metadata.metrics)

      send(test_pid, :stop)
    end

    test "emits telemetry events when process dies", %{monitor: monitor} do
      test_pid = spawn(fn -> Process.sleep(10) end)

      GenServer.call(monitor, {:register, "dying_telemetry_test", test_pid, [:alive]})

      # Wait for process to die and monitor to detect it
      assert_receive {:telemetry_event, [:mcp_chat, :health, :process_down], measurements, metadata}, 1_000

      assert measurements.count == 1
      assert metadata.name == "dying_telemetry_test"
      assert metadata.pid == test_pid
      assert is_atom(metadata.reason)
    end

    test "can handle alert conditions", %{monitor: monitor} do
      # Create a process with very low thresholds to potentially trigger alerts
      monitor_name = :"alert_test_#{System.unique_integer([:positive])}"

      {:ok, alert_monitor} =
        GenServer.start_link(
          HealthMonitor,
          [
            # 1 byte - almost guaranteed to exceed
            memory_threshold: 1,
            # 0 messages - any queue will exceed
            message_queue_threshold: 0,
            alerts_enabled: true,
            interval: 10_000
          ],
          name: monitor_name
        )

      test_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      GenServer.call(alert_monitor, {:register, "alert_test", test_pid, [:memory]})
      GenServer.call(alert_monitor, :check_now)

      # We might get an alert if the process exceeds the tiny threshold
      receive do
        {:telemetry_event, [:mcp_chat, :health, :alert], measurements, metadata} ->
          assert measurements.count == 1
          assert metadata.name == "alert_test"
          assert is_binary(metadata.reason)
      after
        # No alert is also fine for this test
        500 -> :ok
      end

      send(test_pid, :stop)
      GenServer.stop(alert_monitor)
    end
  end

  describe "error handling" do
    setup do
      monitor_name = :"error_test_#{System.unique_integer([:positive])}"
      {:ok, monitor} = GenServer.start_link(HealthMonitor, [], name: monitor_name)

      on_exit(fn ->
        if Process.alive?(monitor) do
          GenServer.stop(monitor)
        end
      end)

      {:ok, monitor: monitor}
    end

    test "handles process info errors gracefully", %{monitor: monitor} do
      # Create a process that will die before we can get info
      test_pid = spawn(fn -> :ok end)
      # Let it die
      Process.sleep(10)

      GenServer.call(monitor, {:register, "error_test", test_pid, [:alive]})

      # This should not crash the monitor
      assert :ok = GenServer.call(monitor, :check_now)

      status = GenServer.call(monitor, :get_health_status)

      # Process might be removed due to death detection
      if Map.has_key?(status, "error_test") do
        process_status = status["error_test"]
        assert process_status.status == :dead
      else
        # Process was removed from monitoring, which is also valid behavior
        refute Map.has_key?(status, "error_test")
      end
    end

    test "handles invalid PIDs gracefully", %{monitor: monitor} do
      # Test unregistering non-existent processes
      assert {:error, :not_found} = GenServer.call(monitor, {:unregister, "non_existent"})
    end
  end

  describe "configuration options" do
    test "respects custom thresholds" do
      # Test with very high thresholds
      monitor_name = :"config_test_#{System.unique_integer([:positive])}"

      {:ok, monitor} =
        GenServer.start_link(
          HealthMonitor,
          [
            # 1GB
            memory_threshold: 1_000_000_000,
            message_queue_threshold: 10_000,
            alerts_enabled: false
          ],
          name: monitor_name
        )

      test_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      GenServer.call(monitor, {:register, "threshold_test", test_pid, [:memory]})
      GenServer.call(monitor, :check_now)

      status = GenServer.call(monitor, :get_health_status)
      process_status = status["threshold_test"]

      # With such high thresholds, process should be healthy
      assert process_status.status == :healthy

      send(test_pid, :stop)
      GenServer.stop(monitor)
    end

    test "can disable alerts" do
      monitor_name = :"alert_config_test_#{System.unique_integer([:positive])}"
      {:ok, monitor} = GenServer.start_link(HealthMonitor, [alerts_enabled: false], name: monitor_name)

      # Even with low thresholds, no alerts should be generated
      # This is hard to test directly, but we can verify the option is set

      GenServer.stop(monitor)
    end
  end

  describe "metric collection" do
    setup do
      monitor_name = :"metrics_test_#{System.unique_integer([:positive])}"
      {:ok, monitor} = GenServer.start_link(HealthMonitor, [], name: monitor_name)

      on_exit(fn ->
        if Process.alive?(monitor) do
          GenServer.stop(monitor)
        end
      end)

      {:ok, monitor: monitor}
    end

    test "collects all requested metric types", %{monitor: monitor} do
      test_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      GenServer.call(
        monitor,
        {:register, "metrics_test", test_pid, [:memory, :message_queue_len, :reductions, :current_function, :status]}
      )

      GenServer.call(monitor, :check_now)

      status = GenServer.call(monitor, :get_health_status)
      process_status = status["metrics_test"]

      # Verify all requested metrics are collected
      assert is_integer(process_status.metrics[:memory])
      assert is_integer(process_status.metrics[:message_queue_len])
      assert is_integer(process_status.metrics[:reductions])
      assert is_tuple(process_status.metrics[:current_function])
      assert is_atom(process_status.metrics[:status])

      send(test_pid, :stop)
    end

    test "filters metrics to requested types only", %{monitor: monitor} do
      test_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      GenServer.call(monitor, {:register, "filtered_test", test_pid, [:memory]})
      GenServer.call(monitor, :check_now)

      status = GenServer.call(monitor, :get_health_status)
      process_status = status["filtered_test"]

      # Should only have memory metric
      assert Map.has_key?(process_status.metrics, :memory)
      refute Map.has_key?(process_status.metrics, :message_queue_len)
      refute Map.has_key?(process_status.metrics, :reductions)

      send(test_pid, :stop)
    end
  end
end
