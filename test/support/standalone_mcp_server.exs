#!/usr/bin/env elixir

# Standalone MCP Server for Testing
# This server implements a minimal MCP protocol without external dependencies

defmodule StandaloneMCPServer do
  @moduledoc """
  A completely standalone MCP server that uses only Elixir stdlib.
  """

  def start do
    loop(%{initialized: false})
  end

  defp loop(state) do
    case IO.gets("") do
      :eof ->
        :ok

      {:error, _} ->
        :ok

      line ->
        process_line(line, state)
    end
  end

  defp process_line(line, state) do
    line = String.trim(line)

    if line != "" do
      {response, new_state} = handle_json_rpc(line, state)
      send_response_if_present(response)
      loop(new_state)
    else
      loop(state)
    end
  end

  defp send_response_if_present(nil), do: :ok
  defp send_response_if_present(response), do: IO.puts(response)

  defp handle_json_rpc(line, state) do
    # Very basic JSON parsing without dependencies
    cond do
      String.contains?(line, "\"method\":\"initialize\"") ->
        id = extract_id(line)
        response = build_initialize_response(id)
        {response, %{state | initialized: true}}

      String.contains?(line, "\"method\":\"tools/list\"") ->
        id = extract_id(line)
        response = build_tools_list_response(id)
        {response, state}

      String.contains?(line, "\"method\":\"tools/call\"") ->
        id = extract_id(line)
        tool_name = extract_tool_name(line)
        response = build_tool_call_response(id, tool_name)
        {response, state}

      true ->
        {nil, state}
    end
  end

  defp extract_id(line) do
    case Regex.run(~r/"id":(\d+)/, line) do
      [_, id] -> id
      _ -> "1"
    end
  end

  defp extract_tool_name(line) do
    case Regex.run(~r/"name":"([^"]+)"/, line) do
      [_, name] -> name
      _ -> "unknown"
    end
  end

  defp build_initialize_response(id) do
    ~s({"jsonrpc":"2.0","id":#{id},"result":{"protocolVersion":"2025-03-26","capabilities":{"tools":{}},"serverInfo":{"name":"standalone-test-server","version":"1.0.0"}}})
  end

  defp build_tools_list_response(id) do
    ~s({"jsonrpc":"2.0","id":#{id},"result":{"tools":[{"name":"get_current_time","description":"Get the current time","inputSchema":{"type":"object","properties":{}}}]}})
  end

  defp build_tool_call_response(id, "get_current_time") do
    time = DateTime.utc_now() |> DateTime.to_iso8601()
    ~s({"jsonrpc":"2.0","id":#{id},"result":{"content":[{"type":"text","text":"Current time: #{time}"}]}})
  end

  defp build_tool_call_response(id, tool_name) do
    ~s({"jsonrpc":"2.0","id":#{id},"error":{"code":-32_601,"message":"Unknown tool: #{tool_name}"}})
  end
end

# Start the server
StandaloneMCPServer.start()
