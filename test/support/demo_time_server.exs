#!/usr/bin/env elixir

# Demo Time MCP Server for E2E Testing
# A simple MCP server that provides time-related tools

defmodule DemoTimeServer do
  @moduledoc """
  A demo MCP server that provides time-related functionality for testing.
  Uses the ex_mcp library to implement a stdio-based server.
  """

  def main(_args) do
    # Start the MCP server
    {:ok, server} =
      ExMCP.Server.start_link(
        name: "demo-time-server",
        version: "1.0.0",
        transport: :stdio
      )

    # Register tools
    ExMCP.Server.add_tool(server, %{
      name: "get_current_time",
      description: "Get the current time in a specified timezone",
      input_schema: %{
        type: "object",
        properties: %{
          timezone: %{
            type: "string",
            description: "Timezone (e.g., 'UTC', 'America/New_York')",
            default: "UTC"
          }
        }
      },
      handler: &handle_get_current_time/1
    })

    ExMCP.Server.add_tool(server, %{
      name: "add_time",
      description: "Add hours to the current time",
      input_schema: %{
        type: "object",
        properties: %{
          hours: %{
            type: "number",
            description: "Number of hours to add"
          }
        },
        required: ["hours"]
      },
      handler: &handle_add_time/1
    })

    ExMCP.Server.add_tool(server, %{
      name: "time_until",
      description: "Calculate time until a future timestamp",
      input_schema: %{
        type: "object",
        properties: %{
          target_time: %{
            type: "string",
            description: "Target time in ISO format"
          }
        },
        required: ["target_time"]
      },
      handler: &handle_time_until/1
    })

    # Add resources
    ExMCP.Server.add_resource(server, %{
      uri: "time://current",
      name: "Current Time",
      description: "The current system time",
      mime_type: "application/json",
      reader: &read_current_time_resource/0
    })

    ExMCP.Server.add_resource(server, %{
      uri: "time://zones",
      name: "Available Timezones",
      description: "List of available timezone identifiers",
      mime_type: "application/json",
      reader: &read_timezones_resource/0
    })

    # Keep the server running
    Process.sleep(:infinity)
  end

  defp handle_get_current_time(%{"timezone" => timezone}) do
    time = get_time_in_timezone(timezone)

    {:ok,
     %{
       "time" => DateTime.to_iso8601(time),
       "timezone" => timezone,
       "unix" => DateTime.to_unix(time)
     }}
  end

  defp handle_get_current_time(_params) do
    handle_get_current_time(%{"timezone" => "UTC"})
  end

  defp handle_add_time(%{"hours" => hours}) when is_number(hours) do
    current = DateTime.utc_now()
    seconds_to_add = round(hours * 3_600)
    future = DateTime.add(current, seconds_to_add, :second)

    {:ok,
     %{
       "current" => DateTime.to_iso8601(current),
       "future" => DateTime.to_iso8601(future),
       "hours_added" => hours
     }}
  end

  defp handle_add_time(_params) do
    {:error, "Invalid parameters: 'hours' must be a number"}
  end

  defp handle_time_until(%{"target_time" => target_str}) do
    case DateTime.from_iso8601(target_str) do
      {:ok, target, _} ->
        current = DateTime.utc_now()
        diff_seconds = DateTime.diff(target, current)

        {:ok,
         %{
           "current" => DateTime.to_iso8601(current),
           "target" => DateTime.to_iso8601(target),
           "seconds_until" => diff_seconds,
           "hours_until" => diff_seconds / 3_600,
           "days_until" => diff_seconds / 86_400
         }}

      {:error, _} ->
        {:error, "Invalid target_time format. Use ISO 8_601 format."}
    end
  end

  defp read_current_time_resource() do
    current = DateTime.utc_now()

    Jason.encode!(%{
      "iso8601" => DateTime.to_iso8601(current),
      "unix" => DateTime.to_unix(current),
      "human" => Calendar.strftime(current, "%B %d, %Y at %I:%M %p UTC")
    })
  end

  defp read_timezones_resource() do
    # Simple list of common timezones for testing
    zones = [
      "UTC",
      "America/New_York",
      "America/Chicago",
      "America/Denver",
      "America/Los_Angeles",
      "Europe/London",
      "Europe/Paris",
      "Asia/Tokyo",
      "Australia/Sydney"
    ]

    Jason.encode!(%{"timezones" => zones})
  end

  defp get_time_in_timezone("UTC"), do: DateTime.utc_now()

  defp get_time_in_timezone(timezone) do
    # For testing, just add/subtract hours based on common zones
    utc = DateTime.utc_now()

    offset_hours =
      case timezone do
        "America/New_York" -> -5
        "America/Chicago" -> -6
        "America/Denver" -> -7
        "America/Los_Angeles" -> -8
        "Europe/London" -> 0
        "Europe/Paris" -> 1
        "Asia/Tokyo" -> 9
        "Australia/Sydney" -> 11
        _ -> 0
      end

    DateTime.add(utc, offset_hours * 3_600, :second)
  end
end

# Start the server
DemoTimeServer.main(System.argv())
