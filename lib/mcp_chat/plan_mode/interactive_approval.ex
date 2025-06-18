defmodule MCPChat.PlanMode.InteractiveApproval do
  @moduledoc """
  Handles interactive approval workflows for Plan Mode execution.

  Provides different approval modes:
  - Plan-level approval (approve entire plan)
  - Step-by-step approval (approve each step individually)
  - Risk-based approval (automatic for safe, prompt for dangerous)
  - Batch approval (approve groups of steps)
  """

  alias MCPChat.PlanMode.{Plan, Step, SafetyAnalyzer}
  alias MCPChat.PlanMode.SimpleRenderer, as: Renderer
  require Logger

  @type approval_mode :: :plan_level | :step_by_step | :risk_based | :batch
  @type approval_result :: :approved | :rejected | :modified | :paused
  @type approval_context :: %{
          mode: approval_mode(),
          session_id: String.t(),
          user_preferences: map(),
          risk_tolerance: :conservative | :moderate | :aggressive
        }

  @doc """
  Requests approval for a plan using the specified mode.
  """
  @spec request_plan_approval(map(), approval_context()) :: {:ok, approval_result(), map()} | {:error, term()}
  def request_plan_approval(plan, context) do
    Logger.info("Requesting plan approval",
      plan_id: plan[:id],
      mode: context.mode,
      risk_tolerance: context.risk_tolerance
    )

    case context.mode do
      :plan_level ->
        handle_plan_level_approval(plan, context)

      :step_by_step ->
        handle_step_by_step_approval(plan, context)

      :risk_based ->
        handle_risk_based_approval(plan, context)

      :batch ->
        handle_batch_approval(plan, context)
    end
  end

  @doc """
  Requests approval for a single step during execution.
  """
  @spec request_step_approval(map(), map(), approval_context()) :: {:ok, approval_result()} | {:error, term()}
  def request_step_approval(step, plan, context) do
    Logger.info("Requesting step approval",
      step_id: step[:id],
      step_type: step[:type],
      risk_level: step[:risk_level]
    )

    case should_prompt_for_step?(step, context) do
      true ->
        display_step_approval_prompt(step, plan, context)

      false ->
        Logger.info("Step auto-approved", step_id: step[:id], reason: "below risk tolerance")
        {:ok, :approved}
    end
  end

  @doc """
  Displays a plan modification interface allowing users to edit before approval.
  """
  @spec request_plan_modification(map(), approval_context()) :: {:ok, map()} | {:error, term()}
  def request_plan_modification(plan, context) do
    Logger.info("Opening plan modification interface", plan_id: plan[:id])

    IO.puts("\n" <> IO.ANSI.cyan() <> "📝 Plan Modification Mode" <> IO.ANSI.reset())
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    # Display current plan
    display_plan_summary(plan)

    IO.puts("\nModification Options:")
    IO.puts("  [a] Add step")
    IO.puts("  [r] Remove step")
    IO.puts("  [m] Modify step")
    IO.puts("  [o] Reorder steps")
    IO.puts("  [s] Show full plan")
    IO.puts("  [d] Done editing")
    IO.puts("  [c] Cancel modifications")

    handle_modification_commands(plan, context)
  end

  # Private functions for different approval modes

  defp handle_plan_level_approval(plan, context) do
    # Analyze plan safety
    safety_report = SafetyAnalyzer.analyze(plan)

    IO.puts("\n" <> IO.ANSI.blue() <> "📋 Plan Approval Required" <> IO.ANSI.reset())
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    # Display plan overview
    display_plan_summary(plan)

    # Display safety analysis
    display_safety_summary(safety_report)

    # Show approval options
    IO.puts("\nApproval Options:")
    IO.puts("  [y] Approve and execute plan")
    IO.puts("  [n] Reject plan")
    IO.puts("  [m] Modify plan before approval")
    IO.puts("  [s] Switch to step-by-step mode")
    IO.puts("  [d] Show detailed plan view")
    IO.puts("  [r] Show safety analysis details")
    IO.puts("  [?] Help")

    case get_user_input("\nYour choice: ") do
      "y" ->
        if safety_report.safe_to_proceed do
          {:ok, :approved, plan}
        else
          IO.puts("\n⚠️  Plan has critical safety issues and cannot be auto-approved.")
          handle_unsafe_plan_approval(plan, safety_report, context)
        end

      "n" ->
        IO.puts("\n❌ Plan rejected by user")
        {:ok, :rejected, plan}

      "m" ->
        case request_plan_modification(plan, context) do
          {:ok, modified_plan} ->
            handle_plan_level_approval(modified_plan, context)

          error ->
            error
        end

      "s" ->
        new_context = %{context | mode: :step_by_step}
        handle_step_by_step_approval(plan, new_context)

      "d" ->
        IO.puts("\n" <> Renderer.render(plan))
        handle_plan_level_approval(plan, context)

      "r" ->
        display_detailed_safety_analysis(safety_report)
        handle_plan_level_approval(plan, context)

      "?" ->
        display_approval_help()
        handle_plan_level_approval(plan, context)

      _ ->
        IO.puts("Invalid option. Please try again.")
        handle_plan_level_approval(plan, context)
    end
  end

  defp handle_step_by_step_approval(plan, context) do
    IO.puts("\n" <> IO.ANSI.blue() <> "👣 Step-by-Step Approval Mode" <> IO.ANSI.reset())
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    IO.puts("Each step will be presented for individual approval during execution.")

    display_plan_summary(plan)

    IO.puts("\nStep-by-Step Options:")
    IO.puts("  [y] Start step-by-step execution")
    IO.puts("  [p] Preview all steps first")
    IO.puts("  [c] Configure step approval settings")
    IO.puts("  [b] Go back to plan-level approval")
    IO.puts("  [n] Cancel")

    case get_user_input("\nYour choice: ") do
      "y" ->
        {:ok, :approved, %{plan | execution_mode: :step_by_step}}

      "p" ->
        display_step_preview(plan)
        handle_step_by_step_approval(plan, context)

      "c" ->
        new_context = configure_step_approval_settings(context)
        handle_step_by_step_approval(plan, new_context)

      "b" ->
        new_context = %{context | mode: :plan_level}
        handle_plan_level_approval(plan, new_context)

      "n" ->
        {:ok, :rejected, plan}

      _ ->
        IO.puts("Invalid option. Please try again.")
        handle_step_by_step_approval(plan, context)
    end
  end

  defp handle_risk_based_approval(plan, context) do
    # Analyze each step's risk level
    step_risks = analyze_step_risks(plan)

    {auto_approved, requires_approval} =
      Enum.split_with(step_risks, fn {_step, risk} ->
        is_auto_approvable?(risk, context.risk_tolerance)
      end)

    IO.puts("\n" <> IO.ANSI.blue() <> "⚖️  Risk-Based Approval" <> IO.ANSI.reset())
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    IO.puts("Risk Tolerance: #{format_risk_tolerance(context.risk_tolerance)}")
    IO.puts("Steps requiring approval: #{length(requires_approval)}/#{length(step_risks)}")

    if length(auto_approved) > 0 do
      IO.puts("\n✅ Auto-approved steps (#{length(auto_approved)}):")

      Enum.each(auto_approved, fn {step, risk} ->
        IO.puts("  • #{step[:description]} [#{format_risk_level(risk)}]")
      end)
    end

    if length(requires_approval) > 0 do
      IO.puts("\n⚠️  Steps requiring approval (#{length(requires_approval)}):")

      Enum.each(requires_approval, fn {step, risk} ->
        IO.puts("  • #{step[:description]} [#{format_risk_level(risk)}]")
      end)
    end

    IO.puts("\nRisk-Based Options:")
    IO.puts("  [y] Approve (will prompt for high-risk steps during execution)")
    IO.puts("  [a] Approve all (override risk checks)")
    IO.puts("  [r] Review high-risk steps now")
    IO.puts("  [c] Change risk tolerance")
    IO.puts("  [n] Reject plan")

    case get_user_input("\nYour choice: ") do
      "y" ->
        execution_plan = %{plan | execution_mode: :risk_based, risk_tolerance: context.risk_tolerance}
        {:ok, :approved, execution_plan}

      "a" ->
        execution_plan = %{plan | execution_mode: :batch, risk_override: true}
        {:ok, :approved, execution_plan}

      "r" ->
        review_high_risk_steps(requires_approval, plan, context)

      "c" ->
        new_context = configure_risk_tolerance(context)
        handle_risk_based_approval(plan, new_context)

      "n" ->
        {:ok, :rejected, plan}

      _ ->
        IO.puts("Invalid option. Please try again.")
        handle_risk_based_approval(plan, context)
    end
  end

  defp handle_batch_approval(plan, context) do
    # Group steps into logical batches
    batches = group_steps_into_batches(plan[:steps] || [])

    IO.puts("\n" <> IO.ANSI.blue() <> "📦 Batch Approval Mode" <> IO.ANSI.reset())
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    IO.puts("Steps grouped into #{length(batches)} batches:")

    Enum.with_index(batches, 1)
    |> Enum.each(fn {batch, index} ->
      IO.puts("\nBatch #{index} (#{length(batch)} steps):")

      Enum.each(batch, fn step ->
        IO.puts("  • #{step[:description]} [#{format_risk_level(step[:risk_level] || :safe)}]")
      end)
    end)

    IO.puts("\nBatch Approval Options:")
    IO.puts("  [y] Approve all batches")
    IO.puts("  [s] Select batches to approve")
    IO.puts("  [r] Review individual batches")
    IO.puts("  [n] Reject plan")

    case get_user_input("\nYour choice: ") do
      "y" ->
        execution_plan = %{plan | execution_mode: :batch, batches: batches}
        {:ok, :approved, execution_plan}

      "s" ->
        handle_selective_batch_approval(batches, plan, context)

      "r" ->
        handle_batch_review(batches, plan, context)

      "n" ->
        {:ok, :rejected, plan}

      _ ->
        IO.puts("Invalid option. Please try again.")
        handle_batch_approval(plan, context)
    end
  end

  # Step approval during execution

  defp display_step_approval_prompt(step, plan, context) do
    IO.puts("\n" <> IO.ANSI.yellow() <> "⏸️  Step Approval Required" <> IO.ANSI.reset())
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    # Display step details
    display_step_details(step, plan)

    # Show approval options based on risk level
    options = get_step_approval_options(step, context)

    IO.puts("\nStep Options:")

    Enum.each(options, fn {key, description} ->
      IO.puts("  [#{key}] #{description}")
    end)

    case get_user_input("\nYour choice: ") do
      "y" ->
        {:ok, :approved}

      "n" ->
        {:ok, :rejected}

      "s" ->
        {:ok, :paused}

      "m" ->
        case modify_step(step, context) do
          {:ok, modified_step} ->
            # Would need to update plan with modified step
            {:ok, :modified}

          error ->
            error
        end

      "d" ->
        display_detailed_step_info(step, plan)
        display_step_approval_prompt(step, plan, context)

      "?" ->
        display_step_approval_help()
        display_step_approval_prompt(step, plan, context)

      _ ->
        IO.puts("Invalid option. Please try again.")
        display_step_approval_prompt(step, plan, context)
    end
  end

  # Helper functions

  defp should_prompt_for_step?(step, context) do
    step_risk = step[:risk_level] || :safe

    case context.risk_tolerance do
      :conservative ->
        step_risk in [:moderate, :dangerous]

      :moderate ->
        step_risk == :dangerous

      :aggressive ->
        # Never prompt automatically
        false
    end
  end

  defp display_plan_summary(plan) do
    IO.puts("\nPlan: #{plan[:description] || "Untitled Plan"}")
    IO.puts("Steps: #{length(plan[:steps] || [])}")

    if plan[:estimated_cost] do
      IO.puts("Estimated Cost: #{plan[:estimated_cost]}")
    end

    if plan[:risk_level] do
      IO.puts("Risk Level: #{format_risk_level(plan[:risk_level])}")
    end
  end

  defp display_safety_summary(safety_report) do
    IO.puts("\n🔒 Safety Analysis:")
    IO.puts("Overall Risk: #{format_risk_level(safety_report.overall_risk)}")
    IO.puts("Safe to Proceed: #{if safety_report.safe_to_proceed, do: "✅ YES", else: "❌ NO"}")

    if length(safety_report.risk_factors) > 0 do
      IO.puts("Risk Factors: #{length(safety_report.risk_factors)}")
    end

    if not Enum.empty?(safety_report.blockers) do
      IO.puts("\n🚫 Critical Issues:")

      Enum.each(safety_report.blockers, fn blocker ->
        IO.puts("  • #{blocker}")
      end)
    end
  end

  defp display_detailed_safety_analysis(safety_report) do
    IO.puts("\n" <> IO.ANSI.cyan() <> "🔍 Detailed Safety Analysis" <> IO.ANSI.reset())
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    IO.puts("Overall Risk: #{format_risk_level(safety_report.overall_risk)}")
    IO.puts("Analysis Time: #{safety_report.analysis_timestamp}")
    IO.puts("Safe to Proceed: #{if safety_report.safe_to_proceed, do: "✅ YES", else: "❌ NO"}")

    if not Enum.empty?(safety_report.risk_factors) do
      IO.puts("\n⚠️  Risk Factors (#{length(safety_report.risk_factors)}):")

      Enum.each(safety_report.risk_factors, fn factor ->
        IO.puts("  • #{format_severity(factor.severity)} #{factor.description}")
        IO.puts("    Mitigation: #{factor.mitigation}")
      end)
    end

    if not Enum.empty?(safety_report.warnings) do
      IO.puts("\n⚠️  Warnings:")

      Enum.each(safety_report.warnings, fn warning ->
        IO.puts("  • #{warning}")
      end)
    end

    if not Enum.empty?(safety_report.recommendations) do
      IO.puts("\n💡 Recommendations:")

      Enum.each(Enum.take(safety_report.recommendations, 5), fn rec ->
        IO.puts("  • #{rec}")
      end)
    end

    IO.puts("\nPress Enter to continue...")
    IO.gets("")
  end

  defp display_step_details(step, _plan) do
    IO.puts("Step: #{step[:description] || "Untitled Step"}")
    IO.puts("Type: #{step[:type]}")
    IO.puts("Risk Level: #{format_risk_level(step[:risk_level] || :safe)}")

    if step[:prerequisites] && length(step[:prerequisites]) > 0 do
      IO.puts("Prerequisites: #{Enum.join(step[:prerequisites], ", ")}")
    end

    case step[:type] do
      :tool ->
        action = step[:action] || %{}
        IO.puts("Tool: #{action[:tool_name]} (#{action[:server]})")

      :command ->
        action = step[:action] || %{}
        cmd_str = [action[:command] | action[:args] || []] |> Enum.join(" ")
        IO.puts("Command: #{cmd_str}")

      :message ->
        action = step[:action] || %{}
        content_preview = String.slice(action[:content] || "", 0, 50)
        IO.puts("Message: #{content_preview}...")

      _ ->
        IO.puts("Action: #{inspect(step[:action])}")
    end
  end

  defp get_step_approval_options(step, _context) do
    base_options = [
      {"y", "Approve and execute step"},
      {"n", "Reject step (stop execution)"},
      {"s", "Skip this step"},
      {"d", "Show detailed step information"}
    ]

    risk_options =
      case step[:risk_level] do
        :dangerous ->
          [{"m", "Modify step before execution"}]

        _ ->
          []
      end

    base_options ++ risk_options ++ [{"?", "Help"}]
  end

  defp analyze_step_risks(plan) do
    steps = plan[:steps] || []

    Enum.map(steps, fn step ->
      risk_level = step[:risk_level] || :safe
      {step, risk_level}
    end)
  end

  defp is_auto_approvable?(risk_level, tolerance) do
    case {risk_level, tolerance} do
      {:safe, _} -> true
      {:moderate, :aggressive} -> true
      {:moderate, :moderate} -> true
      {:dangerous, :aggressive} -> true
      _ -> false
    end
  end

  defp group_steps_into_batches(steps) do
    # Simple grouping by step type and risk level
    steps
    |> Enum.chunk_by(fn step ->
      {step[:type], step[:risk_level] || :safe}
    end)
    |> Enum.reject(&Enum.empty?/1)
  end

  # UI Helper functions

  defp format_risk_level(:safe), do: IO.ANSI.green() <> "SAFE" <> IO.ANSI.reset()
  defp format_risk_level(:moderate), do: IO.ANSI.yellow() <> "MODERATE" <> IO.ANSI.reset()
  defp format_risk_level(:dangerous), do: IO.ANSI.red() <> "DANGEROUS" <> IO.ANSI.reset()
  defp format_risk_level(:critical), do: IO.ANSI.red() <> IO.ANSI.bright() <> "CRITICAL" <> IO.ANSI.reset()
  defp format_risk_level(other), do: to_string(other)

  defp format_severity(:low), do: IO.ANSI.blue() <> "LOW" <> IO.ANSI.reset()
  defp format_severity(:medium), do: IO.ANSI.yellow() <> "MEDIUM" <> IO.ANSI.reset()
  defp format_severity(:high), do: IO.ANSI.red() <> "HIGH" <> IO.ANSI.reset()
  defp format_severity(:critical), do: IO.ANSI.red() <> IO.ANSI.bright() <> "CRITICAL" <> IO.ANSI.reset()

  defp format_risk_tolerance(:conservative), do: "Conservative (prompt for moderate+ risk)"
  defp format_risk_tolerance(:moderate), do: "Moderate (prompt for dangerous+ risk)"
  defp format_risk_tolerance(:aggressive), do: "Aggressive (minimal prompting)"

  defp get_user_input(prompt) do
    IO.gets(prompt)
    |> String.trim()
    |> String.downcase()
  end

  # Placeholder functions for complex interactions

  defp handle_unsafe_plan_approval(_plan, _safety_report, _context) do
    IO.puts("Critical safety issues must be resolved before approval.")
    {:ok, :rejected, %{}}
  end

  defp handle_modification_commands(plan, _context) do
    IO.puts("Plan modification interface would be implemented here.")
    {:ok, plan}
  end

  defp display_approval_help do
    IO.puts("\n" <> IO.ANSI.cyan() <> "📖 Plan Approval Help" <> IO.ANSI.reset())
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    IO.puts("• Approve (y): Execute the plan as designed")
    IO.puts("• Reject (n): Cancel plan execution entirely")
    IO.puts("• Modify (m): Edit steps before execution")
    IO.puts("• Step-by-step (s): Approve each step individually")
    IO.puts("• Detailed view (d): Show complete plan breakdown")
    IO.puts("• Safety details (r): View comprehensive risk analysis")
  end

  defp display_step_preview(plan) do
    IO.puts("\n" <> IO.ANSI.cyan() <> "👀 Step Preview" <> IO.ANSI.reset())
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    Enum.with_index(plan[:steps] || [], 1)
    |> Enum.each(fn {step, index} ->
      IO.puts("#{index}. #{step[:description]} [#{format_risk_level(step[:risk_level] || :safe)}]")
    end)

    IO.puts("\nPress Enter to continue...")
    IO.gets("")
  end

  defp configure_step_approval_settings(context) do
    IO.puts("\n🔧 Configure Step Approval Settings:")
    IO.puts("  [1] Conservative (prompt for all moderate+ risk steps)")
    IO.puts("  [2] Moderate (prompt only for dangerous steps)")
    IO.puts("  [3] Aggressive (minimal prompting)")

    choice = get_user_input("Risk tolerance [1-3]: ")

    new_tolerance =
      case choice do
        "1" -> :conservative
        "2" -> :moderate
        "3" -> :aggressive
        _ -> context.risk_tolerance
      end

    %{context | risk_tolerance: new_tolerance}
  end

  defp configure_risk_tolerance(context) do
    configure_step_approval_settings(context)
  end

  defp review_high_risk_steps(_requires_approval, plan, context) do
    IO.puts("High-risk step review would be implemented here.")
    {:ok, :approved, plan}
  end

  defp handle_selective_batch_approval(_batches, plan, _context) do
    IO.puts("Selective batch approval would be implemented here.")
    {:ok, :approved, plan}
  end

  defp handle_batch_review(_batches, plan, context) do
    IO.puts("Batch review interface would be implemented here.")
    handle_batch_approval(plan, context)
  end

  defp modify_step(step, _context) do
    IO.puts("Step modification interface would be implemented here.")
    {:ok, step}
  end

  defp display_detailed_step_info(step, _plan) do
    IO.puts("\n" <> IO.ANSI.cyan() <> "🔍 Detailed Step Information" <> IO.ANSI.reset())
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    IO.puts("ID: #{step[:id]}")
    IO.puts("Description: #{step[:description]}")
    IO.puts("Type: #{step[:type]}")
    IO.puts("Risk Level: #{format_risk_level(step[:risk_level] || :safe)}")

    if step[:action] do
      IO.puts("Action Details: #{inspect(step[:action])}")
    end

    if step[:rollback_info] do
      IO.puts("Rollback: #{inspect(step[:rollback_info])}")
    end

    IO.puts("\nPress Enter to continue...")
    IO.gets("")
  end

  defp display_step_approval_help do
    IO.puts("\n" <> IO.ANSI.cyan() <> "📖 Step Approval Help" <> IO.ANSI.reset())
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    IO.puts("• Approve (y): Execute this step")
    IO.puts("• Reject (n): Stop execution entirely")
    IO.puts("• Skip (s): Skip this step and continue")
    IO.puts("• Modify (m): Edit step before execution")
    IO.puts("• Details (d): Show complete step information")
  end
end
