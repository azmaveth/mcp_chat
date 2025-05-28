defmodule MCPChat.CLI.Commands.ConcurrentTools do
  @moduledoc """
  Commands for concurrent tool execution.

  Provides /concurrent command for testing and managing concurrent tool operations.
  """

  use MCPChat.CLI.Commands.Base

  alias MCPChat.MCP.{ConcurrentToolExecutor, ServerManager}

  @doc """
  Handle concurrent tool commands.
  """
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

  defp show_help() do
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

  defp test_concurrent_execution() do
    show_info("Running concurrent tool execution test...")

    # Get available servers
    servers = ServerManager.list_servers()
    connected_servers = Enum.filter(servers, &(&1.status == :connected))

    if Enum.empty?(connected_servers) do
      show_error("No connected MCP servers available for testing")
    else
      # Create test tool calls using available servers
      test_calls = create_test_tool_calls(connected_servers)

      if Enum.empty?(test_calls) do
        show_error("No suitable tools found for concurrent execution test")
      else
        show_info("Testing with #{length(test_calls)} concurrent tool calls...")

        # Execute with progress callback
        progress_callback = fn update ->
          case update.phase do
            :starting ->
              show_info("Starting execution of #{update.total} tools in #{update.groups} groups...")

            :completed ->
              duration_sec = update.duration_ms / 1_000
              show_info("Completed: #{update.completed} successful, #{update.failed} failed (#{duration_sec}s)")
          end
        end

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
    end

    :ok
  end

  defp create_test_tool_calls(servers) do
    # Try to find safe tools for testing
    Enum.flat_map(servers, fn server ->
      case ServerManager.get_tools(server.name) do
        {:ok, tools} ->
          safe_tools =
            tools
            |> Enum.filter(fn tool ->
              tool_name = tool["name"] || ""
              ConcurrentToolExecutor.tool_safe_for_concurrency?(tool_name)
            end)
            # Limit to 2 tools per server
            |> Enum.take(2)

          Enum.map(safe_tools, fn tool ->
            # Create minimal arguments for testing
            args = create_test_arguments(tool)
            {server.name, tool["name"], args}
          end)

        _ ->
          []
      end
    end)
    # Limit total test calls
    |> Enum.take(6)
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

    if length(successful) > 0 do
      avg_duration =
        successful
        |> Enum.map(& &1.duration_ms)
        |> Enum.sum()
        |> div(length(successful))

      show_info("Average duration: #{avg_duration}ms")
    end

    # Show detailed results
    if length(results) <= 10 do
      show_info("\nDetailed Results:")

      Enum.each(results, fn result ->
        status_icon = if result.status == :success, do: "✅", else: "❌"
        IO.puts("  #{status_icon} #{result.server_name}:#{result.tool_name} (#{result.duration_ms}ms)")

        if result.status != :success and result.error do
          IO.puts("    Error: #{inspect(result.error)}")
        end
      end)
    end
  end

  defp execute_concurrent_tools(tool_specs) do
    if Enum.empty?(tool_specs) do
      show_error("No tool specifications provided")
    else
      # Parse tool specifications
      case parse_tool_specifications(tool_specs) do
        {:ok, tool_calls} ->
          show_info("Executing #{length(tool_calls)} tools concurrently...")

          # Execute with progress tracking
          progress_callback = fn update ->
            case update.phase do
              :starting ->
                show_info("Starting concurrent execution...")

              :completed ->
                show_info("Execution completed: #{update.completed} successful, #{update.failed} failed")
            end
          end

          case ConcurrentToolExecutor.execute_concurrent(tool_calls,
                 progress_callback: progress_callback
               ) do
            {:ok, results} ->
              show_execution_results(results)

            {:error, reason} ->
              show_error("Execution failed: #{inspect(reason)}")
          end

        {:error, reason} ->
          show_error("Invalid tool specification: #{reason}")
      end
    end

    :ok
  end

  defp parse_tool_specifications(specs) do
    try do
      tool_calls =
        Enum.map(specs, fn spec ->
          case String.split(spec, ":", parts: 3) do
            [server, tool] ->
              {server, tool, %{}}

            [server, tool, args_str] ->
              args = parse_arguments(args_str)
              {server, tool, args}

            _ ->
              throw({:invalid_format, spec})
          end
        end)

      {:ok, tool_calls}
    catch
      {:invalid_format, spec} ->
        {:error, "Invalid format for '#{spec}'. Use server:tool:arg1=value1,arg2=value2"}

      error ->
        {:error, "Parse error: #{inspect(error)}"}
    end
  end

  defp parse_arguments(args_str) do
    if String.trim(args_str) == "" do
      %{}
    else
      args_str
      |> String.split(",")
      |> Enum.map(fn pair ->
        case String.split(pair, "=", parts: 2) do
          [key, value] -> {String.trim(key), String.trim(value)}
          [key] -> {String.trim(key), ""}
        end
      end)
      |> Map.new()
    end
  end

  defp show_execution_results(results) do
    show_info("\nExecution Results:")
    show_info("=================")

    Enum.each(results, fn result ->
      status_color =
        case result.status do
          :success -> :green
          :failed -> :red
          :crashed -> :red
        end

      status_text =
        case result.status do
          :success -> "SUCCESS"
          :failed -> "FAILED"
          :crashed -> "CRASHED"
        end

      IO.puts("#{result.server_name}:#{result.tool_name} - #{status_text} (#{result.duration_ms}ms)")

      case result.status do
        :success ->
          if result.result do
            formatted_result = format_tool_result(result.result)
            IO.puts("  Result: #{formatted_result}")
          end

        _ ->
          if result.error do
            IO.puts("  Error: #{inspect(result.error)}")
          end
      end
    end)
  end

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

  defp show_execution_stats() do
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
