defmodule BeamIntegration.Orchestrator do
  @moduledoc """
  Orchestrates multi-agent workflows using BEAM message passing.
  """
  use GenServer
  require Logger
  
  defmodule Workflow do
    defstruct [:id, :steps, :current_step, :context, :status, :results]
  end
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def execute_workflow(workflow_type, params \\ %{}) do
    GenServer.call(__MODULE__, {:execute_workflow, workflow_type, params}, :infinity)
  end
  
  def get_workflow_status(workflow_id) do
    GenServer.call(__MODULE__, {:get_status, workflow_id})
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    state = %{
      workflows: %{},
      workflow_counter: 0
    }
    {:ok, state}
  end
  
  @impl true
  def handle_call({:execute_workflow, workflow_type, params}, from, state) do
    workflow_id = state.workflow_counter + 1
    
    workflow = %Workflow{
      id: workflow_id,
      steps: get_workflow_steps(workflow_type, params),
      current_step: 0,
      context: params,
      status: :running,
      results: []
    }
    
    # Start workflow execution asynchronously
    self() |> send({:execute_step, workflow_id})
    
    new_state = %{state |
      workflows: Map.put(state.workflows, workflow_id, {workflow, from}),
      workflow_counter: workflow_id
    }
    
    {:noreply, new_state}
  end
  
  def handle_call({:get_status, workflow_id}, _from, state) do
    case Map.get(state.workflows, workflow_id) do
      {workflow, _from} ->
        {:reply, {:ok, workflow.status, workflow.results}, state}
      nil ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl true
  def handle_info({:execute_step, workflow_id}, state) do
    case Map.get(state.workflows, workflow_id) do
      {workflow, from} ->
        case execute_next_step(workflow) do
          {:continue, updated_workflow} ->
            # Schedule next step
            self() |> send({:execute_step, workflow_id})
            
            new_state = %{state |
              workflows: Map.put(state.workflows, workflow_id, {updated_workflow, from})
            }
            {:noreply, new_state}
          
          {:complete, final_workflow} ->
            # Reply to original caller
            GenServer.reply(from, {:ok, final_workflow.results})
            
            # Update workflow status
            new_state = %{state |
              workflows: Map.put(state.workflows, workflow_id, {final_workflow, nil})
            }
            {:noreply, new_state}
          
          {:error, reason, failed_workflow} ->
            # Reply with error
            GenServer.reply(from, {:error, reason})
            
            # Update workflow status
            new_state = %{state |
              workflows: Map.put(state.workflows, workflow_id, {failed_workflow, nil})
            }
            {:noreply, new_state}
        end
      
      nil ->
        Logger.warn("Unknown workflow: #{workflow_id}")
        {:noreply, state}
    end
  end
  
  def handle_info({:mcp_response, query_id, result}, state) do
    # Handle async responses from agents
    # Find the workflow waiting for this response
    {workflow_id, updated_state} = 
      Enum.find_value(state.workflows, {nil, state}, fn {wf_id, {workflow, from}} ->
        if workflow.context[:pending_query_id] == query_id do
          case result do
            {:ok, response} ->
              updated_workflow = %{workflow |
                results: workflow.results ++ [response],
                context: Map.delete(workflow.context, :pending_query_id)
              }
              
              new_workflows = Map.put(state.workflows, wf_id, {updated_workflow, from})
              new_state = %{state | workflows: new_workflows}
              
              # Continue workflow
              self() |> send({:execute_step, wf_id})
              
              {wf_id, new_state}
            
            {:error, reason} ->
              failed_workflow = %{workflow | status: :failed}
              GenServer.reply(from, {:error, reason})
              
              new_workflows = Map.put(state.workflows, wf_id, {failed_workflow, nil})
              new_state = %{state | workflows: new_workflows}
              
              {wf_id, new_state}
          end
        else
          nil
        end
      end)
    
    if workflow_id do
      {:noreply, updated_state}
    else
      Logger.warn("Received response for unknown query: #{query_id}")
      {:noreply, state}
    end
  end
  
  # Private Functions
  
  defp get_workflow_steps(:code_review, params) do
    [
      {:analyze, :researcher, "Analyze this code and identify potential issues:\n\n#{params.code}"},
      {:suggest, :coder, "Based on this analysis, suggest improvements:\n\n{previous_result}"},
      {:review, :reviewer, "Review these suggested improvements:\n\n{previous_result}"}
    ]
  end
  
  defp get_workflow_steps(:research_and_implement, params) do
    [
      {:research, :researcher, "Research best practices for: #{params.topic}"},
      {:design, :coder, "Design a solution based on:\n\n{previous_result}"},
      {:implement, :coder, "Implement the design:\n\n{previous_result}"},
      {:review, :reviewer, "Review the implementation:\n\n{previous_result}"}
    ]
  end
  
  defp get_workflow_steps(:pair_programming, params) do
    [
      {:plan, :coder, "Create a plan for: #{params.task}"},
      {:implement, :coder, "Start implementing:\n\n{previous_result}"},
      {:review_and_refine, :reviewer, "Review and suggest refinements:\n\n{previous_result}"},
      {:finalize, :coder, "Apply refinements:\n\n{previous_result}"}
    ]
  end
  
  defp execute_next_step(%Workflow{current_step: step, steps: steps} = workflow) 
       when step >= length(steps) do
    {:complete, %{workflow | status: :completed}}
  end
  
  defp execute_next_step(%Workflow{context: %{pending_query_id: _}} = workflow) do
    # Waiting for async response
    {:continue, workflow}
  end
  
  defp execute_next_step(workflow) do
    {step_name, agent, prompt_template} = Enum.at(workflow.steps, workflow.current_step)
    
    # Substitute previous results in prompt
    prompt = 
      if workflow.current_step > 0 && String.contains?(prompt_template, "{previous_result}") do
        previous_result = List.last(workflow.results) || ""
        String.replace(prompt_template, "{previous_result}", previous_result)
      else
        prompt_template
      end
    
    Logger.info("Executing step #{step_name} with agent #{agent}")
    
    # Send async query to agent
    query_id = :erlang.unique_integer([:positive])
    BeamIntegration.AgentServer.query_async(agent, prompt, self(), [])
    
    updated_workflow = %{workflow |
      current_step: workflow.current_step + 1,
      context: Map.put(workflow.context, :pending_query_id, query_id)
    }
    
    {:continue, updated_workflow}
  end
end