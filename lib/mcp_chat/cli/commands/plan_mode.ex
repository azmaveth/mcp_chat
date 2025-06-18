defmodule MCPChat.CLI.Commands.PlanMode do
  @moduledoc """
  Plan Mode commands for the CLI.

  Provides commands for creating, previewing, approving, and executing plans:
  - /plan <description> - Create a new plan from natural language
  - /plan show [plan_id] - Show plan details
  - /plan approve [plan_id] - Approve a plan for execution
  - /plan execute [plan_id] - Execute an approved plan
  - /plan list - List all plans
  - /plan cancel [plan_id] - Cancel a plan
  """

  alias MCPChat.PlanMode.{Plan, Parser, SafetyAnalyzer, InteractiveApproval, Executor}
  alias MCPChat.PlanMode.SimpleRenderer, as: Renderer
  alias MCPChat.Session
  require Logger

  @doc """
  Handles plan mode commands.
  """
  def handle_command(["plan"], session_id) do
    display_plan_help()
    :ok
  end

  def handle_command(["plan", "help"], _session_id) do
    display_plan_help()
    :ok
  end

  def handle_command(["plan", "list"], session_id) do
    list_plans(session_id)
  end

  def handle_command(["plan", "show"], session_id) do
    show_current_plan(session_id)
  end

  def handle_command(["plan", "show", plan_id], session_id) do
    show_plan(session_id, plan_id)
  end

  def handle_command(["plan", "approve"], session_id) do
    approve_current_plan(session_id)
  end

  def handle_command(["plan", "approve", plan_id], session_id) do
    approve_plan(session_id, plan_id)
  end

  def handle_command(["plan", "execute"], session_id) do
    execute_current_plan(session_id)
  end

  def handle_command(["plan", "execute", plan_id], session_id) do
    execute_plan(session_id, plan_id)
  end

  def handle_command(["plan", "cancel"], session_id) do
    cancel_current_plan(session_id)
  end

  def handle_command(["plan", "cancel", plan_id], session_id) do
    cancel_plan(session_id, plan_id)
  end

  def handle_command(["plan" | description_parts], session_id) when length(description_parts) > 0 do
    description = Enum.join(description_parts, " ")
    create_plan(session_id, description)
  end

  def handle_command(["plan" | _], _session_id) do
    IO.puts("❌ Invalid plan command. Use '/plan help' for usage.")
    :error
  end

  # Plan creation and management

  defp create_plan(session_id, description) do
    IO.puts("\n" <> IO.ANSI.blue() <> "🧠 Creating Plan..." <> IO.ANSI.reset())
    IO.puts("Description: #{description}")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    # Get session context for plan creation
    context = get_session_context(session_id)

    case Parser.parse(description, context) do
      {:ok, plan} ->
        IO.puts("✅ Plan created successfully!")

        # Store the plan in session state
        store_plan_in_session(session_id, plan)

        # Display the plan
        IO.puts("\n" <> Renderer.render(plan))

        # Perform safety analysis
        safety_report = SafetyAnalyzer.analyze(plan)
        display_safety_summary(safety_report)

        # Prompt for approval
        request_plan_approval(session_id, plan, safety_report)

      {:error, reason} ->
        IO.puts("❌ Failed to create plan: #{inspect(reason)}")
        :error
    end
  end

  defp show_plan(session_id, plan_id) do
    case get_plan_from_session(session_id, plan_id) do
      {:ok, plan} ->
        IO.puts("\n" <> Renderer.render(plan))

        # Show safety analysis if available
        if plan[:safety_report] do
          IO.puts("\n🔒 Safety Analysis:")
          display_safety_summary(plan[:safety_report])
        end

        :ok

      {:error, :not_found} ->
        IO.puts("❌ Plan '#{plan_id}' not found")
        :error
    end
  end

  defp show_current_plan(session_id) do
    case get_current_plan(session_id) do
      {:ok, plan} ->
        show_plan(session_id, plan[:id])

      {:error, :no_current_plan} ->
        IO.puts("❌ No current plan. Create one with '/plan <description>'")
        :error
    end
  end

  defp list_plans(session_id) do
    plans = get_all_plans(session_id)

    if Enum.empty?(plans) do
      IO.puts("📝 No plans found. Create one with '/plan <description>'")
    else
      IO.puts("\n📋 Plans:")
      IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

      Enum.each(plans, fn plan ->
        status_icon = format_plan_status_icon(plan[:status])
        risk_indicator = format_risk_level(plan[:risk_level] || :safe)
        steps_count = length(plan[:steps] || [])

        IO.puts("#{status_icon} #{plan[:id]} - #{plan[:description]}")
        IO.puts("   Steps: #{steps_count} | Risk: #{risk_indicator} | Status: #{plan[:status]}")
      end)
    end

    :ok
  end

  defp approve_plan(session_id, plan_id) do
    case get_plan_from_session(session_id, plan_id) do
      {:ok, plan} ->
        approve_plan_interactive(session_id, plan)

      {:error, :not_found} ->
        IO.puts("❌ Plan '#{plan_id}' not found")
        :error
    end
  end

  defp approve_current_plan(session_id) do
    case get_current_plan(session_id) do
      {:ok, plan} ->
        approve_plan_interactive(session_id, plan)

      {:error, :no_current_plan} ->
        IO.puts("❌ No current plan. Create one with '/plan <description>'")
        :error
    end
  end

  defp execute_plan(session_id, plan_id) do
    case get_plan_from_session(session_id, plan_id) do
      {:ok, plan} ->
        execute_plan_if_approved(session_id, plan)

      {:error, :not_found} ->
        IO.puts("❌ Plan '#{plan_id}' not found")
        :error
    end
  end

  defp execute_current_plan(session_id) do
    case get_current_plan(session_id) do
      {:ok, plan} ->
        execute_plan_if_approved(session_id, plan)

      {:error, :no_current_plan} ->
        IO.puts("❌ No current plan. Create one with '/plan <description>'")
        :error
    end
  end

  defp cancel_plan(session_id, plan_id) do
    case get_plan_from_session(session_id, plan_id) do
      {:ok, plan} ->
        updated_plan = Plan.update_status(plan, :cancelled)
        update_plan_in_session(session_id, updated_plan)

        IO.puts("✅ Plan '#{plan_id}' cancelled")
        :ok

      {:error, :not_found} ->
        IO.puts("❌ Plan '#{plan_id}' not found")
        :error
    end
  end

  defp cancel_current_plan(session_id) do
    case get_current_plan(session_id) do
      {:ok, plan} ->
        cancel_plan(session_id, plan[:id])

      {:error, :no_current_plan} ->
        IO.puts("❌ No current plan to cancel")
        :error
    end
  end

  # Interactive approval and execution

  defp request_plan_approval(session_id, plan, safety_report) do
    context = %{
      mode: :plan_level,
      session_id: session_id,
      user_preferences: %{},
      risk_tolerance: :moderate
    }

    IO.puts("\n" <> IO.ANSI.yellow() <> "⏸️  Plan Approval Required" <> IO.ANSI.reset())
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    if not safety_report.safe_to_proceed do
      IO.puts("⚠️  This plan has critical safety issues:")

      Enum.each(safety_report.blockers, fn blocker ->
        IO.puts("   • #{blocker}")
      end)

      IO.puts("\nThis plan cannot be auto-approved.")
    end

    IO.puts("\nOptions:")
    IO.puts("  • '/plan approve' - Approve plan for execution")
    IO.puts("  • '/plan execute' - Approve and execute immediately")
    IO.puts("  • '/plan show' - Review plan details")
    IO.puts("  • '/plan cancel' - Cancel this plan")

    if not safety_report.safe_to_proceed do
      IO.puts("\n⚠️  Manual review required before approval.")
    end

    :ok
  end

  defp approve_plan_interactive(session_id, plan) do
    # Perform fresh safety analysis
    safety_report = SafetyAnalyzer.analyze(plan)

    context = %{
      mode: :plan_level,
      session_id: session_id,
      user_preferences: %{},
      risk_tolerance: :moderate
    }

    # Store updated safety report
    updated_plan = Map.put(plan, :safety_report, safety_report)
    update_plan_in_session(session_id, updated_plan)

    case InteractiveApproval.request_plan_approval(updated_plan, context) do
      {:ok, :approved, approved_plan} ->
        final_plan = Plan.update_status(approved_plan, :approved)
        update_plan_in_session(session_id, final_plan)

        IO.puts("\n✅ Plan approved!")
        IO.puts("Use '/plan execute' to run the approved plan.")
        :ok

      {:ok, :rejected, _} ->
        rejected_plan = Plan.update_status(plan, :rejected)
        update_plan_in_session(session_id, rejected_plan)

        IO.puts("\n❌ Plan rejected")
        :ok

      {:ok, :modified, modified_plan} ->
        update_plan_in_session(session_id, modified_plan)
        IO.puts("\n📝 Plan modified. Use '/plan approve' to approve the changes.")
        :ok

      {:error, reason} ->
        IO.puts("\n❌ Approval failed: #{inspect(reason)}")
        :error
    end
  end

  defp execute_plan_if_approved(session_id, plan) do
    case plan[:status] do
      :approved ->
        IO.puts("\n🚀 Executing Plan...")
        IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        execution_mode = plan[:execution_mode] || :batch

        case Executor.execute(plan, session_id, execution_mode) do
          {:ok, completed_plan} ->
            update_plan_in_session(session_id, completed_plan)
            IO.puts("\n✅ Plan executed successfully!")
            IO.puts("Completed steps: #{length(completed_plan.execution_state.completed_steps)}")
            :ok

          {:error, reason} ->
            IO.puts("\n❌ Plan execution failed: #{inspect(reason)}")
            :error

          {:paused, paused_plan} ->
            update_plan_in_session(session_id, paused_plan)
            IO.puts("\n⏸️  Plan execution paused")
            IO.puts("Use '/plan execute' to resume")
            :ok
        end

      :draft ->
        IO.puts("❌ Plan must be approved before execution. Use '/plan approve' first.")
        :error

      :rejected ->
        IO.puts("❌ Cannot execute rejected plan")
        :error

      :cancelled ->
        IO.puts("❌ Cannot execute cancelled plan")
        :error

      status ->
        IO.puts("❌ Cannot execute plan in status: #{status}")
        :error
    end
  end

  # Session state management

  defp get_session_context(session_id) do
    # Get current session context for plan creation
    case Session.get_context(session_id) do
      {:ok, context} ->
        %{
          current_directory: context[:current_directory] || File.cwd!(),
          recent_files: context[:recent_files] || [],
          project_info: context[:project_info] || %{}
        }

      {:error, _} ->
        %{
          current_directory: File.cwd!(),
          recent_files: [],
          project_info: %{}
        }
    end
  end

  defp store_plan_in_session(session_id, plan) do
    # Store plan in session state
    Session.put_context(session_id, :current_plan, plan)
    Session.put_context(session_id, :plan_history, [plan | get_plan_history(session_id)])
  end

  defp update_plan_in_session(session_id, plan) do
    # Update current plan
    Session.put_context(session_id, :current_plan, plan)

    # Update in history
    updated_history =
      get_plan_history(session_id)
      |> Enum.map(fn p ->
        if p[:id] == plan[:id], do: plan, else: p
      end)

    Session.put_context(session_id, :plan_history, updated_history)
  end

  defp get_plan_from_session(session_id, plan_id) do
    case Enum.find(get_plan_history(session_id), &(&1[:id] == plan_id)) do
      nil -> {:error, :not_found}
      plan -> {:ok, plan}
    end
  end

  defp get_current_plan(session_id) do
    case Session.get_context(session_id, :current_plan) do
      {:ok, plan} when not is_nil(plan) -> {:ok, plan}
      _ -> {:error, :no_current_plan}
    end
  end

  defp get_all_plans(session_id) do
    get_plan_history(session_id)
  end

  defp get_plan_history(session_id) do
    case Session.get_context(session_id, :plan_history) do
      {:ok, history} when is_list(history) -> history
      _ -> []
    end
  end

  # Display helpers

  defp display_plan_help do
    IO.puts("""

    #{IO.ANSI.blue()}📋 Plan Mode Commands#{IO.ANSI.reset()}
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    #{IO.ANSI.yellow()}Create Plans:#{IO.ANSI.reset()}
      /plan <description>           Create plan from natural language
                                   Example: /plan refactor the User module

    #{IO.ANSI.yellow()}Manage Plans:#{IO.ANSI.reset()}
      /plan list                   List all plans
      /plan show [plan_id]         Show plan details (current if no ID)
      /plan approve [plan_id]      Approve plan for execution
      /plan execute [plan_id]      Execute approved plan
      /plan cancel [plan_id]       Cancel plan

    #{IO.ANSI.yellow()}Examples:#{IO.ANSI.reset()}
      /plan add tests for the auth module
      /plan refactor database connection code
      /plan fix memory leak in server loop
      /plan show                   # Show current plan
      /plan approve                # Approve current plan
      /plan execute                # Execute current plan

    #{IO.ANSI.yellow()}Plan Types Supported:#{IO.ANSI.reset()}
      • Refactoring (extract methods, modularize code)
      • Testing (generate unit/integration tests)
      • Debugging (systematic issue investigation)
      • Code Review (analysis and improvements)
      • Creation (generate new modules/functions)
      • Updates (modify existing code safely)

    #{IO.ANSI.yellow()}Safety Features:#{IO.ANSI.reset()}
      • Risk assessment for all operations
      • Interactive approval for dangerous actions
      • Automatic rollback information
      • Step-by-step execution control
      • Cost estimation
    """)
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

    if not Enum.empty?(safety_report.warnings) do
      IO.puts("\n⚠️  Warnings:")

      Enum.take(safety_report.warnings, 3)
      |> Enum.each(fn warning ->
        IO.puts("  • #{warning}")
      end)
    end
  end

  defp format_plan_status_icon(:draft), do: "📝"
  defp format_plan_status_icon(:pending_approval), do: "⏳"
  defp format_plan_status_icon(:approved), do: "✅"
  defp format_plan_status_icon(:executing), do: "🚀"
  defp format_plan_status_icon(:completed), do: "✅"
  defp format_plan_status_icon(:failed), do: "❌"
  defp format_plan_status_icon(:cancelled), do: "🚫"
  defp format_plan_status_icon(:rejected), do: "❌"
  defp format_plan_status_icon(_), do: "❓"

  defp format_risk_level(:safe), do: IO.ANSI.green() <> "SAFE" <> IO.ANSI.reset()
  defp format_risk_level(:moderate), do: IO.ANSI.yellow() <> "MODERATE" <> IO.ANSI.reset()
  defp format_risk_level(:dangerous), do: IO.ANSI.red() <> "DANGEROUS" <> IO.ANSI.reset()
  defp format_risk_level(:critical), do: IO.ANSI.red() <> IO.ANSI.bright() <> "CRITICAL" <> IO.ANSI.reset()
  defp format_risk_level(other), do: to_string(other)
end
