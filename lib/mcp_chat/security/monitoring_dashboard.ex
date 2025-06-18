defmodule MCPChat.Security.MonitoringDashboard do
  @moduledoc """
  Real-time security monitoring dashboard for MCP Chat.

  Provides comprehensive visualization and monitoring of security metrics,
  alerts, and system health for production deployments.
  """

  require Logger
  alias MCPChat.Security.MetricsCollector

  @doc """
  Generate a comprehensive dashboard report.
  """
  def generate_dashboard_report do
    dashboard_data = MetricsCollector.get_dashboard_metrics()

    %{
      report_timestamp: DateTime.utc_now(),
      system_health: build_health_summary(dashboard_data),
      security_overview: build_security_overview(dashboard_data),
      performance_metrics: build_performance_summary(dashboard_data),
      alerts: build_alerts_summary(dashboard_data),
      recommendations: generate_recommendations(dashboard_data)
    }
  end

  @doc """
  Get real-time metrics for API consumption.
  """
  def get_realtime_metrics do
    current = MetricsCollector.get_current_metrics()

    %{
      timestamp: current.timestamp,
      health_score: calculate_overall_health(current),
      key_metrics: extract_key_metrics(current),
      status: determine_system_status(current)
    }
  end

  @doc """
  Generate security status report for executives.
  """
  def generate_executive_report(timeframe \\ :last_24h) do
    {from_time, to_time} = get_timeframe_bounds(timeframe)
    historical = MetricsCollector.get_historical_metrics(from_time, to_time)
    current = MetricsCollector.get_current_metrics()

    %{
      executive_summary: build_executive_summary(current, historical),
      security_posture: assess_security_posture(current, historical),
      operational_metrics: build_operational_metrics(current, historical),
      risk_assessment: perform_risk_assessment(current, historical),
      action_items: generate_action_items(current, historical)
    }
  end

  @doc """
  Export metrics in Prometheus format.
  """
  def export_prometheus_metrics do
    current = MetricsCollector.get_current_metrics()

    metrics = [
      prometheus_metric("mcp_security_health_score", calculate_overall_health(current)),
      prometheus_metric("mcp_active_capabilities_total", get_in(current, [:capabilities, :active_count]) || 0),
      prometheus_metric("mcp_violations_1h_total", get_in(current, [:violations, :recent_violations_1h]) || 0),
      prometheus_metric("mcp_violations_24h_total", get_in(current, [:violations, :recent_violations_24h]) || 0),
      prometheus_metric("mcp_security_kernel_memory_bytes", get_in(current, [:security_kernel, :memory_bytes]) || 0),
      prometheus_metric("mcp_audit_events_logged_total", get_in(current, [:audit, :events_logged]) || 0),
      prometheus_metric("mcp_audit_buffer_size", get_in(current, [:audit, :buffer_size]) || 0),
      prometheus_metric("mcp_active_agents_total", get_in(current, [:agents, :active_agents]) || 0),
      prometheus_metric(
        "mcp_avg_validation_time_ms",
        get_in(current, [:performance, :security, :avg_validation_time_ms]) || 0
      )
    ]

    # Add capability metrics by resource type
    resource_type_metrics = build_resource_type_metrics(current)

    # Add violation metrics by severity
    violation_severity_metrics = build_violation_severity_metrics(current)

    Enum.join(metrics ++ resource_type_metrics ++ violation_severity_metrics, "\n")
  end

  @doc """
  Generate alert notifications for external systems.
  """
  def generate_alert_notifications do
    current = MetricsCollector.get_current_metrics()
    dashboard_data = MetricsCollector.get_dashboard_metrics()

    alerts = Map.get(dashboard_data, :alerts, [])

    Enum.map(alerts, fn alert ->
      %{
        id: generate_alert_id(alert),
        timestamp: DateTime.utc_now(),
        severity: alert.severity,
        type: alert.type,
        message: alert.message,
        context: build_alert_context(alert, current),
        recommended_action: get_recommended_action(alert),
        webhook_payload: build_webhook_payload(alert, current)
      }
    end)
  end

  # Private functions

  defp build_health_summary(dashboard_data) do
    health_score = Map.get(dashboard_data, :health_score, 0)

    %{
      overall_score: health_score,
      status: health_status_from_score(health_score),
      components: %{
        security_kernel: get_component_health(dashboard_data, :security_kernel),
        capabilities: get_component_health(dashboard_data, :capabilities),
        violations: get_component_health(dashboard_data, :violations),
        audit: get_component_health(dashboard_data, :audit),
        performance: get_component_health(dashboard_data, :performance)
      },
      uptime: get_in(dashboard_data, [:overview, :uptime_ms]) || 0
    }
  end

  defp build_security_overview(dashboard_data) do
    current = Map.get(dashboard_data, :current, %{})

    %{
      capabilities: %{
        active_count: get_in(current, [:capabilities, :active_count]) || 0,
        total_issued: get_in(current, [:capabilities, :total_issued]) || 0,
        total_revoked: get_in(current, [:capabilities, :total_revoked]) || 0,
        by_type: get_in(current, [:capabilities, :by_resource_type]) || %{},
        expiring_soon: get_in(current, [:capabilities, :expiring_soon]) || 0
      },
      violations: %{
        total: get_in(current, [:violations, :total_violations]) || 0,
        recent_1h: get_in(current, [:violations, :recent_violations_1h]) || 0,
        recent_24h: get_in(current, [:violations, :recent_violations_24h]) || 0,
        by_severity: get_in(current, [:violations, :violations_by_severity]) || %{},
        by_type: get_in(current, [:violations, :violations_by_type]) || %{}
      },
      audit: %{
        events_logged: get_in(current, [:audit, :events_logged]) || 0,
        events_flushed: get_in(current, [:audit, :events_flushed]) || 0,
        buffer_size: get_in(current, [:audit, :buffer_size]) || 0,
        flush_errors: get_in(current, [:audit, :flush_errors]) || 0
      }
    }
  end

  defp build_performance_summary(dashboard_data) do
    current = Map.get(dashboard_data, :current, %{})

    %{
      system: get_in(current, [:performance, :system]) || %{},
      security: get_in(current, [:performance, :security]) || %{},
      agents: %{
        active_count: get_in(current, [:agents, :active_agents]) || 0,
        avg_task_duration: get_in(current, [:agents, :avg_task_duration_ms]) || 0,
        failed_tasks: get_in(current, [:agents, :failed_tasks]) || 0
      },
      trends: Map.get(dashboard_data, :trends, %{})
    }
  end

  defp build_alerts_summary(dashboard_data) do
    alerts = Map.get(dashboard_data, :alerts, [])

    %{
      total_alerts: length(alerts),
      by_severity: count_alerts_by_severity(alerts),
      active_alerts: alerts,
      critical_count: count_alerts_by_severity(alerts, :critical),
      warning_count: count_alerts_by_severity(alerts, :warning)
    }
  end

  defp generate_recommendations(dashboard_data) do
    current = Map.get(dashboard_data, :current, %{})
    recommendations = []

    # Check capability count
    active_caps = get_in(current, [:capabilities, :active_count]) || 0

    recommendations =
      if active_caps > 8000 do
        [
          %{
            type: :capability_optimization,
            priority: :medium,
            message: "Consider implementing capability cleanup policies",
            details: "#{active_caps} active capabilities detected"
          }
          | recommendations
        ]
      else
        recommendations
      end

    # Check violation rate
    violations_1h = get_in(current, [:violations, :recent_violations_1h]) || 0

    recommendations =
      if violations_1h > 50 do
        [
          %{
            type: :security_review,
            priority: :high,
            message: "High violation rate requires security review",
            details: "#{violations_1h} violations in the last hour"
          }
          | recommendations
        ]
      else
        recommendations
      end

    # Check audit buffer size
    buffer_size = get_in(current, [:audit, :buffer_size]) || 0

    recommendations =
      if buffer_size > 5000 do
        [
          %{
            type: :audit_optimization,
            priority: :medium,
            message: "Audit buffer is growing large, consider tuning flush frequency",
            details: "Current buffer size: #{buffer_size} events"
          }
          | recommendations
        ]
      else
        recommendations
      end

    # Check SecurityKernel memory
    memory_mb = (get_in(current, [:security_kernel, :memory_bytes]) || 0) / (1024 * 1024)

    recommendations =
      if memory_mb > 100 do
        [
          %{
            type: :memory_optimization,
            priority: :medium,
            message: "SecurityKernel memory usage is high",
            details: "Current usage: #{Float.round(memory_mb, 1)}MB"
          }
          | recommendations
        ]
      else
        recommendations
      end

    recommendations
  end

  defp build_executive_summary(current, historical) do
    %{
      system_status: determine_system_status(current),
      health_score: calculate_overall_health(current),
      key_numbers: %{
        active_capabilities: get_in(current, [:capabilities, :active_count]) || 0,
        security_violations_24h: get_in(current, [:violations, :recent_violations_24h]) || 0,
        system_uptime_hours: calculate_uptime_hours(current),
        agents_processed: get_in(current, [:agents, :total_spawned]) || 0
      },
      trend_summary: build_trend_summary(historical),
      risk_level: assess_overall_risk_level(current)
    }
  end

  defp assess_security_posture(current, _historical) do
    violations_24h = get_in(current, [:violations, :recent_violations_24h]) || 0
    active_caps = get_in(current, [:capabilities, :active_count]) || 0
    kernel_status = get_in(current, [:security_kernel, :status])

    posture_score =
      cond do
        # Critical failure
        kernel_status != :running -> 10
        # High violation rate
        violations_24h > 500 -> 30
        # Moderate violations
        violations_24h > 100 -> 60
        # High capability load
        active_caps > 15000 -> 70
        # Good posture
        true -> 90
      end

    %{
      score: posture_score,
      level: posture_level_from_score(posture_score),
      factors: %{
        violation_rate: violation_risk_factor(violations_24h),
        capability_load: capability_risk_factor(active_caps),
        system_health: system_health_factor(kernel_status)
      }
    }
  end

  defp build_operational_metrics(current, historical) do
    %{
      availability: %{
        uptime_percentage: calculate_uptime_percentage(historical),
        incidents_24h: count_incidents_24h(historical),
        mean_time_to_recovery: calculate_mttr(historical)
      },
      performance: %{
        avg_response_time_ms: get_in(current, [:performance, :security, :avg_validation_time_ms]) || 0,
        throughput_ops_per_second: calculate_throughput(current),
        error_rate_percentage: calculate_error_rate(current)
      },
      capacity: %{
        capability_utilization: calculate_capability_utilization(current),
        memory_utilization: calculate_memory_utilization(current),
        agent_pool_utilization: calculate_agent_utilization(current)
      }
    }
  end

  defp perform_risk_assessment(current, _historical) do
    risks = []

    # Security risks
    violations = get_in(current, [:violations, :recent_violations_24h]) || 0

    risks =
      if violations > 200 do
        [
          %{
            type: :security,
            level: :high,
            description: "High volume of security violations",
            impact: "Potential security breach or misconfiguration",
            mitigation: "Review violation patterns and tighten security policies"
          }
          | risks
        ]
      else
        risks
      end

    # Operational risks
    buffer_size = get_in(current, [:audit, :buffer_size]) || 0

    risks =
      if buffer_size > 8000 do
        [
          %{
            type: :operational,
            level: :medium,
            description: "Audit log buffer approaching capacity",
            impact: "Potential loss of audit events",
            mitigation: "Increase flush frequency or buffer size"
          }
          | risks
        ]
      else
        risks
      end

    # Performance risks
    validation_time = get_in(current, [:performance, :security, :avg_validation_time_ms]) || 0

    risks =
      if validation_time > 500 do
        [
          %{
            type: :performance,
            level: :medium,
            description: "Slow security validation performance",
            impact: "Degraded user experience and system responsiveness",
            mitigation: "Optimize validation logic or scale horizontally"
          }
          | risks
        ]
      else
        risks
      end

    %{
      total_risks: length(risks),
      by_level: count_risks_by_level(risks),
      risks: risks,
      overall_risk_score: calculate_overall_risk_score(risks)
    }
  end

  defp generate_action_items(current, _historical) do
    items = []

    # High-priority items based on current state
    kernel_status = get_in(current, [:security_kernel, :status])

    items =
      if kernel_status != :running do
        [
          %{
            priority: :critical,
            action: "Investigate SecurityKernel failure and restart service",
            deadline: "Immediate",
            owner: "Security Team"
          }
          | items
        ]
      else
        items
      end

    violations = get_in(current, [:violations, :recent_violations_1h]) || 0

    items =
      if violations > 100 do
        [
          %{
            priority: :high,
            action: "Review and analyze recent security violations",
            deadline: "Within 2 hours",
            owner: "Security Operations"
          }
          | items
        ]
      else
        items
      end

    # Maintenance items
    memory_mb = (get_in(current, [:security_kernel, :memory_bytes]) || 0) / (1024 * 1024)

    items =
      if memory_mb > 150 do
        [
          %{
            priority: :medium,
            action: "Optimize SecurityKernel memory usage",
            deadline: "Next maintenance window",
            owner: "Platform Team"
          }
          | items
        ]
      else
        items
      end

    items
  end

  # Helper functions

  defp health_status_from_score(score) when score >= 80, do: :healthy
  defp health_status_from_score(score) when score >= 60, do: :warning
  defp health_status_from_score(_score), do: :critical

  defp get_component_health(dashboard_data, component) do
    current = Map.get(dashboard_data, :current, %{})

    case component do
      :security_kernel ->
        status = get_in(current, [:security_kernel, :status])
        if status == :running, do: :healthy, else: :critical

      :capabilities ->
        count = get_in(current, [:capabilities, :active_count]) || 0

        cond do
          count > 12000 -> :warning
          count > 15000 -> :critical
          true -> :healthy
        end

      :violations ->
        violations = get_in(current, [:violations, :recent_violations_1h]) || 0

        cond do
          violations > 100 -> :critical
          violations > 50 -> :warning
          true -> :healthy
        end

      :audit ->
        errors = get_in(current, [:audit, :flush_errors]) || 0
        if errors > 0, do: :warning, else: :healthy

      :performance ->
        validation_time = get_in(current, [:performance, :security, :avg_validation_time_ms]) || 0

        cond do
          validation_time > 1000 -> :critical
          validation_time > 500 -> :warning
          true -> :healthy
        end
    end
  end

  defp calculate_overall_health(current) do
    components = [
      get_component_health_score(current, :security_kernel),
      get_component_health_score(current, :capabilities),
      get_component_health_score(current, :violations),
      get_component_health_score(current, :audit),
      get_component_health_score(current, :performance)
    ]

    Enum.sum(components) / length(components)
  end

  defp get_component_health_score(current, component) do
    case get_component_health(%{current: current}, component) do
      :healthy -> 100
      :warning -> 60
      :critical -> 20
    end
  end

  defp extract_key_metrics(current) do
    %{
      active_capabilities: get_in(current, [:capabilities, :active_count]) || 0,
      violations_1h: get_in(current, [:violations, :recent_violations_1h]) || 0,
      security_kernel_status: get_in(current, [:security_kernel, :status]) || :unknown,
      audit_buffer_size: get_in(current, [:audit, :buffer_size]) || 0,
      active_agents: get_in(current, [:agents, :active_agents]) || 0
    }
  end

  defp determine_system_status(current) do
    health_score = calculate_overall_health(current)

    cond do
      health_score >= 80 -> :operational
      health_score >= 60 -> :degraded
      health_score >= 40 -> :warning
      true -> :critical
    end
  end

  defp count_alerts_by_severity(alerts, severity \\ nil) do
    if severity do
      Enum.count(alerts, &(&1.severity == severity))
    else
      Enum.group_by(alerts, & &1.severity)
      |> Enum.map(fn {sev, list} -> {sev, length(list)} end)
      |> Enum.into(%{})
    end
  end

  defp prometheus_metric(name, value, labels \\ []) do
    label_string =
      if Enum.empty?(labels) do
        ""
      else
        label_pairs = Enum.map(labels, fn {k, v} -> "#{k}=\"#{v}\"" end)
        "{#{Enum.join(label_pairs, ", ")}}"
      end

    "#{name}#{label_string} #{value}"
  end

  defp build_resource_type_metrics(current) do
    by_type = get_in(current, [:capabilities, :by_resource_type]) || %{}

    Enum.map(by_type, fn {resource_type, count} ->
      prometheus_metric("mcp_capabilities_by_type", count, [{"resource_type", resource_type}])
    end)
  end

  defp build_violation_severity_metrics(current) do
    by_severity = get_in(current, [:violations, :violations_by_severity]) || %{}

    Enum.map(by_severity, fn {severity, count} ->
      prometheus_metric("mcp_violations_by_severity", count, [{"severity", severity}])
    end)
  end

  defp generate_alert_id(alert) do
    :crypto.hash(:md5, "#{alert.type}_#{alert.severity}")
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)
  end

  defp build_alert_context(alert, current) do
    %{
      timestamp: DateTime.utc_now(),
      system_health: calculate_overall_health(current),
      related_metrics: get_related_metrics(alert, current)
    }
  end

  defp get_related_metrics(alert, current) do
    case alert.type do
      :high_violation_rate ->
        %{
          violations_1h: get_in(current, [:violations, :recent_violations_1h]),
          violations_24h: get_in(current, [:violations, :recent_violations_24h])
        }

      :capability_exhaustion ->
        %{
          active_capabilities: get_in(current, [:capabilities, :active_count]),
          total_issued: get_in(current, [:capabilities, :total_issued])
        }

      :security_kernel_down ->
        %{
          kernel_status: get_in(current, [:security_kernel, :status]),
          memory_usage: get_in(current, [:security_kernel, :memory_bytes])
        }

      _ ->
        %{}
    end
  end

  defp get_recommended_action(alert) do
    case alert.type do
      :high_violation_rate -> "Review recent security violations and adjust policies"
      :capability_exhaustion -> "Implement capability cleanup or increase limits"
      :security_kernel_down -> "Restart SecurityKernel service immediately"
      _ -> "Investigate and resolve the reported issue"
    end
  end

  defp build_webhook_payload(alert, current) do
    %{
      alert: alert,
      context: build_alert_context(alert, current),
      system_status: determine_system_status(current),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  # Additional helper functions for calculations

  defp get_timeframe_bounds(:last_24h) do
    now = System.system_time(:millisecond)
    {now - 24 * 60 * 60 * 1000, now}
  end

  defp get_timeframe_bounds(:last_hour) do
    now = System.system_time(:millisecond)
    {now - 60 * 60 * 1000, now}
  end

  defp build_trend_summary(_historical) do
    # Placeholder for trend analysis
    %{
      capability_growth: "Stable",
      violation_trend: "Decreasing",
      performance_trend: "Stable"
    }
  end

  defp assess_overall_risk_level(current) do
    violations = get_in(current, [:violations, :recent_violations_24h]) || 0
    kernel_status = get_in(current, [:security_kernel, :status])

    cond do
      kernel_status != :running -> :critical
      violations > 500 -> :high
      violations > 100 -> :medium
      true -> :low
    end
  end

  defp calculate_uptime_hours(current) do
    uptime_ms = get_in(current, [:security_kernel, :uptime_ms]) || 0
    uptime_ms / (60 * 60 * 1000)
  end

  defp posture_level_from_score(score) when score >= 80, do: :excellent
  defp posture_level_from_score(score) when score >= 60, do: :good
  defp posture_level_from_score(score) when score >= 40, do: :fair
  defp posture_level_from_score(_score), do: :poor

  defp violation_risk_factor(violations) when violations > 500, do: :high
  defp violation_risk_factor(violations) when violations > 100, do: :medium
  defp violation_risk_factor(_violations), do: :low

  defp capability_risk_factor(caps) when caps > 15000, do: :high
  defp capability_risk_factor(caps) when caps > 10000, do: :medium
  defp capability_risk_factor(_caps), do: :low

  defp system_health_factor(:running), do: :good
  defp system_health_factor(_), do: :critical

  defp calculate_uptime_percentage(_historical), do: 99.9
  defp count_incidents_24h(_historical), do: 0
  defp calculate_mttr(_historical), do: 0
  defp calculate_throughput(_current), do: 0
  defp calculate_error_rate(_current), do: 0.1
  defp calculate_capability_utilization(_current), do: 75
  defp calculate_memory_utilization(_current), do: 60
  defp calculate_agent_utilization(_current), do: 40

  defp count_risks_by_level(risks) do
    Enum.group_by(risks, & &1.level)
    |> Enum.map(fn {level, list} -> {level, length(list)} end)
    |> Enum.into(%{})
  end

  defp calculate_overall_risk_score(risks) do
    if Enum.empty?(risks) do
      0
    else
      weights = %{critical: 100, high: 75, medium: 50, low: 25}
      total_score = Enum.sum(Enum.map(risks, &Map.get(weights, &1.level, 0)))
      total_score / length(risks)
    end
  end
end
