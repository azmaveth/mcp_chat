#!/usr/bin/env elixir

# Simple MCP Time Server for Testing
# This is a minimal MCP server that doesn't require external dependencies

defmodule SimpleMCPServer do
  @moduledoc """
  A simple MCP server implementation for testing stdio transport.
  Implements basic JSON-RPC 2.0 protocol over stdio.
  """

  def start() do
    # Start receiving messages
    loop(%{initialized: false})
  end

  defp loop(state) do
    case read_message() do
      {:ok, message} ->
        {response, new_state} = handle_message(message, state)

        if response do
          send_message(response)
        end

        loop(new_state)

      :eof ->
        :ok
    end
  end

  defp read_message() do
    case IO.gets("") do
      :eof ->
        :eof

      {:error, _} ->
        :eof

      line ->
        # Simple JSON parsing
        case Jason.decode(String.trim(line)) do
          {:ok, message} -> {:ok, message}
          # Skip invalid lines
          {:error, _} -> read_message()
        end
    end
  end

  defp send_message(message) do
    json = Jason.encode!(message)
    IO.puts(json)
  end

  defp handle_message(%{"jsonrpc" => "2.0", "method" => "initialize", "id" => id}, state) do
    response = %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "protocolVersion" => "2024-11-05",
        "capabilities" => %{
          "tools" => %{}
        },
        "serverInfo" => %{
          "name" => "simple-time-server",
          "version" => "1.0.0"
        }
      }
    }

    {response, %{state | initialized: true}}
  end

  defp handle_message(%{"jsonrpc" => "2.0", "method" => "tools/list", "id" => id}, state) do
    response = %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "tools" => [
          %{
            "name" => "get_current_time",
            "description" => "Get the current time",
            "inputSchema" => %{
              "type" => "object",
              "properties" => %{}
            }
          }
        ]
      }
    }

    {response, state}
  end

  defp handle_message(%{"jsonrpc" => "2.0", "method" => "tools/call", "id" => id, "params" => params}, state) do
    tool_name = params["name"]

    result =
      case tool_name do
        "get_current_time" ->
          %{
            "content" => [
              %{
                "type" => "text",
                "text" => "Current time: #{DateTime.utc_now() |> DateTime.to_string()}"
              }
            ]
          }

        _ ->
          %{"error" => "Unknown tool: #{tool_name}"}
      end

    response = %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => result
    }

    {response, state}
  end

  defp handle_message(_message, state) do
    # Ignore unknown messages
    {nil, state}
  end
end

# Check if Jason is available
unless Code.ensure_loaded?(Jason) do
  IO.puts(:stderr, "Error: Jason module not available. This script requires Jason to be in the path.")
  System.halt(1)
end

# Start the server
SimpleMCPServer.start()
