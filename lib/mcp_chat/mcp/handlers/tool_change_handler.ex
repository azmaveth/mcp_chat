defmodule MCPChat.MCP.Handlers.ToolChangeHandler do
  @moduledoc """
  Handles tool-related notifications from MCP servers.
  Updates cached tool lists and notifies the user of changes.
  """
  @behaviour MCPChat.MCP.NotificationHandler

  require Logger
  alias MCPChat.CLI.Renderer

  defstruct [:tool_cache, :last_update]

  @impl true
  def init(_args) do
    {:ok, %__MODULE__{tool_cache: %{}, last_update: %{}}}
  end

  @impl true
  def handle_notification(server_name, :tools_list_changed, _params, state) do
    Logger.info("Tools list changed for server: #{server_name}")

    # Clear cache for this server
    new_cache = Map.delete(state.tool_cache, server_name)
    new_last_update = Map.put(state.last_update, server_name, DateTime.utc_now())

    # Notify user
    Renderer.show_info("🔧 Tools updated for server: #{server_name}")
    Renderer.show_info("Use /mcp tools #{server_name} to see the updated list")

    # Emit telemetry event
    :telemetry.execute(
      [:mcp_chat, :notification, :tools_changed],
      %{count: 1},
      %{server: server_name}
    )

    {:ok, %{state | tool_cache: new_cache, last_update: new_last_update}}
  end

  def handle_notification(_server_name, _type, _params, state) do
    # Ignore other notification types
    {:ok, state}
  end
end
