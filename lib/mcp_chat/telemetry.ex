defmodule MCPChat.Telemetry do
  @moduledoc """
  Telemetry integration for MCP Chat.

  This module provides telemetry instrumentation for MCP Chat operations
  and integrates with ExLLM's comprehensive telemetry system.

  ## Events

  MCP Chat emits the following telemetry events:

  - `[:mcp_chat, :session, :started]` - When a chat session starts
  - `[:mcp_chat, :session, :ended]` - When a chat session ends
  - `[:mcp_chat, :command, :executed]` - When a CLI command is executed
  - `[:mcp_chat, :streaming, :chunk_processed]` - When a streaming chunk is processed
  - `[:mcp_chat, :mcp, :server_connected]` - When an MCP server connects
  - `[:mcp_chat, :mcp, :tool_called]` - When an MCP tool is called

  ## Integration with ExLLM

  This module automatically integrates with ExLLM's telemetry system to provide
  comprehensive observability for LLM operations.
  """

  require Logger

  @doc """
  Attach default telemetry handlers for MCP Chat events.

  This includes both MCP Chat events and ExLLM events for comprehensive monitoring.
  """
  def attach_default_handlers do
    # Attach MCP Chat event handlers
    attach_mcp_chat_handlers()

    # Attach ExLLM event handlers
    attach_ex_llm_handlers()

    :ok
  end

  @doc """
  Detach all telemetry handlers.
  """
  def detach_all_handlers do
    :telemetry.detach("mcp-chat-handlers")
    :telemetry.detach("mcp-chat-ex-llm-handlers")
    :ok
  end

  @doc """
  Emit a session started event.
  """
  def emit_session_started(session_id, metadata \\ %{}) do
    :telemetry.execute(
      [:mcp_chat, :session, :started],
      %{session_id: session_id},
      Map.merge(%{timestamp: System.system_time(:millisecond)}, metadata)
    )
  end

  @doc """
  Emit a session ended event.
  """
  def emit_session_ended(session_id, duration_ms, metadata \\ %{}) do
    :telemetry.execute(
      [:mcp_chat, :session, :ended],
      %{session_id: session_id, duration: duration_ms},
      Map.merge(%{timestamp: System.system_time(:millisecond)}, metadata)
    )
  end

  @doc """
  Emit a command executed event.
  """
  def emit_command_executed(command, duration_ms, success, metadata \\ %{}) do
    :telemetry.execute(
      [:mcp_chat, :command, :executed],
      %{duration: duration_ms, success: success},
      Map.merge(%{command: command, timestamp: System.system_time(:millisecond)}, metadata)
    )
  end

  @doc """
  Emit an MCP server connected event.
  """
  def emit_mcp_server_connected(server_name, metadata \\ %{}) do
    :telemetry.execute(
      [:mcp_chat, :mcp, :server_connected],
      %{},
      Map.merge(%{server_name: server_name, timestamp: System.system_time(:millisecond)}, metadata)
    )
  end

  @doc """
  Emit an MCP tool called event.
  """
  def emit_mcp_tool_called(server_name, tool_name, duration_ms, success, metadata \\ %{}) do
    :telemetry.execute(
      [:mcp_chat, :mcp, :tool_called],
      %{duration: duration_ms, success: success},
      Map.merge(
        %{
          server_name: server_name,
          tool_name: tool_name,
          timestamp: System.system_time(:millisecond)
        },
        metadata
      )
    )
  end

  # Private functions

  defp attach_mcp_chat_handlers do
    events = [
      [:mcp_chat, :session, :started],
      [:mcp_chat, :session, :ended],
      [:mcp_chat, :command, :executed],
      [:mcp_chat, :streaming, :chunk_processed],
      [:mcp_chat, :mcp, :server_connected],
      [:mcp_chat, :mcp, :tool_called]
    ]

    :telemetry.attach_many(
      "mcp-chat-handlers",
      events,
      &handle_mcp_chat_event/4,
      %{}
    )
  end

  defp attach_ex_llm_handlers do
    # Get ExLLM telemetry events and attach handlers
    ex_llm_events = [
      [:ex_llm, :chat, :start],
      [:ex_llm, :chat, :stop],
      [:ex_llm, :chat, :exception],
      [:ex_llm, :stream, :start],
      [:ex_llm, :stream, :chunk],
      [:ex_llm, :stream, :stop],
      [:ex_llm, :stream, :exception],
      [:ex_llm, :cost, :calculated],
      [:ex_llm, :cache, :hit],
      [:ex_llm, :cache, :miss]
    ]

    :telemetry.attach_many(
      "mcp-chat-ex-llm-handlers",
      ex_llm_events,
      &handle_ex_llm_event/4,
      %{}
    )
  end

  defp handle_mcp_chat_event(event, measurements, metadata, _config) do
    level = get_log_level(event)
    message = format_mcp_chat_message(event, measurements, metadata)
    Logger.log(level, message, metadata)
  end

  defp format_mcp_chat_message(event, measurements, metadata) do
    case event do
      [:mcp_chat, :session, :started] ->
        "Chat session started"

      [:mcp_chat, :session, :ended] ->
        duration_sec = measurements[:duration] / 1_000
        "Chat session ended after #{duration_sec}s"

      [:mcp_chat, :command, :executed] ->
        status = if measurements[:success], do: "succeeded", else: "failed"
        "Command '#{metadata[:command]}' #{status} in #{measurements[:duration]}ms"

      [:mcp_chat, :streaming, :chunk_processed] ->
        "Processed streaming chunk (#{measurements[:chunk_size]} bytes)"

      [:mcp_chat, :mcp, :server_connected] ->
        "MCP server '#{metadata[:server_name]}' connected"

      [:mcp_chat, :mcp, :tool_called] ->
        status = if measurements[:success], do: "succeeded", else: "failed"
        "MCP tool '#{metadata[:tool_name]}' #{status} in #{measurements[:duration]}ms"

      _ ->
        "MCP Chat event: #{inspect(event)}"
    end
  end

  defp handle_ex_llm_event(event, measurements, metadata, _config) do
    level = get_log_level(event)
    message = format_ex_llm_message(event, measurements, metadata)
    Logger.log(level, message, metadata)
  end

  defp format_ex_llm_message(event, measurements, metadata) do
    case event do
      [:ex_llm, :chat, :start] ->
        "LLM chat request started"

      [:ex_llm, :chat, :stop] ->
        duration_ms = System.convert_time_unit(measurements[:duration], :native, :millisecond)
        cost = Map.get(metadata, :cost_cents, 0)
        "LLM chat completed in #{duration_ms}ms (cost: #{format_cost(cost)})"

      [:ex_llm, :chat, :exception] ->
        "LLM chat failed: #{inspect(metadata[:reason])}"

      [:ex_llm, :stream, :start] ->
        "LLM streaming started"

      [:ex_llm, :stream, :chunk] ->
        "LLM streaming chunk received"

      [:ex_llm, :stream, :stop] ->
        duration_ms = System.convert_time_unit(measurements[:duration], :native, :millisecond)
        chunks = measurements[:chunks] || 0
        "LLM streaming completed in #{duration_ms}ms (#{chunks} chunks)"

      [:ex_llm, :stream, :exception] ->
        "LLM streaming failed: #{inspect(metadata[:reason])}"

      [:ex_llm, :cost, :calculated] ->
        cost = measurements[:cost] || 0
        "LLM cost calculated: #{format_cost(cost)}"

      [:ex_llm, :cache, :hit] ->
        "LLM cache hit for key: #{metadata[:key]}"

      [:ex_llm, :cache, :miss] ->
        "LLM cache miss for key: #{metadata[:key]}"

      _ ->
        "ExLLM event: #{inspect(event)}"
    end
  end

  defp get_log_level(event) do
    cond do
      is_error_event?(event) -> :error
      is_info_event?(event) -> :info
      true -> :debug
    end
  end

  defp is_error_event?(event) do
    case event do
      [_, _, :exception] -> true
      [_, _, :failed] -> true
      _ -> false
    end
  end

  defp is_info_event?(event) do
    case event do
      [:mcp_chat, :session, :started] -> true
      [:mcp_chat, :session, :ended] -> true
      [:mcp_chat, :mcp, :server_connected] -> true
      [:ex_llm, :chat, :start] -> true
      [:ex_llm, :chat, :stop] -> true
      [:ex_llm, :stream, :start] -> true
      [:ex_llm, :stream, :stop] -> true
      _ -> false
    end
  end

  defp format_cost(cost_cents) when is_number(cost_cents) do
    "$#{Float.round(cost_cents / 100, 4)}"
  end

  defp format_cost(_), do: "$0.0_000"
end
