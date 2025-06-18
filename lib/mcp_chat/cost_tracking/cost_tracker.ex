defmodule MCPChat.CostTracking.CostTracker do
  @moduledoc """
  Real-time cost tracking for LLM usage across all providers.

  This module tracks token usage and costs for each message,
  maintains running totals, and provides cost breakdowns by
  provider, model, and time period.
  """

  use GenServer
  require Logger

  alias MCPChat.CostTracking.{CostCalculator, BudgetManager, UsageLogger}
  alias MCPChat.Persistence.EventStore

  @cost_tracker_state_file "~/.mcp_chat/cost_tracker_state.dat"
  # 30 seconds
  @cost_flush_interval 30_000
  # 5 minutes
  @usage_summary_interval 300_000

  # Cost tracker state
  defstruct [
    # %{session_id => session_cost_data}
    :session_costs,
    # %{date => daily_total}
    :daily_totals,
    # %{year_month => monthly_total}
    :monthly_totals,
    # %{provider => total_cost}
    :provider_totals,
    # %{model => usage_stats}
    :model_usage,
    # Budget tracking state
    :budget_manager,
    # Timer for periodic cost flushing
    :flush_timer,
    # Timer for usage summaries
    :summary_timer,
    # Active cost alerts
    :cost_alerts,
    # Last flush timestamp
    :last_flush,
    # Running lifetime total
    :total_lifetime_cost
  ]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Record a cost for an LLM interaction.
  """
  def record_cost(session_id, cost_data) do
    GenServer.cast(__MODULE__, {:record_cost, session_id, cost_data})
  end

  @doc """
  Get current session costs.
  """
  def get_session_cost(session_id) do
    GenServer.call(__MODULE__, {:get_session_cost, session_id})
  end

  @doc """
  Get cost summary for a time period.
  """
  def get_cost_summary(period \\ :today) do
    GenServer.call(__MODULE__, {:get_cost_summary, period})
  end

  @doc """
  Get cost breakdown by provider.
  """
  def get_provider_breakdown(period \\ :today) do
    GenServer.call(__MODULE__, {:get_provider_breakdown, period})
  end

  @doc """
  Get model usage statistics.
  """
  def get_model_usage_stats(period \\ :today) do
    GenServer.call(__MODULE__, {:get_model_usage_stats, period})
  end

  @doc """
  Get budget status and alerts.
  """
  def get_budget_status do
    GenServer.call(__MODULE__, :get_budget_status)
  end

  @doc """
  Set or update budget limits.
  """
  def set_budget_limit(limit_type, amount, period \\ :monthly) do
    GenServer.call(__MODULE__, {:set_budget_limit, limit_type, amount, period})
  end

  @doc """
  Get cost optimization recommendations.
  """
  def get_optimization_recommendations do
    GenServer.call(__MODULE__, :get_optimization_recommendations)
  end

  @doc """
  Force flush cost data to persistent storage.
  """
  def flush_costs do
    GenServer.call(__MODULE__, :flush_costs)
  end

  @doc """
  Get detailed usage report.
  """
  def generate_usage_report(opts \\ []) do
    GenServer.call(__MODULE__, {:generate_usage_report, opts})
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    Logger.info("Starting Cost Tracker")

    state = %__MODULE__{
      session_costs: %{},
      daily_totals: %{},
      monthly_totals: %{},
      provider_totals: %{},
      model_usage: %{},
      cost_alerts: [],
      total_lifetime_cost: 0.0,
      last_flush: DateTime.utc_now()
    }

    case initialize_cost_tracker(state, opts) do
      {:ok, initialized_state} ->
        # Start periodic timers
        flush_timer = Process.send_after(self(), :flush_costs, @cost_flush_interval)
        summary_timer = Process.send_after(self(), :generate_usage_summary, @usage_summary_interval)

        final_state = %{initialized_state | flush_timer: flush_timer, summary_timer: summary_timer}

        Logger.info("Cost Tracker initialized",
          lifetime_cost: final_state.total_lifetime_cost,
          active_sessions: map_size(final_state.session_costs)
        )

        {:ok, final_state}

      {:error, reason} ->
        Logger.error("Failed to initialize Cost Tracker", reason: inspect(reason))
        {:stop, reason}
    end
  end

  @impl true
  def handle_cast({:record_cost, session_id, cost_data}, state) do
    new_state = record_cost_impl(session_id, cost_data, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_call({:get_session_cost, session_id}, _from, state) do
    result = Map.get(state.session_costs, session_id, %{total_cost: 0.0, message_count: 0})
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_cost_summary, period}, _from, state) do
    result = calculate_cost_summary(period, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_provider_breakdown, period}, _from, state) do
    result = calculate_provider_breakdown(period, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_model_usage_stats, period}, _from, state) do
    result = calculate_model_usage_stats(period, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_budget_status, _from, state) do
    result = BudgetManager.get_status(state.budget_manager)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:set_budget_limit, limit_type, amount, period}, _from, state) do
    case BudgetManager.set_limit(state.budget_manager, limit_type, amount, period) do
      {:ok, updated_budget_manager} ->
        new_state = %{state | budget_manager: updated_budget_manager}
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_optimization_recommendations, _from, state) do
    recommendations = generate_optimization_recommendations(state)
    {:reply, recommendations, state}
  end

  @impl true
  def handle_call(:flush_costs, _from, state) do
    case flush_cost_data(state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:generate_usage_report, opts}, _from, state) do
    report = UsageLogger.generate_report(state, opts)
    {:reply, report, state}
  end

  @impl true
  def handle_info(:flush_costs, state) do
    # Periodic cost flushing
    new_state =
      case flush_cost_data(state) do
        {:ok, flushed_state} ->
          flushed_state

        {:error, reason} ->
          Logger.error("Failed to flush cost data", reason: inspect(reason))
          state
      end

    # Schedule next flush
    timer = Process.send_after(self(), :flush_costs, @cost_flush_interval)
    final_state = %{new_state | flush_timer: timer}

    {:noreply, final_state}
  end

  @impl true
  def handle_info(:generate_usage_summary, state) do
    # Generate periodic usage summary
    generate_and_log_usage_summary(state)

    # Check budget alerts
    new_state = check_and_process_budget_alerts(state)

    # Schedule next summary
    timer = Process.send_after(self(), :generate_usage_summary, @usage_summary_interval)
    final_state = %{new_state | summary_timer: timer}

    {:noreply, final_state}
  end

  # Private functions

  defp initialize_cost_tracker(state, opts) do
    # Load persisted cost data
    state_with_data = load_persisted_cost_data(state)

    # Initialize budget manager
    budget_opts = Keyword.get(opts, :budget_config, [])

    case BudgetManager.start_link(budget_opts) do
      {:ok, budget_manager} ->
        {:ok, %{state_with_data | budget_manager: budget_manager}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp record_cost_impl(session_id, cost_data, state) do
    # Extract cost information
    %{
      provider: provider,
      model: model,
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: total_tokens,
      cost: cost,
      timestamp: timestamp
    } = cost_data

    # Update session costs
    session_cost =
      Map.get(state.session_costs, session_id, %{
        total_cost: 0.0,
        message_count: 0,
        total_tokens: 0,
        messages: []
      })

    updated_session_cost = %{
      total_cost: session_cost.total_cost + cost,
      message_count: session_cost.message_count + 1,
      total_tokens: session_cost.total_tokens + total_tokens,
      messages: [cost_data | Enum.take(session_cost.messages, 99)]
    }

    # Update daily totals
    date_key = Date.to_string(DateTime.to_date(timestamp))
    daily_total = Map.get(state.daily_totals, date_key, 0.0)
    updated_daily_totals = Map.put(state.daily_totals, date_key, daily_total + cost)

    # Update monthly totals
    month_key = "#{timestamp.year}-#{String.pad_leading("#{timestamp.month}", 2, "0")}"
    monthly_total = Map.get(state.monthly_totals, month_key, 0.0)
    updated_monthly_totals = Map.put(state.monthly_totals, month_key, monthly_total + cost)

    # Update provider totals
    provider_total = Map.get(state.provider_totals, provider, 0.0)
    updated_provider_totals = Map.put(state.provider_totals, provider, provider_total + cost)

    # Update model usage
    model_stats =
      Map.get(state.model_usage, model, %{
        usage_count: 0,
        total_cost: 0.0,
        total_tokens: 0,
        avg_cost_per_token: 0.0
      })

    updated_model_stats = %{
      usage_count: model_stats.usage_count + 1,
      total_cost: model_stats.total_cost + cost,
      total_tokens: model_stats.total_tokens + total_tokens,
      avg_cost_per_token: (model_stats.total_cost + cost) / (model_stats.total_tokens + total_tokens)
    }

    # Log cost event
    cost_event = %{
      event_type: :llm_cost_recorded,
      session_id: session_id,
      provider: provider,
      model: model,
      cost: cost,
      tokens: total_tokens,
      timestamp: timestamp
    }

    EventStore.append_event(cost_event)

    # Update state
    %{
      state
      | session_costs: Map.put(state.session_costs, session_id, updated_session_cost),
        daily_totals: updated_daily_totals,
        monthly_totals: updated_monthly_totals,
        provider_totals: updated_provider_totals,
        model_usage: Map.put(state.model_usage, model, updated_model_stats),
        total_lifetime_cost: state.total_lifetime_cost + cost
    }
  end

  defp calculate_cost_summary(period, state) do
    case period do
      :today ->
        today = Date.to_string(Date.utc_today())
        cost = Map.get(state.daily_totals, today, 0.0)
        %{period: :today, total_cost: cost, date: today}

      :this_month ->
        current_month = Date.utc_today()
        month_key = "#{current_month.year}-#{String.pad_leading("#{current_month.month}", 2, "0")}"
        cost = Map.get(state.monthly_totals, month_key, 0.0)
        %{period: :this_month, total_cost: cost, month: month_key}

      :lifetime ->
        %{period: :lifetime, total_cost: state.total_lifetime_cost}

      {:last_n_days, n} ->
        end_date = Date.utc_today()
        start_date = Date.add(end_date, -n)

        cost = calculate_date_range_cost(start_date, end_date, state)
        %{period: {:last_n_days, n}, total_cost: cost, start_date: start_date, end_date: end_date}
    end
  end

  defp calculate_provider_breakdown(period, state) do
    # For now, return current provider totals
    # In a full implementation, this would filter by period
    provider_costs = state.provider_totals
    total_cost = Enum.reduce(provider_costs, 0.0, fn {_provider, cost}, acc -> acc + cost end)

    breakdown =
      Enum.map(provider_costs, fn {provider, cost} ->
        percentage = if total_cost > 0, do: cost / total_cost * 100, else: 0.0

        %{
          provider: provider,
          cost: cost,
          percentage: percentage
        }
      end)
      |> Enum.sort_by(& &1.cost, :desc)

    %{
      period: period,
      total_cost: total_cost,
      providers: breakdown
    }
  end

  defp calculate_model_usage_stats(period, state) do
    # For now, return current model usage stats
    # In a full implementation, this would filter by period
    model_stats = state.model_usage

    sorted_models =
      Enum.map(model_stats, fn {model, stats} ->
        Map.put(stats, :model, model)
      end)
      |> Enum.sort_by(& &1.total_cost, :desc)

    %{
      period: period,
      models: sorted_models,
      total_models_used: map_size(model_stats)
    }
  end

  defp generate_optimization_recommendations(state) do
    recommendations = []

    # Analyze model usage patterns
    recommendations = analyze_model_efficiency(state, recommendations)

    # Check for high-cost sessions
    recommendations = check_high_cost_sessions(state, recommendations)

    # Analyze provider costs
    recommendations = analyze_provider_costs(state, recommendations)

    recommendations
  end

  defp analyze_model_efficiency(state, recommendations) do
    # Find models with high cost per token
    high_cost_models =
      state.model_usage
      |> Enum.filter(fn {_model, stats} -> stats.avg_cost_per_token > 0.001 end)
      |> Enum.sort_by(fn {_model, stats} -> stats.avg_cost_per_token end, :desc)
      |> Enum.take(3)

    if length(high_cost_models) > 0 do
      recommendation = %{
        type: :model_efficiency,
        priority: :medium,
        title: "Consider more cost-effective models",
        description: "Some models have high cost per token ratios",
        details: high_cost_models,
        potential_savings: estimate_model_savings(high_cost_models)
      }

      [recommendation | recommendations]
    else
      recommendations
    end
  end

  defp check_high_cost_sessions(state, recommendations) do
    # Find sessions with unusually high costs
    high_cost_sessions =
      state.session_costs
      |> Enum.filter(fn {_session_id, session_cost} -> session_cost.total_cost > 1.0 end)
      |> Enum.sort_by(fn {_session_id, session_cost} -> session_cost.total_cost end, :desc)
      |> Enum.take(5)

    if length(high_cost_sessions) > 0 do
      recommendation = %{
        type: :session_analysis,
        priority: :high,
        title: "High-cost sessions detected",
        description: "Some sessions have accumulated significant costs",
        details: high_cost_sessions,
        suggestion: "Consider using cheaper models for routine tasks"
      }

      [recommendation | recommendations]
    else
      recommendations
    end
  end

  defp analyze_provider_costs(state, recommendations) do
    # Compare provider costs if multiple providers are used
    provider_count = map_size(state.provider_totals)

    if provider_count > 1 do
      sorted_providers =
        state.provider_totals
        |> Enum.sort_by(fn {_provider, cost} -> cost end, :desc)

      [{most_expensive, highest_cost}, {least_expensive, lowest_cost} | _] = sorted_providers

      if highest_cost > lowest_cost * 2 do
        recommendation = %{
          type: :provider_optimization,
          priority: :medium,
          title: "Provider cost optimization opportunity",
          description: "Significant cost difference between providers",
          details: %{
            most_expensive: {most_expensive, highest_cost},
            least_expensive: {least_expensive, lowest_cost},
            potential_savings: highest_cost - lowest_cost
          },
          suggestion: "Consider using #{least_expensive} for routine tasks"
        }

        [recommendation | recommendations]
      else
        recommendations
      end
    else
      recommendations
    end
  end

  defp estimate_model_savings(high_cost_models) do
    # Estimate potential savings by switching to more efficient models
    Enum.reduce(high_cost_models, 0.0, fn {_model, stats}, acc ->
      # Assume 30% savings by switching to more efficient model
      acc + stats.total_cost * 0.3
    end)
  end

  defp calculate_date_range_cost(start_date, end_date, state) do
    Date.range(start_date, end_date)
    |> Enum.reduce(0.0, fn date, acc ->
      date_key = Date.to_string(date)
      acc + Map.get(state.daily_totals, date_key, 0.0)
    end)
  end

  defp flush_cost_data(state) do
    try do
      # Prepare state data for persistence
      persistable_state = %{
        daily_totals: state.daily_totals,
        monthly_totals: state.monthly_totals,
        provider_totals: state.provider_totals,
        model_usage: state.model_usage,
        total_lifetime_cost: state.total_lifetime_cost,
        last_flush: DateTime.utc_now()
      }

      # Serialize and write to file
      state_path = Path.expand(@cost_tracker_state_file)
      state_dir = Path.dirname(state_path)
      File.mkdir_p!(state_dir)

      serialized_state = :erlang.term_to_binary(persistable_state)
      File.write!(state_path, serialized_state)

      Logger.debug("Cost data flushed to persistent storage",
        path: state_path,
        size_bytes: byte_size(serialized_state)
      )

      {:ok, %{state | last_flush: persistable_state.last_flush}}
    rescue
      error ->
        Logger.error("Failed to flush cost data", error: inspect(error))
        {:error, error}
    end
  end

  defp load_persisted_cost_data(state) do
    state_path = Path.expand(@cost_tracker_state_file)

    if File.exists?(state_path) do
      try do
        serialized_state = File.read!(state_path)
        persisted_state = :erlang.binary_to_term(serialized_state)

        Logger.info("Loaded persisted cost data",
          lifetime_cost: persisted_state.total_lifetime_cost,
          last_flush: persisted_state.last_flush
        )

        %{
          state
          | daily_totals: persisted_state.daily_totals,
            monthly_totals: persisted_state.monthly_totals,
            provider_totals: persisted_state.provider_totals,
            model_usage: persisted_state.model_usage,
            total_lifetime_cost: persisted_state.total_lifetime_cost
        }
      rescue
        error ->
          Logger.warning("Failed to load persisted cost data", error: inspect(error))
          state
      end
    else
      Logger.info("No persisted cost data found, starting fresh")
      state
    end
  end

  defp generate_and_log_usage_summary(state) do
    summary = %{
      timestamp: DateTime.utc_now(),
      lifetime_cost: state.total_lifetime_cost,
      active_sessions: map_size(state.session_costs),
      daily_cost: calculate_cost_summary(:today, state).total_cost,
      monthly_cost: calculate_cost_summary(:this_month, state).total_cost,
      top_providers: get_top_providers(state, 3),
      top_models: get_top_models(state, 3)
    }

    # Log usage summary event
    summary_event = %{
      event_type: :usage_summary_generated,
      summary: summary,
      timestamp: summary.timestamp
    }

    EventStore.append_event(summary_event)

    Logger.info("Usage summary generated", summary)
  end

  defp check_and_process_budget_alerts(state) do
    # Check budget thresholds and generate alerts
    case BudgetManager.check_thresholds(state.budget_manager, state) do
      {:ok, alerts, updated_budget_manager} ->
        # Process any new alerts
        Enum.each(alerts, &process_budget_alert/1)

        %{state | budget_manager: updated_budget_manager, cost_alerts: alerts ++ state.cost_alerts}

      {:error, _reason} ->
        state
    end
  end

  defp process_budget_alert(alert) do
    Logger.warning("Budget alert triggered", alert)

    # Create alert event
    alert_event = %{
      event_type: :budget_alert_triggered,
      alert: alert,
      timestamp: DateTime.utc_now()
    }

    EventStore.append_event(alert_event)
  end

  defp get_top_providers(state, limit) do
    state.provider_totals
    |> Enum.sort_by(fn {_provider, cost} -> cost end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {provider, cost} -> %{provider: provider, cost: cost} end)
  end

  defp get_top_models(state, limit) do
    state.model_usage
    |> Enum.sort_by(fn {_model, stats} -> stats.total_cost end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {model, stats} -> %{model: model, cost: stats.total_cost} end)
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("Cost Tracker shutting down")

    # Final flush of cost data
    case flush_cost_data(state) do
      {:ok, _} -> Logger.debug("Final cost data flush completed")
      {:error, error} -> Logger.error("Final cost data flush failed", error: inspect(error))
    end

    # Cancel timers
    if state.flush_timer, do: Process.cancel_timer(state.flush_timer)
    if state.summary_timer, do: Process.cancel_timer(state.summary_timer)

    :ok
  end
end
