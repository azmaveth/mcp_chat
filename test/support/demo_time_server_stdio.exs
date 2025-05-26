#!/usr/bin/env elixir

# Demo Time MCP Server for E2E Testing
# This server runs as a separate OS process and communicates via stdio

Mix.install([
  {:ex_mcp, path: "../../../ex_mcp"},
  {:jason, "~> 1.4"}
])

defmodule DemoTimeServer.Handler do
  @moduledoc """
  MCP server handler that provides time-related functionality.
  """

  use ExMCP.Server.Handler
  require Logger

  @impl true
  def handle_initialize(_params, state) do
    {:ok,
     %{
       "serverInfo" => %{
         "name" => "demo-time-server",
         "version" => "1.0.0"
       },
       "capabilities" => %{
         "tools" => %{},
         "resources" => %{}
       }
     }, state}
  end

  @impl true
  def handle_list_tools(_params, state) do
    tools = [
      %{
        "name" => "get_current_time",
        "description" => "Get the current time in a specified timezone",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "timezone" => %{
              "type" => "string",
              "description" => "Timezone (e.g., 'UTC', 'America/New_York')",
              "default" => "UTC"
            }
          }
        }
      },
      %{
        "name" => "add_time",
        "description" => "Add hours and minutes to the current time",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "hours" => %{
              "type" => "integer",
              "description" => "Hours to add"
            },
            "minutes" => %{
              "type" => "integer",
              "description" => "Minutes to add"
            }
          },
          "required" => ["hours", "minutes"]
        }
      },
      %{
        "name" => "time_until",
        "description" => "Calculate time until a target time",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "target_time" => %{
              "type" => "string",
              "description" => "Target time in ISO 8_601 format"
            }
          },
          "required" => ["target_time"]
        }
      }
    ]

    {:ok, %{"tools" => tools}, state}
  end

  @impl true
  def handle_call_tool("get_current_time", arguments, state) do
    timezone = Map.get(arguments, "timezone", "UTC")

    # For demo purposes, always use UTC
    time = DateTime.utc_now() |> DateTime.to_iso8601()

    result = %{
      "type" => "text",
      "text" => "Current time in #{timezone}: #{time}"
    }

    {:ok, %{"content" => [result], "time" => time}, state}
  end

  def handle_call_tool("add_time", arguments, state) do
    hours = Map.get(arguments, "hours", 0)
    minutes = Map.get(arguments, "minutes", 0)

    future_time =
      DateTime.utc_now()
      |> DateTime.add(hours * 3_600 + minutes * 60, :second)
      |> DateTime.to_iso8601()

    result = %{
      "type" => "text",
      "text" => "Time after adding #{hours} hours and #{minutes} minutes: #{future_time}"
    }

    {:ok, %{"content" => [result]}, state}
  end

  def handle_call_tool("time_until", arguments, state) do
    target_str = Map.get(arguments, "target_time", "")

    case DateTime.from_iso8601(target_str) do
      {:ok, target, _offset} ->
        now = DateTime.utc_now()
        diff_seconds = DateTime.diff(target, now)

        hours = div(diff_seconds, 3_600)
        minutes = div(rem(diff_seconds, 3_600), 60)

        result = %{
          "type" => "text",
          "text" => "Time until #{target_str}: #{hours} hours and #{minutes} minutes"
        }

        {:ok, %{"content" => [result]}, state}

      {:error, _} ->
        {:error,
         %{
           "code" => -32_602,
           "message" => "Invalid target_time format"
         }, state}
    end
  end

  def handle_call_tool(name, _arguments, state) do
    {:error,
     %{
       "code" => -32_601,
       "message" => "Unknown tool: #{name}"
     }, state}
  end

  @impl true
  def handle_list_resources(_params, state) do
    {:ok, %{"resources" => []}, state}
  end
end

# Start the server
{:ok, _server} =
  ExMCP.Server.start_link(
    transport: :stdio,
    handler: DemoTimeServer.Handler
  )

# Keep the process alive
Process.sleep(:infinity)
