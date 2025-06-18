defmodule MCPChat.PlanMode.SimpleRenderer do
  @moduledoc """
  Simple text renderer for execution plans without complex colorization.
  """

  alias MCPChat.PlanMode.{Plan}

  @doc """
  Renders a complete plan for display.
  """
  def render(%Plan{} = plan, _opts \\ []) do
    [
      render_header(plan),
      render_separator(),
      render_steps(plan.steps),
      render_separator(),
      render_summary(plan),
      render_approval_prompt(plan)
    ]
    |> Enum.join("\n")
  end

  @doc """
  Renders execution progress for a step.
  """
  def render_progress(step, message, _opts \\ []) do
    status_icon =
      case step.status do
        :executing -> "⟳"
        :completed -> "✓"
        :failed -> "✗"
        :rolled_back -> "↶"
        _ -> " "
      end

    "#{status_icon} #{message}"
  end

  @doc """
  Renders the approval prompt options.
  """
  def render_approval_options(_colorize \\ true) do
    options = [
      {"y", "Approve entire plan"},
      {"n", "Reject plan"},
      {"e", "Edit plan"},
      {"s", "Step-by-step approval"},
      {"d", "Show more details"},
      {"?", "Show help"}
    ]

    options
    |> Enum.map(fn {key, desc} -> "  #{key} - #{desc}" end)
    |> Enum.join("\n")
  end

  # Private rendering functions

  defp render_header(%Plan{description: desc}) do
    "Plan: #{desc}"
  end

  defp render_separator() do
    String.duplicate("━", 50)
  end

  defp render_steps(steps) do
    steps
    |> Enum.with_index(1)
    |> Enum.map(fn {step, idx} ->
      render_step(step, idx)
    end)
    |> Enum.join("\n\n")
  end

  defp render_step(step, index) do
    # Step header
    risk_badge = render_risk_badge(step.risk_level)
    status_badge = render_status_badge(step.status)

    # Prerequisites
    prereq_note =
      if step.prerequisites && length(step.prerequisites) > 0 do
        deps = Enum.join(step.prerequisites, ", ")
        " (requires: #{deps})"
      else
        ""
      end

    header = "Step #{index}: #{step.description} #{risk_badge}#{status_badge}#{prereq_note}"

    # Step details
    details = render_step_details(step)

    if details do
      header <> "\n" <> details
    else
      header
    end
  end

  defp render_step_details(step) do
    details =
      case step.type do
        :tool ->
          render_tool_details(step.action)

        :message ->
          render_message_details(step.action)

        :command ->
          render_command_details(step.action)

        :checkpoint ->
          render_checkpoint_details(step.action)

        :conditional ->
          render_conditional_details(step.action)
      end

    # Add rollback info if present
    rollback_info =
      if step.rollback_info do
        "Rollback: #{inspect(step.rollback_info.type)}"
      end

    [details, rollback_info]
    |> Enum.filter(& &1)
    |> Enum.map(fn line -> "  └─ #{line}" end)
    |> Enum.join("\n")
  end

  defp render_tool_details(%{server: server, tool_name: tool, arguments: args}) do
    tool_text = "Tool: #{tool}@#{server}"
    args_text = if map_size(args) > 0, do: " #{inspect(args)}", else: ""
    tool_text <> args_text
  end

  defp render_message_details(%{content: content, model: model}) do
    preview = String.slice(content, 0, 60)
    preview = if String.length(content) > 60, do: preview <> "...", else: preview
    model_text = if model, do: " (#{model})", else: ""
    "Message: \"#{preview}\"#{model_text}"
  end

  defp render_command_details(%{command: cmd, args: args, working_dir: dir}) do
    full_command = Enum.join([cmd | args], " ")
    dir_text = if dir, do: " in #{dir}", else: ""
    "Command: #{full_command}#{dir_text}"
  end

  defp render_checkpoint_details(%{name: name, save_state: save}) do
    save_text = if save, do: " (saving state)", else: ""
    "Checkpoint: #{name}#{save_text}"
  end

  defp render_conditional_details(%{condition: condition, true_step: t_step, false_step: f_step}) do
    branches =
      if f_step do
        "then #{t_step}, else #{f_step}"
      else
        "then #{t_step}"
      end

    "If: #{condition} → #{branches}"
  end

  defp render_risk_badge(:safe), do: "[SAFE]"
  defp render_risk_badge(:moderate), do: "[MODERATE]"
  defp render_risk_badge(:dangerous), do: "[DANGEROUS]"

  defp render_status_badge(:executing), do: " ⟳"
  defp render_status_badge(:completed), do: " ✓"
  defp render_status_badge(:failed), do: " ✗"
  defp render_status_badge(:rolled_back), do: " ↶"
  defp render_status_badge(_), do: ""

  defp render_summary(%Plan{} = plan) do
    # Cost estimation
    cost_text =
      if plan.estimated_cost.tokens > 0 do
        tokens = trunc(plan.estimated_cost.tokens)
        amount = Float.round(plan.estimated_cost.amount, 4)
        "\nEstimated tokens: #{tokens} (~$#{amount})"
      else
        ""
      end

    # Risk summary
    risk_text = "\nRisk: #{String.upcase(to_string(plan.risk_level))}"

    risk_note =
      case plan.risk_level do
        :moderate -> " (file modifications)"
        :dangerous -> " (destructive operations)"
        _ -> ""
      end

    # Step count
    step_count = length(plan.steps)
    step_text = "\nSteps: #{step_count}"

    cost_text <> risk_text <> risk_note <> step_text
  end

  defp render_approval_prompt(%Plan{status: :pending_approval}) do
    "\nApprove? [y/n/e/s/d/?]: "
  end

  defp render_approval_prompt(_), do: ""
end
