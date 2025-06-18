defmodule MCPChat.PlanMode.Renderer do
  @moduledoc """
  Renders execution plans for CLI display.

  Provides formatted output of plans with color coding,
  risk indicators, and interactive approval options.
  """

  alias MCPChat.PlanMode.{Plan, Step}

  # Import ANSI tag function for colored output
  import IO.ANSI, only: [format: 1]

  defp tag(text, color) do
    IO.ANSI.format([color, text, :reset])
  end

  @doc """
  Renders a complete plan for display.
  """
  def render(%Plan{} = plan, opts \\ []) do
    verbose = Keyword.get(opts, :verbose, false)
    colorize = Keyword.get(opts, :color, true)

    [
      render_header(plan, colorize),
      render_separator(colorize),
      render_steps(plan.steps, verbose, colorize),
      render_separator(colorize),
      render_summary(plan, colorize),
      render_approval_prompt(plan, colorize)
    ]
    |> Enum.join("\n")
  end

  @doc """
  Renders a single step for display.
  """
  def render_step(%{} = step, index, opts \\ []) do
    verbose = Keyword.get(opts, :verbose, false)
    colorize = Keyword.get(opts, :color, true)
    indent = Keyword.get(opts, :indent, 0)

    [
      render_step_header(step, index, indent, colorize),
      if(verbose, do: render_step_details(step, indent + 2, colorize), else: nil)
    ]
    |> Enum.filter(& &1)
    |> Enum.join("\n")
  end

  @doc """
  Renders execution progress for a step.
  """
  def render_progress(step, message, opts \\ []) do
    colorize = Keyword.get(opts, :color, true)

    status_icon =
      case step.status do
        :executing -> if(colorize, do: Colors.yellow("⟳"), else: "⟳")
        :completed -> if(colorize, do: Colors.green("✓"), else: "✓")
        :failed -> if(colorize, do: Colors.red("✗"), else: "✗")
        :rolled_back -> if(colorize, do: Colors.blue("↶"), else: "↶")
        _ -> " "
      end

    "#{status_icon} #{message}"
  end

  @doc """
  Renders the approval prompt options.
  """
  def render_approval_options(colorize \\ true) do
    options = [
      {if(colorize, do: IO.ANSI.green() <> "y" <> IO.ANSI.reset(), else: "y"), "Approve entire plan"},
      {if(colorize, do: IO.ANSI.red() <> "n" <> IO.ANSI.reset(), else: "n"), "Reject plan"},
      {if(colorize, do: IO.ANSI.yellow() <> "e" <> IO.ANSI.reset(), else: "e"), "Edit plan"},
      {if(colorize, do: IO.ANSI.blue() <> "s" <> IO.ANSI.reset(), else: "s"), "Step-by-step approval"},
      {if(colorize, do: IO.ANSI.cyan() <> "d" <> IO.ANSI.reset(), else: "d"), "Show more details"},
      {if(colorize, do: IO.ANSI.magenta() <> "?" <> IO.ANSI.reset(), else: "?"), "Show help"}
    ]

    options
    |> Enum.map(fn {key, desc} -> "  #{key} - #{desc}" end)
    |> Enum.join("\n")
  end

  # Private rendering functions

  defp render_header(%Plan{description: desc}, colorize) do
    header = "Plan: #{desc}"
    if colorize, do: IO.ANSI.bright() <> header <> IO.ANSI.reset(), else: header
  end

  defp render_separator(colorize) do
    line = String.duplicate("━", 50)
    if colorize, do: IO.ANSI.light_black() <> line <> IO.ANSI.reset(), else: line
  end

  defp render_steps(steps, verbose, colorize) do
    steps
    |> Enum.with_index(1)
    |> Enum.map(fn {step, idx} ->
      render_step(step, idx, verbose: verbose, color: colorize)
    end)
    |> Enum.join("\n\n")
  end

  defp render_step_header(step, index, indent, colorize) do
    indent_str = String.duplicate(" ", indent)

    # Step number and description
    step_num = if colorize, do: IO.ANSI.bright() <> "Step #{index}:" <> IO.ANSI.reset(), else: "Step #{index}:"

    # Risk indicator
    risk_badge = render_risk_badge(step.risk_level, colorize)

    # Status indicator (if executing or completed)
    status_badge = render_status_badge(step.status, colorize)

    # Prerequisites indicator
    prereq_note =
      if step.prerequisites && length(step.prerequisites) > 0 do
        deps = Enum.join(step.prerequisites, ", ")

        if colorize,
          do: IO.ANSI.light_black() <> " (requires: #{deps})" <> IO.ANSI.reset(),
          else: " (requires: #{deps})"
      else
        ""
      end

    "#{indent_str}#{step_num} #{step.description} #{risk_badge}#{status_badge}#{prereq_note}"
  end

  defp render_step_details(step, indent, colorize) do
    indent_str = String.duplicate(" ", indent)

    details =
      case step.type do
        :tool ->
          render_tool_details(step.action, colorize)

        :message ->
          render_message_details(step.action, colorize)

        :command ->
          render_command_details(step.action, colorize)

        :checkpoint ->
          render_checkpoint_details(step.action, colorize)

        :conditional ->
          render_conditional_details(step.action, colorize)
      end

    # Add rollback info if present
    rollback_info =
      if step.rollback_info do
        rollback_text = "Rollback: #{inspect(step.rollback_info.type)}"
        if colorize, do: IO.ANSI.light_black() <> rollback_text <> IO.ANSI.reset(), else: rollback_text
      end

    [details, rollback_info]
    |> Enum.filter(& &1)
    |> Enum.map(fn line -> "#{indent_str}└─ #{line}" end)
    |> Enum.join("\n")
  end

  defp render_tool_details(%{server: server, tool_name: tool, arguments: args}, colorize) do
    tool_text = "Tool: #{tool}@#{server}"
    args_text = if map_size(args) > 0, do: " #{inspect(args)}", else: ""

    if colorize do
      tag(tool_text, :cyan) <> tag(args_text, :light_black)
    else
      tool_text <> args_text
    end
  end

  defp render_message_details(%{content: content, model: model}, colorize) do
    preview = String.slice(content, 0, 60)
    preview = if String.length(content) > 60, do: preview <> "...", else: preview

    model_text = if model, do: " (#{model})", else: ""

    if colorize do
      tag("Message:", :yellow) <> " \"#{preview}\"" <> tag(model_text, :light_black)
    else
      "Message: \"#{preview}\"#{model_text}"
    end
  end

  defp render_command_details(%{command: cmd, args: args, working_dir: dir}, colorize) do
    full_command = Enum.join([cmd | args], " ")
    dir_text = if dir, do: " in #{dir}", else: ""

    if colorize do
      tag("Command:", :green) <> " #{full_command}" <> tag(dir_text, :light_black)
    else
      "Command: #{full_command}#{dir_text}"
    end
  end

  defp render_checkpoint_details(%{name: name, save_state: save}, colorize) do
    save_text = if save, do: " (saving state)", else: ""

    if colorize do
      tag("Checkpoint:", :blue) <> " #{name}" <> tag(save_text, :light_black)
    else
      "Checkpoint: #{name}#{save_text}"
    end
  end

  defp render_conditional_details(%{condition: condition, true_step: t_step, false_step: f_step}, colorize) do
    branches =
      if f_step do
        "then #{t_step}, else #{f_step}"
      else
        "then #{t_step}"
      end

    if colorize do
      tag("If:", :magenta) <> " #{condition} → #{branches}"
    else
      "If: #{condition} → #{branches}"
    end
  end

  defp render_risk_badge(:safe, true), do: Colors.green("[SAFE]")
  defp render_risk_badge(:moderate, true), do: Colors.yellow("[MODERATE]")
  defp render_risk_badge(:dangerous, true), do: Colors.red("[DANGEROUS]")
  defp render_risk_badge(level, false), do: "[#{String.upcase(to_string(level))}]"

  defp render_status_badge(:executing, true), do: IO.ANSI.yellow() <> " ⟳" <> IO.ANSI.reset()
  defp render_status_badge(:completed, true), do: IO.ANSI.green() <> " ✓" <> IO.ANSI.reset()
  defp render_status_badge(:failed, true), do: IO.ANSI.red() <> " ✗" <> IO.ANSI.reset()
  defp render_status_badge(:rolled_back, true), do: IO.ANSI.blue() <> " ↶" <> IO.ANSI.reset()
  defp render_status_badge(:executing, false), do: " ⟳"
  defp render_status_badge(:completed, false), do: " ✓"
  defp render_status_badge(:failed, false), do: " ✗"
  defp render_status_badge(:rolled_back, false), do: " ↶"
  defp render_status_badge(_, _), do: ""

  defp render_summary(%Plan{} = plan, colorize) do
    # Cost estimation
    cost_text =
      if plan.estimated_cost.tokens > 0 do
        tokens = :erlang.float_to_binary(plan.estimated_cost.tokens * 1.0, decimals: 0)
        amount = :erlang.float_to_binary(plan.estimated_cost.amount, decimals: 4)
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

    summary = cost_text <> risk_text <> risk_note <> step_text

    if colorize do
      cost_part = if cost_text != "", do: Colors.cyan(cost_text), else: ""

      risk_part =
        case plan.risk_level do
          :safe -> Colors.green(risk_text)
          :moderate -> Colors.yellow(risk_text)
          :dangerous -> Colors.red(risk_text)
        end <> Colors.dim(risk_note)

      step_part = Colors.bright(step_text)

      cost_part <> risk_part <> step_part
    else
      summary
    end
  end

  defp render_approval_prompt(%Plan{status: :pending_approval}, colorize) do
    prompt = "\nApprove? [y/n/e/s/d/?]: "
    if colorize, do: Colors.bright(prompt), else: prompt
  end

  defp render_approval_prompt(_, _), do: ""
end
