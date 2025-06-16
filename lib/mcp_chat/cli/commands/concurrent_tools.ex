defmodule MCPChat.CLI.Commands.ConcurrentTools do
  @moduledoc """
  Commands for concurrent tool execution.

  Provides /concurrent command for testing and managing concurrent tool operations.
  """

  use MCPChat.CLI.Commands.Base

  alias MCPChat.MCP.{ConcurrentToolExecutor, ServerManager}

  @doc """
  Get the list of commands provided by this module.
  """
  def commands do
    [
      %{
        name: "concurrent",
        description: "Execute tools concurrently with safety checks",
        usage: "/concurrent <subcommand> [args...]",
        subcommands: [
          %{name: "test", description: "Run concurrent execution test"},
          %{name: "execute", description: "Execute multiple tools concurrently"},
          %{name: "stats", description: "Show execution statistics"},
          %{name: "safety", description: "Check if tool is safe for concurrency"},
          %{name: "help", description: "Show this help"}
        ]
      }
    ]
  end

  def handle_command(["concurrent" | args]) do
    case args do
      [] ->
        show_help()

      ["help"] ->
        show_help()

      ["test"] ->
        test_concurrent_execution()

      ["execute" | tool_specs] ->
        execute_concurrent_tools(tool_specs)

      ["stats"] ->
        show_execution_stats()

      ["safety", tool_name] ->
        check_tool_safety(tool_name)

      _ ->
        show_error("Unknown concurrent command. Use '/concurrent help' for usage.")
    end
  end

  @doc """
  Handle commands that are not concurrent commands (required by Base behavior).
  """
  def handle_command(_command_args) do
    # This module only handles concurrent commands, return not handled for all others
    :not_handled
  end

  defp show_help do
    show_info("""
    Concurrent Tool Execution Commands:

    /concurrent test                     - Run concurrent execution test
    /concurrent execute <tool_specs>     - Execute multiple tools concurrently
    /concurrent stats                    - Show execution statistics
    /concurrent safety <tool_name>       - Check if tool is safe for concurrency

    Tool Specification Format:
      server:tool:arg1=value1,arg2=value2

    Examples:
      /concurrent test
      /concurrent execute server1:read_file:path=/tmp/test.txt server2:get_weather:city=NYC
      /concurrent safety write_file
    """)
  end

  defp test_concurrent_execution do
    show_info("Running concurrent tool execution test...")

    # Get available servers
    servers = ServerManager.list_servers()
    connected_servers = Enum.filter(servers, &(&1.status == :connected))

    if Enum.empty?(connected_servers) do
      show_error("No connected MCP servers available for testing")
    else
      # Create test tool calls using available servers
      test_calls = create_test_tool_calls(connected_servers)

      execute_test_calls_if_available(test_calls)
    end

    :ok
  end

  defp execute_test_calls_if_available(test_calls) do
    if Enum.empty?(test_calls) do
      show_error("No suitable tools found for concurrent execution test")
    else
      run_concurrent_test(test_calls)
    end
  end

  defp run_concurrent_test(test_calls) do
    show_info("Testing with #{length(test_calls)} concurrent tool calls...")

    progress_callback = create_progress_callback()

    case ConcurrentToolExecutor.execute_concurrent(test_calls,
           max_concurrency: 3,
           timeout: 10_000,
           progress_callback: progress_callback
         ) do
      {:ok, results} ->
        show_test_results(results)

      {:error, reason} ->
        show_error("Concurrent execution test failed: #{inspect(reason)}")
    end
  end

  defp create_progress_callback do
    fn update ->
      case update.phase do
        :starting ->
          show_info("Starting execution of #{update.total} tools in #{update.groups} groups...")

        :completed ->
          duration_sec = update.duration_ms / 1_000
          show_info("Completed: #{update.completed} successful, #{update.failed} failed (#{duration_sec}s)")
      end
    end
  end

  defp create_test_tool_calls(servers) do
    servers
    |> Enum.flat_map(&get_server_test_tools/1)
    |> Enum.take(6)
  end

  defp get_server_test_tools(server) do
    case ServerManager.get_tools(server.name) do
      {:ok, tools} ->
        tools
        |> filter_safe_tools()
        |> Enum.take(2)
        |> create_tool_calls(server.name)

      _ ->
        []
    end
  end

  defp filter_safe_tools(tools) do
    Enum.filter(tools, fn tool ->
      tool_name = tool["name"] || ""
      ConcurrentToolExecutor.tool_safe_for_concurrency?(tool_name)
    end)
  end

  defp create_tool_calls(safe_tools, server_name) do
    Enum.map(safe_tools, fn tool ->
      args = create_test_arguments(tool)
      {server_name, tool["name"], args}
    end)
  end

  defp create_test_arguments(tool) do
    # Create safe test arguments based on tool schema
    schema = tool["inputSchema"] || %{}
    properties = schema["properties"] || %{}

    # Create minimal valid arguments
    properties
    # Limit to first 3 parameters
    |> Enum.take(3)
    |> Enum.map(fn {param_name, param_schema} ->
      {param_name, create_test_value(param_schema)}
    end)
    |> Map.new()
  end

  defp create_test_value(schema) do
    case schema["type"] do
      "string" -> "test_value"
      "number" -> 42
      "integer" -> 42
      "boolean" -> true
      "array" -> []
      "object" -> %{}
      _ -> "test"
    end
  end

  defp show_test_results(results) do
    {successful, failed} = Enum.split_with(results, &(&1.status == :success))

    show_info("\nConcurrent Execution Test Results:")
    show_info("================================")
    show_info("Total executions: #{length(results)}")
    show_info("Successful: #{length(successful)}")
    show_info("Failed: #{length(failed)}")

    show_average_duration_if_applicable(successful)
    show_detailed_results_if_applicable(results)
  end

  defp show_average_duration_if_applicable(successful) do
    if length(successful) > 0 do
      avg_duration = calculate_average_duration(successful)
      show_info("Average duration: #{avg_duration}ms")
    end
  end

  defp calculate_average_duration(successful) do
    successful
    |> Enum.map(& &1.duration_ms)
    |> Enum.sum()
    |> div(length(successful))
  end

  defp show_detailed_results_if_applicable(results) do
    if length(results) <= 10 do
      show_info("\nDetailed Results:")
      Enum.each(results, &display_result_summary/1)
    end
  end

  defp display_result_summary(result) do
    status_icon = if result.status == :success, do: "✅", else: "❌"
    IO.puts("  #{status_icon} #{result.server_name}:#{result.tool_name} (#{result.duration_ms}ms)")

    if result.status != :success and result.error do
      IO.puts("    Error: #{inspect(result.error)}")
    end
  end

  defp execute_concurrent_tools(tool_specs) do
    if Enum.empty?(tool_specs) do
      show_error("No tool specifications provided")
    else
      perform_concurrent_execution(tool_specs)
    end

    :ok
  end

  defp perform_concurrent_execution(tool_specs) do
    case parse_tool_specifications(tool_specs) do
      {:ok, tool_calls} ->
        execute_parsed_tools(tool_calls)

      {:error, reason} ->
        show_error("Invalid tool specification: #{reason}")
    end
  end

  defp execute_parsed_tools(tool_calls) do
    show_info("Executing #{length(tool_calls)} tools concurrently...")

    progress_callback = &handle_execution_progress/1

    case ConcurrentToolExecutor.execute_concurrent(tool_calls,
           progress_callback: progress_callback
         ) do
      {:ok, results} ->
        show_execution_results(results)

      {:error, reason} ->
        show_error("Execution failed: #{inspect(reason)}")
    end
  end

  defp parse_tool_specifications(specs) do
    # Use Enum.reduce_while to handle errors properly without throw/catch
    result =
      Enum.reduce_while(specs, {:ok, []}, fn spec, {:ok, acc} ->
        case parse_single_tool_specification(spec) do
          {:ok, tool_call} ->
            {:cont, {:ok, [tool_call | acc]}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, tool_calls} ->
        {:ok, Enum.reverse(tool_calls)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_single_tool_specification(spec) do
    case String.split(spec, ":", parts: 3) do
      [server, tool] ->
        {:ok, {server, tool, %{}}}

      [server, tool, args_str] ->
        case parse_arguments(args_str) do
          {:ok, args} ->
            {:ok, {server, tool, args}}

          {:error, reason} ->
            {:error, "Failed to parse arguments for '#{spec}': #{reason}"}
        end

      _ ->
        {:error, "Invalid format for '#{spec}'. Use server:tool:arg1=value1,arg2=value2"}
    end
  end

  defp parse_arguments(args_str) do
    if String.trim(args_str) == "" do
      {:ok, %{}}
    else
      parse_non_empty_arguments(args_str)
    end
  end

  defp parse_non_empty_arguments(args_str) do
    try do
      args =
        args_str
        |> String.split(",")
        |> Enum.map(&parse_key_value_pair/1)
        |> Map.new()

      {:ok, args}
    rescue
      e ->
        {:error, "Invalid argument format: #{inspect(e)}"}
    end
  end

  defp parse_key_value_pair(pair) do
    case String.split(pair, "=", parts: 2) do
      [key, value] -> {String.trim(key), String.trim(value)}
      [key] -> {String.trim(key), ""}
    end
  end

  defp show_execution_results(results) do
    show_info("\nExecution Results:")
    show_info("=================")

    Enum.each(results, &display_single_result/1)
  end

  defp display_single_result(result) do
    status_text = get_status_text(result.status)
    IO.puts("#{result.server_name}:#{result.tool_name} - #{status_text} (#{result.duration_ms}ms)")
    display_result_details(result)
  end

  defp get_status_text(:success), do: "SUCCESS"
  defp get_status_text(:failed), do: "FAILED"
  defp get_status_text(:crashed), do: "CRASHED"

  defp display_result_details(%{status: :success, result: result}) when result != nil do
    formatted_result = format_tool_result(result)
    IO.puts("  Result: #{formatted_result}")
  end

  defp display_result_details(%{error: error}) when error != nil do
    IO.puts("  Error: #{inspect(error)}")
  end

  defp display_result_details(_result), do: :ok

  defp handle_execution_progress(%{phase: :starting}) do
    show_info("Starting concurrent execution...")
  end

  defp handle_execution_progress(%{phase: :completed} = update) do
    show_info("Execution completed: #{update.completed} successful, #{update.failed} failed")
  end

  defp handle_execution_progress(_update), do: :ok

  defp format_tool_result(result) when is_map(result) do
    case Jason.encode(result) do
      {:ok, json} ->
        if String.length(json) > 200 do
          String.slice(json, 0, 200) <> "..."
        else
          json
        end

      _ ->
        inspect(result)
    end
  end

  defp format_tool_result(result), do: inspect(result)

  defp show_execution_stats do
    stats = ConcurrentToolExecutor.get_execution_stats()

    show_info("Concurrent Tool Execution Statistics:")
    show_info("===================================")
    show_info("Total executions: #{stats.total_executions}")
    show_info("Concurrent executions: #{stats.concurrent_executions}")
    show_info("Average duration: #{stats.average_duration}ms")
    show_info("Success rate: #{stats.success_rate}%")

    :ok
  end

  defp check_tool_safety(tool_name) do
    is_safe = ConcurrentToolExecutor.tool_safe_for_concurrency?(tool_name)

    if is_safe do
      show_info("✅ Tool '#{tool_name}' is SAFE for concurrent execution")
    else
      show_info("⚠️  Tool '#{tool_name}' is UNSAFE for concurrent execution")
      show_info("   This tool may modify state or have side effects that could")
      show_info("   cause issues when run concurrently with other tools.")
    end

    :ok
  end
end
