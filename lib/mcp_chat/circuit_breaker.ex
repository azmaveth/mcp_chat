defmodule MCPChat.CircuitBreaker do
  @moduledoc """
  Circuit breaker pattern implementation for external service calls.
  Prevents cascade failures by temporarily blocking calls to failing services.

  States:
  - :closed - Normal operation, calls pass through
  - :open - Service is failing, calls are blocked
  - :half_open - Testing if service has recovered
  """
  use GenServer
  require Logger

  defstruct [
    :name,
    :state,
    :failure_count,
    :success_count,
    :last_failure_time,
    :failure_threshold,
    :success_threshold,
    :timeout,
    :reset_timeout,
    :half_open_requests
  ]

  @default_failure_threshold 5
  @default_success_threshold 3
  @default_timeout 5_000
  @default_reset_timeout 30_000

  # Client API

  @doc """
  Starts a circuit breaker with the given options.

  Options:
  - name: Circuit breaker name (required)
  - failure_threshold: Number of failures before opening circuit (default: 5)
  - success_threshold: Number of successes in half-open before closing (default: 3)
  - timeout: Call timeout in ms (default: 5_000)
  - reset_timeout: Time before trying half-open state in ms (default: 30_000)
  """
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Executes a function through the circuit breaker.
  Returns {:ok, result} or {:error, reason}.
  """
  def call(breaker, fun) when is_function(fun, 0) do
    GenServer.call(breaker, {:call, fun}, :infinity)
  end

  @doc """
  Gets the current state of the circuit breaker.
  """
  def get_state(breaker) do
    GenServer.call(breaker, :get_state)
  end

  @doc """
  Manually resets the circuit breaker to closed state.
  """
  def reset(breaker) do
    GenServer.call(breaker, :reset)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      state: :closed,
      failure_count: 0,
      success_count: 0,
      last_failure_time: nil,
      failure_threshold: opts[:failure_threshold] || @default_failure_threshold,
      success_threshold: opts[:success_threshold] || @default_success_threshold,
      timeout: opts[:timeout] || @default_timeout,
      reset_timeout: opts[:reset_timeout] || @default_reset_timeout,
      half_open_requests: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:call, fun}, from, state) do
    case state.state do
      :closed ->
        execute_call(fun, from, state)

      :open ->
        if should_attempt_reset?(state) do
          # Transition to half-open
          Logger.info("Circuit breaker #{state.name} transitioning to half-open")
          new_state = %{state | state: :half_open, half_open_requests: 0}
          execute_call(fun, from, new_state)
        else
          {:reply, {:error, :circuit_open}, state}
        end

      :half_open ->
        if state.half_open_requests < state.success_threshold do
          new_state = %{state | half_open_requests: state.half_open_requests + 1}
          execute_call(fun, from, new_state)
        else
          # Too many concurrent requests in half-open state
          {:reply, {:error, :circuit_half_open_limit}, state}
        end
    end
  end

  def handle_call(:get_state, _from, state) do
    info = %{
      state: state.state,
      failure_count: state.failure_count,
      success_count: state.success_count,
      last_failure_time: state.last_failure_time
    }

    {:reply, info, state}
  end

  def handle_call(:reset, _from, state) do
    new_state = %{
      state
      | state: :closed,
        failure_count: 0,
        success_count: 0,
        last_failure_time: nil,
        half_open_requests: 0
    }

    Logger.info("Circuit breaker #{state.name} manually reset")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info({:call_result, from, result}, state) do
    new_state = handle_call_result(result, state)
    GenServer.reply(from, result)
    {:noreply, new_state}
  end

  # Private Functions

  defp execute_call(fun, from, state) do
    # Execute the call in a separate process with timeout
    task =
      Task.async(fn ->
        try do
          {:ok, fun.()}
        catch
          kind, reason ->
            {:error, {kind, reason}}
        end
      end)

    # Monitor the task
    Process.send_after(self(), {:timeout, task.ref}, state.timeout)

    # Store the from reference for later reply
    spawn(fn ->
      result =
        case Task.yield(task, state.timeout) || Task.shutdown(task) do
          {:ok, {:ok, value}} -> {:ok, value}
          {:ok, {:error, reason}} -> {:error, reason}
          nil -> {:error, :timeout}
          {:exit, reason} -> {:error, {:exit, reason}}
        end

      send(state.name, {:call_result, from, result})
    end)

    {:noreply, state}
  end

  defp handle_call_result({:ok, _}, state) do
    case state.state do
      :closed ->
        # Reset failure count on success
        %{state | failure_count: 0}

      :half_open ->
        new_success_count = state.success_count + 1

        if new_success_count >= state.success_threshold do
          # Close the circuit
          Logger.info("Circuit breaker #{state.name} closing after successful recovery")
          %{state | state: :closed, failure_count: 0, success_count: 0, half_open_requests: 0}
        else
          %{state | success_count: new_success_count}
        end

      :open ->
        # Shouldn't happen, but handle gracefully
        state
    end
  end

  defp handle_call_result({:error, reason}, state) do
    Logger.warning("Circuit breaker #{state.name} recorded failure: #{inspect(reason)}")

    case state.state do
      :closed ->
        new_failure_count = state.failure_count + 1

        if new_failure_count >= state.failure_threshold do
          # Open the circuit
          Logger.error("Circuit breaker #{state.name} opening after #{new_failure_count} failures")

          %{
            state
            | state: :open,
              failure_count: new_failure_count,
              last_failure_time: System.monotonic_time(:millisecond)
          }
        else
          %{state | failure_count: new_failure_count}
        end

      :half_open ->
        # Failure in half-open state, reopen immediately
        Logger.warning("Circuit breaker #{state.name} reopening after failure in half-open state")

        %{
          state
          | state: :open,
            failure_count: state.failure_count + 1,
            success_count: 0,
            last_failure_time: System.monotonic_time(:millisecond),
            half_open_requests: 0
        }

      :open ->
        # Already open, update failure time
        %{state | failure_count: state.failure_count + 1, last_failure_time: System.monotonic_time(:millisecond)}
    end
  end

  defp should_attempt_reset?(%{last_failure_time: nil}), do: true

  defp should_attempt_reset?(%{last_failure_time: last_failure, reset_timeout: timeout}) do
    current_time = System.monotonic_time(:millisecond)
    current_time - last_failure >= timeout
  end
end
