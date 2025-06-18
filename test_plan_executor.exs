#!/usr/bin/env elixir

# Test Plan Executor functionality
# Run with: elixir test_plan_executor.exs

defmodule TestPlanExecutor do
  alias MCPChat.PlanMode.{Plan, Step, Executor}
  alias MCPChat.PlanMode.SimpleRenderer, as: Renderer
  
  def run do
    IO.puts """
    
    ==========================================
    🚀 Testing Plan Executor
    ==========================================
    """
    
    # Test 1: Create a simple executable plan
    IO.puts "\n1️⃣ Creating and executing a simple plan...\n"
    
    simple_plan = create_simple_plan()
    IO.puts Renderer.render(simple_plan)
    
    # Approve the plan
    approved_plan = Plan.update_status(simple_plan, :approved)
    
    # Execute the plan
    case Executor.execute(approved_plan, "test_session", :batch) do
      {:ok, completed_plan} ->
        IO.puts "\n✅ Plan executed successfully!"
        IO.puts "Status: #{completed_plan.status}"
        IO.puts "Completed steps: #{length(completed_plan.execution_state.completed_steps)}"
        
      {:error, reason} ->
        IO.puts "\n❌ Plan execution failed: #{inspect(reason)}"
    end
    
    # Test 2: Step-by-step execution
    IO.puts "\n\n2️⃣ Testing step-by-step execution...\n"
    
    step_plan = create_step_by_step_plan()
    approved_step_plan = Plan.update_status(step_plan, :approved)
    
    IO.puts "Plan created with #{length(step_plan.steps)} steps"
    IO.puts "This would normally prompt for approval at each step."
    
    # Test 3: Plan with failure
    IO.puts "\n\n3️⃣ Testing plan with intentional failure...\n"
    
    failure_plan = create_failure_plan()
    approved_failure_plan = Plan.update_status(failure_plan, :approved)
    
    case Executor.execute(approved_failure_plan, "test_session", :batch) do
      {:ok, completed_plan} ->
        IO.puts "✅ Unexpected success: #{completed_plan.status}"
        
      {:error, {:step_failed, step_id, reason, failed_plan}} ->
        IO.puts "✅ Expected failure handled correctly"
        IO.puts "Failed step: #{step_id}"
        IO.puts "Reason: #{inspect(reason)}"
        IO.puts "Plan status: #{failed_plan.status}"
    end
    
    # Test 4: Conditional execution
    IO.puts "\n\n4️⃣ Testing conditional step execution...\n"
    
    conditional_plan = create_conditional_plan()
    approved_conditional_plan = Plan.update_status(conditional_plan, :approved)
    
    case Executor.execute(approved_conditional_plan, "test_session", :batch) do
      {:ok, completed_plan} ->
        IO.puts "✅ Conditional plan executed"
        IO.puts "Completed steps: #{length(completed_plan.execution_state.completed_steps)}"
        
      {:error, reason} ->
        IO.puts "❌ Conditional execution failed: #{inspect(reason)}"
    end
    
    # Test 5: Rollback capability
    IO.puts "\n\n5️⃣ Testing rollback capability...\n"
    
    rollback_plan = create_rollback_plan()
    
    # Simulate partial execution
    partial_plan = %{rollback_plan | 
      status: :executing,
      execution_state: %{
        current_step: nil,
        completed_steps: ["step_1", "step_2"],
        failed_steps: [],
        rollback_stack: [
          %{
            step_id: "step_2",
            rollback_info: %{type: :delete_file, path: "/tmp/test_backup"},
            context: %{created_file: "/tmp/test_backup"}
          },
          %{
            step_id: "step_1",
            rollback_info: %{type: :restore_file, backup_path: "/tmp/original.backup", original_path: "/tmp/original"},
            context: %{backup_created: true}
          }
        ]
      }
    }
    
    case Executor.rollback(partial_plan, "step_1", "test_session") do
      {:ok, rolled_back_plan} ->
        IO.puts "✅ Rollback successful"
        
      {:error, reason} ->
        IO.puts "⚠️  Rollback simulation: #{inspect(reason)}"
        IO.puts "(This is expected since we're not creating actual files)"
    end
    
    IO.puts "\n✨ Plan Executor test complete!"
  end
  
  # Helper functions to create test plans
  
  defp create_simple_plan do
    Plan.new("Simple test plan")
    |> Plan.add_step(
      Step.new_message(
        "Analyze test scenario",
        "Let's analyze a simple test case for plan execution"
      )
    )
    |> Plan.add_step(
      Step.new_checkpoint("test_checkpoint")
    )
    |> Plan.add_step(
      Step.new_message(
        "Complete analysis",
        "Analysis complete, proceeding with next steps",
        prerequisites: ["step_1", "step_2"]
      )
    )
  end
  
  defp create_step_by_step_plan do
    Plan.new("Step-by-step execution test")
    |> Plan.add_step(
      Step.new_command(
        "List current directory",
        "ls",
        ["-la"]
      )
    )
    |> Plan.add_step(
      Step.new_command(
        "Show current time",
        "date",
        []
      )
    )
  end
  
  defp create_failure_plan do
    Plan.new("Plan with intentional failure")
    |> Plan.add_step(
      Step.new_message(
        "Start operation",
        "Starting a test operation that will succeed"
      )
    )
    |> Plan.add_step(
      Step.new_command(
        "Intentional failure",
        "nonexistent_command",
        ["--invalid-flag"],
        prerequisites: ["step_1"]
      )
    )
  end
  
  defp create_conditional_plan do
    Plan.new("Conditional execution test")
    |> Plan.add_step(
      Step.new_message(
        "Check conditions",
        "Checking if conditions are met for next step"
      )
    )
    |> Plan.add_step(
      Step.new_conditional(
        "Decide next action",
        "step_1.status == :completed",
        "step_3",
        nil,
        prerequisites: ["step_1"]
      )
    )
    |> Plan.add_step(
      Step.new_message(
        "Final step",
        "This step runs if condition is true",
        prerequisites: ["step_2"]
      )
    )
  end
  
  defp create_rollback_plan do
    Plan.new("Rollback capability test")
    |> Plan.add_step(
      Step.new_command(
        "Create backup",
        "cp",
        ["important_file.txt", "important_file.backup"],
        rollback_info: %{
          type: :restore_file,
          backup_path: "important_file.backup",
          original_path: "important_file.txt"
        }
      )
    )
    |> Plan.add_step(
      Step.new_command(
        "Create temp file",
        "touch",
        ["/tmp/test_file"],
        rollback_info: %{
          type: :delete_file,
          path: "/tmp/test_file"
        },
        prerequisites: ["step_1"]
      )
    )
  end
end

# Ensure required modules are available
Code.require_file("lib/mcp_chat/plan_mode/plan.ex")
Code.require_file("lib/mcp_chat/plan_mode/step.ex")
Code.require_file("lib/mcp_chat/plan_mode/simple_renderer.ex")
Code.require_file("lib/mcp_chat/plan_mode/executor.ex")

# Mock the Gateway module for testing
unless Code.ensure_loaded?(MCPChat.Gateway) do
  defmodule MCPChat.Gateway do
    def execute_tool(_session_id, tool_name, _args) do
      case tool_name do
        "nonexistent_tool" -> {:error, :tool_not_found}
        _ -> {:ok, %{result: "Tool #{tool_name} executed successfully", data: %{}}}
      end
    end
    
    def send_message(_session_id, message) do
      if String.contains?(message, "fail") do
        {:error, :message_failed}
      else
        :ok
      end
    end
  end
end

TestPlanExecutor.run()