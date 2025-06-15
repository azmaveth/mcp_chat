defmodule MCPChat.MCP.Handlers.ResourceChangeHandler do
  @moduledoc """
  Handles resource-related notifications from MCP servers.
  Updates cached resource lists and notifies the user of changes.
  """
  @behaviour MCPChat.MCP.NotificationHandler

  require Logger
  alias MCPChat.{CLI.Renderer, Session}

  defstruct [:session_pid, :cache]

  @impl true
  def init(args) do
    session_pid = Keyword.get(args, :session_pid, MCPChat.Session)
    {:ok, %__MODULE__{session_pid: session_pid, cache: %{}}}
  end

  @impl true
  def handle_notification(server_name, :resources_list_changed, _params, state) do
    Logger.info("Resources list changed for server: #{server_name}")

    # Clear cache for this server
    new_cache = Map.delete(state.cache, server_name)

    # Notify user
    Renderer.show_info("📋 Resources updated for server: #{server_name}")
    Renderer.show_info("Use /mcp resources #{server_name} to see the updated list")

    # Could trigger auto-refresh here if desired
    # refresh_resources(server_name)

    {:ok, %{state | cache: new_cache}}
  end

  def handle_notification(server_name, :resources_updated, params, state) do
    uri = Map.get(params, "uri", "unknown")
    Logger.info("Resource updated - Server: #{server_name}, URI: #{uri}")

    # Clear specific resource from cache
    new_cache =
      case Map.get(state.cache, server_name) do
        nil ->
          state.cache

        server_cache ->
          updated_server_cache = Map.delete(server_cache, uri)
          Map.put(state.cache, server_name, updated_server_cache)
      end

    # Notify user
    Renderer.show_info("📝 Resource updated: #{uri}")

    # Update session context if this resource is in use
    update_session_context(state.session_pid, uri)

    {:ok, %{state | cache: new_cache}}
  end

  def handle_notification(_server_name, _type, _params, state) do
    # Ignore other notification types
    {:ok, state}
  end

  # Private Functions

  defp update_session_context(session_pid, uri) do
    # Check if this resource is in the current context
    case Session.get_context_files(session_pid) do
      {:ok, files} ->
        if Map.has_key?(files, uri) do
          Renderer.show_warning("⚠️  Context file updated: #{uri}")
          Renderer.show_info("Consider refreshing with: /context rm #{uri} && /context add #{uri}")
        end

      _ ->
        :ok
    end
  end
end
