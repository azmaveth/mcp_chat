# ExLLM Cost Tracking Enhancement Specification

## Overview

This specification outlines enhancements to ExLLM's cost tracking system based on advanced features found in MCP Chat's implementation. These enhancements will improve cost visibility, user experience, and provide additional cost analysis capabilities.

## Current ExLLM Cost System Analysis

### Existing Strengths ✅
- Automatic cost calculation and attachment to responses
- YAML-based pricing database for easy maintenance
- Comprehensive provider coverage (8+ providers, 100+ models)
- Real-time cost calculation using actual API usage data
- Consistent cost format across all providers
- Core API: `calculate/3`, `estimate_tokens/1`, `format/1`, `list_pricing/0`, `compare/2`

### Enhancement Opportunities 🎯
Based on MCP Chat's advanced cost tracking features, the following enhancements are recommended:

## 1. Enhanced Cost Formatting

### Current ExLLM Implementation
```elixir
# Basic formatting in ExLLM.Cost.format/1
def format(cost) when is_float(cost) do
  "$#{:erlang.float_to_binary(cost, decimals: 4)}"
end
```

### Proposed Enhancement
```elixir
def format(cost, opts \\ []) do
  style = Keyword.get(opts, :style, :auto)
  precision = Keyword.get(opts, :precision, :auto)
  
  case {style, precision} do
    {:auto, :auto} -> auto_format(cost)
    {:detailed, _} -> detailed_format(cost)
    {:compact, _} -> compact_format(cost)
    {_, precision} -> fixed_precision_format(cost, precision)
  end
end

# Intelligent context-aware formatting
defp auto_format(cost) when cost < 0.01 do
  cents = cost * 100
  "#{:erlang.float_to_binary(cents, decimals: 3)}¢"
end

defp auto_format(cost) when cost < 1.0 do
  "$#{:erlang.float_to_binary(cost, decimals: 4)}"
end

defp auto_format(cost) when cost < 100.0 do
  "$#{:erlang.float_to_binary(cost, decimals: 2)}"
end

defp auto_format(cost) do
  formatted = :erlang.float_to_binary(cost, decimals: 2)
  "$#{add_thousands_separator(formatted)}"
end

# Add thousands separators for readability
defp add_thousands_separator(number_string) do
  # Implementation for comma separation
end
```

### Benefits
- **Context-aware display**: Very small costs show in cents, larger costs with appropriate precision
- **Readability**: Thousands separators for large amounts
- **Flexibility**: Multiple formatting options for different use cases

## 2. Session-Level Cost Aggregation

### Proposed New Module: `ExLLM.Cost.Session`

```elixir
defmodule ExLLM.Cost.Session do
  @moduledoc """
  Session-level cost tracking and aggregation functionality.
  """
  
  defstruct [
    :session_id,
    :start_time,
    total_cost: 0.0,
    total_input_tokens: 0,
    total_output_tokens: 0,
    messages: [],
    provider_breakdown: %{},
    model_breakdown: %{}
  ]
  
  @doc """
  Initialize a new cost tracking session.
  """
  def new(session_id) do
    %__MODULE__{
      session_id: session_id,
      start_time: DateTime.utc_now(),
      messages: []
    }
  end
  
  @doc """
  Add a response cost to the session tracking.
  """
  def add_response(session, response) do
    if response.cost do
      %{session |
        total_cost: session.total_cost + response.cost.total_cost,
        total_input_tokens: session.total_input_tokens + (response.usage.input_tokens || 0),
        total_output_tokens: session.total_output_tokens + (response.usage.output_tokens || 0),
        messages: [create_message_cost_entry(response) | session.messages],
        provider_breakdown: update_provider_breakdown(session.provider_breakdown, response),
        model_breakdown: update_model_breakdown(session.model_breakdown, response)
      }
    else
      session
    end
  end
  
  @doc """
  Get session cost summary with detailed breakdown.
  """
  def get_summary(session) do
    %{
      session_id: session.session_id,
      duration: DateTime.diff(DateTime.utc_now(), session.start_time, :second),
      total_cost: session.total_cost,
      total_tokens: session.total_input_tokens + session.total_output_tokens,
      input_tokens: session.total_input_tokens,
      output_tokens: session.total_output_tokens,
      message_count: length(session.messages),
      average_cost_per_message: safe_divide(session.total_cost, length(session.messages)),
      cost_per_1k_tokens: calculate_cost_per_1k_tokens(session),
      provider_breakdown: session.provider_breakdown,
      model_breakdown: session.model_breakdown
    }
  end
  
  @doc """
  Format session cost summary for display.
  """
  def format_summary(session, opts \\ []) do
    summary = get_summary(session)
    format = Keyword.get(opts, :format, :detailed)
    
    case format do
      :detailed -> format_detailed_summary(summary)
      :compact -> format_compact_summary(summary)
      :table -> format_table_summary(summary)
    end
  end
  
  # Private helper functions
  defp create_message_cost_entry(response) do
    %{
      timestamp: DateTime.utc_now(),
      cost: response.cost.total_cost,
      input_tokens: response.usage.input_tokens || 0,
      output_tokens: response.usage.output_tokens || 0,
      model: response.cost.model,
      provider: extract_provider_from_model(response.cost.model)
    }
  end
  
  # Additional helper functions...
end
```

### Benefits
- **Session cost aggregation**: Track cumulative costs across conversations
- **Detailed breakdowns**: Per-provider and per-model cost analysis
- **Usage analytics**: Average costs, cost per token, efficiency metrics
- **Multiple display formats**: Detailed, compact, and table formats

## 3. Cost Analysis and Comparison Tools

### Proposed Module: `ExLLM.Cost.Analysis`

```elixir
defmodule ExLLM.Cost.Analysis do
  @moduledoc """
  Advanced cost analysis and comparison tools.
  """
  
  @doc """
  Compare costs across multiple providers for the same input.
  """
  def compare_providers(input_text, providers, opts \\ []) do
    estimated_tokens = ExLLM.Cost.estimate_tokens(input_text)
    
    providers
    |> Enum.map(fn provider ->
      models = get_available_models(provider)
      costs = Enum.map(models, &calculate_estimated_cost(&1, estimated_tokens))
      
      %{
        provider: provider,
        models: costs,
        cheapest: Enum.min_by(costs, & &1.total_cost),
        most_expensive: Enum.max_by(costs, & &1.total_cost)
      }
    end)
    |> sort_by_cheapest()
  end
  
  @doc """
  Get cost optimization recommendations.
  """
  def get_recommendations(usage_pattern, opts \\ []) do
    budget = Keyword.get(opts, :budget)
    priorities = Keyword.get(opts, :priorities, [:cost])
    
    models = ExLLM.Cost.list_pricing()
    
    recommendations =
      models
      |> filter_by_budget(budget)
      |> score_models(usage_pattern, priorities)
      |> Enum.take(5)
    
    %{
      recommendations: recommendations,
      analysis: analyze_usage_pattern(usage_pattern),
      potential_savings: calculate_potential_savings(usage_pattern, recommendations)
    }
  end
  
  @doc """
  Calculate cost efficiency metrics.
  """
  def calculate_efficiency(session_data) do
    %{
      cost_per_message: session_data.total_cost / length(session_data.messages),
      cost_per_1k_tokens: (session_data.total_cost / session_data.total_tokens) * 1000,
      input_output_ratio: session_data.total_input_tokens / session_data.total_output_tokens,
      efficiency_score: calculate_efficiency_score(session_data),
      benchmark_comparison: compare_to_benchmarks(session_data)
    }
  end
  
  @doc """
  Generate cost forecasting based on usage trends.
  """
  def forecast_costs(historical_sessions, forecast_period \\ :month) do
    usage_trend = analyze_usage_trend(historical_sessions)
    cost_trend = analyze_cost_trend(historical_sessions)
    
    %{
      forecast_period: forecast_period,
      estimated_messages: extrapolate_messages(usage_trend, forecast_period),
      estimated_tokens: extrapolate_tokens(usage_trend, forecast_period),
      estimated_cost: extrapolate_cost(cost_trend, forecast_period),
      confidence_level: calculate_confidence(historical_sessions),
      recommendations: generate_cost_recommendations(cost_trend)
    }
  end
end
```

### Benefits
- **Provider cost comparison**: Find cheapest options for specific use cases
- **Optimization recommendations**: Suggest cost-effective model choices
- **Efficiency metrics**: Understand cost patterns and efficiency
- **Cost forecasting**: Predict future costs based on usage trends

## 4. Enhanced Pricing Database Features

### Proposed Enhancement: Dynamic Pricing Updates

```elixir
defmodule ExLLM.Cost.PricingManager do
  @moduledoc """
  Dynamic pricing database management with update capabilities.
  """
  
  @doc """
  Load pricing from external source (API, updated YAML, etc.)
  """
  def update_pricing(source \\ :yaml) do
    case source do
      :yaml -> load_pricing_from_yaml()
      :api -> fetch_latest_pricing_from_api()
      :manual -> load_manual_pricing_updates()
    end
  end
  
  @doc """
  Validate pricing data integrity.
  """
  def validate_pricing(pricing_data) do
    required_fields = [:model, :provider, :input_per_1m, :output_per_1m]
    
    pricing_data
    |> Enum.map(&validate_pricing_entry(&1, required_fields))
    |> Enum.group_by(& &1.status)
  end
  
  @doc """
  Get pricing history and changes.
  """
  def get_pricing_history(model, provider) do
    # Implementation to track pricing changes over time
  end
  
  @doc """
  Compare current pricing with historical data.
  """
  def detect_pricing_changes do
    # Implementation to detect when pricing has changed
  end
end
```

### Benefits
- **Dynamic updates**: Update pricing without code changes
- **Validation**: Ensure pricing data integrity
- **Change tracking**: Monitor pricing changes over time
- **External integration**: Support for API-based pricing updates

## 5. Cost Display and UI Utilities

### Proposed Module: `ExLLM.Cost.Display`

```elixir
defmodule ExLLM.Cost.Display do
  @moduledoc """
  Utilities for displaying cost information in various formats.
  """
  
  @doc """
  Generate cost breakdown table.
  """
  def cost_breakdown_table(cost_data, opts \\ []) do
    format = Keyword.get(opts, :format, :ascii)
    
    case format do
      :ascii -> generate_ascii_table(cost_data)
      :markdown -> generate_markdown_table(cost_data)
      :csv -> generate_csv_output(cost_data)
      :json -> Jason.encode!(cost_data)
    end
  end
  
  @doc """
  Generate cost summary for CLI display.
  """
  def cli_summary(session_summary) do
    """
    💰 Session Cost Summary
    =====================
    
    Total Cost: #{ExLLM.Cost.format(session_summary.total_cost)}
    Total Tokens: #{format_number(session_summary.total_tokens)}
      ├─ Input: #{format_number(session_summary.input_tokens)}
      └─ Output: #{format_number(session_summary.output_tokens)}
    
    Messages: #{session_summary.message_count}
    Avg Cost/Message: #{ExLLM.Cost.format(session_summary.average_cost_per_message)}
    Cost/1K Tokens: #{ExLLM.Cost.format(session_summary.cost_per_1k_tokens)}
    
    #{format_provider_breakdown(session_summary.provider_breakdown)}
    """
  end
  
  @doc """
  Generate real-time cost display for streaming responses.
  """
  def streaming_cost_display(current_cost, estimated_final_cost) do
    progress = current_cost / estimated_final_cost * 100
    
    """
    💰 #{ExLLM.Cost.format(current_cost)} (#{format_percentage(progress)}% of estimated #{ExLLM.Cost.format(estimated_final_cost)})
    """
  end
  
  @doc """
  Generate cost alert messages.
  """
  def cost_alert(alert_type, data) do
    case alert_type do
      :budget_exceeded -> "🚨 Budget exceeded! Current: #{ExLLM.Cost.format(data.current)}, Budget: #{ExLLM.Cost.format(data.budget)}"
      :high_cost_warning -> "⚠️  High cost detected: #{ExLLM.Cost.format(data.cost)} for this message"
      :efficiency_warning -> "📊 Low efficiency detected. Consider switching to a more cost-effective model."
    end
  end
end
```

### Benefits
- **Flexible display formats**: ASCII tables, markdown, CSV, JSON
- **CLI-friendly output**: Well-formatted terminal display
- **Real-time cost display**: Show costs during streaming responses
- **Alert system**: Budget and efficiency warnings

## 6. Configuration and Settings

### Proposed Enhancement: Cost Tracking Configuration

```elixir
# In ExLLM configuration
config :ex_llm, :cost_tracking,
  enabled: true,
  auto_attach: true,  # Automatically attach cost to responses
  session_tracking: true,  # Enable session-level cost aggregation
  display_format: :auto,  # :auto, :detailed, :compact
  budget_alerts: [
    session_budget: 1.0,  # Alert if session exceeds $1.00
    message_budget: 0.10   # Alert if single message exceeds $0.10
  ],
  efficiency_monitoring: true,
  cost_logging: :info  # Log cost information at info level
```

### Benefits
- **Configurable behavior**: Enable/disable features as needed
- **Budget controls**: Set spending limits and alerts
- **Logging integration**: Optional cost logging
- **Default settings**: Sensible defaults with override capability

## Implementation Priority

### Phase 1 (High Priority)
1. **Enhanced Cost Formatting** - Immediate user experience improvement
2. **Session Cost Aggregation** - Enable comprehensive cost tracking
3. **Display Utilities** - Better cost visibility

### Phase 2 (Medium Priority)
1. **Cost Analysis Tools** - Advanced cost optimization features
2. **Configuration System** - Flexible cost tracking behavior
3. **Alert System** - Budget and efficiency monitoring

### Phase 3 (Future Enhancement)
1. **Dynamic Pricing Updates** - External pricing integration
2. **Advanced Analytics** - Historical analysis and forecasting
3. **Integration Helpers** - Standardized integration patterns

## Testing Requirements

### Unit Tests
- Cost calculation accuracy across all providers
- Formatting functions with various input ranges
- Session aggregation logic
- Analysis and comparison algorithms

### Integration Tests
- Cost data flow through response pipeline
- Session tracking across multiple messages
- Configuration system behavior
- Alert triggering and display

### Performance Tests
- Cost calculation performance impact
- Memory usage for session tracking
- Large dataset analysis performance

## Backward Compatibility

All enhancements must maintain backward compatibility with existing ExLLM.Cost API:
- Existing functions maintain current signatures
- New features are opt-in via configuration
- Default behavior remains unchanged
- Deprecation warnings for any changes

## Documentation Requirements

1. **API Documentation**: Complete function documentation with examples
2. **Configuration Guide**: How to configure cost tracking features
3. **Integration Guide**: How to integrate enhanced cost tracking
4. **Migration Guide**: Upgrading from basic to enhanced cost tracking
5. **Examples**: Common usage patterns and integration examples

## Success Metrics

1. **User Experience**: Improved cost visibility and understanding
2. **Adoption**: High usage of enhanced cost features
3. **Performance**: Minimal impact on response time and memory
4. **Accuracy**: Precise cost calculations across all providers
5. **Maintainability**: Easy to update pricing and add new providers

This specification provides a comprehensive roadmap for enhancing ExLLM's cost tracking system with advanced features while maintaining its core strengths and architectural principles.