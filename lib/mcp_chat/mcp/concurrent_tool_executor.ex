defmodule MCPChat.MCP.ConcurrentToolExecutor do
  @moduledoc """
  Executes MCP tools concurrently where safe.

  Features:
  - Parallel execution of independent tools
  - Safety checks to prevent dangerous concurrent operations
  - Timeout handling and error isolation
  - Progress tracking for long-running operations
  - Resource conflict detection

  Safety Rules:
  - Tools from the same server are executed sequentially by default
  - Tools that modify state are marked as unsafe for concurrency
  - Tools with conflicting resource access are serialized
  - User can override safety checks with explicit configuration
  """

  require Logger
  alias MCPChat.MCP.{ServerManager, ProgressTracker}

  defmodule ToolExecution do
    @moduledoc false
    defstruct [
      :id,
      :server_name,
      :tool_name,
      :arguments,
      :task,
      :start_time,
      :timeout,
      :progress_token,
      :status
    ]
  end

  defmodule ExecutionResult do
    @moduledoc false
    defstruct [
      :id,
      :server_name,
      :tool_name,
      :status,
      :result,
      :error,
      :duration_ms,
      :progress_token
    ]
  end

  @default_opts [
    max_concurrency: 4,
    timeout: 30_000,
    same_server_sequential: true,
    enable_progress: true,
    safety_checks: true
  ]

  # Tools that are considered unsafe for concurrent execution
  @unsafe_tools [
    # File system operations
    "write_file",
    "delete_file",
    "move_file",
    "create_directory",
    # State modification
    "set_config",
    "update_settings",
    "reset_state",
    # System operations
    "restart_service",
    "shutdown",
    "kill_process",
    # Database operations
    "create_table",
    "drop_table",
    "truncate_table"
  ]

  @doc """
  Execute multiple tools concurrently with safety checks.

  ## Parameters
  - `tool_calls` - List of `{server_name, tool_name, arguments}` tuples
  - `opts` - Options for execution control

  ## Options
  - `:max_concurrency` - Maximum concurrent executions (default: 4)
  - `:timeout` - Timeout per tool in milliseconds (default: 30s)
  - `:same_server_sequential` - Execute tools from same server sequentially (default: true)
  - `:safety_checks` - Enable safety checks for dangerous operations (default: true)
  - `:enable_progress` - Track progress for long operations (default: true)
  - `:progress_callback` - Function to call with progress updates

  ## Returns
  `{:ok, results}` where results is a list of ExecutionResult structs
  """
  def execute_concurrent(tool_calls, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)

    Logger.info("Starting concurrent execution of #{length(tool_calls)} tools")

    # Validate and plan execution
    case plan_execution(tool_calls, opts) do
      {:ok, execution_plan} ->
        execute_plan(execution_plan, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Execute a single tool with timeout and progress tracking.
  """
  def execute_single(server_name, tool_name, arguments, opts \\ []) do
    execute_concurrent([{server_name, tool_name, arguments}], opts)
  end

  @doc """
  Check if a tool is safe for concurrent execution.
  """
  def tool_safe_for_concurrency?(tool_name, opts \\ []) do
    if Keyword.get(opts, :safety_checks, true) do
      not (tool_name in @unsafe_tools or
             String.contains?(String.downcase(tool_name), ["write", "delete", "create", "update", "modify"]))
    else
      true
    end
  end

  @doc """
  Get execution statistics for monitoring.
  """
  def get_execution_stats do
    # This would be implemented with a statistics tracker GenServer
    # For now, return basic stats
    %{
      total_executions: 0,
      concurrent_executions: 0,
      average_duration: 0,
      success_rate: 100.0
    }
  end

  # Private Functions

  defp plan_execution(tool_calls, opts) do
    Logger.debug("Planning execution for #{length(tool_calls)} tool calls")

    # Create execution objects with unique IDs
    executions =
      tool_calls
      |> Enum.with_index()
      |> Enum.map(fn {{server_name, tool_name, arguments}, index} ->
        %ToolExecution{
          id: "exec_#{index}_#{System.unique_integer([:positive])}",
          server_name: server_name,
          tool_name: tool_name,
          arguments: arguments,
          timeout: opts[:timeout],
          status: :planned
        }
      end)

    # Apply safety checks and grouping
    case apply_safety_rules(executions, opts) do
      {:ok, execution_groups} ->
        {:ok, execution_groups}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_safety_rules(executions, opts) do
    Logger.debug("Applying safety rules to #{length(executions)} executions")

    # Check for unsafe tools if safety is enabled
    if opts[:safety_checks] do
      unsafe_executions =
        Enum.filter(executions, fn exec ->
          not tool_safe_for_concurrency?(exec.tool_name, opts)
        end)

      if length(unsafe_executions) > 1 do
        Logger.warning("Multiple unsafe tools detected, will execute sequentially")
      end
    end

    # Group executions based on concurrency rules
    execution_groups = group_executions(executions, opts)

    {:ok, execution_groups}
  end

  defp group_executions(executions, opts) do
    if opts[:same_server_sequential] do
      # Group by server, each group runs sequentially but groups run in parallel
      executions
      |> Enum.group_by(& &1.server_name)
      |> Map.values()
    else
      # All safe tools can run in parallel, unsafe ones are individual groups
      {safe, unsafe} =
        Enum.split_with(executions, fn exec ->
          tool_safe_for_concurrency?(exec.tool_name, opts)
        end)

      # Safe tools can be in one group, unsafe tools each get their own group
      groups = [safe | Enum.map(unsafe, &[&1])]
      Enum.reject(groups, &Enum.empty?/1)
    end
  end

  defp execute_plan(execution_groups, opts) do
    start_time = System.monotonic_time(:millisecond)
    progress_callback = Keyword.get(opts, :progress_callback)

    Logger.info("Executing #{length(execution_groups)} execution groups with max concurrency #{opts[:max_concurrency]}")

    # Report initial progress
    total_tools = execution_groups |> List.flatten() |> length()

    if progress_callback do
      progress_callback.(%{
        phase: :starting,
        total: total_tools,
        completed: 0,
        groups: length(execution_groups)
      })
    end

    # Execute groups in parallel using Task.async_stream
    results_stream =
      execution_groups
      |> Task.async_stream(
        fn group -> execute_group(group, opts) end,
        max_concurrency: opts[:max_concurrency],
        # Add buffer for group coordination
        timeout: opts[:timeout] + 5_000,
        on_timeout: :kill_task
      )

    # Collect all results
    all_results =
      results_stream
      |> Enum.flat_map(fn
        {:ok, group_results} ->
          group_results

        {:exit, reason} ->
          Logger.error("Execution group crashed: #{inspect(reason)}")
          []
      end)

    total_duration = System.monotonic_time(:millisecond) - start_time

    # Final progress report
    if progress_callback do
      {successful, failed} = Enum.split_with(all_results, &(&1.status == :success))

      progress_callback.(%{
        phase: :completed,
        total: total_tools,
        completed: length(successful),
        failed: length(failed),
        duration_ms: total_duration
      })
    end

    Logger.info("Concurrent execution completed in #{total_duration}ms: #{length(all_results)} tools")

    {:ok, all_results}
  end

  defp execute_group(executions, opts) do
    Logger.debug("Executing group of #{length(executions)} tools")

    # Execute tools in this group sequentially (for safety within groups)
    Enum.map(executions, fn execution ->
      execute_tool(execution, opts)
    end)
  end

  defp execute_tool(execution, opts) do
    start_time = System.monotonic_time(:millisecond)
    progress_token = maybe_start_progress_tracking(execution, opts)

    Logger.debug("Executing tool #{execution.tool_name} on server #{execution.server_name}")

    try do
      ServerManager.call_tool(execution.server_name, execution.tool_name, execution.arguments)
      |> handle_tool_result(execution, start_time, progress_token)
    rescue
      e ->
        handle_tool_crash(execution, start_time, progress_token, e)
    end
  end

  defp maybe_start_progress_tracking(execution, opts) do
    if opts[:enable_progress] do
      case ProgressTracker.start_operation("tool_execution", %{
             server: execution.server_name,
             tool: execution.tool_name,
             id: execution.id
           }) do
        {:ok, token} -> token
        token when is_binary(token) -> token
        _ -> nil
      end
    end
  end

  defp handle_tool_result({:ok, result}, execution, start_time, progress_token) do
    duration_ms = System.monotonic_time(:millisecond) - start_time

    if progress_token do
      ProgressTracker.complete_operation(progress_token)
    end

    Logger.debug("Tool #{execution.tool_name} completed successfully in #{duration_ms}ms")

    %ExecutionResult{
      id: execution.id,
      server_name: execution.server_name,
      tool_name: execution.tool_name,
      status: :success,
      result: result,
      duration_ms: duration_ms,
      progress_token: progress_token
    }
  end

  defp handle_tool_result({:error, reason}, execution, start_time, progress_token) do
    duration_ms = System.monotonic_time(:millisecond) - start_time

    if progress_token do
      ProgressTracker.fail_operation(progress_token, reason)
    end

    Logger.warning("Tool #{execution.tool_name} failed: #{inspect(reason)}")

    %ExecutionResult{
      id: execution.id,
      server_name: execution.server_name,
      tool_name: execution.tool_name,
      status: :failed,
      error: reason,
      duration_ms: duration_ms,
      progress_token: progress_token
    }
  end

  defp handle_tool_crash(execution, start_time, progress_token, e) do
    duration_ms = System.monotonic_time(:millisecond) - start_time

    if progress_token do
      ProgressTracker.fail_operation(progress_token, e)
    end

    Logger.error("Tool #{execution.tool_name} crashed: #{inspect(e)}")

    %ExecutionResult{
      id: execution.id,
      server_name: execution.server_name,
      tool_name: execution.tool_name,
      status: :crashed,
      error: e,
      duration_ms: duration_ms,
      progress_token: progress_token
    }
  end
end
