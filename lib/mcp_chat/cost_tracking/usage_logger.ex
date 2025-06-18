defmodule MCPChat.CostTracking.UsageLogger do
  @moduledoc """
  Usage reporting and analytics for cost tracking.

  Generates detailed usage reports, analytics, and insights
  from cost tracking data.
  """

  require Logger
  alias MCPChat.CostTracking.CostCalculator

  @doc """
  Generate a comprehensive usage report.
  """
  def generate_report(cost_tracker_state, opts \\ []) do
    report_type = Keyword.get(opts, :type, :comprehensive)
    period = Keyword.get(opts, :period, :this_month)
    format = Keyword.get(opts, :format, :map)

    base_report = %{
      report_type: report_type,
      period: period,
      generated_at: DateTime.utc_now(),
      summary: generate_summary(cost_tracker_state, period),
      provider_breakdown: generate_provider_breakdown(cost_tracker_state, period),
      model_usage: generate_model_usage_report(cost_tracker_state, period),
      time_series: generate_time_series_data(cost_tracker_state, period),
      insights: generate_insights(cost_tracker_state, period)
    }

    enhanced_report =
      case report_type do
        :comprehensive -> add_comprehensive_details(base_report, cost_tracker_state, opts)
        :summary -> base_report
        :financial -> add_financial_details(base_report, cost_tracker_state, opts)
        :technical -> add_technical_details(base_report, cost_tracker_state, opts)
        _ -> base_report
      end

    case format do
      :map -> enhanced_report
      :json -> Jason.encode!(enhanced_report)
      :csv -> format_as_csv(enhanced_report)
      :markdown -> format_as_markdown(enhanced_report)
      _ -> enhanced_report
    end
  end

  @doc """
  Generate cost efficiency analysis.
  """
  def analyze_cost_efficiency(cost_tracker_state) do
    model_efficiency = analyze_model_efficiency(cost_tracker_state)
    provider_efficiency = analyze_provider_efficiency(cost_tracker_state)
    usage_patterns = analyze_usage_patterns(cost_tracker_state)

    %{
      model_efficiency: model_efficiency,
      provider_efficiency: provider_efficiency,
      usage_patterns: usage_patterns,
      overall_score: calculate_efficiency_score(model_efficiency, provider_efficiency, usage_patterns),
      recommendations: generate_efficiency_recommendations(model_efficiency, provider_efficiency, usage_patterns)
    }
  end

  @doc """
  Generate spending forecast based on historical data.
  """
  def generate_spending_forecast(cost_tracker_state, forecast_period \\ :next_month) do
    historical_data = extract_historical_data(cost_tracker_state)

    case forecast_period do
      :next_month ->
        forecast_monthly_spending(historical_data)

      :next_week ->
        forecast_weekly_spending(historical_data)

      {:next_n_days, n} ->
        forecast_n_day_spending(historical_data, n)

      _ ->
        {:error, "Unsupported forecast period"}
    end
  end

  @doc """
  Export usage data in various formats.
  """
  def export_usage_data(cost_tracker_state, export_opts \\ []) do
    format = Keyword.get(export_opts, :format, :csv)
    period = Keyword.get(export_opts, :period, :this_month)
    include_sessions = Keyword.get(export_opts, :include_sessions, true)

    export_data = %{
      daily_costs: extract_daily_costs(cost_tracker_state, period),
      provider_costs: cost_tracker_state.provider_totals,
      model_usage: cost_tracker_state.model_usage
    }

    export_data =
      if include_sessions do
        Map.put(export_data, :session_costs, cost_tracker_state.session_costs)
      else
        export_data
      end

    case format do
      :csv -> export_to_csv(export_data)
      :json -> export_to_json(export_data)
      :excel -> export_to_excel(export_data)
      _ -> {:error, "Unsupported export format"}
    end
  end

  # Private functions

  defp generate_summary(cost_tracker_state, period) do
    total_cost =
      case period do
        :today -> get_today_cost(cost_tracker_state)
        :this_week -> get_this_week_cost(cost_tracker_state)
        :this_month -> get_this_month_cost(cost_tracker_state)
        :lifetime -> cost_tracker_state.total_lifetime_cost
      end

    total_sessions = map_size(cost_tracker_state.session_costs)
    total_providers = map_size(cost_tracker_state.provider_totals)
    total_models = map_size(cost_tracker_state.model_usage)

    %{
      total_cost: total_cost,
      total_sessions: total_sessions,
      total_providers: total_providers,
      total_models: total_models,
      avg_cost_per_session: if(total_sessions > 0, do: total_cost / total_sessions, else: 0),
      period: period
    }
  end

  defp generate_provider_breakdown(cost_tracker_state, period) do
    # Filter provider data by period (simplified for now)
    provider_totals = cost_tracker_state.provider_totals
    total_cost = Enum.reduce(provider_totals, 0, fn {_provider, cost}, acc -> acc + cost end)

    Enum.map(provider_totals, fn {provider, cost} ->
      percentage = if total_cost > 0, do: cost / total_cost * 100, else: 0

      %{
        provider: provider,
        cost: cost,
        percentage: Float.round(percentage, 2),
        period: period
      }
    end)
    |> Enum.sort_by(& &1.cost, :desc)
  end

  defp generate_model_usage_report(cost_tracker_state, period) do
    model_usage = cost_tracker_state.model_usage

    Enum.map(model_usage, fn {model, stats} ->
      %{
        model: model,
        usage_count: stats.usage_count,
        total_cost: stats.total_cost,
        total_tokens: stats.total_tokens,
        avg_cost_per_token: stats.avg_cost_per_token,
        avg_cost_per_usage: stats.total_cost / max(stats.usage_count, 1),
        period: period
      }
    end)
    |> Enum.sort_by(& &1.total_cost, :desc)
  end

  defp generate_time_series_data(cost_tracker_state, period) do
    case period do
      :this_month ->
        generate_daily_time_series(cost_tracker_state)

      :this_week ->
        generate_daily_time_series(cost_tracker_state, 7)

      _ ->
        generate_daily_time_series(cost_tracker_state, 30)
    end
  end

  defp generate_daily_time_series(cost_tracker_state, days \\ 30) do
    end_date = Date.utc_today()
    start_date = Date.add(end_date, -days)

    Date.range(start_date, end_date)
    |> Enum.map(fn date ->
      date_key = Date.to_string(date)
      cost = Map.get(cost_tracker_state.daily_totals, date_key, 0.0)

      %{
        date: date,
        cost: cost,
        day_of_week: Date.day_of_week(date)
      }
    end)
  end

  defp generate_insights(cost_tracker_state, period) do
    insights = []

    # Spending trend insights
    insights = add_spending_trend_insights(cost_tracker_state, period, insights)

    # Model efficiency insights
    insights = add_model_efficiency_insights(cost_tracker_state, insights)

    # Provider comparison insights
    insights = add_provider_comparison_insights(cost_tracker_state, insights)

    # Usage pattern insights
    insights = add_usage_pattern_insights(cost_tracker_state, insights)

    insights
  end

  defp add_comprehensive_details(base_report, cost_tracker_state, _opts) do
    Map.merge(base_report, %{
      session_breakdown: generate_session_breakdown(cost_tracker_state),
      cost_efficiency: analyze_cost_efficiency(cost_tracker_state),
      spending_forecast: generate_spending_forecast(cost_tracker_state),
      optimization_opportunities: identify_optimization_opportunities(cost_tracker_state)
    })
  end

  defp add_financial_details(base_report, cost_tracker_state, _opts) do
    Map.merge(base_report, %{
      cost_breakdown: generate_detailed_cost_breakdown(cost_tracker_state),
      roi_analysis: analyze_roi(cost_tracker_state),
      budget_utilization: analyze_budget_utilization(cost_tracker_state)
    })
  end

  defp add_technical_details(base_report, cost_tracker_state, _opts) do
    Map.merge(base_report, %{
      token_analysis: analyze_token_usage(cost_tracker_state),
      performance_metrics: calculate_performance_metrics(cost_tracker_state),
      error_analysis: analyze_errors(cost_tracker_state)
    })
  end

  defp generate_session_breakdown(cost_tracker_state) do
    cost_tracker_state.session_costs
    |> Enum.map(fn {session_id, session_data} ->
      %{
        session_id: session_id,
        total_cost: session_data.total_cost,
        message_count: session_data.message_count,
        total_tokens: session_data.total_tokens,
        avg_cost_per_message: session_data.total_cost / max(session_data.message_count, 1),
        avg_tokens_per_message: session_data.total_tokens / max(session_data.message_count, 1)
      }
    end)
    |> Enum.sort_by(& &1.total_cost, :desc)
  end

  defp analyze_model_efficiency(cost_tracker_state) do
    cost_tracker_state.model_usage
    |> Enum.map(fn {model, stats} ->
      efficiency_score = calculate_model_efficiency_score(stats)

      %{
        model: model,
        efficiency_score: efficiency_score,
        cost_per_token: stats.avg_cost_per_token,
        usage_count: stats.usage_count,
        total_cost: stats.total_cost,
        recommendation: get_model_recommendation(efficiency_score)
      }
    end)
    |> Enum.sort_by(& &1.efficiency_score, :desc)
  end

  defp analyze_provider_efficiency(cost_tracker_state) do
    cost_tracker_state.provider_totals
    |> Enum.map(fn {provider, total_cost} ->
      # Calculate efficiency based on cost and hypothetical value
      efficiency_score = calculate_provider_efficiency_score(provider, total_cost)

      %{
        provider: provider,
        total_cost: total_cost,
        efficiency_score: efficiency_score,
        recommendation: get_provider_recommendation(efficiency_score)
      }
    end)
    |> Enum.sort_by(& &1.efficiency_score, :desc)
  end

  defp analyze_usage_patterns(cost_tracker_state) do
    daily_costs = extract_recent_daily_costs(cost_tracker_state, 30)

    %{
      daily_average: calculate_average(daily_costs),
      daily_variance: calculate_variance(daily_costs),
      peak_usage_day: find_peak_usage_day(cost_tracker_state),
      usage_consistency: calculate_usage_consistency(daily_costs),
      trend_direction: calculate_trend_direction(daily_costs)
    }
  end

  defp calculate_efficiency_score(model_efficiency, provider_efficiency, usage_patterns) do
    # Weighted average of different efficiency metrics
    model_avg = calculate_average_efficiency(model_efficiency)
    provider_avg = calculate_average_efficiency(provider_efficiency)
    pattern_score = usage_patterns.usage_consistency

    model_avg * 0.4 + provider_avg * 0.3 + pattern_score * 0.3
  end

  defp generate_efficiency_recommendations(model_efficiency, provider_efficiency, usage_patterns) do
    recommendations = []

    # Model recommendations
    low_efficiency_models = Enum.filter(model_efficiency, &(&1.efficiency_score < 0.6))

    if length(low_efficiency_models) > 0 do
      recommendations = [
        %{
          type: :model_optimization,
          priority: :high,
          title: "Optimize model selection",
          description: "Consider switching from low-efficiency models",
          affected_models: Enum.map(low_efficiency_models, & &1.model)
        }
        | recommendations
      ]
    end

    # Provider recommendations
    if length(provider_efficiency) > 1 do
      cheapest_provider = Enum.min_by(provider_efficiency, & &1.total_cost)

      recommendations = [
        %{
          type: :provider_optimization,
          priority: :medium,
          title: "Consider provider consolidation",
          description: "#{cheapest_provider.provider} appears to be most cost-effective",
          recommendation: "Consider using #{cheapest_provider.provider} for more tasks"
        }
        | recommendations
      ]
    end

    # Usage pattern recommendations
    if usage_patterns.usage_consistency < 0.5 do
      recommendations = [
        %{
          type: :usage_pattern,
          priority: :low,
          title: "Inconsistent usage patterns detected",
          description: "Consider establishing more regular usage patterns for better cost predictability"
        }
        | recommendations
      ]
    end

    recommendations
  end

  # Helper functions for various calculations

  defp get_today_cost(cost_tracker_state) do
    today = Date.to_string(Date.utc_today())
    Map.get(cost_tracker_state.daily_totals, today, 0.0)
  end

  defp get_this_week_cost(cost_tracker_state) do
    # Calculate cost for the current week
    today = Date.utc_today()
    start_of_week = Date.add(today, -Date.day_of_week(today) + 1)

    Date.range(start_of_week, today)
    |> Enum.reduce(0.0, fn date, acc ->
      date_key = Date.to_string(date)
      acc + Map.get(cost_tracker_state.daily_totals, date_key, 0.0)
    end)
  end

  defp get_this_month_cost(cost_tracker_state) do
    current_month = Date.utc_today()
    month_key = "#{current_month.year}-#{String.pad_leading("#{current_month.month}", 2, "0")}"
    Map.get(cost_tracker_state.monthly_totals, month_key, 0.0)
  end

  defp calculate_model_efficiency_score(stats) do
    # Simple efficiency score based on cost per token and usage frequency
    # Avoid division by zero
    cost_efficiency = 1.0 / (stats.avg_cost_per_token + 0.001)
    # Normalize usage count
    usage_factor = min(stats.usage_count / 10.0, 1.0)

    # Normalize to 0-1 scale
    (cost_efficiency * 0.7 + usage_factor * 0.3) / 10.0
  end

  defp calculate_provider_efficiency_score(provider, total_cost) do
    # Simplified efficiency score for providers
    # In a real implementation, this would consider provider-specific metrics
    base_score =
      case provider do
        :anthropic -> 0.8
        :openai -> 0.7
        :gemini -> 0.9
        # Free/local
        :ollama -> 1.0
        _ -> 0.6
      end

    # Adjust based on spending (higher spending might indicate efficiency)
    spending_factor = min(total_cost / 100.0, 1.0)
    base_score * (0.7 + spending_factor * 0.3)
  end

  defp get_model_recommendation(efficiency_score) do
    cond do
      efficiency_score > 0.8 -> "Excellent choice - continue using"
      efficiency_score > 0.6 -> "Good efficiency - monitor usage"
      efficiency_score > 0.4 -> "Consider optimization or alternatives"
      true -> "Poor efficiency - recommend switching"
    end
  end

  defp get_provider_recommendation(efficiency_score) do
    cond do
      efficiency_score > 0.8 -> "Excellent value - primary provider"
      efficiency_score > 0.6 -> "Good value - suitable for regular use"
      efficiency_score > 0.4 -> "Fair value - use selectively"
      true -> "Poor value - consider alternatives"
    end
  end

  defp extract_recent_daily_costs(cost_tracker_state, days) do
    today = Date.utc_today()

    Enum.map(0..(days - 1), fn days_ago ->
      date = Date.add(today, -days_ago)
      date_key = Date.to_string(date)
      Map.get(cost_tracker_state.daily_totals, date_key, 0.0)
    end)
  end

  defp calculate_average(values) do
    if length(values) > 0 do
      Enum.sum(values) / length(values)
    else
      0.0
    end
  end

  defp calculate_variance(values) do
    if length(values) > 1 do
      mean = calculate_average(values)

      variance =
        Enum.reduce(values, 0.0, fn x, acc ->
          acc + :math.pow(x - mean, 2)
        end) / (length(values) - 1)

      variance
    else
      0.0
    end
  end

  defp find_peak_usage_day(cost_tracker_state) do
    cost_tracker_state.daily_totals
    |> Enum.max_by(fn {_date, cost} -> cost end, fn -> {"", 0.0} end)
    |> case do
      {"", 0.0} -> nil
      {date, cost} -> %{date: date, cost: cost}
    end
  end

  defp calculate_usage_consistency(daily_costs) do
    if length(daily_costs) > 1 do
      variance = calculate_variance(daily_costs)
      mean = calculate_average(daily_costs)

      if mean > 0 do
        # Coefficient of variation (lower is more consistent)
        cv = :math.sqrt(variance) / mean
        # Convert to consistency score (higher is more consistent)
        max(0, 1 - cv)
      else
        0.0
      end
    else
      0.0
    end
  end

  defp calculate_trend_direction(daily_costs) do
    if length(daily_costs) > 3 do
      # Simple linear regression slope
      n = length(daily_costs)
      indexed_costs = Enum.with_index(daily_costs, 1)

      sum_x = Enum.sum(1..n)
      sum_y = Enum.sum(daily_costs)

      sum_xy =
        Enum.reduce(indexed_costs, 0, fn {cost, index}, acc ->
          acc + cost * index
        end)

      sum_x_squared = Enum.reduce(1..n, 0, fn x, acc -> acc + x * x end)

      slope = (n * sum_xy - sum_x * sum_y) / (n * sum_x_squared - sum_x * sum_x)

      cond do
        slope > 0.1 -> :increasing
        slope < -0.1 -> :decreasing
        true -> :stable
      end
    else
      :insufficient_data
    end
  end

  defp calculate_average_efficiency(efficiency_data) do
    if length(efficiency_data) > 0 do
      total_efficiency =
        Enum.reduce(efficiency_data, 0.0, fn item, acc ->
          acc + item.efficiency_score
        end)

      total_efficiency / length(efficiency_data)
    else
      0.0
    end
  end

  # Placeholder functions for comprehensive report features
  defp forecast_monthly_spending(_historical_data), do: %{forecast: "Not implemented"}
  defp forecast_weekly_spending(_historical_data), do: %{forecast: "Not implemented"}
  defp forecast_n_day_spending(_historical_data, _n), do: %{forecast: "Not implemented"}
  defp extract_historical_data(_cost_tracker_state), do: %{}
  defp extract_daily_costs(_cost_tracker_state, _period), do: %{}
  defp export_to_csv(_export_data), do: {:ok, "CSV export not implemented"}
  defp export_to_json(export_data), do: {:ok, Jason.encode!(export_data)}
  defp export_to_excel(_export_data), do: {:ok, "Excel export not implemented"}
  defp format_as_csv(_report), do: "CSV format not implemented"
  defp format_as_markdown(_report), do: "Markdown format not implemented"
  defp generate_detailed_cost_breakdown(_state), do: %{}
  defp analyze_roi(_state), do: %{}
  defp analyze_budget_utilization(_state), do: %{}
  defp analyze_token_usage(_state), do: %{}
  defp calculate_performance_metrics(_state), do: %{}
  defp analyze_errors(_state), do: %{}
  defp identify_optimization_opportunities(_state), do: []

  # Insight generation helpers
  defp add_spending_trend_insights(_state, _period, insights), do: insights
  defp add_model_efficiency_insights(_state, insights), do: insights
  defp add_provider_comparison_insights(_state, insights), do: insights
  defp add_usage_pattern_insights(_state, insights), do: insights
end
