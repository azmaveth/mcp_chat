defmodule MCPChat.CLI.Commands.ExportWithAgents do
  @moduledoc """
  Example of how to integrate agent architecture into existing CLI commands.
  This shows export functionality using agents for async processing with progress.
  """

  use MCPChat.CLI.Commands.Base

  alias MCPChat.CLI.AgentBridge

  @impl true
  def commands do
    %{
      "export" => "Export the current session using agent architecture"
    }
  end

  @impl true
  def handle_command("export", args) do
    handle_export_async(args)
  end

  def handle_command(_command, _args) do
    :not_handled
  end

  @doc "Export the current session using agent architecture"
  def handle_export_async(args) do
    {format, path} = parse_export_args(args)

    show_info("📦 Starting export to #{format} format...")

    # Get current session data for export
    session_data = prepare_session_data()

    # Request export through agent bridge
    case AgentBridge.export_session_async(format, %{
           path: path,
           session_data: session_data,
           include_metadata: true,
           include_attachments: false
         }) do
      {:ok, %{export_id: export_id, estimated_duration: duration}} ->
        show_info("Export started (ID: #{export_id})")
        show_info("Estimated duration: #{format_export_duration(duration)}")
        show_info("Progress updates will appear automatically...")

        # The EventSubscriber will handle progress updates
        :ok

      {:error, reason} ->
        show_error("Failed to start export: #{inspect(reason)}")
    end
  end

  @doc "Show status of active exports"
  def show_export_status do
    operations = AgentBridge.list_active_operations()

    export_ops =
      Enum.filter(operations, fn {_id, info} ->
        info.agent_type == :export && info.alive
      end)

    if Enum.empty?(export_ops) do
      show_info("No active exports")
    else
      show_info("Active exports:")

      Enum.each(export_ops, fn {id, info} ->
        format = info.task_spec[:format] || "unknown"
        duration = format_duration_since(info.started_at)
        show_info("  • #{format} export (#{id}): running for #{duration}")
      end)
    end

    :ok
  end

  # Private functions

  defp parse_export_args([]) do
    {:json, generate_default_path(:json)}
  end

  defp parse_export_args([format]) when format in ["json", "markdown", "md"] do
    format_atom = if format == "md", do: :markdown, else: :json
    {format_atom, generate_default_path(format_atom)}
  end

  defp parse_export_args([format, path | _]) do
    format_atom = if format == "md", do: :markdown, else: :json
    {format_atom, path}
  end

  defp generate_default_path(format) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)
    ext = if format == :json, do: "json", else: "md"
    "chat_export_#{timestamp}.#{ext}"
  end

  defp prepare_session_data do
    # TODO: Get current session data with Gateway API
    # For now, return minimal data
    %{
      messages: [],
      context: %{},
      metadata: %{
        exported_at: DateTime.utc_now(),
        message_count: 0,
        session_id: "unknown",
        llm_backend: "unknown"
      }
    }
  end

  defp format_export_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_export_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 1)}s"
  defp format_export_duration(ms), do: "#{div(ms, 60_000)}m #{rem(div(ms, 1000), 60)}s"

  defp format_duration_since(started_at) do
    duration_ms = DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
    format_export_duration(duration_ms)
  end
end
