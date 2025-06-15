#!/usr/bin/env elixir

# Demo Calculator MCP Server for E2E Testing
# A simple MCP server that provides calculation tools

defmodule DemoCalculatorServer do
  @moduledoc """
  A demo MCP server that provides calculation functionality for testing.
  Includes progress support for long-running calculations.
  """

  def main(_args) do
    # Start the MCP server
    {:ok, server} =
      ExMCP.Server.start_link(
        name: "demo-calculator-server",
        version: "1.0.0",
        transport: :stdio,
        capabilities: %{
          tools: true,
          resources: true,
          # Enable progress notifications
          progress: true
        }
      )

    # Register tools
    ExMCP.Server.add_tool(server, %{
      name: "calculate",
      description: "Perform basic arithmetic calculations",
      input_schema: %{
        type: "object",
        properties: %{
          expression: %{
            type: "string",
            description: "Math expression (e.g., '2 + 2', '10 * 5')"
          }
        },
        required: ["expression"]
      },
      handler: &handle_calculate/1
    })

    ExMCP.Server.add_tool(server, %{
      name: "factorial",
      description: "Calculate factorial of a number",
      input_schema: %{
        type: "object",
        properties: %{
          n: %{
            type: "integer",
            description: "Number to calculate factorial of"
          },
          with_progress: %{
            type: "boolean",
            description: "Show progress updates",
            default: false
          }
        },
        required: ["n"]
      },
      handler: fn params -> handle_factorial(server, params) end
    })

    ExMCP.Server.add_tool(server, %{
      name: "fibonacci",
      description: "Calculate Fibonacci sequence",
      input_schema: %{
        type: "object",
        properties: %{
          n: %{
            type: "integer",
            description: "Number of Fibonacci numbers to generate"
          }
        },
        required: ["n"]
      },
      handler: &handle_fibonacci/1
    })

    ExMCP.Server.add_tool(server, %{
      name: "statistics",
      description: "Calculate statistics for a list of numbers",
      input_schema: %{
        type: "object",
        properties: %{
          numbers: %{
            type: "array",
            items: %{type: "number"},
            description: "List of numbers"
          }
        },
        required: ["numbers"]
      },
      handler: &handle_statistics/1
    })

    # Add resources
    ExMCP.Server.add_resource(server, %{
      uri: "calc://constants",
      name: "Mathematical Constants",
      description: "Common mathematical constants",
      mime_type: "application/json",
      reader: &read_constants_resource/0
    })

    ExMCP.Server.add_resource(server, %{
      uri: "calc://history",
      name: "Calculation History",
      description: "Recent calculations performed",
      mime_type: "application/json",
      reader: &read_history_resource/0
    })

    # Keep the server running
    Process.sleep(:infinity)
  end

  defp handle_calculate(%{"expression" => expr}) do
    # Simple expression evaluator for basic operations
    result = evaluate_expression(expr)
    add_to_history(expr, result)
    {:ok, %{"expression" => expr, "result" => result}}
  rescue
    _ -> {:error, "Invalid expression: #{expr}"}
  end

  defp handle_factorial(server, %{"n" => n} = params) when is_integer(n) and n >= 0 do
    with_progress = Map.get(params, "with_progress", false)

    if with_progress and n > 10 do
      # Send progress notifications for large factorials
      result = factorial_with_progress(server, n)
      {:ok, %{"n" => n, "result" => result}}
    else
      result = factorial(n)
      {:ok, %{"n" => n, "result" => result}}
    end
  end

  defp handle_factorial(_server, _params) do
    {:error, "Invalid parameters: 'n' must be a non-negative integer"}
  end

  defp handle_fibonacci(%{"n" => n}) when is_integer(n) and n > 0 do
    sequence = fibonacci_sequence(n)
    {:ok, %{"n" => n, "sequence" => sequence}}
  end

  defp handle_fibonacci(_params) do
    {:error, "Invalid parameters: 'n' must be a positive integer"}
  end

  defp handle_statistics(%{"numbers" => numbers}) when is_list(numbers) do
    if Enum.all?(numbers, &is_number/1) do
      stats = calculate_stats(numbers)
      {:ok, stats}
    else
      {:error, "All elements must be numbers"}
    end
  end

  defp handle_statistics(_params) do
    {:error, "Invalid parameters: 'numbers' must be an array"}
  end

  defp evaluate_expression(expr) do
    # Very simple expression parser for testing
    # Only supports +, -, *, / with two operands
    result = Regex.run(~r/^\s*(-?\d+(?:\.\d+)?)\s*([\+\-\*\/])\s*(-?\d+(?:\.\d+)?)\s*$/, expr)

    case result do
      [_, a, op, b] ->
        num_a = parse_number(a)
        num_b = parse_number(b)
        apply_operation(op, num_a, num_b)

      _ ->
        raise "Invalid expression format"
    end
  end

  defp parse_number(str) do
    String.to_float(str)
  rescue
    _ -> String.to_integer(str)
  end

  defp apply_operation("+", a, b), do: a + b
  defp apply_operation("-", a, b), do: a - b
  defp apply_operation("*", a, b), do: a * b

  defp apply_operation("/", a, b) do
    if b == 0 do
      raise("Division by zero")
    else
      a / b
    end
  end

  defp apply_operation(op, _, _), do: raise("Unsupported operator: #{op}")

  defp factorial(0), do: 1
  defp factorial(n) when n > 0, do: n * factorial(n - 1)

  defp factorial_with_progress(server, n) do
    # Simulate progress for demonstration
    Enum.reduce(1..n, 1, fn i, acc ->
      if rem(i, 5) == 0 do
        progress = i / n

        ExMCP.Server.send_progress(server, %{
          progress: progress,
          message: "Calculating factorial: #{i}/#{n}"
        })
      end

      # Small delay to simulate computation
      if i > 15, do: Process.sleep(10)

      acc * i
    end)
  end

  defp fibonacci_sequence(n) do
    Stream.unfold({0, 1}, fn {a, b} -> {a, {b, a + b}} end)
    |> Enum.take(n)
  end

  defp calculate_stats(numbers) do
    count = length(numbers)
    sum = Enum.sum(numbers)
    mean = sum / count

    sorted = Enum.sort(numbers)

    median =
      if rem(count, 2) == 0 do
        mid = div(count, 2)
        (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
      else
        Enum.at(sorted, div(count, 2))
      end

    variance =
      Enum.reduce(numbers, 0, fn x, acc ->
        acc + :math.pow(x - mean, 2)
      end) / count

    std_dev = :math.sqrt(variance)

    %{
      "count" => count,
      "sum" => sum,
      "mean" => mean,
      "median" => median,
      "min" => Enum.min(numbers),
      "max" => Enum.max(numbers),
      "variance" => variance,
      "std_dev" => std_dev
    }
  end

  defp read_constants_resource do
    Jason.encode!(%{
      "pi" => :math.pi(),
      "e" => :math.exp(1),
      "sqrt2" => :math.sqrt(2),
      "golden_ratio" => (1 + :math.sqrt(5)) / 2
    })
  end

  defp read_history_resource do
    # For testing, return a static history
    Jason.encode!(%{
      "history" => [
        %{"expression" => "2 + 2", "result" => 4, "timestamp" => "2024-01-01T12:00:00Z"},
        %{"expression" => "10 * 5", "result" => 50, "timestamp" => "2024-01-01T12:01:00Z"}
      ]
    })
  end

  defp add_to_history(_expr, _result) do
    # In a real implementation, this would store history
    :ok
  end
end

# Start the server
DemoCalculatorServer.main(System.argv())
