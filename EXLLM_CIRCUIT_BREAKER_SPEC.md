# ExLLM Circuit Breaker Implementation Specification

## Overview

This specification outlines the implementation of circuit breaker patterns in ExLLM's retry mechanism, based on analysis of MCP Chat's circuit breaker implementation and ExLLM's existing fault tolerance capabilities. The goal is to enhance ExLLM with production-grade circuit breaker functionality while leveraging its superior retry logic.

## Current State Analysis

### ExLLM Strengths ✅
- Advanced retry logic with exponential backoff and jitter
- Provider-specific retry policies and error handling
- Comprehensive error classification (retryable vs non-retryable)
- Stream recovery capabilities for interrupted operations
- Robust HTTP client with timeout and connection management

### Missing Circuit Breaker ❌
- Circuit breaker module defined but not implemented
- No failure rate tracking across requests
- No fail-fast mechanism during service outages
- No protection against cascading failures

## Architecture Design

### 1. High-Performance Circuit Breaker Core

#### Primary Implementation: ETS-Based State Management

```elixir
defmodule ExLLM.CircuitBreaker do
  @moduledoc """
  High-performance circuit breaker implementation using ETS for concurrent access.
  
  Implements the classic three-state pattern:
  - :closed - Normal operation, requests pass through
  - :open - Service failing, requests blocked with fail-fast
  - :half_open - Testing service recovery with limited requests
  """
  
  @table_name :ex_llm_circuit_breakers
  
  # Circuit breaker state structure
  @circuit_fields [
    :name,              # Circuit identifier
    :state,             # :closed | :open | :half_open  
    :failure_count,     # Current consecutive failures
    :success_count,     # Successes in half-open state
    :last_failure_time, # Timestamp of last failure
    :config             # Circuit configuration
  ]
  
  defstruct @circuit_fields
  
  @doc """
  Initialize the circuit breaker system.
  Called during ExLLM application startup.
  """
  def init do
    :ets.new(@table_name, [
      :named_table, 
      :public, 
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])
  end
  
  @doc """
  Execute a function with circuit breaker protection.
  
  ## Options
    * `:failure_threshold` - Number of failures before opening circuit (default: 5)
    * `:success_threshold` - Number of successes to close from half-open (default: 3)
    * `:reset_timeout` - Milliseconds before attempting half-open (default: 30_000)
    * `:timeout` - Function execution timeout (default: 30_000)
    * `:name` - Circuit name (auto-generated if not provided)
  
  ## Examples
      iex> ExLLM.CircuitBreaker.call("api_service", fn -> 
      ...>   HTTPClient.get("/api/data")
      ...> end)
      {:ok, response}
      
      iex> ExLLM.CircuitBreaker.call("failing_service", fn -> 
      ...>   raise "Service down"
      ...> end)
      {:error, :circuit_open}
  """
  def call(circuit_name, fun, opts \\ []) when is_function(fun, 0) do
    config = build_config(opts)
    state = get_or_create_circuit(circuit_name, config)
    
    case state.state do
      :closed -> 
        execute_with_monitoring(circuit_name, fun, config)
      :open -> 
        handle_open_circuit(circuit_name, state, config)
      :half_open ->
        execute_with_monitoring(circuit_name, fun, config)
    end
  end
  
  @doc """
  Get current circuit breaker state and statistics.
  """
  def get_stats(circuit_name) do
    case :ets.lookup(@table_name, circuit_name) do
      [{^circuit_name, state}] -> 
        {:ok, Map.from_struct(state)}
      [] -> 
        {:error, :circuit_not_found}
    end
  end
  
  @doc """
  Manually reset a circuit breaker to closed state.
  """
  def reset(circuit_name) do
    case :ets.lookup(@table_name, circuit_name) do
      [{^circuit_name, state}] ->
        new_state = %{state | 
          state: :closed,
          failure_count: 0,
          success_count: 0,
          last_failure_time: nil
        }
        :ets.insert(@table_name, {circuit_name, new_state})
        emit_telemetry(:state_change, circuit_name, state.state, :closed)
        :ok
      [] ->
        {:error, :circuit_not_found}
    end
  end
  
  # Private Implementation
  
  defp execute_with_monitoring(circuit_name, fun, config) do
    start_time = System.monotonic_time(:millisecond)
    timeout = config.timeout
    
    task = Task.async(fun)
    
    try do
      case Task.yield(task, timeout) do
        {:ok, result} ->
          duration = System.monotonic_time(:millisecond) - start_time
          record_success(circuit_name)
          emit_telemetry(:call_success, circuit_name, %{duration: duration})
          {:ok, result}
          
        nil ->
          Task.shutdown(task, :brutal_kill)
          record_failure(circuit_name, :timeout)
          emit_telemetry(:call_timeout, circuit_name, %{timeout: timeout})
          {:error, :timeout}
      end
    rescue
      error ->
        duration = System.monotonic_time(:millisecond) - start_time
        record_failure(circuit_name, error)
        emit_telemetry(:call_failure, circuit_name, %{duration: duration, error: error})
        {:error, error}
    end
  end
  
  defp handle_open_circuit(circuit_name, state, config) do
    if should_attempt_reset?(state, config) do
      transition_to_half_open(circuit_name)
      emit_telemetry(:state_change, circuit_name, :open, :half_open)
      execute_with_monitoring(circuit_name, fn -> 
        {:error, :circuit_testing}
      end, config)
    else
      emit_telemetry(:call_rejected, circuit_name, %{reason: :circuit_open})
      {:error, :circuit_open}
    end
  end
  
  defp record_success(circuit_name) do
    [{^circuit_name, state}] = :ets.lookup(@table_name, circuit_name)
    
    new_state = case state.state do
      :half_open ->
        new_success_count = state.success_count + 1
        if new_success_count >= state.config.success_threshold do
          %{state | 
            state: :closed,
            success_count: 0,
            failure_count: 0
          }
        else
          %{state | success_count: new_success_count}
        end
      
      :closed ->
        %{state | failure_count: 0}
    end
    
    :ets.insert(@table_name, {circuit_name, new_state})
    
    if state.state != new_state.state do
      emit_telemetry(:state_change, circuit_name, state.state, new_state.state)
    end
  end
  
  defp record_failure(circuit_name, reason) do
    [{^circuit_name, state}] = :ets.lookup(@table_name, circuit_name)
    
    new_failure_count = state.failure_count + 1
    current_time = System.monotonic_time(:millisecond)
    
    new_state = if new_failure_count >= state.config.failure_threshold do
      %{state |
        state: :open,
        failure_count: new_failure_count,
        last_failure_time: current_time
      }
    else
      %{state |
        failure_count: new_failure_count,
        last_failure_time: current_time
      }
    end
    
    :ets.insert(@table_name, {circuit_name, new_state})
    
    if state.state != new_state.state do
      emit_telemetry(:state_change, circuit_name, state.state, new_state.state)
    end
    
    emit_telemetry(:failure_recorded, circuit_name, %{
      reason: reason,
      failure_count: new_failure_count,
      threshold: state.config.failure_threshold
    })
  end
  
  defp should_attempt_reset?(state, config) do
    current_time = System.monotonic_time(:millisecond)
    time_since_failure = current_time - (state.last_failure_time || 0)
    time_since_failure >= config.reset_timeout
  end
  
  defp transition_to_half_open(circuit_name) do
    [{^circuit_name, state}] = :ets.lookup(@table_name, circuit_name)
    new_state = %{state | state: :half_open, success_count: 0}
    :ets.insert(@table_name, {circuit_name, new_state})
  end
  
  defp get_or_create_circuit(circuit_name, config) do
    case :ets.lookup(@table_name, circuit_name) do
      [{^circuit_name, state}] -> 
        # Update config if provided
        updated_state = %{state | config: Map.merge(state.config, config)}
        :ets.insert(@table_name, {circuit_name, updated_state})
        updated_state
      [] -> 
        create_circuit(circuit_name, config)
    end
  end
  
  defp create_circuit(circuit_name, config) do
    state = %__MODULE__{
      name: circuit_name,
      state: :closed,
      failure_count: 0,
      success_count: 0,
      last_failure_time: nil,
      config: config
    }
    :ets.insert(@table_name, {circuit_name, state})
    emit_telemetry(:circuit_created, circuit_name, %{config: config})
    state
  end
  
  defp build_config(opts) do
    %{
      failure_threshold: Keyword.get(opts, :failure_threshold, 5),
      success_threshold: Keyword.get(opts, :success_threshold, 3),
      reset_timeout: Keyword.get(opts, :reset_timeout, 30_000),
      timeout: Keyword.get(opts, :timeout, 30_000)
    }
  end
  
  defp emit_telemetry(event, circuit_name, metadata) do
    :telemetry.execute(
      [:ex_llm, :circuit_breaker, event],
      %{count: 1},
      %{circuit_name: circuit_name} |> Map.merge(metadata)
    )
  end
end
```

### 2. Integration with Retry Logic

#### Enhanced Retry Module

```elixir
defmodule ExLLM.Retry do
  @moduledoc """
  Enhanced retry logic with circuit breaker integration.
  """
  
  @doc """
  Execute function with combined circuit breaker and retry protection.
  
  This function integrates circuit breaker protection with ExLLM's existing
  retry logic, providing comprehensive fault tolerance.
  
  ## Options
    * `:circuit_breaker` - Circuit breaker options (see ExLLM.CircuitBreaker.call/3)
    * `:retry` - Retry options (see with_retry/2)
    * `:circuit_name` - Custom circuit name (default: auto-generated)
  """
  def with_circuit_breaker_retry(fun, opts \\ []) when is_function(fun, 0) do
    {circuit_opts, retry_opts} = split_options(opts)
    circuit_name = Keyword.get(circuit_opts, :circuit_name) || generate_circuit_name()
    
    ExLLM.CircuitBreaker.call(circuit_name, fn ->
      with_retry(fun, retry_opts)
    end, circuit_opts)
  end
  
  @doc """
  Provider-specific retry with circuit breaker protection.
  
  Uses provider-specific configurations for both retry and circuit breaker behavior.
  """
  def with_provider_circuit_breaker(provider, fun, opts \\ []) do
    circuit_name = :"#{provider}_circuit"
    provider_config = get_provider_config(provider)
    
    # Merge provider defaults with user options
    circuit_opts = Keyword.merge(provider_config.circuit_breaker, 
                                 Keyword.get(opts, :circuit_breaker, []))
    retry_opts = Keyword.merge(provider_config.retry,
                              Keyword.get(opts, :retry, []))
    
    ExLLM.CircuitBreaker.call(circuit_name, fn ->
      with_retry(fun, retry_opts)
    end, circuit_opts)
  end
  
  @doc """
  Enhanced chat function with circuit breaker protection.
  """
  def chat_with_circuit_breaker(provider, messages, opts \\ []) do
    with_provider_circuit_breaker(provider, fn ->
      ExLLM.chat(provider, messages, opts)
    end, opts)
  end
  
  @doc """
  Enhanced streaming with circuit breaker protection.
  """
  def stream_with_circuit_breaker(provider, messages, opts \\ []) do
    circuit_opts = Keyword.put(opts, :timeout, 120_000) # Longer timeout for streams
    
    with_provider_circuit_breaker(provider, fn ->
      ExLLM.stream_chat(provider, messages, opts)
    end, circuit_breaker: circuit_opts)
  end
  
  # Provider-specific configurations
  defp get_provider_config(provider) do
    base_config = %{
      circuit_breaker: [
        failure_threshold: 5,
        success_threshold: 3,
        reset_timeout: 30_000,
        timeout: 30_000
      ],
      retry: [
        max_attempts: 3,
        base_delay: 1000,
        max_delay: 30_000,
        jitter: true
      ]
    }
    
    provider_overrides = case provider do
      :openai -> %{
        circuit_breaker: [failure_threshold: 3, reset_timeout: 60_000],
        retry: [max_delay: 60_000]
      }
      :anthropic -> %{
        circuit_breaker: [failure_threshold: 5, reset_timeout: 30_000],
        retry: [base_delay: 2000]
      }
      :bedrock -> %{
        circuit_breaker: [failure_threshold: 7, reset_timeout: 45_000],
        retry: [max_attempts: 5, max_delay: 20_000]
      }
      _ -> %{}
    end
    
    deep_merge(base_config, provider_overrides)
  end
  
  defp split_options(opts) do
    circuit_breaker_opts = Keyword.get(opts, :circuit_breaker, [])
    retry_opts = Keyword.get(opts, :retry, [])
    
    # Add any top-level options to retry_opts for backward compatibility
    retry_opts = opts
    |> Keyword.drop([:circuit_breaker, :circuit_name])
    |> Keyword.merge(retry_opts)
    
    {circuit_breaker_opts, retry_opts}
  end
  
  defp generate_circuit_name do
    "circuit_#{System.unique_integer([:positive])}"
  end
  
  defp deep_merge(left, right) do
    Map.merge(left, right, fn
      _key, left_val, right_val when is_map(left_val) and is_map(right_val) ->
        deep_merge(left_val, right_val)
      _key, _left_val, right_val ->
        right_val
    end)
  end
end
```

### 3. Stream Recovery Integration

#### Circuit Breaker for Stream Operations

```elixir
defmodule ExLLM.StreamRecovery.CircuitBreaker do
  @moduledoc """
  Circuit breaker integration for stream recovery operations.
  """
  
  @doc """
  Start a recoverable stream with circuit breaker protection.
  """
  def recoverable_stream_with_circuit_breaker(provider, messages, opts \\ []) do
    circuit_name = :"#{provider}_stream_circuit"
    
    # Longer timeout for streaming operations
    circuit_opts = [
      timeout: Keyword.get(opts, :timeout, 120_000),
      failure_threshold: Keyword.get(opts, :failure_threshold, 3),
      reset_timeout: Keyword.get(opts, :reset_timeout, 60_000)
    ]
    
    ExLLM.CircuitBreaker.call(circuit_name, fn ->
      ExLLM.StreamRecovery.recoverable_stream(provider, messages, opts)
    end, circuit_opts)
  end
  
  @doc """
  Recover a stream with circuit breaker protection.
  """
  def recover_with_circuit_breaker(recovery_id, opts \\ []) do
    case ExLLM.StreamRecovery.get_recovery_context(recovery_id) do
      {:ok, context} ->
        circuit_name = :"#{context.provider}_stream_circuit"
        
        ExLLM.CircuitBreaker.call(circuit_name, fn ->
          ExLLM.StreamRecovery.continue_stream(recovery_id, opts)
        end, timeout: 120_000)
      
      error -> error
    end
  end
  
  @doc """
  Check if stream recovery is available (circuit not open).
  """
  def recovery_available?(provider) do
    circuit_name = :"#{provider}_stream_circuit"
    
    case ExLLM.CircuitBreaker.get_stats(circuit_name) do
      {:ok, %{state: :open}} -> false
      {:ok, _} -> true
      {:error, :circuit_not_found} -> true # No circuit = available
    end
  end
end
```

### 4. Configuration and Management

#### Configuration Schema

```elixir
# ExLLM configuration
config :ex_llm, :circuit_breaker,
  # Global defaults
  enabled: true,
  global_defaults: [
    failure_threshold: 5,
    success_threshold: 3,
    reset_timeout: 30_000,
    timeout: 30_000
  ],
  
  # Provider-specific configurations
  providers: [
    openai: [
      failure_threshold: 3,
      reset_timeout: 60_000,
      timeout: 45_000
    ],
    anthropic: [
      failure_threshold: 5,
      reset_timeout: 30_000,
      timeout: 30_000
    ],
    bedrock: [
      failure_threshold: 7,
      reset_timeout: 45_000,
      timeout: 60_000
    ]
  ],
  
  # Advanced features
  telemetry: [
    enabled: true,
    detailed_metrics: false,
    log_state_changes: true
  ],
  
  # Auto-recovery features
  adaptive_thresholds: [
    enabled: false,
    adjustment_factor: 0.1,
    min_threshold: 2,
    max_threshold: 20
  ]
```

#### Configuration Management Module

```elixir
defmodule ExLLM.CircuitBreaker.Config do
  @moduledoc """
  Configuration management for circuit breakers.
  """
  
  @doc """
  Get configuration for a specific provider or circuit.
  """
  def get_config(provider_or_circuit) do
    base_config = Application.get_env(:ex_llm, :circuit_breaker, [])
    global_defaults = Keyword.get(base_config, :global_defaults, [])
    
    provider_config = case provider_or_circuit do
      provider when is_atom(provider) ->
        providers = Keyword.get(base_config, :providers, [])
        Keyword.get(providers, provider, [])
      _ ->
        []
    end
    
    Keyword.merge(global_defaults, provider_config)
  end
  
  @doc """
  Update configuration at runtime.
  """
  def update_config(provider, new_config) do
    current = Application.get_env(:ex_llm, :circuit_breaker, [])
    providers = Keyword.get(current, :providers, [])
    
    updated_providers = Keyword.put(providers, provider, new_config)
    updated_config = Keyword.put(current, :providers, updated_providers)
    
    Application.put_env(:ex_llm, :circuit_breaker, updated_config)
    
    # Notify existing circuits of configuration change
    :telemetry.execute([:ex_llm, :circuit_breaker, :config_updated], 
                      %{}, %{provider: provider, config: new_config})
  end
  
  @doc """
  Validate configuration parameters.
  """
  def validate_config(config) do
    required_fields = [:failure_threshold, :success_threshold, :reset_timeout]
    
    Enum.reduce_while(required_fields, :ok, fn field, :ok ->
      case Keyword.get(config, field) do
        nil -> {:halt, {:error, "Missing required field: #{field}"}}
        value when not is_integer(value) or value <= 0 ->
          {:halt, {:error, "Invalid value for #{field}: must be positive integer"}}
        _ -> {:cont, :ok}
      end
    end)
  end
end
```

### 5. Telemetry and Observability

#### Comprehensive Telemetry Events

```elixir
defmodule ExLLM.CircuitBreaker.Telemetry do
  @moduledoc """
  Telemetry instrumentation for circuit breaker operations.
  """
  
  @events [
    # Circuit lifecycle events
    [:ex_llm, :circuit_breaker, :circuit_created],
    [:ex_llm, :circuit_breaker, :state_change],
    
    # Call events
    [:ex_llm, :circuit_breaker, :call_success],
    [:ex_llm, :circuit_breaker, :call_failure],
    [:ex_llm, :circuit_breaker, :call_timeout],
    [:ex_llm, :circuit_breaker, :call_rejected],
    
    # Failure tracking
    [:ex_llm, :circuit_breaker, :failure_recorded],
    [:ex_llm, :circuit_breaker, :success_recorded],
    
    # Configuration events
    [:ex_llm, :circuit_breaker, :config_updated],
    [:ex_llm, :circuit_breaker, :circuit_reset]
  ]
  
  @doc """
  List all available telemetry events.
  """
  def events, do: @events
  
  @doc """
  Attach standard telemetry handlers for logging and metrics.
  """
  def attach_default_handlers do
    :telemetry.attach_many(
      "ex_llm_circuit_breaker_logger",
      @events,
      &handle_telemetry_event/4,
      %{handler_type: :logger}
    )
    
    :telemetry.attach_many(
      "ex_llm_circuit_breaker_metrics",
      @events,
      &handle_telemetry_event/4,
      %{handler_type: :metrics}
    )
  end
  
  @doc """
  Get circuit breaker metrics for monitoring systems.
  """
  def get_metrics(circuit_name \\ :all) do
    case circuit_name do
      :all -> get_all_circuit_metrics()
      name -> get_single_circuit_metrics(name)
    end
  end
  
  defp handle_telemetry_event(event, measurements, metadata, %{handler_type: :logger}) do
    case event do
      [:ex_llm, :circuit_breaker, :state_change] ->
        Logger.info("Circuit breaker #{metadata.circuit_name} state changed: #{metadata.old_state} -> #{metadata.new_state}")
      
      [:ex_llm, :circuit_breaker, :call_rejected] ->
        Logger.warn("Circuit breaker #{metadata.circuit_name} rejected call: #{metadata.reason}")
      
      [:ex_llm, :circuit_breaker, :failure_recorded] ->
        Logger.warn("Circuit breaker #{metadata.circuit_name} recorded failure (#{metadata.failure_count}/#{metadata.threshold}): #{inspect(metadata.reason)}")
      
      _ -> :ok
    end
  end
  
  defp handle_telemetry_event(event, measurements, metadata, %{handler_type: :metrics}) do
    # Integration with metrics systems (Prometheus, StatsD, etc.)
    case event do
      [:ex_llm, :circuit_breaker, :call_success] ->
        increment_counter("ex_llm.circuit_breaker.calls.success", 
                         tags: [circuit_name: metadata.circuit_name])
        record_histogram("ex_llm.circuit_breaker.call_duration", 
                        measurements.duration,
                        tags: [circuit_name: metadata.circuit_name])
      
      [:ex_llm, :circuit_breaker, :call_failure] ->
        increment_counter("ex_llm.circuit_breaker.calls.failure",
                         tags: [circuit_name: metadata.circuit_name])
      
      [:ex_llm, :circuit_breaker, :state_change] ->
        set_gauge("ex_llm.circuit_breaker.state",
                 state_to_numeric(metadata.new_state),
                 tags: [circuit_name: metadata.circuit_name])
      
      _ -> :ok
    end
  end
  
  # Placeholder functions for metrics integration
  defp increment_counter(_metric, _opts), do: :ok
  defp record_histogram(_metric, _value, _opts), do: :ok
  defp set_gauge(_metric, _value, _opts), do: :ok
  
  defp state_to_numeric(:closed), do: 0
  defp state_to_numeric(:half_open), do: 1
  defp state_to_numeric(:open), do: 2
end
```

### 6. Advanced Features

#### Adaptive Circuit Breaker

```elixir
defmodule ExLLM.CircuitBreaker.Adaptive do
  @moduledoc """
  Adaptive circuit breaker that adjusts thresholds based on service behavior.
  """
  
  use GenServer
  
  @update_interval 60_000 # Check every minute
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    if Application.get_env(:ex_llm, :circuit_breaker)[:adaptive_thresholds][:enabled] do
      schedule_update()
    end
    {:ok, %{}}
  end
  
  def handle_info(:update_thresholds, state) do
    update_all_circuit_thresholds()
    schedule_update()
    {:noreply, state}
  end
  
  defp update_all_circuit_thresholds do
    # Get all active circuits
    circuits = :ets.tab2list(:ex_llm_circuit_breakers)
    
    Enum.each(circuits, fn {circuit_name, circuit_state} ->
      update_circuit_thresholds(circuit_name, circuit_state)
    end)
  end
  
  defp update_circuit_thresholds(circuit_name, circuit_state) do
    metrics = get_circuit_metrics(circuit_name)
    new_thresholds = calculate_adaptive_thresholds(metrics, circuit_state)
    
    if should_update_thresholds?(circuit_state, new_thresholds) do
      update_circuit_config(circuit_name, new_thresholds)
      
      :telemetry.execute([:ex_llm, :circuit_breaker, :threshold_update], 
                        %{}, %{circuit_name: circuit_name, thresholds: new_thresholds})
    end
  end
  
  defp calculate_adaptive_thresholds(metrics, circuit_state) do
    config = Application.get_env(:ex_llm, :circuit_breaker)[:adaptive_thresholds]
    
    error_rate = safe_divide(metrics.failures, metrics.total_calls)
    adjustment_factor = config[:adjustment_factor]
    
    current_threshold = circuit_state.config.failure_threshold
    
    new_threshold = cond do
      error_rate > 0.2 -> # High error rate, lower threshold
        max(config[:min_threshold], 
            round(current_threshold * (1 - adjustment_factor)))
      
      error_rate < 0.05 -> # Low error rate, raise threshold
        min(config[:max_threshold],
            round(current_threshold * (1 + adjustment_factor)))
      
      true -> # Stable error rate, no change
        current_threshold
    end
    
    %{failure_threshold: new_threshold}
  end
  
  defp schedule_update do
    Process.send_after(self(), :update_thresholds, @update_interval)
  end
  
  defp safe_divide(_numerator, 0), do: 0
  defp safe_divide(numerator, denominator), do: numerator / denominator
end
```

#### Bulkhead Pattern Integration

```elixir
defmodule ExLLM.CircuitBreaker.Bulkhead do
  @moduledoc """
  Bulkhead pattern implementation for resource isolation.
  """
  
  @doc """
  Execute function with both circuit breaker and bulkhead protection.
  """
  def call_with_bulkhead(resource_pool, circuit_name, fun, opts \\ []) do
    case acquire_resource(resource_pool, opts) do
      {:ok, resource} ->
        try do
          ExLLM.CircuitBreaker.call(circuit_name, fn ->
            fun.(resource)
          end, opts)
        after
          release_resource(resource_pool, resource)
        end
      
      {:error, :no_resources_available} ->
        {:error, :bulkhead_full}
    end
  end
  
  @doc """
  Provider-specific bulkhead with circuit breaker.
  """
  def provider_call_with_bulkhead(provider, fun, opts \\ []) do
    resource_pool = :"#{provider}_pool"
    circuit_name = :"#{provider}_circuit"
    
    call_with_bulkhead(resource_pool, circuit_name, fun, opts)
  end
  
  # Resource pool management
  defp acquire_resource(pool_name, opts) do
    timeout = Keyword.get(opts, :acquire_timeout, 5_000)
    
    case :poolboy.checkout(pool_name, true, timeout) do
      :full -> {:error, :no_resources_available}
      worker -> {:ok, worker}
    end
  end
  
  defp release_resource(pool_name, resource) do
    :poolboy.checkin(pool_name, resource)
  end
end
```

## Implementation Phases

### Phase 1: Core Implementation (2-3 weeks)
1. **ETS-based Circuit Breaker** - High-performance state management
2. **Basic Integration with Retry** - Combine existing retry with circuit breaker
3. **Provider-Specific Circuits** - Per-provider circuit configurations
4. **Essential Telemetry** - State changes and basic metrics

**Deliverables:**
- Working circuit breaker with three-state pattern
- Integration with ExLLM.chat/3 and ExLLM.stream_chat/3
- Provider-specific configurations
- Basic telemetry events

### Phase 2: Enhanced Features (2-3 weeks)
1. **Stream Recovery Integration** - Circuit breaker for streaming operations
2. **Configuration Management** - Runtime configuration updates
3. **Comprehensive Telemetry** - Detailed metrics and observability
4. **Management APIs** - Circuit status, reset, statistics

**Deliverables:**
- Stream circuit breaker integration
- Configuration API and validation
- Full telemetry instrumentation
- Management and monitoring APIs

### Phase 3: Advanced Patterns (3-4 weeks)
1. **Adaptive Thresholds** - Dynamic threshold adjustment
2. **Bulkhead Pattern** - Resource isolation
3. **Health Check Integration** - Proactive circuit management
4. **Performance Optimization** - Further ETS optimizations

**Deliverables:**
- Adaptive circuit breaker behavior
- Resource isolation capabilities
- Health check integration
- Performance benchmarks and optimizations

## Testing Strategy

### Unit Tests
```elixir
defmodule ExLLM.CircuitBreakerTest do
  use ExUnit.Case
  
  describe "circuit breaker states" do
    test "starts in closed state" do
      circuit_name = "test_circuit"
      result = ExLLM.CircuitBreaker.call(circuit_name, fn -> :ok end)
      
      assert {:ok, :ok} = result
      assert {:ok, %{state: :closed}} = ExLLM.CircuitBreaker.get_stats(circuit_name)
    end
    
    test "opens after failure threshold" do
      circuit_name = "failing_circuit"
      
      # Trigger failures up to threshold
      for _ <- 1..5 do
        ExLLM.CircuitBreaker.call(circuit_name, fn -> 
          raise "test failure" 
        end, failure_threshold: 5)
      end
      
      # Next call should be rejected
      result = ExLLM.CircuitBreaker.call(circuit_name, fn -> :ok end)
      assert {:error, :circuit_open} = result
    end
    
    test "transitions to half-open after reset timeout" do
      # Implementation for half-open state testing
    end
  end
  
  describe "integration with retry" do
    test "combines circuit breaker with retry logic" do
      # Test retry + circuit breaker integration
    end
  end
end
```

### Integration Tests
```elixir
defmodule ExLLM.CircuitBreakerIntegrationTest do
  use ExUnit.Case
  
  describe "provider integration" do
    test "protects OpenAI calls with circuit breaker" do
      # Mock OpenAI to fail consistently
      # Verify circuit breaker opens
      # Verify subsequent calls fail fast
    end
    
    test "stream recovery works with circuit breaker" do
      # Test stream + circuit breaker + recovery
    end
  end
end
```

### Performance Tests
```elixir
defmodule ExLLM.CircuitBreakerPerformanceTest do
  use ExUnit.Case
  
  test "high concurrency performance" do
    # Test 1000+ concurrent calls through circuit breaker
    # Verify performance acceptable vs direct calls
  end
  
  test "memory usage under load" do
    # Test memory consumption with many circuits
  end
end
```

## Migration and Compatibility

### Backward Compatibility
- All existing ExLLM APIs remain unchanged
- Circuit breaker is opt-in via new functions
- Existing retry behavior preserved
- No breaking changes to public APIs

### Migration Path
1. **Phase 1**: Add new circuit breaker APIs alongside existing
2. **Phase 2**: Update examples and documentation to recommend circuit breaker
3. **Phase 3**: Consider deprecating direct retry functions (optional)

### MCP Chat Integration
Once ExLLM implements circuit breakers, MCP Chat can:
1. Remove custom CircuitBreaker module
2. Use ExLLM's integrated circuit breaker + retry
3. Leverage provider-specific configurations
4. Access enhanced telemetry and observability

## Success Metrics

### Performance Metrics
- Circuit breaker call overhead < 1ms
- ETS operations < 0.1ms
- Memory usage linear with number of circuits
- Concurrent throughput within 5% of direct calls

### Reliability Metrics
- Failure detection within 1 failure threshold
- Recovery detection within 1 success threshold
- State transitions logged with telemetry
- Zero false positives in testing

### Adoption Metrics
- API usage in existing ExLLM applications
- Integration with monitoring systems
- Community feedback and contributions
- Performance in production workloads

## Conclusion

This specification provides a comprehensive roadmap for implementing production-grade circuit breaker patterns in ExLLM. The implementation leverages Elixir's strengths (ETS, telemetry, concurrent processing) while integrating seamlessly with ExLLM's existing retry mechanisms.

Key benefits:
- **High Performance**: ETS-based state management for concurrent access
- **Provider Awareness**: Tailored circuit breaker behavior per provider
- **Stream Integration**: Circuit breaker protection for streaming operations
- **Comprehensive Observability**: Rich telemetry for monitoring and debugging
- **Flexible Configuration**: Runtime configuration with validation
- **Advanced Patterns**: Adaptive thresholds and bulkhead isolation

The result will be a best-in-class fault tolerance system that provides robust protection against cascading failures while maintaining high performance and observability.