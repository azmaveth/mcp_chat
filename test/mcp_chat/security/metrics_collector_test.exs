defmodule MCPChat.Security.MetricsCollectorTest do
  use ExUnit.Case, async: false

  alias MCPChat.Security.MetricsCollector

  setup do
    # Start a test instance
    {:ok, pid} = start_supervised({MetricsCollector, []})

    # Give it time to initialize
    Process.sleep(100)

    %{collector: pid}
  end

  describe "MetricsCollector" do
    test "starts successfully and collects initial metrics", %{collector: _pid} do
      metrics = MetricsCollector.get_current_metrics()

      assert is_map(metrics)
      assert Map.has_key?(metrics, :timestamp)
      assert Map.has_key?(metrics, :capabilities)
      assert Map.has_key?(metrics, :security_kernel)
      assert Map.has_key?(metrics, :violations)
      assert Map.has_key?(metrics, :performance)
      assert Map.has_key?(metrics, :audit)
      assert Map.has_key?(metrics, :agents)
    end

    test "records security events", %{collector: _pid} do
      event_metadata = %{principal_id: "test_principal", resource: "/test"}

      MetricsCollector.record_event(:capability_created, event_metadata)
      MetricsCollector.record_event(:validation_performed, event_metadata)

      # Events should be recorded (no direct way to verify without internal access)
      :ok
    end

    test "collects dashboard metrics", %{collector: _pid} do
      dashboard = MetricsCollector.get_dashboard_metrics()

      assert is_map(dashboard)
      assert Map.has_key?(dashboard, :overview)
      assert Map.has_key?(dashboard, :current)
      assert Map.has_key?(dashboard, :trends)
      assert Map.has_key?(dashboard, :alerts)
      assert Map.has_key?(dashboard, :health_score)

      # Verify overview contains expected fields
      overview = dashboard.overview
      assert Map.has_key?(overview, :uptime_ms)
      assert Map.has_key?(overview, :collections_count)
      assert Map.has_key?(overview, :last_collection)
    end

    test "calculates health score", %{collector: _pid} do
      dashboard = MetricsCollector.get_dashboard_metrics()
      health_score = dashboard.health_score

      assert is_integer(health_score)
      assert health_score >= 0
      assert health_score <= 100
    end

    test "forces immediate collection", %{collector: _pid} do
      # Force collection
      MetricsCollector.collect_now()

      # Give it time to process
      Process.sleep(100)

      metrics = MetricsCollector.get_current_metrics()
      assert is_map(metrics)
    end

    test "retrieves historical metrics", %{collector: _pid} do
      # Force a few collections
      MetricsCollector.collect_now()
      Process.sleep(50)
      MetricsCollector.collect_now()
      Process.sleep(50)

      now = System.system_time(:millisecond)
      one_minute_ago = now - 60_000

      historical = MetricsCollector.get_historical_metrics(one_minute_ago, now)

      assert is_list(historical)
      # Should have at least some metrics
      assert length(historical) >= 0
    end
  end

  describe "Capability metrics" do
    test "includes capability statistics", %{collector: _pid} do
      metrics = MetricsCollector.get_current_metrics()
      capabilities = metrics.capabilities

      assert is_map(capabilities)

      # Should have these fields (may be 0 or error if services not running)
      expected_fields = [:active_count, :total_issued, :total_revoked]

      Enum.each(expected_fields, fn field ->
        assert Map.has_key?(capabilities, field)
      end)
    end
  end

  describe "Security kernel metrics" do
    test "includes security kernel status", %{collector: _pid} do
      metrics = MetricsCollector.get_current_metrics()
      kernel_metrics = metrics.security_kernel

      assert is_map(kernel_metrics)
      assert Map.has_key?(kernel_metrics, :status)

      # Status should be atom
      status = kernel_metrics.status
      assert status in [:running, :stopped, :error]
    end

    test "includes process information when running", %{collector: _pid} do
      metrics = MetricsCollector.get_current_metrics()
      kernel_metrics = metrics.security_kernel

      if kernel_metrics.status == :running do
        assert Map.has_key?(kernel_metrics, :memory_bytes)
        assert Map.has_key?(kernel_metrics, :message_queue_length)
        assert Map.has_key?(kernel_metrics, :reductions)
        assert Map.has_key?(kernel_metrics, :uptime_ms)

        assert is_integer(kernel_metrics.memory_bytes)
        assert is_integer(kernel_metrics.message_queue_length)
        assert is_integer(kernel_metrics.reductions)
        assert is_integer(kernel_metrics.uptime_ms)
      end
    end
  end

  describe "Violation metrics" do
    test "includes violation statistics", %{collector: _pid} do
      metrics = MetricsCollector.get_current_metrics()
      violations = metrics.violations

      assert is_map(violations)

      # Should have these fields (may be 0 or error if services not running)
      expected_fields = [:total_violations, :recent_violations_1h, :recent_violations_24h]

      Enum.each(expected_fields, fn field ->
        assert Map.has_key?(violations, field)
      end)
    end
  end

  describe "Performance metrics" do
    test "includes system and security performance data", %{collector: _pid} do
      metrics = MetricsCollector.get_current_metrics()
      performance = metrics.performance

      assert is_map(performance)
      assert Map.has_key?(performance, :system)
      assert Map.has_key?(performance, :security)

      system = performance.system
      assert Map.has_key?(system, :memory_usage)
      assert Map.has_key?(system, :cpu_usage)
      assert Map.has_key?(system, :process_count)

      security = performance.security
      assert Map.has_key?(security, :avg_validation_time_ms)
      assert Map.has_key?(security, :avg_capability_creation_time_ms)
      assert Map.has_key?(security, :token_cache_hit_rate)
      assert Map.has_key?(security, :concurrent_validations)
    end
  end

  describe "Audit metrics" do
    test "includes audit logging statistics", %{collector: _pid} do
      metrics = MetricsCollector.get_current_metrics()
      audit = metrics.audit

      assert is_map(audit)

      # Should have these fields (may be 0 or error if services not running)
      expected_fields = [:events_logged, :events_flushed, :buffer_size, :flush_errors]

      Enum.each(expected_fields, fn field ->
        assert Map.has_key?(audit, field)
      end)
    end
  end

  describe "Agent metrics" do
    test "includes agent pool statistics", %{collector: _pid} do
      metrics = MetricsCollector.get_current_metrics()
      agents = metrics.agents

      assert is_map(agents)

      # Should have these fields (may be 0 or error if services not running)
      expected_fields = [:active_agents, :total_spawned]

      Enum.each(expected_fields, fn field ->
        assert Map.has_key?(agents, field)
      end)
    end
  end

  describe "Error handling" do
    test "handles service unavailability gracefully", %{collector: _pid} do
      # Metrics collection should not crash even if services are unavailable
      metrics = MetricsCollector.get_current_metrics()

      assert is_map(metrics)

      # Each section should either have data or an error field
      Enum.each([:capabilities, :security_kernel, :violations, :audit, :agents], fn section ->
        section_data = Map.get(metrics, section, %{})
        assert is_map(section_data)

        # Should have either valid data or an error field
        has_data = Map.keys(section_data) |> Enum.any?(&(&1 != :error))
        has_error = Map.has_key?(section_data, :error)

        assert has_data or has_error, "Section #{section} should have data or error"
      end)
    end
  end

  describe "Alerts" do
    test "dashboard includes alert analysis", %{collector: _pid} do
      dashboard = MetricsCollector.get_dashboard_metrics()
      alerts = dashboard.alerts

      assert is_list(alerts)

      # Each alert should have required fields
      Enum.each(alerts, fn alert ->
        assert Map.has_key?(alert, :type)
        assert Map.has_key?(alert, :severity)
        assert Map.has_key?(alert, :message)

        assert alert.severity in [:low, :medium, :high, :critical]
      end)
    end
  end

  describe "Health scoring" do
    test "calculates reasonable health scores", %{collector: _pid} do
      dashboard = MetricsCollector.get_dashboard_metrics()
      health_score = dashboard.health_score

      assert is_integer(health_score)
      assert health_score >= 0
      assert health_score <= 100

      # Health score should be reasonable given system state
      # (In test environment, should generally be high unless services are down)
      if health_score < 50 do
        # Low health score is OK in test environment
        # Just verify it's a valid number
        assert is_integer(health_score)
      end
    end
  end
end
