defmodule MCPChatWeb.HealthController do
  use MCPChatWeb, :controller

  def index(conn, _params) do
    health_status = %{
      status: "healthy",
      application: "mcp_chat",
      version: "0.7.0",
      uptime: get_uptime(),
      agents: get_agent_count(),
      sessions: get_session_count()
    }

    json(conn, health_status)
  end

  defp get_uptime do
    {uptime, _} = :erlang.statistics(:wall_clock)
    uptime
  end

  defp get_agent_count do
    # Try to get agent count, default to 0
    try do
      case MCPChat.Agents.AgentSupervisor.list_agents() do
        {:ok, agents} -> length(agents)
        _ -> 0
      end
    rescue
      _ -> 0
    end
  end

  defp get_session_count do
    # Try to get session count, default to 0
    try do
      case MCPChat.Gateway.list_active_sessions() do
        {:ok, sessions} -> length(sessions)
        _ -> 0
      end
    rescue
      _ -> 0
    end
  end
end
