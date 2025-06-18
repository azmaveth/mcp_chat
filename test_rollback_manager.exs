#!/usr/bin/env elixir

# Test Rollback Manager functionality
# Run with: elixir test_rollback_manager.exs

defmodule TestRollbackManager do
  alias MCPChat.PlanMode.{Plan, Step, RollbackManager}
  
  def run do
    IO.puts """
    
    ==========================================
    ↩️  Testing Rollback Manager
    ==========================================
    """
    
    # Test 1: Analyze steps for rollback information
    IO.puts "\n1️⃣ Testing step analysis for rollback information...\n"
    
    test_step_analysis()
    
    # Test 2: Create rollback operations
    IO.puts "\n2️⃣ Testing rollback operation creation...\n"
    
    test_rollback_operation_creation()
    
    # Test 3: Validate rollback operations
    IO.puts "\n3️⃣ Testing rollback validation...\n"
    
    test_rollback_validation()
    
    # Test 4: Find rollback operations for targets
    IO.puts "\n4️⃣ Testing rollback operation discovery...\n"
    
    test_rollback_discovery()
    
    # Test 5: Dry run rollback
    IO.puts "\n5️⃣ Testing dry run rollback...\n"
    
    test_dry_run_rollback()
    
    IO.puts "\n✨ Rollback Manager test complete!"
  end
  
  defp test_step_analysis do
    # Test command step analysis
    cp_step = Step.new_command("Copy file", "cp", ["source.txt", "dest.txt"])
    case RollbackManager.analyze_step_for_rollback(cp_step) do
      {:ok, rollback_info} ->
        IO.puts "✅ cp command analysis: #{inspect(rollback_info)}"
      {:error, reason} ->
        IO.puts "❌ cp command analysis failed: #{inspect(reason)}"
    end
    
    mv_step = Step.new_command("Move file", "mv", ["old_location.txt", "new_location.txt"])
    case RollbackManager.analyze_step_for_rollback(mv_step) do
      {:ok, rollback_info} ->
        IO.puts "✅ mv command analysis: #{inspect(rollback_info)}"
      {:error, reason} ->
        IO.puts "❌ mv command analysis failed: #{inspect(reason)}"
    end
    
    mkdir_step = Step.new_command("Create directory", "mkdir", ["new_directory"])
    case RollbackManager.analyze_step_for_rollback(mkdir_step) do
      {:ok, rollback_info} ->
        IO.puts "✅ mkdir command analysis: #{inspect(rollback_info)}"
      {:error, reason} ->
        IO.puts "❌ mkdir command analysis failed: #{inspect(reason)}"
    end
    
    rm_step = Step.new_command("Remove file", "rm", ["-f", "file.txt"])
    case RollbackManager.analyze_step_for_rollback(rm_step) do
      {:ok, rollback_info} ->
        IO.puts "⚠️  rm command analysis (should fail): #{inspect(rollback_info)}"
      {:error, reason} ->
        IO.puts "✅ rm command correctly identified as irreversible: #{inspect(reason)}"
    end
    
    # Test tool step analysis
    write_step = Step.new_tool("Write file", "filesystem", "write_file", %{"path" => "test.txt", "content" => "data"})
    case RollbackManager.analyze_step_for_rollback(write_step) do
      {:ok, rollback_info} ->
        IO.puts "✅ write_file tool analysis: #{inspect(rollback_info)}"
      {:error, reason} ->
        IO.puts "❌ write_file tool analysis failed: #{inspect(reason)}"
    end
    
    delete_step = Step.new_tool("Delete file", "filesystem", "delete_file", %{"path" => "test.txt"})
    case RollbackManager.analyze_step_for_rollback(delete_step) do
      {:ok, rollback_info} ->
        IO.puts "⚠️  delete_file tool analysis (should fail): #{inspect(rollback_info)}"
      {:error, reason} ->
        IO.puts "✅ delete_file tool correctly identified as irreversible: #{inspect(reason)}"
    end
    
    # Test message step (should not need rollback)
    message_step = Step.new_message("Send message", "Hello world")
    case RollbackManager.analyze_step_for_rollback(message_step) do
      {:ok, rollback_info} ->
        IO.puts "✅ message step analysis: #{inspect(rollback_info)}"
      {:error, reason} ->
        IO.puts "❌ message step analysis failed: #{inspect(reason)}"
    end
  end
  
  defp test_rollback_operation_creation do
    rollback_info = %{
      type: :restore_file,
      backup_path: "/tmp/backup.txt",
      original_path: "/tmp/original.txt"
    }
    
    context = %{
      file_size: 1024,
      timestamp: DateTime.utc_now()
    }
    
    operation = RollbackManager.create_rollback_operation("step_123", rollback_info, context)
    
    IO.puts "✅ Rollback operation created:"
    IO.puts "  Step ID: #{operation.step_id}"
    IO.puts "  Type: #{operation.rollback_info.type}"
    IO.puts "  Context keys: #{Map.keys(operation.context) |> Enum.join(", ")}"
    IO.puts "  Timestamp: #{operation.timestamp}"
  end
  
  defp test_rollback_validation do
    # Test file restore validation
    file_restore_op = RollbackManager.create_rollback_operation(
      "step_1",
      %{
        type: :restore_file,
        backup_path: "/nonexistent/backup.txt",
        original_path: "/tmp/original.txt"
      }
    )
    
    case RollbackManager.validate_rollback(file_restore_op) do
      :ok ->
        IO.puts "⚠️  File restore validation unexpectedly passed"
      {:error, reason} ->
        IO.puts "✅ File restore validation correctly failed: #{inspect(reason)}"
    end
    
    # Test file deletion validation
    file_delete_op = RollbackManager.create_rollback_operation(
      "step_2",
      %{
        type: :delete_file,
        path: "/nonexistent/file.txt"
      }
    )
    
    case RollbackManager.validate_rollback(file_delete_op) do
      :ok ->
        IO.puts "⚠️  File deletion validation unexpectedly passed"
      {:error, reason} ->
        IO.puts "✅ File deletion validation correctly failed: #{inspect(reason)}"
    end
    
    # Test checkpoint restore validation (should pass)
    checkpoint_op = RollbackManager.create_rollback_operation(
      "step_3",
      %{
        type: :restore_from_checkpoint,
        checkpoint: "test_checkpoint"
      }
    )
    
    case RollbackManager.validate_rollback(checkpoint_op) do
      :ok ->
        IO.puts "✅ Checkpoint restore validation passed"
      {:error, reason} ->
        IO.puts "❌ Checkpoint restore validation failed: #{inspect(reason)}"
    end
    
    # Test unsupported rollback type
    unsupported_op = RollbackManager.create_rollback_operation(
      "step_4",
      %{
        type: :unsupported_type,
        data: "some data"
      }
    )
    
    case RollbackManager.validate_rollback(unsupported_op) do
      :ok ->
        IO.puts "⚠️  Unsupported rollback type unexpectedly passed"
      {:error, reason} ->
        IO.puts "✅ Unsupported rollback type correctly rejected: #{inspect(reason)}"
    end
  end
  
  defp test_rollback_discovery do
    # Create a mock plan with rollback stack
    rollback_stack = [
      RollbackManager.create_rollback_operation(
        "step_1",
        %{type: :restore_file, backup_path: "/tmp/backup1.txt", original_path: "/tmp/file1.txt"}
      ),
      RollbackManager.create_rollback_operation(
        "step_2", 
        %{type: :delete_file, path: "/tmp/created_file.txt"}
      ),
      RollbackManager.create_rollback_operation(
        "step_3",
        %{type: :restore_from_checkpoint, checkpoint: "test_checkpoint"}
      ),
      RollbackManager.create_rollback_operation(
        "step_4",
        %{type: :undo_command, undo_command: "chmod", undo_args: ["644", "/tmp/file.txt"]}
      )
    ]
    
    plan = %{
      id: "test_plan",
      description: "Test plan with rollback",
      steps: [],
      status: :executing,
      execution_state: %{
        rollback_stack: rollback_stack,
        completed_steps: ["step_1", "step_2", "step_3", "step_4"],
        current_step: nil,
        failed_steps: []
      }
    }
    
    # Test rollback to specific step
    case RollbackManager.rollback_to_point(plan, "step_2", "test_session", dry_run: true) do
      {:ok, operations} ->
        IO.puts "✅ Rollback to step_2 found #{length(operations)} operations:"
        Enum.each(operations, fn op ->
          IO.puts "  - #{op.step_id}: #{op.rollback_info.type}"
        end)
      {:error, reason} ->
        IO.puts "❌ Rollback to step_2 failed: #{inspect(reason)}"
    end
    
    # Test rollback to checkpoint
    case RollbackManager.rollback_to_point(plan, "checkpoint_test_checkpoint", "test_session", dry_run: true) do
      {:ok, operations} ->
        IO.puts "✅ Rollback to checkpoint found #{length(operations)} operations:"
        Enum.each(operations, fn op ->
          IO.puts "  - #{op.step_id}: #{op.rollback_info.type}"
        end)
      {:error, reason} ->
        IO.puts "❌ Rollback to checkpoint failed: #{inspect(reason)}"
    end
    
    # Test rollback to beginning
    case RollbackManager.rollback_to_point(plan, "beginning", "test_session", dry_run: true) do
      {:ok, operations} ->
        IO.puts "✅ Rollback to beginning found #{length(operations)} operations:"
        Enum.each(operations, fn op ->
          IO.puts "  - #{op.step_id}: #{op.rollback_info.type}"
        end)
      {:error, reason} ->
        IO.puts "❌ Rollback to beginning failed: #{inspect(reason)}"
    end
    
    # Test invalid rollback target
    case RollbackManager.rollback_to_point(plan, "invalid_target", "test_session", dry_run: true) do
      {:ok, operations} ->
        IO.puts "⚠️  Invalid rollback target unexpectedly succeeded with #{length(operations)} operations"
      {:error, reason} ->
        IO.puts "✅ Invalid rollback target correctly rejected: #{inspect(reason)}"
    end
  end
  
  defp test_dry_run_rollback do
    # Create a simple plan with some rollback operations
    rollback_stack = [
      RollbackManager.create_rollback_operation(
        "step_1",
        %{type: :restore_file, backup_path: "/tmp/backup.txt", original_path: "/tmp/original.txt"}
      ),
      RollbackManager.create_rollback_operation(
        "step_2",
        %{type: :delete_file, path: "/tmp/temp_file.txt"}
      )
    ]
    
    plan = %{
      id: "dry_run_test",
      description: "Dry run test plan",
      steps: [],
      status: :executing,
      execution_state: %{
        rollback_stack: rollback_stack,
        completed_steps: ["step_1", "step_2"],
        current_step: nil,
        failed_steps: []
      }
    }
    
    IO.puts "Testing dry run rollback (no actual operations executed):"
    
    case RollbackManager.rollback_to_point(plan, "beginning", "test_session", dry_run: true) do
      {:ok, operations} ->
        IO.puts "✅ Dry run successful, would execute #{length(operations)} rollback operations:"
        Enum.with_index(operations, 1)
        |> Enum.each(fn {op, index} ->
          IO.puts "  #{index}. Step #{op.step_id}: #{op.rollback_info.type}"
          case op.rollback_info.type do
            :restore_file ->
              IO.puts "     → Restore #{op.rollback_info.original_path} from #{op.rollback_info.backup_path}"
            :delete_file ->
              IO.puts "     → Delete #{op.rollback_info.path}"
            _ ->
              IO.puts "     → #{inspect(op.rollback_info)}"
          end
        end)
        
        IO.puts "\n💡 This was a dry run - no actual rollback operations were performed."
        
      {:error, reason} ->
        IO.puts "❌ Dry run failed: #{inspect(reason)}"
    end
  end
end

# Ensure required modules are available
Code.require_file("lib/mcp_chat/plan_mode/plan.ex")
Code.require_file("lib/mcp_chat/plan_mode/step.ex")
Code.require_file("lib/mcp_chat/plan_mode/rollback_manager.ex")

# Mock the Gateway module for testing
unless Code.ensure_loaded?(MCPChat.Gateway) do
  defmodule MCPChat.Gateway do
    def execute_tool(_session_id, tool_name, _args) do
      case tool_name do
        "delete_file" -> {:ok, %{result: "File deleted successfully"}}
        "delete_directory" -> {:ok, %{result: "Directory deleted successfully"}}
        _ -> {:error, :tool_not_found}
      end
    end
  end
end

TestRollbackManager.run()