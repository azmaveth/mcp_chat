defmodule MCPChatWeb.AgentMonitorLive do
  use MCPChatWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to agent events
      Phoenix.PubSub.subscribe(MCPChat.PubSub, "system:agents")
    end

    {:ok,
     socket
     |> assign(:page_title, "Agent Monitor")
     |> assign(:agents, get_all_agents())
     |> assign(:selected_agent, nil)}
  end

  @impl true
  def handle_info({:agent_status_changed, agent_id, status}, socket) do
    agents = update_agent_status(socket.assigns.agents, agent_id, status)
    {:noreply, assign(socket, :agents, agents)}
  end

  @impl true
  def handle_info({:agent_created, agent_info}, socket) do
    agents = [agent_info | socket.assigns.agents]
    {:noreply, assign(socket, :agents, agents)}
  end

  @impl true
  def handle_info({:agent_destroyed, agent_id}, socket) do
    agents = Enum.reject(socket.assigns.agents, &(&1.id == agent_id))
    {:noreply, assign(socket, :agents, agents)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_agent", %{"agent_id" => agent_id}, socket) do
    {:noreply, assign(socket, :selected_agent, agent_id)}
  end

  @impl true
  def handle_event("refresh_agents", _params, socket) do
    {:noreply, assign(socket, :agents, get_all_agents())}
  end

  @impl true
  def handle_event("stop_agent", %{"agent_id" => agent_id}, socket) do
    case MCPChat.Agents.AgentSupervisor.stop_agent(agent_id) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Agent #{agent_id} stopped successfully")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to stop agent: #{reason}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="agent-monitor">
      <h2>Agent Monitor</h2>
      
      <div class="card">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
          <h3>All Agents</h3>
          <button class="btn" phx-click="refresh_agents">
            Refresh
          </button>
        </div>

        <%= if Enum.empty?(@agents) do %>
          <p>No agents currently running</p>
        <% else %>
          <div style="display: grid; gap: 1rem;">
            <%= for agent <- @agents do %>
              <div 
                class="agent-card" 
                style={"border: 1px solid #e5e7eb; border-radius: 4px; padding: 1rem; cursor: pointer; #{if @selected_agent == agent.id, do: "border-color: #3b82f6; background: #eff6ff;", else: ""}"}
                phx-click="select_agent"
                phx-value-agent_id={agent.id}
              >
                <div style="display: flex; justify-content: space-between; align-items: center;">
                  <div style="flex: 1;">
                    <div style="display: flex; align-items: center; gap: 0.5rem;">
                      <span class={"status-indicator status-#{agent.status}"}></span>
                      <strong><%= agent.type %></strong>
                      <span style="font-size: 0.875rem; color: #6b7280;">(ID: <%= agent.id %>)</span>
                    </div>
                    
                    <div style="margin-top: 0.5rem; font-size: 0.875rem; color: #6b7280;">
                      <div>Status: <%= agent.status %></div>
                      <div>Session: <%= agent.session_id || "none" %></div>
                      <div>Started: <%= format_time(agent.started_at) %></div>
                      <div>Last Activity: <%= format_time(agent.last_activity) %></div>
                      <%= if agent.memory_usage do %>
                        <div>Memory: <%= agent.memory_usage %>KB</div>
                      <% end %>
                    </div>
                  </div>
                  
                  <div style="display: flex; gap: 0.5rem;">
                    <a href={"/agents/#{agent.id}"} class="btn">
                      Details
                    </a>
                    <%= if agent.status == :active do %>
                      <button 
                        class="btn" 
                        style="background: #ef4444;"
                        phx-click="stop_agent"
                        phx-value-agent_id={agent.id}
                        onclick="return confirm('Are you sure you want to stop this agent?')"
                      >
                        Stop
                      </button>
                    <% end %>
                  </div>
                </div>

                <%= if @selected_agent == agent.id do %>
                  <div style="margin-top: 1rem; padding-top: 1rem; border-top: 1px solid #e5e7eb;">
                    <h4>Agent Details</h4>
                    <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-top: 0.5rem;">
                      <div>
                        <strong>Process ID:</strong> <%= inspect(agent.pid) %>
                      </div>
                      <div>
                        <strong>Supervisor:</strong> <%= agent.supervisor || "none" %>
                      </div>
                      <div>
                        <strong>Configuration:</strong> <%= agent.config || "default" %>
                      </div>
                      <%= if agent.metrics do %>
                        <div>
                          <strong>Messages Processed:</strong> <%= agent.metrics.messages_processed || 0 %>
                        </div>
                        <div>
                          <strong>Errors:</strong> <%= agent.metrics.errors || 0 %>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <div class="card">
        <h3>Agent Statistics</h3>
        <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 1rem;">
          <div style="text-align: center; padding: 1rem; border: 1px solid #e5e7eb; border-radius: 4px;">
            <div style="font-size: 2rem; font-weight: bold; color: #059669;"><%= count_agents_by_status(@agents, :active) %></div>
            <div>Active</div>
          </div>
          <div style="text-align: center; padding: 1rem; border: 1px solid #e5e7eb; border-radius: 4px;">
            <div style="font-size: 2rem; font-weight: bold; color: #d97706;"><%= count_agents_by_status(@agents, :idle) %></div>
            <div>Idle</div>
          </div>
          <div style="text-align: center; padding: 1rem; border: 1px solid #e5e7eb; border-radius: 4px;">
            <div style="font-size: 2rem; font-weight: bold; color: #dc2626;"><%= count_agents_by_status(@agents, :error) %></div>
            <div>Error</div>
          </div>
          <div style="text-align: center; padding: 1rem; border: 1px solid #e5e7eb; border-radius: 4px;">
            <div style="font-size: 2rem; font-weight: bold; color: #4f46e5;"><%= length(@agents) %></div>
            <div>Total</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions
  defp get_all_agents do
    try do
      case MCPChat.Agents.AgentSupervisor.list_agents() do
        {:ok, agents} ->
          Enum.map(agents, fn {id, pid, type} ->
            %{
              id: id,
              type: type,
              pid: pid,
              status: get_agent_status(pid),
              session_id: get_agent_session_id(pid),
              started_at: get_agent_start_time(pid),
              last_activity: DateTime.utc_now(),
              supervisor: "AgentSupervisor",
              config: get_agent_config(pid),
              memory_usage: get_memory_usage(pid),
              metrics: get_agent_metrics(pid)
            }
          end)

        {:error, _} ->
          []
      end
    rescue
      _ -> []
    end
  end

  defp get_agent_status(pid) when is_pid(pid) do
    if Process.alive?(pid), do: :active, else: :error
  end

  defp get_agent_status(_), do: :error

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

  defp get_agent_start_time(pid) when is_pid(pid) do
    try do
      GenServer.call(pid, :get_start_time, 1000)
    rescue
      _ -> DateTime.utc_now()
    catch
      :exit, _ -> DateTime.utc_now()
    end
  end

  defp get_agent_start_time(_), do: DateTime.utc_now()

  defp get_agent_config(pid) when is_pid(pid) do
    try do
      GenServer.call(pid, :get_config, 1000)
    rescue
      _ -> nil
    catch
      :exit, _ -> nil
    end
  end

  defp get_agent_config(_), do: nil

  defp get_memory_usage(pid) when is_pid(pid) do
    try do
      {:memory, memory} = Process.info(pid, :memory)
      # Convert to KB
      div(memory, 1024)
    rescue
      _ -> nil
    catch
      :exit, _ -> nil
    end
  end

  defp get_memory_usage(_), do: nil

  defp get_agent_metrics(pid) when is_pid(pid) do
    try do
      GenServer.call(pid, :get_metrics, 1000)
    rescue
      _ -> nil
    catch
      :exit, _ -> nil
    end
  end

  defp get_agent_metrics(_), do: nil

  defp update_agent_status(agents, agent_id, new_status) do
    Enum.map(agents, fn agent ->
      if agent.id == agent_id do
        %{agent | status: new_status, last_activity: DateTime.utc_now()}
      else
        agent
      end
    end)
  end

  defp count_agents_by_status(agents, status) do
    Enum.count(agents, &(&1.status == status))
  end

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_time(_), do: "unknown"
end
