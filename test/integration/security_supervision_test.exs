defmodule MCPChat.SecuritySupervisionTest do
  @moduledoc """
  Integration tests for security modules in the supervision tree.

  Tests that security components start correctly, handle failures gracefully,
  and integrate properly with the overall application architecture.
  """

  use ExUnit.Case, async: false

  alias MCPChat.Security.{SecurityKernel, AuditLogger}

  @moduletag :integration
  @moduletag :supervision

  describe "security module supervision" do
    test "security modules start with application" do
      # Verify that security modules are running as part of the application
      assert Process.whereis(SecurityKernel) != nil
      assert Process.whereis(AuditLogger) != nil

      # Verify they are alive and responding
      assert Process.alive?(Process.whereis(SecurityKernel))
      assert Process.alive?(Process.whereis(AuditLogger))
    end

    test "security modules can handle basic operations" do
      # Test that the supervised security modules work correctly
      assert {:ok, capability} =
               SecurityKernel.request_capability(
                 :filesystem,
                 %{paths: ["/tmp"]},
                 "supervision_test"
               )

      assert is_binary(capability.id)

      # Test audit logging
      AuditLogger.log_event_sync(:supervision_test, %{test: "data"}, "supervision_test")

      stats = AuditLogger.get_stats()
      assert stats.events_logged >= 1
    end

    test "security kernel handles restart correctly" do
      original_pid = Process.whereis(SecurityKernel)
      assert original_pid != nil

      # Create some test data
      {:ok, capability} =
        SecurityKernel.request_capability(
          :filesystem,
          %{paths: ["/tmp"]},
          "restart_test"
        )

      # Verify capability exists
      assert {:ok, capabilities} = SecurityKernel.list_capabilities("restart_test")
      assert length(capabilities) == 1

      # Simulate a crash by stopping the process
      GenServer.stop(original_pid, :kill)

      # Give supervisor time to restart
      Process.sleep(100)

      # Verify a new process was started
      new_pid = Process.whereis(SecurityKernel)
      assert new_pid != nil
      assert new_pid != original_pid

      # Verify the new process is working (state will be lost, which is expected)
      assert {:ok, new_capability} =
               SecurityKernel.request_capability(
                 :filesystem,
                 %{paths: ["/tmp"]},
                 "restart_test_new"
               )

      assert is_binary(new_capability.id)
    end

    test "audit logger handles restart correctly" do
      original_pid = Process.whereis(AuditLogger)
      assert original_pid != nil

      # Log some events
      AuditLogger.log_event_sync(:before_restart, %{}, "restart_test")

      initial_stats = AuditLogger.get_stats()
      assert initial_stats.events_logged >= 1

      # Simulate a crash
      GenServer.stop(original_pid, :kill)

      # Give supervisor time to restart
      Process.sleep(100)

      # Verify a new process was started
      new_pid = Process.whereis(AuditLogger)
      assert new_pid != nil
      assert new_pid != original_pid

      # Verify the new process is working
      AuditLogger.log_event_sync(:after_restart, %{}, "restart_test")

      # Stats will be reset after restart
      new_stats = AuditLogger.get_stats()
      assert new_stats.events_logged >= 1
    end

    test "security system survives individual component failures" do
      # Get initial pids
      kernel_pid = Process.whereis(SecurityKernel)
      logger_pid = Process.whereis(AuditLogger)

      # Kill the audit logger
      GenServer.stop(logger_pid, :kill)
      Process.sleep(50)

      # Security kernel should still work
      assert {:ok, capability} =
               SecurityKernel.request_capability(
                 :filesystem,
                 %{paths: ["/tmp"]},
                 "component_failure_test"
               )

      assert is_binary(capability.id)
      assert Process.alive?(kernel_pid)

      # Audit logger should have restarted
      new_logger_pid = Process.whereis(AuditLogger)
      assert new_logger_pid != nil
      assert new_logger_pid != logger_pid
      assert Process.alive?(new_logger_pid)
    end
  end

  describe "application integration" do
    test "security system integrates with PubSub" do
      # Verify PubSub is available (needed for agent architecture)
      pubsub_pid = Process.whereis(MCPChat.PubSub)
      assert pubsub_pid != nil

      # Test that security events could be published (if implemented)
      # This is a placeholder for future event integration
      assert Process.alive?(pubsub_pid)
    end

    test "security configuration is loaded correctly" do
      # Test that security modules respect application configuration

      # Security should be enabled by default
      assert MCPChat.Security.security_enabled?()

      # Test configuration override
      original_value = Application.get_env(:mcp_chat, :security_enabled, true)

      try do
        Application.put_env(:mcp_chat, :security_enabled, false)
        assert not MCPChat.Security.security_enabled?()
      after
        Application.put_env(:mcp_chat, :security_enabled, original_value)
      end
    end

    test "security modules handle application shutdown gracefully" do
      # Test that security modules can handle shutdown signals
      kernel_pid = Process.whereis(SecurityKernel)
      logger_pid = Process.whereis(AuditLogger)

      # Send shutdown signal
      GenServer.stop(kernel_pid, :shutdown)
      GenServer.stop(logger_pid, :shutdown)

      # Give time for graceful shutdown
      Process.sleep(100)

      # Supervisor should restart them
      new_kernel_pid = Process.whereis(SecurityKernel)
      new_logger_pid = Process.whereis(AuditLogger)

      assert new_kernel_pid != nil
      assert new_logger_pid != nil
      assert new_kernel_pid != kernel_pid
      assert new_logger_pid != logger_pid
    end
  end

  describe "performance under supervision" do
    test "supervised security modules maintain performance" do
      # Test that supervision overhead doesn't significantly impact performance
      event_count = 100

      {time_microseconds, _result} =
        :timer.tc(fn ->
          Enum.each(1..event_count, fn i ->
            # Create capabilities
            SecurityKernel.request_capability(
              :filesystem,
              %{paths: ["/tmp/#{i}"]},
              "perf_test_#{i}"
            )

            # Log events
            AuditLogger.log_event(:perf_test, %{index: i}, "perf_test")
          end)

          # Ensure all operations complete
          AuditLogger.flush()
        end)

      # Should complete in reasonable time
      # Less than 1 second
      assert time_microseconds < 1_000_000

      # Verify operations succeeded
      stats = SecurityKernel.get_security_stats()
      assert stats.total_capabilities >= event_count

      audit_stats = AuditLogger.get_stats()
      assert audit_stats.events_flushed >= event_count
    end

    test "concurrent operations work correctly under supervision" do
      # Test concurrent operations across both security modules
      task_count = 20

      tasks =
        Enum.map(1..task_count, fn i ->
          Task.async(fn ->
            # Concurrent capability requests
            {:ok, capability} =
              SecurityKernel.request_capability(
                :filesystem,
                %{paths: ["/tmp/concurrent_#{i}"]},
                "concurrent_test_#{i}"
              )

            # Concurrent audit logging
            AuditLogger.log_event(:concurrent_test, %{task: i}, "concurrent_test_#{i}")

            # Validate the capability
            SecurityKernel.validate_capability(capability, :read, "/tmp/concurrent_#{i}/test.txt")
          end)
        end)

      results = Task.await_many(tasks, 5000)

      # All tasks should succeed
      assert Enum.all?(results, fn result -> result == :ok end)

      # Verify all operations were tracked
      stats = SecurityKernel.get_security_stats()
      assert stats.performance_stats.capabilities_created >= task_count
      assert stats.performance_stats.capabilities_validated >= task_count
    end
  end

  describe "fault tolerance" do
    test "system recovers from rapid component failures" do
      # Rapidly kill and restart components to test fault tolerance
      original_kernel = Process.whereis(SecurityKernel)
      original_logger = Process.whereis(AuditLogger)

      # Rapid failure simulation
      Enum.each(1..3, fn _i ->
        GenServer.stop(Process.whereis(SecurityKernel), :kill)
        GenServer.stop(Process.whereis(AuditLogger), :kill)
        # Brief pause for restart
        Process.sleep(50)
      end)

      # Give final time for stabilization
      Process.sleep(200)

      # Verify system is stable and working
      final_kernel = Process.whereis(SecurityKernel)
      final_logger = Process.whereis(AuditLogger)

      assert final_kernel != nil
      assert final_logger != nil
      assert final_kernel != original_kernel
      assert final_logger != original_logger

      # Verify functionality
      assert {:ok, capability} =
               SecurityKernel.request_capability(
                 :filesystem,
                 %{paths: ["/tmp"]},
                 "fault_tolerance_test"
               )

      AuditLogger.log_event_sync(:fault_tolerance_test, %{}, "fault_tolerance_test")

      assert is_binary(capability.id)
    end

    test "system handles resource exhaustion gracefully" do
      # Test behavior under memory/resource pressure
      # Create many capabilities to test memory usage
      large_count = 500

      capabilities =
        Enum.map(1..large_count, fn i ->
          {:ok, cap} =
            SecurityKernel.request_capability(
              :filesystem,
              %{paths: ["/tmp/stress_#{i}"]},
              # Reuse some principals
              "stress_test_#{rem(i, 10)}"
            )

          cap
        end)

      assert length(capabilities) == large_count

      # Verify system is still responsive
      stats = SecurityKernel.get_security_stats()
      assert stats.total_capabilities >= large_count

      # Test cleanup works under load
      SecurityKernel.cleanup_expired_capabilities()

      # System should still be responsive
      assert {:ok, _new_cap} =
               SecurityKernel.request_capability(
                 :filesystem,
                 %{paths: ["/tmp"]},
                 "post_stress_test"
               )
    end
  end

  describe "monitoring and observability" do
    test "security modules provide monitoring data" do
      # Test that supervised modules provide useful monitoring information

      # Security kernel stats
      kernel_stats = SecurityKernel.get_security_stats()
      assert is_map(kernel_stats)
      assert Map.has_key?(kernel_stats, :total_capabilities)
      assert Map.has_key?(kernel_stats, :performance_stats)

      # Audit logger stats
      audit_stats = AuditLogger.get_stats()
      assert is_map(audit_stats)
      assert Map.has_key?(audit_stats, :events_logged)
      assert Map.has_key?(audit_stats, :uptime)

      # Verify stats are realistic
      assert is_integer(kernel_stats.total_capabilities)
      assert is_integer(audit_stats.events_logged)
      assert audit_stats.uptime >= 0
    end

    test "modules handle health checks correctly" do
      # Verify modules respond to basic health checks

      # Test SecurityKernel health
      kernel_pid = Process.whereis(SecurityKernel)
      assert Process.alive?(kernel_pid)

      # Should respond to info messages
      send(kernel_pid, :health_check)
      # Give time to process
      Process.sleep(10)
      assert Process.alive?(kernel_pid)

      # Test AuditLogger health
      logger_pid = Process.whereis(AuditLogger)
      assert Process.alive?(logger_pid)

      send(logger_pid, :health_check)
      Process.sleep(10)
      assert Process.alive?(logger_pid)
    end
  end
end
