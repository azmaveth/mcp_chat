defmodule MCPChat.Application do
  @moduledoc """
  Main OTP application for MCP Chat client.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        # Configuration manager
        MCPChat.Config,
        # Session manager
        MCPChat.Session,
        # Alias manager
        MCPChat.Alias.ExAliasAdapter,
        # Model loader for local LLMs
        MCPChat.LLM.ModelLoader,
        # Line editor for CLI input
        MCPChat.CLI.ExReadlineAdapter,
        # MCP server manager (handles the dynamic supervisor internally)
        MCPChat.MCP.ServerManager
      ] ++ mcp_server_children()

    opts = [strategy: :one_for_one, name: MCPChat.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp mcp_server_children() do
    # Wait a bit for Config to initialize
    Process.sleep(100)

    config =
      case Process.whereis(MCPChat.Config) do
        nil -> %{}
        _ -> MCPChat.Config.get(:mcp_server) || %{}
      end

    children = []

    # TODO: Update MCP server components to use ex_mcp
    # Add stdio server if enabled
    # children =
    #   if config[:stdio_enabled] do
    #     [MCPChat.MCPServer.StdioServer | children]
    #   else
    #     children
    #   end

    # Add SSE server if enabled
    # children =
    #   if config[:sse_enabled] do
    #     port = config[:sse_port] || 8_080

    #     [
    #       %{
    #         id: MCPChat.MCPServer.SSEServer,
    #         start: {MCPChat.MCPServer.SSEServer, :start_link, [[port: port]]}
    #       }
    #       | children
    #     ]
    #   else
    #     children
    #   end

    children
  end
end
