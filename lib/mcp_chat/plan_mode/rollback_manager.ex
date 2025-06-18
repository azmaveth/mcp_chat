defmodule MCPChat.PlanMode.RollbackManager do
  @moduledoc """
  Manages rollback operations for executed plan steps.

  Provides functionality to:
  - Store rollback information during execution
  - Execute rollback operations in reverse order
  - Verify rollback success
  - Handle rollback failures gracefully
  - Support different rollback strategies
  """

  alias MCPChat.PlanMode.{Plan, Step}
  alias MCPChat.Gateway
  require Logger

  @type rollback_operation :: %{
          step_id: String.t(),
          rollback_info: map(),
          context: map(),
          timestamp: DateTime.t()
        }

  @type rollback_strategy :: :fail_fast | :best_effort | :interactive
  @type rollback_result ::
          {:ok, [rollback_operation()]} | {:error, term()} | {:partial, [rollback_operation()], [term()]}

  @doc """
  Executes rollback operations for a plan back to a specific point.
  """
  @spec rollback_to_point(map(), String.t(), String.t(), keyword()) :: rollback_result()
  def rollback_to_point(plan, target_point, session_id, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :fail_fast)
    dry_run = Keyword.get(opts, :dry_run, false)

    Logger.info("Starting rollback operation",
      plan_id: plan.id,
      target: target_point,
      strategy: strategy,
      dry_run: dry_run
    )

    rollback_stack = get_in(plan, [:execution_state, :rollback_stack]) || []

    case find_rollback_operations(rollback_stack, target_point) do
      {:ok, operations} ->
        if dry_run do
          {:ok, operations}
        else
          execute_rollback_operations(operations, session_id, strategy)
        end

      {:error, reason} ->
        {:error, {:rollback_planning_failed, reason}}
    end
  end

  @doc """
  Validates that a rollback operation can be performed.
  """
  @spec validate_rollback(rollback_operation()) :: :ok | {:error, term()}
  def validate_rollback(%{rollback_info: rollback_info} = operation) do
    case rollback_info.type do
      :restore_file ->
        validate_file_restore(rollback_info)

      :delete_file ->
        validate_file_deletion(rollback_info)

      :restore_from_checkpoint ->
        validate_checkpoint_restore(rollback_info)

      :undo_command ->
        validate_command_undo(rollback_info)

      :tool_rollback ->
        validate_tool_rollback(rollback_info, operation)

      _ ->
        {:error, {:unsupported_rollback_type, rollback_info.type}}
    end
  end

  @doc """
  Creates a rollback operation entry.
  """
  @spec create_rollback_operation(String.t(), map(), map()) :: rollback_operation()
  def create_rollback_operation(step_id, rollback_info, context \\ %{}) do
    %{
      step_id: step_id,
      rollback_info: rollback_info,
      context: context,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Analyzes a step to determine what rollback information should be captured.
  """
  @spec analyze_step_for_rollback(Step.t()) :: {:ok, map()} | {:error, term()}
  def analyze_step_for_rollback(%{type: :command, action: %{command: cmd, args: args}} = _step) do
    case cmd do
      "cp" ->
        if length(args) >= 2 do
          [source, dest | _] = args

          {:ok,
           %{
             type: :delete_file,
             path: dest,
             metadata: %{original_command: "cp", source: source}
           }}
        else
          {:error, :insufficient_arguments}
        end

      "mv" ->
        if length(args) >= 2 do
          [source, dest | _] = args

          {:ok,
           %{
             type: :restore_file,
             backup_path: dest,
             original_path: source,
             metadata: %{original_command: "mv"}
           }}
        else
          {:error, :insufficient_arguments}
        end

      "mkdir" ->
        if length(args) >= 1 do
          [dir | _] = args

          {:ok,
           %{
             type: :delete_file,
             path: dir,
             metadata: %{original_command: "mkdir", is_directory: true}
           }}
        else
          {:error, :insufficient_arguments}
        end

      "chmod" ->
        {:ok,
         %{
           type: :undo_command,
           undo_command: "chmod",
           # Would need to capture original permissions
           metadata: %{requires_permission_capture: true}
         }}

      "rm" ->
        # Cannot rollback rm without prior backup
        {:error, :irreversible_operation}

      _ ->
        {:ok, %{type: :manual_rollback, command: cmd, args: args}}
    end
  end

  def analyze_step_for_rollback(%{type: :tool, action: %{tool_name: tool_name}} = _step) do
    case tool_name do
      "write_file" ->
        {:ok,
         %{
           type: :tool_rollback,
           tool_name: "delete_file",
           metadata: %{original_tool: "write_file"}
         }}

      "create_directory" ->
        {:ok,
         %{
           type: :tool_rollback,
           tool_name: "delete_directory",
           metadata: %{original_tool: "create_directory"}
         }}

      "delete_file" ->
        {:error, :irreversible_operation}

      _ ->
        {:ok, %{type: :manual_rollback, tool_name: tool_name}}
    end
  end

  def analyze_step_for_rollback(%{type: :message}), do: {:ok, %{type: :no_rollback_needed}}
  def analyze_step_for_rollback(%{type: :checkpoint}), do: {:ok, %{type: :no_rollback_needed}}
  def analyze_step_for_rollback(%{type: :conditional}), do: {:ok, %{type: :no_rollback_needed}}

  # Private functions

  defp find_rollback_operations(rollback_stack, target_point) do
    case target_point do
      "step_" <> _ ->
        # Rollback to specific step
        operations =
          rollback_stack
          |> Enum.take_while(fn op -> op.step_id != target_point end)
          |> Enum.reverse()

        {:ok, operations}

      "checkpoint_" <> checkpoint_name ->
        # Rollback to checkpoint
        operations =
          rollback_stack
          |> Enum.take_while(fn op ->
            not match?(%{rollback_info: %{type: :checkpoint, name: ^checkpoint_name}}, op)
          end)
          |> Enum.reverse()

        {:ok, operations}

      "beginning" ->
        # Rollback everything
        {:ok, Enum.reverse(rollback_stack)}

      _ ->
        {:error, {:invalid_rollback_target, target_point}}
    end
  end

  defp execute_rollback_operations(operations, session_id, strategy) do
    Logger.info("Executing #{length(operations)} rollback operations", strategy: strategy)

    case strategy do
      :fail_fast ->
        execute_fail_fast(operations, session_id)

      :best_effort ->
        execute_best_effort(operations, session_id)

      :interactive ->
        execute_interactive(operations, session_id)
    end
  end

  defp execute_fail_fast(operations, session_id) do
    Enum.reduce_while(operations, {:ok, []}, fn operation, {:ok, completed} ->
      Logger.info("Executing rollback", step_id: operation.step_id, type: operation.rollback_info.type)

      case execute_single_rollback(operation, session_id) do
        :ok ->
          {:cont, {:ok, [operation | completed]}}

        {:error, reason} ->
          Logger.error("Rollback failed", step_id: operation.step_id, reason: inspect(reason))
          {:halt, {:error, {:rollback_failed, operation.step_id, reason, completed}}}
      end
    end)
  end

  defp execute_best_effort(operations, session_id) do
    {completed, failed} =
      Enum.reduce(operations, {[], []}, fn operation, {completed_acc, failed_acc} ->
        Logger.info("Executing rollback", step_id: operation.step_id, type: operation.rollback_info.type)

        case execute_single_rollback(operation, session_id) do
          :ok ->
            {[operation | completed_acc], failed_acc}

          {:error, reason} ->
            Logger.warning("Rollback failed but continuing", step_id: operation.step_id, reason: inspect(reason))
            {completed_acc, [{operation, reason} | failed_acc]}
        end
      end)

    if Enum.empty?(failed) do
      {:ok, completed}
    else
      {:partial, completed, failed}
    end
  end

  defp execute_interactive(operations, session_id) do
    Enum.reduce_while(operations, {:ok, []}, fn operation, {:ok, completed} ->
      IO.puts("\n🔄 Rollback Operation:")
      IO.puts("  Step: #{operation.step_id}")
      IO.puts("  Type: #{operation.rollback_info.type}")
      IO.puts("  Description: #{format_rollback_description(operation)}")

      case IO.gets("\nExecute this rollback? [y/n/s]: ") |> String.trim() |> String.downcase() do
        "y" ->
          case execute_single_rollback(operation, session_id) do
            :ok ->
              IO.puts("✅ Rollback successful")
              {:cont, {:ok, [operation | completed]}}

            {:error, reason} ->
              IO.puts("❌ Rollback failed: #{inspect(reason)}")

              case IO.gets("Continue with remaining rollbacks? [y/n]: ") |> String.trim() |> String.downcase() do
                "y" -> {:cont, {:ok, completed}}
                _ -> {:halt, {:error, {:rollback_failed, operation.step_id, reason, completed}}}
              end
          end

        "n" ->
          IO.puts("⏭️  Skipping rollback")
          {:cont, {:ok, completed}}

        "s" ->
          IO.puts("🛑 Stopping rollback process")
          {:halt, {:ok, completed}}

        _ ->
          IO.puts("Please enter 'y' (yes), 'n' (no), or 's' (stop)")
          {:cont, {:ok, completed}}
      end
    end)
  end

  defp execute_single_rollback(%{rollback_info: rollback_info} = operation, session_id) do
    case rollback_info.type do
      :restore_file ->
        execute_file_restore(rollback_info)

      :delete_file ->
        execute_file_deletion(rollback_info)

      :restore_from_checkpoint ->
        execute_checkpoint_restore(rollback_info, session_id)

      :undo_command ->
        execute_command_undo(rollback_info)

      :tool_rollback ->
        execute_tool_rollback(rollback_info, operation, session_id)

      :manual_rollback ->
        execute_manual_rollback(rollback_info, operation)

      :no_rollback_needed ->
        :ok

      _ ->
        {:error, {:unsupported_rollback_type, rollback_info.type}}
    end
  end

  # Validation functions

  defp validate_file_restore(%{backup_path: backup_path, original_path: original_path}) do
    cond do
      not File.exists?(backup_path) ->
        {:error, {:backup_file_missing, backup_path}}

      File.exists?(original_path) ->
        {:error, {:target_file_exists, original_path}}

      true ->
        :ok
    end
  end

  defp validate_file_deletion(%{path: path}) do
    if File.exists?(path) do
      :ok
    else
      {:error, {:file_not_found, path}}
    end
  end

  defp validate_checkpoint_restore(%{checkpoint: checkpoint_name}) do
    # In a real implementation, would check if checkpoint exists
    Logger.info("Validating checkpoint restore", checkpoint: checkpoint_name)
    :ok
  end

  defp validate_command_undo(%{undo_command: command}) do
    # Basic validation - check if command exists
    case System.find_executable(command) do
      nil -> {:error, {:command_not_found, command}}
      _ -> :ok
    end
  end

  defp validate_tool_rollback(%{tool_name: tool_name}, _operation) do
    # Would validate that the rollback tool exists and is available
    Logger.info("Validating tool rollback", tool: tool_name)
    :ok
  end

  # Execution functions

  defp execute_file_restore(%{backup_path: backup_path, original_path: original_path}) do
    try do
      File.rename(backup_path, original_path)
      Logger.info("File restored", from: backup_path, to: original_path)
      :ok
    rescue
      error ->
        {:error, {:file_restore_failed, Exception.message(error)}}
    end
  end

  defp execute_file_deletion(%{path: path}) do
    try do
      if File.dir?(path) do
        File.rmdir(path)
      else
        File.rm(path)
      end

      Logger.info("File deleted during rollback", path: path)
      :ok
    rescue
      error ->
        {:error, {:file_deletion_failed, Exception.message(error)}}
    end
  end

  defp execute_checkpoint_restore(%{checkpoint: checkpoint_name}, _session_id) do
    # In a real implementation, would restore from checkpoint
    Logger.info("Restoring from checkpoint", checkpoint: checkpoint_name)
    :ok
  end

  defp execute_command_undo(%{undo_command: command, undo_args: args}) do
    try do
      case System.cmd(command, args || [], stderr_to_stdout: true) do
        {_output, 0} ->
          Logger.info("Undo command executed", command: command, args: args)
          :ok

        {output, exit_code} ->
          {:error, {:undo_command_failed, exit_code, output}}
      end
    rescue
      error ->
        {:error, {:undo_command_error, Exception.message(error)}}
    end
  end

  defp execute_tool_rollback(%{tool_name: tool_name, arguments: args}, _operation, session_id) do
    case Gateway.execute_tool(session_id, tool_name, args || %{}) do
      {:ok, _result} ->
        Logger.info("Rollback tool executed", tool: tool_name)
        :ok

      {:error, reason} ->
        {:error, {:rollback_tool_failed, tool_name, reason}}
    end
  end

  defp execute_manual_rollback(rollback_info, operation) do
    Logger.warning("Manual rollback required",
      step_id: operation.step_id,
      rollback_info: rollback_info
    )

    IO.puts("\n⚠️  MANUAL ROLLBACK REQUIRED")
    IO.puts("Step: #{operation.step_id}")
    IO.puts("Original operation: #{inspect(rollback_info)}")
    IO.puts("Please manually undo this operation and press Enter to continue...")

    IO.gets("")
    :ok
  end

  # Helper functions

  defp format_rollback_description(%{
         rollback_info: %{type: :restore_file, backup_path: backup, original_path: original}
       }) do
    "Restore #{original} from backup #{backup}"
  end

  defp format_rollback_description(%{rollback_info: %{type: :delete_file, path: path}}) do
    "Delete #{path}"
  end

  defp format_rollback_description(%{rollback_info: %{type: :restore_from_checkpoint, checkpoint: checkpoint}}) do
    "Restore from checkpoint '#{checkpoint}'"
  end

  defp format_rollback_description(%{rollback_info: %{type: :undo_command, undo_command: cmd}}) do
    "Execute undo command '#{cmd}'"
  end

  defp format_rollback_description(%{rollback_info: %{type: :tool_rollback, tool_name: tool}}) do
    "Execute rollback tool '#{tool}'"
  end

  defp format_rollback_description(%{rollback_info: %{type: :manual_rollback}}) do
    "Manual rollback required"
  end

  defp format_rollback_description(_), do: "Unknown rollback operation"
end
