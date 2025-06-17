defmodule MCPChat.Agents.AgentPool do
  @moduledoc """
  Agent Pool manages resource allocation for heavy computational tasks.

  This module implements a worker pool pattern that:
  - Limits concurrent heavy operations to prevent resource exhaustion
  - Queues requests when pool is at capacity
  - Provides monitoring and observability into pool state
  - Handles worker lifecycle and cleanup
  """

  use GenServer
  require Logger

  @default_max_concurrent 3
  @default_queue_timeout 30_000
  @worker_table :agent_pool_workers

  # Public API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Request execution of a tool in the agent pool"
  def request_tool_execution(session_id, task_spec) do
    GenServer.call(__MODULE__, {:request_execution, session_id, task_spec}, @default_queue_timeout)
  end

  @doc "Get current pool status and statistics"
  def get_pool_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc "Get detailed information about active workers"
  def get_worker_details do
    case :ets.info(@worker_table) do
      :undefined -> []
      _ -> get_worker_details_from_ets()
    end
  end

  @doc "Force termination of a specific worker (admin function)"
  def terminate_worker(worker_pid) when is_pid(worker_pid) do
    GenServer.call(__MODULE__, {:terminate_worker, worker_pid})
  end

  @doc "Update pool configuration"
  def update_config(new_config) do
    GenServer.call(__MODULE__, {:update_config, new_config})
  end

  # GenServer implementation

  def init(opts) do
    max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)

    # ETS table for monitoring active workers is created by AgentSupervisor

    Logger.info("Starting Agent Pool", max_concurrent: max_concurrent)

    {:ok,
     %{
       max_concurrent: max_concurrent,
       active_workers: %{},
       queue: :queue.new(),
       worker_count: 0,
       total_completed: 0,
       total_failed: 0,
       queue_timeout: @default_queue_timeout
     }}
  end

  def handle_call({:request_execution, session_id, task_spec}, from, state) do
    if state.worker_count < state.max_concurrent do
      # Start worker immediately
      case start_tool_worker(session_id, task_spec) do
        {:ok, worker_pid} ->
          Process.monitor(worker_pid)

          # Track in ETS for monitoring
          worker_info = {
            worker_pid,
            session_id,
            task_spec,
            DateTime.utc_now(),
            from
          }

          :ets.insert(@worker_table, worker_info)

          new_state = %{
            state
            | active_workers: Map.put(state.active_workers, worker_pid, {session_id, task_spec, from}),
              worker_count: state.worker_count + 1
          }

          Logger.info("Started worker immediately",
            worker_pid: inspect(worker_pid),
            session_id: session_id,
            tool: task_spec.tool_name,
            active_workers: new_state.worker_count
          )

          {:reply, {:ok, worker_pid}, new_state}

        {:error, reason} = error ->
          Logger.error("Failed to start worker",
            session_id: session_id,
            tool: task_spec.tool_name,
            reason: inspect(reason)
          )

          {:reply, error, state}
      end
    else
      # Queue the request
      queue_item = {session_id, task_spec, from, DateTime.utc_now()}
      new_queue = :queue.in(queue_item, state.queue)
      queue_length = :queue.len(new_queue)

      Logger.info("Queued execution request",
        session_id: session_id,
        tool: task_spec.tool_name,
        queue_position: queue_length,
        active_workers: state.worker_count
      )

      # Don't reply immediately - will reply when worker becomes available
      {:noreply, %{state | queue: new_queue}}
    end
  end

  def handle_call(:get_status, _from, state) do
    queue_length = :queue.len(state.queue)

    status = %{
      active_workers: state.worker_count,
      max_concurrent: state.max_concurrent,
      queue_length: queue_length,
      total_completed: state.total_completed,
      total_failed: state.total_failed,
      utilization_pct: round(state.worker_count / state.max_concurrent * 100),
      worker_details: get_worker_details_from_ets()
    }

    {:reply, status, state}
  end

  def handle_call({:terminate_worker, worker_pid}, _from, state) do
    case Map.get(state.active_workers, worker_pid) do
      nil ->
        {:reply, {:error, :worker_not_found}, state}

      {session_id, task_spec, from} ->
        # Terminate the worker
        case DynamicSupervisor.terminate_child(MCPChat.ToolExecutorSupervisor, worker_pid) do
          :ok ->
            # Clean up tracking
            :ets.delete(@worker_table, worker_pid)
            new_workers = Map.delete(state.active_workers, worker_pid)

            # Reply to original caller with termination notice
            GenServer.reply(from, {:error, :worker_terminated})

            Logger.warning("Worker forcefully terminated",
              worker_pid: inspect(worker_pid),
              session_id: session_id,
              tool: task_spec.tool_name
            )

            new_state = %{
              state
              | active_workers: new_workers,
                worker_count: state.worker_count - 1,
                total_failed: state.total_failed + 1
            }

            # Try to start next queued work
            final_state = maybe_start_queued_work(new_state)

            {:reply, :ok, final_state}

          error ->
            {:reply, error, state}
        end
    end
  end

  def handle_call({:update_config, new_config}, _from, state) do
    old_max = state.max_concurrent
    new_max = Map.get(new_config, :max_concurrent, old_max)

    new_state = %{state | max_concurrent: new_max}

    Logger.info("Updated pool configuration",
      old_max_concurrent: old_max,
      new_max_concurrent: new_max
    )

    # If we increased capacity, try to start queued work
    final_state =
      if new_max > old_max do
        start_queued_work_up_to_capacity(new_state)
      else
        new_state
      end

    {:reply, :ok, final_state}
  end

  def handle_info({:DOWN, _ref, :process, worker_pid, reason}, state) do
    # Worker finished, clean up and start next queued work
    :ets.delete(@worker_table, worker_pid)

    case Map.get(state.active_workers, worker_pid) do
      nil ->
        # Unknown worker, ignore
        {:noreply, state}

      {session_id, task_spec, from} ->
        new_workers = Map.delete(state.active_workers, worker_pid)
        new_count = state.worker_count - 1

        # Update completion stats
        {total_completed, total_failed} =
          case reason do
            :normal ->
              {state.total_completed + 1, state.total_failed}

            _ ->
              # Worker crashed, reply to caller with error
              GenServer.reply(from, {:error, {:worker_crashed, reason}})

              Logger.error("Worker crashed",
                worker_pid: inspect(worker_pid),
                session_id: session_id,
                tool: task_spec.tool_name,
                reason: inspect(reason)
              )

              {state.total_completed, state.total_failed + 1}
          end

        new_state = %{
          state
          | active_workers: new_workers,
            worker_count: new_count,
            total_completed: total_completed,
            total_failed: total_failed
        }

        # Try to start next queued work
        final_state = maybe_start_queued_work(new_state)

        {:noreply, final_state}
    end
  end

  # Private helper functions

  defp start_tool_worker(session_id, task_spec) do
    DynamicSupervisor.start_child(
      MCPChat.ToolExecutorSupervisor,
      {MCPChat.Agents.ToolExecutorAgent, {session_id, task_spec}}
    )
  end

  defp maybe_start_queued_work(state) do
    if state.worker_count < state.max_concurrent do
      case :queue.out(state.queue) do
        {{:value, {session_id, task_spec, from, queued_at}}, new_queue} ->
          # Calculate how long this request was queued
          queue_time_ms = DateTime.diff(DateTime.utc_now(), queued_at, :millisecond)

          case start_tool_worker(session_id, task_spec) do
            {:ok, new_worker_pid} ->
              Process.monitor(new_worker_pid)

              # Track new worker
              worker_info = {
                new_worker_pid,
                session_id,
                task_spec,
                DateTime.utc_now(),
                from
              }

              :ets.insert(@worker_table, worker_info)

              # Reply to the queued caller
              GenServer.reply(from, {:ok, new_worker_pid})

              Logger.info("Started queued worker",
                worker_pid: inspect(new_worker_pid),
                session_id: session_id,
                tool: task_spec.tool_name,
                queue_time_ms: queue_time_ms
              )

              %{
                state
                | active_workers: Map.put(state.active_workers, new_worker_pid, {session_id, task_spec, from}),
                  queue: new_queue,
                  worker_count: state.worker_count + 1
              }

            {:error, reason} ->
              # Failed to start queued worker, reply with error
              GenServer.reply(from, {:error, {:failed_to_start_worker, reason}})

              Logger.error("Failed to start queued worker",
                session_id: session_id,
                tool: task_spec.tool_name,
                reason: inspect(reason)
              )

              %{state | queue: new_queue, total_failed: state.total_failed + 1}
          end

        {:empty, _} ->
          # No queued work
          state
      end
    else
      # Pool still at capacity
      state
    end
  end

  defp start_queued_work_up_to_capacity(state) do
    available_slots = state.max_concurrent - state.worker_count

    if available_slots > 0 do
      Enum.reduce(1..available_slots, state, fn _, acc_state ->
        maybe_start_queued_work(acc_state)
      end)
    else
      state
    end
  end

  defp get_worker_details_from_ets do
    try do
      :ets.tab2list(@worker_table)
      |> Enum.map(fn {pid, session_id, task_spec, started_at, _from} ->
        %{
          pid: pid,
          session_id: session_id,
          tool_name: task_spec.tool_name,
          started_at: started_at,
          duration_ms: DateTime.diff(DateTime.utc_now(), started_at, :millisecond),
          alive: Process.alive?(pid)
        }
      end)
    rescue
      _ -> []
    end
  end
end
