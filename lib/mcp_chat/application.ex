defmodule MCPChat.Application do
  @moduledoc """
  Main OTP application for MCP Chat client.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Configuration manager
      MCPChat.Config,
      # Session manager
      MCPChat.Session,
      # MCP server connection supervisor
      {DynamicSupervisor, name: MCPChat.MCP.ServerSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: MCPChat.Supervisor]
    Supervisor.start_link(children, opts)
  end
end