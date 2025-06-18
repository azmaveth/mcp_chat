defmodule MCPChat.CostTracking.BudgetManager do
  @moduledoc """
  Budget management for LLM cost tracking.

  Handles budget limits, alerts, and spending threshold monitoring
  to help users control their AI-related expenses.
  """

  require Logger

  # Budget manager state
  defstruct [
    :daily_limit,
    :weekly_limit,
    :monthly_limit,
    # [50, 75, 90] - percentage thresholds
    :alert_thresholds,
    # Active alerts
    :current_alerts,
    # Historical budget data
    :budget_history,
    :notification_settings,
    # Stop requests when budget exceeded
    :auto_stop_enabled
  ]

  # Alert types
  @alert_types [:approaching_limit, :limit_exceeded, :spending_spike, :budget_reset]

  def start_link(opts \\ []) do
    initial_state = %__MODULE__{
      daily_limit: Keyword.get(opts, :daily_limit),
      weekly_limit: Keyword.get(opts, :weekly_limit),
      monthly_limit: Keyword.get(opts, :monthly_limit),
      alert_thresholds: Keyword.get(opts, :alert_thresholds, [50, 75, 90]),
      current_alerts: [],
      budget_history: [],
      notification_settings: %{
        email_enabled: false,
        slack_enabled: false,
        console_enabled: true
      },
      auto_stop_enabled: Keyword.get(opts, :auto_stop_enabled, false)
    }

    {:ok, initial_state}
  end

  @doc """
  Set a budget limit.
  """
  def set_limit(budget_manager, limit_type, amount, period \\ :monthly) do
    case limit_type do
      :daily when period == :daily ->
        {:ok, %{budget_manager | daily_limit: amount}}

      :weekly when period == :weekly ->
        {:ok, %{budget_manager | weekly_limit: amount}}

      :monthly when period == :monthly ->
        {:ok, %{budget_manager | monthly_limit: amount}}

      _ ->
        {:error, "Invalid limit type or period combination"}
    end
  end

  @doc """
  Get current budget status.
  """
  def get_status(budget_manager) do
    %{
      daily_limit: budget_manager.daily_limit,
      weekly_limit: budget_manager.weekly_limit,
      monthly_limit: budget_manager.monthly_limit,
      alert_thresholds: budget_manager.alert_thresholds,
      active_alerts: budget_manager.current_alerts,
      auto_stop_enabled: budget_manager.auto_stop_enabled,
      notification_settings: budget_manager.notification_settings
    }
  end

  @doc """
  Check budget thresholds against current spending.
  """
  def check_thresholds(budget_manager, cost_tracker_state) do
    new_alerts = []

    # Check daily threshold
    new_alerts = check_daily_threshold(budget_manager, cost_tracker_state, new_alerts)

    # Check weekly threshold (if implemented)
    new_alerts = check_weekly_threshold(budget_manager, cost_tracker_state, new_alerts)

    # Check monthly threshold
    new_alerts = check_monthly_threshold(budget_manager, cost_tracker_state, new_alerts)

    # Update budget manager with new alerts
    updated_budget_manager = %{budget_manager | current_alerts: new_alerts}

    {:ok, new_alerts, updated_budget_manager}
  end

  @doc """
  Update alert thresholds.
  """
  def set_alert_thresholds(budget_manager, thresholds) when is_list(thresholds) do
    # Validate thresholds are between 0 and 100
    valid_thresholds =
      Enum.all?(thresholds, fn threshold ->
        is_number(threshold) and threshold > 0 and threshold <= 100
      end)

    if valid_thresholds do
      sorted_thresholds = Enum.sort(thresholds)
      {:ok, %{budget_manager | alert_thresholds: sorted_thresholds}}
    else
      {:error, "Alert thresholds must be numbers between 0 and 100"}
    end
  end

  @doc """
  Enable or disable auto-stop when budget is exceeded.
  """
  def set_auto_stop(budget_manager, enabled) when is_boolean(enabled) do
    {:ok, %{budget_manager | auto_stop_enabled: enabled}}
  end

  @doc """
  Update notification settings.
  """
  def update_notification_settings(budget_manager, settings) do
    current_settings = budget_manager.notification_settings
    updated_settings = Map.merge(current_settings, settings)

    {:ok, %{budget_manager | notification_settings: updated_settings}}
  end

  @doc """
  Check if a request should be blocked due to budget limits.
  """
  def should_block_request?(budget_manager, cost_tracker_state, estimated_cost) do
    if budget_manager.auto_stop_enabled do
      # Check if adding estimated cost would exceed any limits
      today_cost = get_today_cost(cost_tracker_state)
      month_cost = get_month_cost(cost_tracker_state)

      daily_exceeded =
        budget_manager.daily_limit &&
          today_cost + estimated_cost > budget_manager.daily_limit

      monthly_exceeded =
        budget_manager.monthly_limit &&
          month_cost + estimated_cost > budget_manager.monthly_limit

      cond do
        daily_exceeded ->
          {:block, :daily_limit_exceeded, budget_manager.daily_limit}

        monthly_exceeded ->
          {:block, :monthly_limit_exceeded, budget_manager.monthly_limit}

        true ->
          :allow
      end
    else
      :allow
    end
  end

  @doc """
  Get spending recommendations based on current usage.
  """
  def get_spending_recommendations(budget_manager, cost_tracker_state) do
    recommendations = []

    # Analyze spending patterns
    recommendations = analyze_spending_patterns(budget_manager, cost_tracker_state, recommendations)

    # Check for budget optimization opportunities
    recommendations = check_budget_optimization(budget_manager, cost_tracker_state, recommendations)

    # Suggest budget adjustments if needed
    recommendations = suggest_budget_adjustments(budget_manager, cost_tracker_state, recommendations)

    recommendations
  end

  @doc """
  Reset alerts (typically called at the start of a new period).
  """
  def reset_alerts(budget_manager, reset_type \\ :all) do
    case reset_type do
      :all ->
        {:ok, %{budget_manager | current_alerts: []}}

      :daily ->
        remaining_alerts =
          Enum.filter(budget_manager.current_alerts, fn alert ->
            alert.period != :daily
          end)

        {:ok, %{budget_manager | current_alerts: remaining_alerts}}

      :monthly ->
        remaining_alerts =
          Enum.filter(budget_manager.current_alerts, fn alert ->
            alert.period != :monthly
          end)

        {:ok, %{budget_manager | current_alerts: remaining_alerts}}
    end
  end

  # Private functions

  defp check_daily_threshold(budget_manager, cost_tracker_state, alerts) do
    if budget_manager.daily_limit do
      today_cost = get_today_cost(cost_tracker_state)
      percentage_used = today_cost / budget_manager.daily_limit * 100

      triggered_thresholds =
        Enum.filter(budget_manager.alert_thresholds, fn threshold ->
          percentage_used >= threshold
        end)

      new_daily_alerts =
        Enum.map(triggered_thresholds, fn threshold ->
          %{
            type: :approaching_limit,
            period: :daily,
            threshold: threshold,
            current_spending: today_cost,
            limit: budget_manager.daily_limit,
            percentage_used: percentage_used,
            triggered_at: DateTime.utc_now()
          }
        end)

      # Check if limit is exceeded
      limit_alerts =
        if percentage_used >= 100 do
          [
            %{
              type: :limit_exceeded,
              period: :daily,
              current_spending: today_cost,
              limit: budget_manager.daily_limit,
              overage: today_cost - budget_manager.daily_limit,
              triggered_at: DateTime.utc_now()
            }
          ]
        else
          []
        end

      alerts ++ new_daily_alerts ++ limit_alerts
    else
      alerts
    end
  end

  defp check_weekly_threshold(_budget_manager, _cost_tracker_state, alerts) do
    # Weekly threshold checking would be implemented here
    # For now, return alerts unchanged
    alerts
  end

  defp check_monthly_threshold(budget_manager, cost_tracker_state, alerts) do
    if budget_manager.monthly_limit do
      month_cost = get_month_cost(cost_tracker_state)
      percentage_used = month_cost / budget_manager.monthly_limit * 100

      triggered_thresholds =
        Enum.filter(budget_manager.alert_thresholds, fn threshold ->
          percentage_used >= threshold
        end)

      new_monthly_alerts =
        Enum.map(triggered_thresholds, fn threshold ->
          %{
            type: :approaching_limit,
            period: :monthly,
            threshold: threshold,
            current_spending: month_cost,
            limit: budget_manager.monthly_limit,
            percentage_used: percentage_used,
            triggered_at: DateTime.utc_now()
          }
        end)

      # Check if limit is exceeded
      limit_alerts =
        if percentage_used >= 100 do
          [
            %{
              type: :limit_exceeded,
              period: :monthly,
              current_spending: month_cost,
              limit: budget_manager.monthly_limit,
              overage: month_cost - budget_manager.monthly_limit,
              triggered_at: DateTime.utc_now()
            }
          ]
        else
          []
        end

      alerts ++ new_monthly_alerts ++ limit_alerts
    else
      alerts
    end
  end

  defp get_today_cost(cost_tracker_state) do
    today = Date.to_string(Date.utc_today())
    Map.get(cost_tracker_state.daily_totals, today, 0.0)
  end

  defp get_month_cost(cost_tracker_state) do
    current_month = Date.utc_today()
    month_key = "#{current_month.year}-#{String.pad_leading("#{current_month.month}", 2, "0")}"
    Map.get(cost_tracker_state.monthly_totals, month_key, 0.0)
  end

  defp analyze_spending_patterns(budget_manager, cost_tracker_state, recommendations) do
    # Analyze if spending is trending upward
    recent_days = get_recent_daily_costs(cost_tracker_state, 7)

    if length(recent_days) >= 3 do
      trend = calculate_spending_trend(recent_days)

      # 20% increase trend
      if trend > 1.2 do
        recommendation = %{
          type: :spending_trend_warning,
          priority: :medium,
          title: "Increasing spending trend detected",
          description: "Your daily spending has increased by #{round((trend - 1) * 100)}% over the past week",
          suggestion: "Consider reviewing your usage patterns or adjusting budget limits",
          trend_factor: trend
        }

        [recommendation | recommendations]
      else
        recommendations
      end
    else
      recommendations
    end
  end

  defp check_budget_optimization(budget_manager, cost_tracker_state, recommendations) do
    # Check if any limits are consistently unused
    if budget_manager.monthly_limit do
      month_cost = get_month_cost(cost_tracker_state)
      utilization = month_cost / budget_manager.monthly_limit * 100

      # Less than 30% utilization
      if utilization < 30 do
        recommendation = %{
          type: :budget_optimization,
          priority: :low,
          title: "Budget underutilization detected",
          description: "You're using only #{round(utilization)}% of your monthly budget",
          suggestion: "Consider reducing your budget limit or increasing usage for better value",
          current_utilization: utilization
        }

        [recommendation | recommendations]
      else
        recommendations
      end
    else
      recommendations
    end
  end

  defp suggest_budget_adjustments(budget_manager, cost_tracker_state, recommendations) do
    # Suggest budget adjustments based on historical usage
    if budget_manager.monthly_limit do
      avg_monthly_spend = calculate_average_monthly_spend(cost_tracker_state)
      current_limit = budget_manager.monthly_limit

      cond do
        avg_monthly_spend > current_limit * 1.1 ->
          # Suggest increasing budget
          suggested_limit = avg_monthly_spend * 1.2

          recommendation = %{
            type: :budget_adjustment,
            priority: :medium,
            title: "Consider increasing monthly budget",
            description: "Your average spending (#{format_currency(avg_monthly_spend)}) exceeds your current limit",
            suggestion: "Consider increasing monthly limit to #{format_currency(suggested_limit)}",
            current_limit: current_limit,
            suggested_limit: suggested_limit
          }

          [recommendation | recommendations]

        avg_monthly_spend < current_limit * 0.6 ->
          # Suggest decreasing budget
          suggested_limit = avg_monthly_spend * 1.3

          recommendation = %{
            type: :budget_adjustment,
            priority: :low,
            title: "Consider reducing monthly budget",
            description: "Your average spending is well below your current limit",
            suggestion:
              "Consider reducing monthly limit to #{format_currency(suggested_limit)} for better budget discipline",
            current_limit: current_limit,
            suggested_limit: suggested_limit
          }

          [recommendation | recommendations]

        true ->
          recommendations
      end
    else
      recommendations
    end
  end

  defp get_recent_daily_costs(cost_tracker_state, days) do
    today = Date.utc_today()

    Enum.map(0..(days - 1), fn days_ago ->
      date = Date.add(today, -days_ago)
      date_key = Date.to_string(date)
      Map.get(cost_tracker_state.daily_totals, date_key, 0.0)
    end)
    # Oldest first
    |> Enum.reverse()
  end

  defp calculate_spending_trend(daily_costs) do
    # Simple linear regression to calculate trend
    n = length(daily_costs)
    indexed_costs = Enum.with_index(daily_costs, 1)

    sum_x = Enum.sum(1..n)
    sum_y = Enum.sum(daily_costs)

    sum_xy =
      Enum.reduce(indexed_costs, 0, fn {cost, index}, acc ->
        acc + cost * index
      end)

    sum_x_squared = Enum.reduce(1..n, 0, fn x, acc -> acc + x * x end)

    # Calculate slope
    slope = (n * sum_xy - sum_x * sum_y) / (n * sum_x_squared - sum_x * sum_x)

    # Return trend factor (1.0 = no change, > 1.0 = increasing, < 1.0 = decreasing)
    if slope >= 0 do
      1.0 + slope
    else
      # Will be less than 1.0 for negative slope
      1.0 + slope
    end
  end

  defp calculate_average_monthly_spend(cost_tracker_state) do
    monthly_totals = cost_tracker_state.monthly_totals

    if map_size(monthly_totals) > 0 do
      total_spend = Enum.reduce(monthly_totals, 0.0, fn {_month, cost}, acc -> acc + cost end)
      total_spend / map_size(monthly_totals)
    else
      0.0
    end
  end

  defp format_currency(amount) do
    "$#{:erlang.float_to_binary(amount, decimals: 2)}"
  end
end
