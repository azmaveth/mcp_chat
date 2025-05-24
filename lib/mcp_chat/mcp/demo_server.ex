defmodule MCPChat.MCP.DemoServer do
  @moduledoc """
  Built-in demo MCP server with useful tools for showcasing capabilities.
  """

  use GenServer
  alias MCPChat.MCP.Protocol

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    {:ok, %{}}
  end

  # MCP Protocol Implementation

  def handle_call({:mcp_request, "initialize", _params}, _from, state) do
    response = %{
      protocolVersion: "2024-11-05",
      capabilities: %{
        tools: %{},
        resources: %{
          subscribe: false,
          listChanged: false
        },
        prompts: %{
          listChanged: false
        }
      },
      serverInfo: %{
        name: "mcp-chat-demo",
        version: "1.0.0"
      }
    }

    {:reply, {:ok, response}, state}
  end

  def handle_call({:mcp_request, "tools/list", _params}, _from, state) do
    tools = [
      %{
        name: "calculate",
        description: "Perform mathematical calculations",
        inputSchema: %{
          type: "object",
          properties: %{
            expression: %{
              type: "string",
              description: "Mathematical expression to evaluate"
            }
          },
          required: ["expression"]
        }
      },
      %{
        name: "get_time",
        description: "Get current date and time in various formats",
        inputSchema: %{
          type: "object",
          properties: %{
            format: %{
              type: "string",
              description: "Time format (iso8601, unix, human)",
              enum: ["iso8601", "unix", "human"],
              default: "iso8601"
            },
            timezone: %{
              type: "string",
              description: "Timezone (e.g., UTC, America/New_York)",
              default: "UTC"
            }
          }
        }
      },
      %{
        name: "generate_data",
        description: "Generate sample data for testing",
        inputSchema: %{
          type: "object",
          properties: %{
            type: %{
              type: "string",
              description: "Type of data to generate",
              enum: ["users", "products", "transactions", "logs"]
            },
            count: %{
              type: "integer",
              description: "Number of items to generate",
              minimum: 1,
              maximum: 100,
              default: 10
            }
          },
          required: ["type"]
        }
      },
      %{
        name: "analyze_text",
        description: "Analyze text for various metrics",
        inputSchema: %{
          type: "object",
          properties: %{
            text: %{
              type: "string",
              description: "Text to analyze"
            },
            metrics: %{
              type: "array",
              description: "Metrics to calculate",
              items: %{
                type: "string",
                enum: ["word_count", "char_count", "readability", "sentiment"]
              },
              default: ["word_count", "char_count"]
            }
          },
          required: ["text"]
        }
      }
    ]

    {:reply, {:ok, %{tools: tools}}, state}
  end

  def handle_call({:mcp_request, "tools/call", params}, _from, state) do
    result =
      case params["name"] do
        "calculate" ->
          calculate(params["arguments"]["expression"])

        "get_time" ->
          get_time(params["arguments"])

        "generate_data" ->
          generate_data(params["arguments"])

        "analyze_text" ->
          analyze_text(params["arguments"])

        _ ->
          {:error, "Unknown tool"}
      end

    case result do
      {:ok, content} ->
        {:reply, {:ok, %{content: [%{type: "text", text: content}]}}, state}

      {:error, error} ->
        {:reply, {:error, %{code: -32_602, message: error}}, state}
    end
  end

  # Tool Implementations

  defp calculate(expression) do
    # Simple calculator using Code.eval_string with safety restrictions
    try do
      # Only allow basic math operations
      safe_expr =
        expression
        |> String.replace(~r/[^0-9+\-*\/\(\)\.\s]/, "")

      if safe_expr != expression do
        {:error, "Invalid characters in expression"}
      else
        {result, _} = Code.eval_string(safe_expr)
        {:ok, "#{expression} = #{result}"}
      end
    rescue
      _ -> {:error, "Failed to evaluate expression"}
    end
  end

  defp get_time(%{"format" => format, "timezone" => _timezone} = _args) do
    now = DateTime.utc_now()

    result =
      case format do
        "unix" ->
          "#{DateTime.to_unix(now)}"

        "human" ->
          Calendar.strftime(now, "%B %d, %Y at %I:%M %p UTC")

        _ ->
          DateTime.to_iso8601(now)
      end

    {:ok, result}
  end

  defp get_time(_args) do
    {:ok, DateTime.utc_now() |> DateTime.to_iso8601()}
  end

  defp generate_data(%{"type" => type, "count" => count}) do
    data =
      case type do
        "users" ->
          Enum.map(1..count, fn i ->
            %{
              id: i,
              name: "User #{i}",
              email: "user#{i}@example.com",
              created_at: DateTime.utc_now() |> DateTime.to_iso8601()
            }
          end)

        "products" ->
          Enum.map(1..count, fn i ->
            %{
              id: i,
              name: "Product #{i}",
              price: :rand.uniform(1_000) / 10,
              stock: :rand.uniform(100)
            }
          end)

        "transactions" ->
          Enum.map(1..count, fn i ->
            %{
              id: i,
              amount: :rand.uniform(10_000) / 100,
              timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
              status: Enum.random(["completed", "pending", "failed"])
            }
          end)

        "logs" ->
          Enum.map(1..count, fn i ->
            %{
              id: i,
              level: Enum.random(["info", "warning", "error"]),
              message: "Log entry #{i}",
              timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
            }
          end)
      end

    {:ok, Jason.encode!(data, pretty: true)}
  end

  defp generate_data(%{"type" => type}) do
    generate_data(%{"type" => type, "count" => 10})
  end

  defp analyze_text(%{"text" => text, "metrics" => metrics}) do
    results =
      Enum.map(metrics, fn metric ->
        case metric do
          "word_count" ->
            words = text |> String.split(~r/\s+/) |> length()
            "Word count: #{words}"

          "char_count" ->
            chars = String.length(text)
            "Character count: #{chars}"

          "readability" ->
            # Simple readability score based on average word length
            words = String.split(text, ~r/\s+/)

            avg_word_length =
              words
              |> Enum.map(&String.length/1)
              |> Enum.sum()
              |> Kernel./(length(words))
              |> Float.round(2)

            "Average word length: #{avg_word_length} (#{readability_level(avg_word_length)})"

          "sentiment" ->
            # Very basic sentiment analysis
            positive_words = ~w[good great excellent amazing wonderful fantastic love like]
            negative_words = ~w[bad terrible awful horrible hate dislike poor wrong]

            words = text |> String.downcase() |> String.split(~r/\s+/)
            positive_count = Enum.count(words, &(&1 in positive_words))
            negative_count = Enum.count(words, &(&1 in negative_words))

            sentiment =
              cond do
                positive_count > negative_count -> "Positive"
                negative_count > positive_count -> "Negative"
                true -> "Neutral"
              end

            "Sentiment: #{sentiment} (#{positive_count} positive, #{negative_count} negative words)"

          _ ->
            "Unknown metric: #{metric}"
        end
      end)

    {:ok, Enum.join(results, "\n")}
  end

  defp analyze_text(%{"text" => text}) do
    analyze_text(%{"text" => text, "metrics" => ["word_count", "char_count"]})
  end

  defp readability_level(avg_length) do
    cond do
      avg_length < 4 -> "Very Easy"
      avg_length < 5 -> "Easy"
      avg_length < 6 -> "Medium"
      avg_length < 7 -> "Difficult"
      true -> "Very Difficult"
    end
  end
end
