defmodule MCPChat.CostTracking.CostDisplay do
  @moduledoc """
  Real-time cost display and visualization for the CLI interface.

  This module handles formatting and displaying cost information
  in the terminal, including running totals, budget status, and
  cost breakdowns.
  """

  alias MCPChat.CostTracking.{CostTracker, BudgetManager}

  @doc """
  Display current session cost information.
  """
  def display_session_cost(session_id, opts \\ []) do
    case CostTracker.get_session_cost(session_id) do
      session_cost when is_map(session_cost) ->
        format_session_cost(session_cost, opts)

      _ ->
        format_no_cost_data()
    end
  end

  @doc """
  Display running cost totals.
  """
  def display_running_totals(opts \\ []) do
    period = Keyword.get(opts, :period, :today)
    show_breakdown = Keyword.get(opts, :breakdown, false)

    summary = CostTracker.get_cost_summary(period)

    output = format_cost_summary(summary, opts)

    if show_breakdown do
      provider_breakdown = CostTracker.get_provider_breakdown(period)
      output <> "\n" <> format_provider_breakdown(provider_breakdown, opts)
    else
      output
    end
  end

  @doc """
  Display budget status with alerts.
  """
  def display_budget_status(opts \\ []) do
    budget_status = CostTracker.get_budget_status()
    format_budget_status(budget_status, opts)
  end

  @doc """
  Display cost for the last message.
  """
  def display_message_cost(cost_data, opts \\ []) do
    format_message_cost(cost_data, opts)
  end

  @doc """
  Display cost optimization recommendations.
  """
  def display_cost_recommendations(opts \\ []) do
    recommendations = CostTracker.get_optimization_recommendations()
    format_recommendations(recommendations, opts)
  end

  @doc """
  Create a cost status bar for the terminal.
  """
  def create_cost_status_bar(session_id, opts \\ []) do
    compact = Keyword.get(opts, :compact, true)
    show_budget = Keyword.get(opts, :show_budget, true)

    session_cost = CostTracker.get_session_cost(session_id)
    today_summary = CostTracker.get_cost_summary(:today)

    status_parts = []

    # Session cost
    session_part = "Session: #{format_currency(session_cost.total_cost || 0.0)}"
    status_parts = [session_part | status_parts]

    # Today's total
    today_part = "Today: #{format_currency(today_summary.total_cost)}"
    status_parts = [today_part | status_parts]

    # Budget status if enabled
    status_parts =
      if show_budget do
        budget_status = CostTracker.get_budget_status()
        budget_part = format_budget_part(budget_status, today_summary.total_cost)
        [budget_part | status_parts]
      else
        status_parts
      end

    separator = if compact, do: " | ", else: " │ "

    status_parts
    |> Enum.reverse()
    |> Enum.join(separator)
    |> add_color_coding(today_summary.total_cost, session_cost.total_cost || 0.0)
  end

  @doc """
  Format cost information for inline display.
  """
  def format_inline_cost(cost_data, opts \\ []) do
    show_tokens = Keyword.get(opts, :tokens, true)
    show_model = Keyword.get(opts, :model, false)

    cost_str = format_currency(cost_data.cost)

    parts = [cost_str]

    parts =
      if show_tokens do
        token_str = format_tokens(cost_data.total_tokens)
        [token_str | parts]
      else
        parts
      end

    parts =
      if show_model do
        model_str = format_model_name(cost_data.model)
        [model_str | parts]
      else
        parts
      end

    parts
    |> Enum.reverse()
    |> Enum.join(" ")
    |> colorize_cost(cost_data.cost)
  end

  # Private formatting functions

  defp format_session_cost(session_cost, opts) do
    show_details = Keyword.get(opts, :details, false)

    main_info = [
      "Session Cost: #{format_currency(session_cost.total_cost)}",
      "Messages: #{session_cost.message_count}",
      "Tokens: #{format_tokens(session_cost.total_tokens)}"
    ]

    if show_details and length(session_cost.messages || []) > 0 do
      details = format_session_details(session_cost.messages)
      Enum.join(main_info, " | ") <> "\n" <> details
    else
      Enum.join(main_info, " | ")
    end
  end

  defp format_session_details(messages) do
    recent_messages = Enum.take(messages, 5)

    details =
      Enum.map(recent_messages, fn message ->
        "  #{format_currency(message.cost)} (#{message.model})"
      end)

    header = "Recent messages:"
    ([header] ++ details) |> Enum.join("\n")
  end

  defp format_no_cost_data do
    "No cost data available for this session"
  end

  defp format_cost_summary(summary, opts) do
    period_str = format_period_name(summary.period)
    show_percentage = Keyword.get(opts, :percentage, false)

    main_line = "#{period_str}: #{format_currency(summary.total_cost)}"

    if show_percentage and summary[:previous_period_cost] do
      change = calculate_percentage_change(summary.total_cost, summary.previous_period_cost)
      change_str = format_percentage_change(change)
      main_line <> " " <> change_str
    else
      main_line
    end
  end

  defp format_provider_breakdown(breakdown, opts) do
    show_percentages = Keyword.get(opts, :percentages, true)
    limit = Keyword.get(opts, :limit, 5)

    header = "Provider Breakdown:"

    provider_lines =
      breakdown.providers
      |> Enum.take(limit)
      |> Enum.map(fn provider ->
        cost_str = format_currency(provider.cost)

        if show_percentages do
          percentage_str = format_percentage(provider.percentage)
          "  #{provider.provider}: #{cost_str} (#{percentage_str})"
        else
          "  #{provider.provider}: #{cost_str}"
        end
      end)

    ([header] ++ provider_lines) |> Enum.join("\n")
  end

  defp format_budget_status(budget_status, opts) do
    show_details = Keyword.get(opts, :details, false)

    lines = []

    # Daily budget
    lines =
      if budget_status.daily_limit do
        today_cost = CostTracker.get_cost_summary(:today).total_cost
        daily_usage = today_cost / budget_status.daily_limit * 100

        daily_line =
          "Daily Budget: #{format_currency(today_cost)} / #{format_currency(budget_status.daily_limit)} (#{format_percentage(daily_usage)})"

        [daily_line | lines]
      else
        lines
      end

    # Monthly budget
    lines =
      if budget_status.monthly_limit do
        month_cost = CostTracker.get_cost_summary(:this_month).total_cost
        monthly_usage = month_cost / budget_status.monthly_limit * 100

        monthly_line =
          "Monthly Budget: #{format_currency(month_cost)} / #{format_currency(budget_status.monthly_limit)} (#{format_percentage(monthly_usage)})"

        [monthly_line | lines]
      else
        lines
      end

    # Alerts
    lines =
      if length(budget_status.active_alerts) > 0 and show_details do
        alert_lines = format_budget_alerts(budget_status.active_alerts)
        lines ++ alert_lines
      else
        lines
      end

    if length(lines) > 0 do
      Enum.reverse(lines) |> Enum.join("\n")
    else
      "No budget limits set"
    end
  end

  defp format_budget_alerts(alerts) do
    header = "Active Alerts:"

    alert_lines =
      Enum.map(alerts, fn alert ->
        case alert.type do
          :approaching_limit ->
            "  ⚠️  #{format_period_name(alert.period)} budget #{format_percentage(alert.threshold)} reached"

          :limit_exceeded ->
            "  🚨 #{format_period_name(alert.period)} budget exceeded by #{format_currency(alert.overage)}"

          _ ->
            "  ℹ️  #{alert.type}"
        end
      end)

    [header | alert_lines]
  end

  defp format_message_cost(cost_data, opts) when is_map(cost_data) do
    compact = Keyword.get(opts, :compact, false)
    show_breakdown = Keyword.get(opts, :breakdown, false)

    if compact do
      format_inline_cost(cost_data, opts)
    else
      main_line =
        "Cost: #{format_currency(cost_data.cost)} | Tokens: #{format_tokens(cost_data.total_tokens)} | Model: #{cost_data.model}"

      if show_breakdown do
        breakdown =
          "  Input: #{format_currency(cost_data.input_cost)} (#{format_tokens(cost_data.prompt_tokens)}) | Output: #{format_currency(cost_data.output_cost)} (#{format_tokens(cost_data.completion_tokens)})"

        main_line <> "\n" <> breakdown
      else
        main_line
      end
    end
  end

  defp format_message_cost(_cost_data, _opts) do
    "Cost data unavailable"
  end

  defp format_recommendations(recommendations, opts) do
    limit = Keyword.get(opts, :limit, 3)
    show_details = Keyword.get(opts, :details, false)

    if recommendations == [] do
      "✅ No optimization recommendations at this time"
    else
      header = "💡 Cost Optimization Recommendations:"

      rec_lines =
        recommendations
        |> Enum.take(limit)
        |> Enum.with_index(1)
        |> Enum.map(fn {rec, index} ->
          priority_icon = get_priority_icon(rec.priority)
          line = "#{index}. #{priority_icon} #{rec.title}"

          if show_details do
            line <> "\n   #{rec.description}"
          else
            line
          end
        end)

      ([header] ++ rec_lines) |> Enum.join("\n")
    end
  end

  defp format_budget_part(budget_status, current_cost) do
    cond do
      budget_status.daily_limit ->
        usage = current_cost / budget_status.daily_limit * 100
        "Budget: #{format_percentage(usage)}"

      budget_status.monthly_limit ->
        month_cost = CostTracker.get_cost_summary(:this_month).total_cost
        usage = month_cost / budget_status.monthly_limit * 100
        "Budget: #{format_percentage(usage)}"

      true ->
        "Budget: Not set"
    end
  end

  # Utility formatting functions

  defp format_currency(amount) when is_number(amount) do
    if amount < 0.01 do
      "$#{:erlang.float_to_binary(amount, decimals: 4)}"
    else
      "$#{:erlang.float_to_binary(amount, decimals: 2)}"
    end
  end

  defp format_currency(_), do: "$0.00"

  defp format_tokens(token_count) when is_number(token_count) do
    cond do
      token_count >= 1000 ->
        "#{Float.round(token_count / 1000.0, 1)}k tokens"

      token_count > 0 ->
        "#{round(token_count)} tokens"

      true ->
        "0 tokens"
    end
  end

  defp format_tokens(_), do: "0 tokens"

  defp format_percentage(percentage) when is_number(percentage) do
    "#{Float.round(percentage, 1)}%"
  end

  defp format_percentage(_), do: "0%"

  defp format_period_name(period) do
    case period do
      :today -> "Today"
      :this_week -> "This Week"
      :this_month -> "This Month"
      :lifetime -> "Lifetime"
      {:last_n_days, n} -> "Last #{n} Days"
      _ -> "Period"
    end
  end

  defp format_model_name(model) when is_binary(model) do
    # Abbreviate long model names
    case model do
      "claude-3-5-sonnet-20241022" -> "Claude-3.5-Sonnet"
      "gpt-4o-mini" -> "GPT-4o-mini"
      "gpt-4-turbo" -> "GPT-4-Turbo"
      _ -> model
    end
  end

  defp format_model_name(model), do: to_string(model)

  defp format_percentage_change(change) when is_number(change) do
    if change > 0 do
      color_text("(+#{format_percentage(change)})", :red)
    else
      color_text("(#{format_percentage(change)})", :green)
    end
  end

  defp format_percentage_change(_), do: ""

  defp calculate_percentage_change(current, previous)
       when is_number(current) and is_number(previous) and previous > 0 do
    (current - previous) / previous * 100
  end

  defp calculate_percentage_change(_, _), do: 0

  defp get_priority_icon(priority) do
    case priority do
      :high -> "🔴"
      :medium -> "🟡"
      :low -> "🟢"
      _ -> "ℹ️"
    end
  end

  # Color coding functions

  defp add_color_coding(text, today_cost, session_cost) do
    cond do
      session_cost > 1.0 or today_cost > 5.0 ->
        color_text(text, :red)

      session_cost > 0.5 or today_cost > 2.0 ->
        color_text(text, :yellow)

      true ->
        color_text(text, :green)
    end
  end

  defp colorize_cost(text, cost) when is_number(cost) do
    cond do
      cost > 0.1 -> color_text(text, :red)
      cost > 0.01 -> color_text(text, :yellow)
      true -> color_text(text, :green)
    end
  end

  defp colorize_cost(text, _), do: text

  defp color_text(text, color) do
    case color do
      :red -> IO.ANSI.red() <> text <> IO.ANSI.reset()
      :green -> IO.ANSI.green() <> text <> IO.ANSI.reset()
      :yellow -> IO.ANSI.yellow() <> text <> IO.ANSI.reset()
      :blue -> IO.ANSI.blue() <> text <> IO.ANSI.reset()
      :magenta -> IO.ANSI.magenta() <> text <> IO.ANSI.reset()
      :cyan -> IO.ANSI.cyan() <> text <> IO.ANSI.reset()
      _ -> text
    end
  end
end
