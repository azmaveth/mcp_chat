defmodule MCPChat.Agents.AgentCoordinator do
  @moduledoc """
  Agent Coordinator manages complex multi-agent workflows and task delegation.

  This module handles:
  - Multi-agent task orchestration
  - Workflow execution with dependencies
  - Agent collaboration and handoffs
  - Result aggregation and coordination
  - Error handling and recovery
  """

  use GenServer
  require Logger

  alias MCPChat.Agents.{AgentRegistry, BaseAgent}
  alias MCPChat.Events.AgentEvents

  # 5 minutes default
  @workflow_timeout 300_000

  # Public API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Execute a multi-agent workflow.
  """
  def execute_workflow(workflow_spec, context \\ %{}) do
    GenServer.call(__MODULE__, {:execute_workflow, workflow_spec, context}, @workflow_timeout)
  end

  @doc """
  Delegate a task to the best available agent.
  """
  def delegate_task(task_spec, options \\ []) do
    GenServer.call(__MODULE__, {:delegate_task, task_spec, options})
  end

  @doc """
  Create a collaborative session between multiple agents.
  """
  def create_collaboration(agent_ids, collaboration_spec) do
    GenServer.call(__MODULE__, {:create_collaboration, agent_ids, collaboration_spec})
  end

  @doc """
  Get status of active workflows.
  """
  def get_workflows_status do
    GenServer.call(__MODULE__, :get_workflows_status)
  end

  @doc """
  Cancel a running workflow.
  """
  def cancel_workflow(workflow_id) do
    GenServer.call(__MODULE__, {:cancel_workflow, workflow_id})
  end

  # GenServer implementation

  def init(_opts) do
    Logger.info("Agent Coordinator started")

    {:ok,
     %{
       workflows: %{},
       collaborations: %{},
       workflow_counter: 0,
       collaboration_counter: 0
     }}
  end

  def handle_call({:execute_workflow, workflow_spec, context}, from, state) do
    workflow_id = generate_workflow_id(state)

    Logger.info("Starting workflow execution",
      workflow_id: workflow_id,
      steps: length(workflow_spec[:steps] || [])
    )

    # Validate workflow
    case validate_workflow(workflow_spec) do
      :ok ->
        # Create workflow state
        workflow = %{
          id: workflow_id,
          spec: workflow_spec,
          context: context,
          status: :running,
          started_at: DateTime.utc_now(),
          current_step: 0,
          results: %{},
          errors: [],
          from: from
        }

        new_state = %{
          state
          | workflows: Map.put(state.workflows, workflow_id, workflow),
            workflow_counter: state.workflow_counter + 1
        }

        # Start workflow execution
        send(self(), {:execute_workflow_step, workflow_id})

        {:noreply, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:delegate_task, task_spec, options}, from, state) do
    # Find the best agent for this task
    case AgentRegistry.find_best_agent_for_task(task_spec) do
      {:ok, agent_info} ->
        Logger.info("Delegating task",
          task_type: task_spec[:type],
          agent_id: agent_info.agent_id,
          agent_type: agent_info.agent_type
        )

        # Execute task on selected agent
        case GenServer.call(agent_info.pid, {:execute_task, task_spec}) do
          {:ok, result} ->
            {:reply, {:ok, result, agent_info.agent_id}, state}

          {:error, reason} ->
            # Try to find alternative agent if specified
            if Keyword.get(options, :retry_on_failure, false) do
              handle_delegation_retry(task_spec, agent_info.agent_id, reason, from, state)
            else
              {:reply, {:error, reason}, state}
            end
        end

      {:error, :no_suitable_agent} ->
        # Try to spawn a suitable agent if auto-spawn is enabled
        if Keyword.get(options, :auto_spawn, false) do
          handle_agent_auto_spawn(task_spec, from, state)
        else
          {:reply, {:error, :no_suitable_agent}, state}
        end
    end
  end

  def handle_call({:create_collaboration, agent_ids, collaboration_spec}, _from, state) do
    collaboration_id = generate_collaboration_id(state)

    # Validate all agents exist and are alive
    case validate_agents_for_collaboration(agent_ids) do
      :ok ->
        collaboration = %{
          id: collaboration_id,
          agent_ids: agent_ids,
          spec: collaboration_spec,
          status: :active,
          started_at: DateTime.utc_now(),
          messages: [],
          shared_context: %{}
        }

        new_state = %{
          state
          | collaborations: Map.put(state.collaborations, collaboration_id, collaboration),
            collaboration_counter: state.collaboration_counter + 1
        }

        # Notify agents about collaboration
        notify_agents_of_collaboration(agent_ids, collaboration)

        {:reply, {:ok, collaboration_id}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_workflows_status, _from, state) do
    status = %{
      active_workflows: map_size(state.workflows),
      active_collaborations: map_size(state.collaborations),
      total_workflows: state.workflow_counter,
      total_collaborations: state.collaboration_counter,
      workflows: get_workflow_summaries(state.workflows),
      collaborations: get_collaboration_summaries(state.collaborations)
    }

    {:reply, status, state}
  end

  def handle_call({:cancel_workflow, workflow_id}, _from, state) do
    case Map.get(state.workflows, workflow_id) do
      nil ->
        {:reply, {:error, :workflow_not_found}, state}

      workflow ->
        # Cancel the workflow
        cancelled_workflow = %{workflow | status: :cancelled, cancelled_at: DateTime.utc_now()}
        new_workflows = Map.put(state.workflows, workflow_id, cancelled_workflow)

        # Reply to original caller
        GenServer.reply(workflow.from, {:error, :workflow_cancelled})

        Logger.info("Workflow cancelled", workflow_id: workflow_id)

        {:reply, :ok, %{state | workflows: new_workflows}}
    end
  end

  # Workflow execution

  def handle_info({:execute_workflow_step, workflow_id}, state) do
    case Map.get(state.workflows, workflow_id) do
      nil ->
        Logger.warning("Workflow not found", workflow_id: workflow_id)
        {:noreply, state}

      workflow ->
        execute_next_workflow_step(workflow, state)
    end
  end

  def handle_info({:workflow_step_completed, workflow_id, step_index, result}, state) do
    case Map.get(state.workflows, workflow_id) do
      nil ->
        {:noreply, state}

      workflow ->
        # Update workflow with step result
        updated_workflow = %{
          workflow
          | results: Map.put(workflow.results, step_index, result),
            current_step: step_index + 1
        }

        new_state = %{state | workflows: Map.put(state.workflows, workflow_id, updated_workflow)}

        # Continue with next step or complete workflow
        if updated_workflow.current_step >= length(workflow.spec.steps) do
          complete_workflow(updated_workflow, new_state)
        else
          send(self(), {:execute_workflow_step, workflow_id})
          {:noreply, new_state}
        end
    end
  end

  def handle_info({:workflow_step_failed, workflow_id, step_index, error}, state) do
    case Map.get(state.workflows, workflow_id) do
      nil ->
        {:noreply, state}

      workflow ->
        # Handle workflow failure
        failed_workflow = %{
          workflow
          | status: :failed,
            errors: [{step_index, error} | workflow.errors],
            failed_at: DateTime.utc_now()
        }

        new_workflows = Map.put(state.workflows, workflow_id, failed_workflow)

        # Reply to original caller
        GenServer.reply(workflow.from, {:error, {:workflow_failed, step_index, error}})

        Logger.error("Workflow failed",
          workflow_id: workflow_id,
          step_index: step_index,
          error: inspect(error)
        )

        {:noreply, %{state | workflows: new_workflows}}
    end
  end

  # Private helper functions

  defp generate_workflow_id(state) do
    "workflow_#{state.workflow_counter + 1}_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"
  end

  defp generate_collaboration_id(state) do
    "collab_#{state.collaboration_counter + 1}_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"
  end

  defp validate_workflow(workflow_spec) do
    cond do
      not is_map(workflow_spec) ->
        {:error, :invalid_workflow_spec}

      not Map.has_key?(workflow_spec, :steps) ->
        {:error, :missing_steps}

      workflow_spec.steps == [] ->
        {:error, :empty_workflow}

      true ->
        :ok
    end
  end

  defp execute_next_workflow_step(workflow, state) do
    steps = workflow.spec.steps
    current_step_index = workflow.current_step

    if current_step_index >= length(steps) do
      complete_workflow(workflow, state)
    else
      step = Enum.at(steps, current_step_index)

      Logger.debug("Executing workflow step",
        workflow_id: workflow.id,
        step_index: current_step_index,
        step_type: step[:type]
      )

      # Check step dependencies
      case check_step_dependencies(step, workflow.results) do
        :ok ->
          execute_workflow_step(workflow, step, current_step_index, state)

        {:error, reason} ->
          send(self(), {:workflow_step_failed, workflow.id, current_step_index, reason})
          {:noreply, state}
      end
    end
  end

  defp execute_workflow_step(workflow, step, step_index, state) do
    # Find appropriate agent for this step
    case AgentRegistry.find_best_agent_for_task(step) do
      {:ok, agent_info} ->
        # Execute step asynchronously
        spawn(fn ->
          try do
            result = GenServer.call(agent_info.pid, {:execute_task, step}, 60_000)
            send(__MODULE__, {:workflow_step_completed, workflow.id, step_index, result})
          rescue
            error ->
              send(__MODULE__, {:workflow_step_failed, workflow.id, step_index, error})
          end
        end)

        {:noreply, state}

      {:error, reason} ->
        send(self(), {:workflow_step_failed, workflow.id, step_index, reason})
        {:noreply, state}
    end
  end

  defp complete_workflow(workflow, state) do
    completed_workflow = %{
      workflow
      | status: :completed,
        completed_at: DateTime.utc_now()
    }

    new_workflows = Map.put(state.workflows, workflow.id, completed_workflow)

    # Reply to original caller with aggregated results
    final_result = %{
      workflow_id: workflow.id,
      status: :completed,
      results: workflow.results,
      duration_ms: DateTime.diff(DateTime.utc_now(), workflow.started_at, :millisecond)
    }

    GenServer.reply(workflow.from, {:ok, final_result})

    Logger.info("Workflow completed",
      workflow_id: workflow.id,
      steps_completed: length(workflow.spec.steps),
      duration_ms: final_result.duration_ms
    )

    {:noreply, %{state | workflows: new_workflows}}
  end

  defp check_step_dependencies(step, completed_results) do
    case step[:dependencies] do
      nil ->
        :ok

      [] ->
        :ok

      deps when is_list(deps) ->
        missing_deps = Enum.reject(deps, &Map.has_key?(completed_results, &1))

        if Enum.empty?(missing_deps) do
          :ok
        else
          {:error, {:missing_dependencies, missing_deps}}
        end
    end
  end

  defp validate_agents_for_collaboration(agent_ids) do
    invalid_agents =
      agent_ids
      |> Enum.reject(fn agent_id ->
        case AgentRegistry.get_agent_pid(agent_id) do
          {:ok, _pid} -> true
          _ -> false
        end
      end)

    if Enum.empty?(invalid_agents) do
      :ok
    else
      {:error, {:invalid_agents, invalid_agents}}
    end
  end

  defp notify_agents_of_collaboration(agent_ids, collaboration) do
    Enum.each(agent_ids, fn agent_id ->
      case AgentRegistry.get_agent_pid(agent_id) do
        {:ok, pid} ->
          send(pid, {:agent_coordination, {:collaboration_started, collaboration}})

        _ ->
          Logger.warning("Could not notify agent of collaboration", agent_id: agent_id)
      end
    end)
  end

  defp get_workflow_summaries(workflows) do
    Enum.map(workflows, fn {id, workflow} ->
      %{
        id: id,
        status: workflow.status,
        started_at: workflow.started_at,
        current_step: workflow.current_step,
        total_steps: length(workflow.spec.steps),
        progress: workflow.current_step / length(workflow.spec.steps) * 100
      }
    end)
  end

  defp get_collaboration_summaries(collaborations) do
    Enum.map(collaborations, fn {id, collab} ->
      %{
        id: id,
        status: collab.status,
        agent_count: length(collab.agent_ids),
        started_at: collab.started_at,
        message_count: length(collab.messages)
      }
    end)
  end

  defp handle_delegation_retry(_task_spec, _failed_agent_id, reason, from, state) do
    # For now, just return the original error
    # In a full implementation, this would find alternative agents
    GenServer.reply(from, {:error, {:retry_failed, reason}})
    {:noreply, state}
  end

  defp handle_agent_auto_spawn(_task_spec, from, state) do
    # For now, just return no agent available
    # In a full implementation, this would spawn appropriate agents
    GenServer.reply(from, {:error, :auto_spawn_not_implemented})
    {:noreply, state}
  end
end
