defmodule MCPChatWeb.DashboardLive do
  use MCPChatWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to system-wide events
      Phoenix.PubSub.subscribe(MCPChat.PubSub, "system:agents")
      Phoenix.PubSub.subscribe(MCPChat.PubSub, "system:sessions")
    end

    {:ok,
     socket
     |> assign(:page_title, "Agent Dashboard")
     |> assign(:agents, get_agent_status())
     |> assign(:sessions, get_active_sessions())
     |> assign(:system_stats, get_system_stats())}
  end

  @impl true
  def handle_info({:agent_status_changed, agent_id, status}, socket) do
    agents = update_agent_in_list(socket.assigns.agents, agent_id, status)
    {:noreply, assign(socket, :agents, agents)}
  end

  @impl true
  def handle_info({:session_created, session_info}, socket) do
    sessions = [session_info | socket.assigns.sessions]
    {:noreply, assign(socket, :sessions, sessions)}
  end

  @impl true
  def handle_info({:session_ended, session_id}, socket) do
    sessions = Enum.reject(socket.assigns.sessions, &(&1.id == session_id))
    {:noreply, assign(socket, :sessions, sessions)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dashboard">
      <h2>System Overview</h2>
      
      <div class="card">
        <h3>System Statistics</h3>
        <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem;">
          <div>
            <strong>Active Sessions:</strong> <%= length(@sessions) %>
          </div>
          <div>
            <strong>Running Agents:</strong> <%= count_active_agents(@agents) %>
          </div>
          <div>
            <strong>Memory Usage:</strong> <%= @system_stats.memory_mb %>MB
          </div>
          <div>
            <strong>Uptime:</strong> <%= @system_stats.uptime %>
          </div>
        </div>
      </div>

      <div class="card">
        <h3>Agent Status</h3>
        <%= if Enum.empty?(@agents) do %>
          <p>No agents currently running</p>
        <% else %>
          <div style="display: grid; gap: 1rem;">
            <%= for agent <- @agents do %>
              <div style="display: flex; align-items: center; padding: 0.5rem; border: 1px solid #e5e7eb; border-radius: 4px;">
                <span class={"status-indicator status-#{agent.status}"}></span>
                <div style="flex: 1;">
                  <strong><%= agent.type %></strong> (ID: <%= agent.id %>)
                  <div style="font-size: 0.875rem; color: #6b7280;">
                    Status: <%= agent.status %> | 
                    Session: <%= agent.session_id || "none" %> |
                    Last Activity: <%= format_time(agent.last_activity) %>
                  </div>
                </div>
                <a href={"/agents/#{agent.id}"} class="btn" style="margin-left: 1rem;">
                  View Details
                </a>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <div class="card">
        <h3>Active Sessions</h3>
        <%= if Enum.empty?(@sessions) do %>
          <p>No active sessions</p>
          <a href="/sessions" class="btn">Create New Session</a>
        <% else %>
          <div style="display: grid; gap: 1rem;">
            <%= for session <- @sessions do %>
              <div style="display: flex; align-items: center; padding: 0.5rem; border: 1px solid #e5e7eb; border-radius: 4px;">
                <span class={"status-indicator status-#{session.status}"}></span>
                <div style="flex: 1;">
                  <strong>Session <%= session.id %></strong>
                  <div style="font-size: 0.875rem; color: #6b7280;">
                    Messages: <%= session.message_count %> | 
                    Started: <%= format_time(session.created_at) %> |
                    Model: <%= session.current_model || "default" %>
                  </div>
                </div>
                <a href={"/sessions/#{session.id}/chat"} class="btn" style="margin-left: 1rem;">
                  Open Chat
                </a>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <div class="card">
        <h3>Quick Actions</h3>
        <div style="display: flex; gap: 1rem; flex-wrap: wrap;">
          <a href="/sessions" class="btn">
            Manage Sessions
          </a>
          <a href="/agents" class="btn">
            Monitor Agents
          </a>
          <button class="btn" phx-click="refresh_all">
            Refresh All
          </button>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("refresh_all", _params, socket) do
    {:noreply,
     socket
     |> assign(:agents, get_agent_status())
     |> assign(:sessions, get_active_sessions())
     |> assign(:system_stats, get_system_stats())}
  end

  # Helper functions
  defp get_agent_status do
    # Get agent status from the agent supervisor
    try do
      case MCPChat.Agents.AgentSupervisor.list_agents() do
        {:ok, agents} ->
          Enum.map(agents, fn {id, pid, type} ->
            %{
              id: id,
              type: type,
              status: get_agent_process_status(pid),
              session_id: get_agent_session_id(pid),
              last_activity: DateTime.utc_now()
            }
          end)

        {:error, _} ->
          []
      end
    rescue
      _ -> []
    end
  end

  defp get_active_sessions do
    # Get active sessions from session manager
    try do
      case MCPChat.Gateway.list_sessions() do
        {:ok, sessions} -> sessions
        {:error, _} -> []
      end
    rescue
      _ ->
        # Mock data for demonstration
        [
          %{
            id: "session_demo_1",
            status: :active,
            message_count: 5,
            created_at: DateTime.utc_now() |> DateTime.add(-3600),
            current_model: "claude-3-sonnet"
          },
          %{
            id: "session_demo_2",
            status: :idle,
            message_count: 12,
            created_at: DateTime.utc_now() |> DateTime.add(-7200),
            current_model: "gpt-4o"
          }
        ]
    end
  end

  defp get_system_stats do
    memory_mb =
      :erlang.memory(:total)
      |> div(1024 * 1024)

    uptime =
      :erlang.statistics(:wall_clock)
      |> elem(0)
      |> div(1000)
      |> format_uptime()

    %{
      memory_mb: memory_mb,
      uptime: uptime
    }
  end

  defp get_agent_process_status(pid) when is_pid(pid) do
    if Process.alive?(pid), do: :active, else: :error
  end

  defp get_agent_process_status(_), do: :error

  defp get_agent_session_id(pid) when is_pid(pid) do
    try do
      GenServer.call(pid, :get_session_id, 1000)
    rescue
      _ -> nil
    catch
      :exit, _ -> nil
    end
  end

  defp get_agent_session_id(_), do: nil

  defp count_active_agents(agents) do
    Enum.count(agents, &(&1.status == :active))
  end

  defp update_agent_in_list(agents, agent_id, new_status) do
    Enum.map(agents, fn agent ->
      if agent.id == agent_id do
        %{agent | status: new_status, last_activity: DateTime.utc_now()}
      else
        agent
      end
    end)
  end

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(_), do: "unknown"

  defp format_uptime(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_uptime(seconds) when seconds < 3600 do
    minutes = div(seconds, 60)
    remaining = rem(seconds, 60)
    "#{minutes}m #{remaining}s"
  end

  defp format_uptime(seconds) do
    hours = div(seconds, 3600)
    remaining_minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{remaining_minutes}m"
  end
end
