defmodule MCPChat.PlanMode.Plan do
  @moduledoc """
  Represents an execution plan with multiple steps.

  A plan is a structured representation of actions to be taken,
  allowing users to preview and approve before execution.
  """

  @type status :: :draft | :pending_approval | :approved | :executing | :completed | :failed | :cancelled
  @type risk_level :: :safe | :moderate | :dangerous

  @type t :: %__MODULE__{
          id: String.t(),
          description: String.t(),
          created_at: DateTime.t(),
          updated_at: DateTime.t(),
          status: status(),
          # Will contain Step structs
          steps: [map()],
          context: map(),
          estimated_cost: map(),
          risk_level: risk_level(),
          metadata: map(),
          execution_state: map()
        }

  defstruct [
    :id,
    :description,
    :created_at,
    :updated_at,
    :status,
    :steps,
    :context,
    :estimated_cost,
    :risk_level,
    :metadata,
    :execution_state
  ]

  @doc """
  Creates a new plan with the given description and steps.
  """
  def new(description, steps \\ []) do
    %__MODULE__{
      id: generate_id(),
      description: description,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      status: :draft,
      steps: steps,
      context: %{},
      estimated_cost: %{tokens: 0, amount: 0.0},
      risk_level: :safe,
      metadata: %{},
      execution_state: %{
        current_step: nil,
        completed_steps: [],
        failed_steps: [],
        rollback_stack: []
      }
    }
  end

  @doc """
  Adds a step to the plan.
  """
  def add_step(%__MODULE__{steps: steps} = plan, step) do
    %{plan | steps: steps ++ [step], updated_at: DateTime.utc_now()}
    |> recalculate_risk()
    |> recalculate_cost()
  end

  @doc """
  Updates the plan status.
  """
  def update_status(%__MODULE__{} = plan, status)
      when status in [:draft, :pending_approval, :approved, :executing, :completed, :failed, :cancelled] do
    %{plan | status: status, updated_at: DateTime.utc_now()}
  end

  @doc """
  Marks a step as completed and updates execution state.
  """
  def complete_step(%__MODULE__{execution_state: exec_state} = plan, step_id) do
    completed_steps = [step_id | exec_state.completed_steps]

    %{plan | execution_state: %{exec_state | completed_steps: completed_steps}, updated_at: DateTime.utc_now()}
  end

  @doc """
  Marks a step as failed and updates execution state.
  """
  def fail_step(%__MODULE__{execution_state: exec_state} = plan, step_id, reason) do
    failed_steps = [{step_id, reason} | exec_state.failed_steps]

    %{
      plan
      | execution_state: %{exec_state | failed_steps: failed_steps},
        status: :failed,
        updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Adds rollback information to the execution state.
  """
  def push_rollback(%__MODULE__{execution_state: exec_state} = plan, rollback_info) do
    rollback_stack = [rollback_info | exec_state.rollback_stack]

    %{plan | execution_state: %{exec_state | rollback_stack: rollback_stack}, updated_at: DateTime.utc_now()}
  end

  @doc """
  Gets the next pending step to execute.
  """
  def next_step(%__MODULE__{steps: steps, execution_state: %{completed_steps: completed}}) do
    Enum.find(steps, fn step ->
      step.id not in completed and
        all_prerequisites_met?(step, completed)
    end)
  end

  @doc """
  Checks if all steps are completed.
  """
  def all_steps_completed?(%__MODULE__{steps: steps, execution_state: %{completed_steps: completed}}) do
    step_ids = Enum.map(steps, & &1.id)
    Enum.all?(step_ids, &(&1 in completed))
  end

  @doc """
  Calculates the overall risk level based on all steps.
  """
  def recalculate_risk(%__MODULE__{steps: steps} = plan) do
    risk_level =
      steps
      |> Enum.map(& &1.risk_level)
      |> Enum.max_by(&risk_to_number/1, fn -> :safe end)

    %{plan | risk_level: risk_level}
  end

  @doc """
  Recalculates the estimated cost based on all steps.
  """
  def recalculate_cost(%__MODULE__{steps: steps} = plan) do
    total_cost =
      steps
      |> Enum.reduce(%{tokens: 0, amount: 0.0}, fn step, acc ->
        %{
          tokens: acc.tokens + Map.get(step.estimated_cost, :tokens, 0),
          amount: acc.amount + Map.get(step.estimated_cost, :amount, 0.0)
        }
      end)

    %{plan | estimated_cost: total_cost}
  end

  @doc """
  Validates the plan structure and dependencies.
  """
  def validate(%__MODULE__{steps: steps} = plan) do
    with :ok <- validate_step_ids_unique(steps),
         :ok <- validate_prerequisites(steps),
         :ok <- validate_at_least_one_step(steps) do
      {:ok, plan}
    end
  end

  # Private functions

  defp generate_id do
    "plan_#{System.system_time(:millisecond)}_#{:rand.uniform(9999)}"
  end

  defp all_prerequisites_met?(%{prerequisites: nil}, _completed), do: true
  defp all_prerequisites_met?(%{prerequisites: []}, _completed), do: true

  defp all_prerequisites_met?(%{prerequisites: prereqs}, completed) do
    Enum.all?(prereqs, &(&1 in completed))
  end

  defp risk_to_number(:safe), do: 1
  defp risk_to_number(:moderate), do: 2
  defp risk_to_number(:dangerous), do: 3

  defp validate_step_ids_unique(steps) do
    ids = Enum.map(steps, & &1.id)

    if length(ids) == length(Enum.uniq(ids)) do
      :ok
    else
      {:error, :duplicate_step_ids}
    end
  end

  defp validate_prerequisites(steps) do
    step_ids = MapSet.new(Enum.map(steps, & &1.id))

    invalid =
      steps
      |> Enum.flat_map(fn step ->
        (step.prerequisites || [])
        |> Enum.reject(&MapSet.member?(step_ids, &1))
        |> Enum.map(&{step.id, &1})
      end)

    if Enum.empty?(invalid) do
      :ok
    else
      {:error, {:invalid_prerequisites, invalid}}
    end
  end

  defp validate_at_least_one_step([]), do: {:error, :no_steps}
  defp validate_at_least_one_step(_), do: :ok
end
