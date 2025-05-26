defmodule MCPChat.MCP.Handlers.ProgressHandler do
  @moduledoc """
  Handles progress notifications from MCP servers.
  Tracks active operations and updates progress UI.
  """
  @behaviour MCPChat.MCP.NotificationHandler

  require Logger
  alias MCPChat.CLI.Renderer

  defstruct [:active_operations, :progress_tracker_pid]

  @impl true
  def init(args) do
    tracker_pid = Keyword.get(args, :progress_tracker_pid)
    {:ok, %__MODULE__{active_operations: %{}, progress_tracker_pid: tracker_pid}}
  end

  @impl true
  def handle_notification(server_name, :progress, params, state) do
    token = Map.get(params, "progressToken", "unknown")
    progress = Map.get(params, "progress", 0)
    total = Map.get(params, "total")

    # Create operation key
    op_key = {server_name, token}

    # Update or create operation tracking
    operation =
      Map.get(state.active_operations, op_key, %{
        started_at: DateTime.utc_now(),
        server: server_name,
        token: token
      })

    updated_operation =
      Map.merge(operation, %{
        progress: progress,
        total: total,
        updated_at: DateTime.utc_now()
      })

    new_operations = Map.put(state.active_operations, op_key, updated_operation)

    # Display progress
    display_progress(server_name, token, progress, total)

    # Notify progress tracker if available
    if state.progress_tracker_pid do
      send(state.progress_tracker_pid, {:progress_update, server_name, token, progress, total})
    end

    # Clean up completed operations
    new_operations =
      if total && progress >= total do
        Renderer.show_success("✅ Operation completed: #{token}")
        Map.delete(new_operations, op_key)
      else
        new_operations
      end

    {:ok, %{state | active_operations: new_operations}}
  end

  def handle_notification(_server_name, _type, _params, state) do
    # Ignore other notification types
    {:ok, state}
  end

  # Private Functions

  defp display_progress(server_name, token, progress, nil) do
    # Indeterminate progress
    Renderer.show_info("⏳ [#{server_name}] #{token}: #{progress} items processed")
  end

  defp display_progress(server_name, token, progress, total) do
    # Calculate percentage
    percentage = round(progress / total * 100)

    # Create progress bar
    bar_width = 20
    filled = round(bar_width * progress / total)
    empty = bar_width - filled

    bar = String.duplicate("█", filled) <> String.duplicate("░", empty)

    Renderer.show_info("📊 [#{server_name}] #{token}: [#{bar}] #{percentage}% (#{progress}/#{total})")
  end
end
