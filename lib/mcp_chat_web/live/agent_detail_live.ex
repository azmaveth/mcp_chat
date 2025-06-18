defmodule MCPChatWeb.AgentDetailLive do
  use MCPChatWeb, :live_view

  @impl true
  def mount(%{"id" => agent_id}, _session, socket) do
    if connected?(socket) do
      # Subscribe to this agent's events
      Phoenix.PubSub.subscribe(MCPChat.PubSub, "agent:#{agent_id}")
      Phoenix.PubSub.subscribe(MCPChat.PubSub, "system:agents")
    end

    case get_agent_details(agent_id) do
      {:ok, agent} ->
        {:ok,
         socket
         |> assign(:page_title, "Agent #{agent_id}")
         |> assign(:agent_id, agent_id)
         |> assign(:agent, agent)
         |> assign(:logs, get_agent_logs(agent_id))
         |> assign(:show_logs, false)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Agent not found")
         |> redirect(to: "/agents")}
    end
  end

  @impl true
  def handle_info({:agent_status_changed, agent_id, new_status}, socket) do
    if agent_id == socket.assigns.agent_id do
      agent = %{socket.assigns.agent | status: new_status, last_activity: DateTime.utc_now()}
      {:noreply, assign(socket, :agent, agent)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:agent_log, agent_id, log_entry}, socket) do
    if agent_id == socket.assigns.agent_id do
      # Keep last 100 logs
      logs = [log_entry | socket.assigns.logs] |> Enum.take(100)
      {:noreply, assign(socket, :logs, logs)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:agent_destroyed, agent_id}, socket) do
    if agent_id == socket.assigns.agent_id do
      {:noreply,
       socket
       |> put_flash(:info, "Agent has been stopped")
       |> redirect(to: "/agents")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:restart_agent, agent_id}, socket) do
    case MCPChat.Agents.AgentSupervisor.start_agent(agent_id, :llm, []) do
      {:ok, _pid} ->
        {:noreply, put_flash(socket, :info, "Agent restarted successfully")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to restart agent: #{reason}")}
    end
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh_agent", _params, socket) do
    case get_agent_details(socket.assigns.agent_id) do
      {:ok, agent} ->
        {:noreply,
         socket
         |> assign(:agent, agent)
         |> assign(:logs, get_agent_logs(socket.assigns.agent_id))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to refresh agent data")}
    end
  end

  @impl true
  def handle_event("toggle_logs", _params, socket) do
    {:noreply, assign(socket, :show_logs, !socket.assigns.show_logs)}
  end

  @impl true
  def handle_event("stop_agent", _params, socket) do
    case MCPChat.Agents.AgentSupervisor.stop_agent(socket.assigns.agent_id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Agent stop request sent")
         |> redirect(to: "/agents")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to stop agent: #{reason}")}
    end
  end

  @impl true
  def handle_event("restart_agent", _params, socket) do
    agent_id = socket.assigns.agent_id

    # Stop and restart agent
    case MCPChat.Agents.AgentSupervisor.stop_agent(agent_id) do
      :ok ->
        # Wait a moment then restart
        Process.send_after(self(), {:restart_agent, agent_id}, 1000)
        {:noreply, put_flash(socket, :info, "Restarting agent...")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to restart agent: #{reason}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="agent-detail">
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
        <h2>Agent Details: <%= @agent_id %></h2>
        <div style="display: flex; gap: 0.5rem;">
          <a href="/agents" class="btn">← Back to Monitor</a>
          <button class="btn" phx-click="refresh_agent">Refresh</button>
        </div>
      </div>

      <!-- Agent Status Card -->
      <div class="card">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
          <h3>Status</h3>
          <div style="display: flex; align-items: center; gap: 0.5rem;">
            <span class={"status-indicator status-#{@agent.status}"}></span>
            <span style="text-transform: capitalize; font-weight: bold;"><%= @agent.status %></span>
          </div>
        </div>

        <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem;">
          <div>
            <strong>Type:</strong> <%= @agent.type %>
          </div>
          <div>
            <strong>Process ID:</strong> <%= inspect(@agent.pid) %>
          </div>
          <div>
            <strong>Session:</strong> <%= @agent.session_id || "none" %>
          </div>
          <div>
            <strong>Started:</strong> <%= format_datetime(@agent.started_at) %>
          </div>
          <div>
            <strong>Last Activity:</strong> <%= format_datetime(@agent.last_activity) %>
          </div>
          <div>
            <strong>Memory Usage:</strong> <%= @agent.memory_usage || 0 %>KB
          </div>
        </div>

        <%= if @agent.config do %>
          <div style="margin-top: 1rem;">
            <h4>Configuration</h4>
            <pre style="background: #f3f4f6; padding: 1rem; border-radius: 4px; overflow-x: auto;"><%= inspect(@agent.config, pretty: true) %></pre>
          </div>
        <% end %>
      </div>

      <!-- Agent Metrics Card -->
      <%= if @agent.metrics do %>
        <div class="card">
          <h3>Performance Metrics</h3>
          <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 1rem;">
            <div style="text-align: center; padding: 1rem; border: 1px solid #e5e7eb; border-radius: 4px;">
              <div style="font-size: 1.5rem; font-weight: bold; color: #059669;"><%= @agent.metrics.messages_processed || 0 %></div>
              <div>Messages Processed</div>
            </div>
            <div style="text-align: center; padding: 1rem; border: 1px solid #e5e7eb; border-radius: 4px;">
              <div style="font-size: 1.5rem; font-weight: bold; color: #d97706;"><%= @agent.metrics.errors || 0 %></div>
              <div>Errors</div>
            </div>
            <div style="text-align: center; padding: 1rem; border: 1px solid #e5e7eb; border-radius: 4px;">
              <div style="font-size: 1.5rem; font-weight: bold; color: #4f46e5;"><%= format_duration(@agent.metrics.uptime || 0) %></div>
              <div>Uptime</div>
            </div>
            <div style="text-align: center; padding: 1rem; border: 1px solid #e5e7eb; border-radius: 4px;">
              <div style="font-size: 1.5rem; font-weight: bold; color: #7c3aed;"><%= @agent.metrics.requests_per_minute || 0 %></div>
              <div>Req/Min</div>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Control Actions Card -->
      <div class="card">
        <h3>Actions</h3>
        <div style="display: flex; gap: 1rem; flex-wrap: wrap;">
          <%= if @agent.status == :active do %>
            <button 
              class="btn" 
              style="background: #ef4444;"
              phx-click="stop_agent"
              onclick="return confirm('Are you sure you want to stop this agent?')"
            >
              Stop Agent
            </button>
            <button 
              class="btn" 
              style="background: #f59e0b;"
              phx-click="restart_agent"
              onclick="return confirm('This will stop and restart the agent. Continue?')"
            >
              Restart Agent
            </button>
          <% else %>
            <button 
              class="btn" 
              style="background: #059669;"
              phx-click="restart_agent"
            >
              Start Agent
            </button>
          <% end %>
          
          <%= if @agent.session_id do %>
            <a href={"/sessions/#{@agent.session_id}/chat"} class="btn">
              Open Session Chat
            </a>
          <% end %>
        </div>
      </div>

      <!-- Logs Card -->
      <div class="card">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
          <h3>Agent Logs</h3>
          <button class="btn" phx-click="toggle_logs">
            <%= if @show_logs, do: "Hide Logs", else: "Show Logs" %>
          </button>
        </div>

        <%= if @show_logs do %>
          <div style="height: 400px; overflow-y: auto; border: 1px solid #e5e7eb; border-radius: 4px; padding: 1rem; background: #f9fafb; font-family: monospace; font-size: 0.875rem;">
            <%= if Enum.empty?(@logs) do %>
              <p style="color: #6b7280;">No logs available</p>
            <% else %>
              <%= for log <- @logs do %>
                <div style={"margin-bottom: 0.5rem; padding: 0.25rem; border-radius: 2px; #{log_color(log.level)}"}>
                  <span style="color: #6b7280;">[<%= format_time(log.timestamp) %>]</span>
                  <span style={"font-weight: bold; color: #{level_color(log.level)};"}><%= String.upcase(to_string(log.level)) %></span>
                  <%= log.message %>
                </div>
              <% end %>
            <% end %>
          </div>
        <% end %>
      </div>

      <!-- System Information Card -->
      <div class="card">
        <h3>System Information</h3>
        <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 1rem;">
          <div>
            <strong>Supervision Tree:</strong>
            <div style="font-family: monospace; font-size: 0.875rem; margin-top: 0.5rem;">
              MCPChat.Supervisor<br>
              └── MCPChat.Agents.AgentSupervisor<br>
              &nbsp;&nbsp;&nbsp;&nbsp;└── <%= @agent_id %> (<%= @agent.type %>)
            </div>
          </div>
          <div>
            <strong>Process Info:</strong>
            <div style="font-size: 0.875rem; margin-top: 0.5rem;">
              Mailbox Size: <%= get_mailbox_size(@agent.pid) %><br>
              Heap Size: <%= get_heap_size(@agent.pid) %>KB<br>
              Reductions: <%= get_reductions(@agent.pid) %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions
  defp get_agent_details(agent_id) do
    try do
      case MCPChat.Agents.AgentSupervisor.get_agent(agent_id) do
        {:ok, {pid, type}} ->
          {:ok,
           %{
             id: agent_id,
             type: type,
             pid: pid,
             status: get_agent_status(pid),
             session_id: get_agent_session_id(pid),
             started_at: get_agent_start_time(pid),
             last_activity: DateTime.utc_now(),
             config: get_agent_config(pid),
             memory_usage: get_memory_usage(pid),
             metrics: get_agent_metrics(pid)
           }}

        {:error, _} ->
          {:error, :not_found}
      end
    rescue
      _ -> {:error, :not_found}
    end
  end

  defp get_agent_logs(agent_id) do
    # Try to get logs from agent process or log store
    try do
      case GenServer.call({:via, Registry, {MCPChat.Agents.Registry, agent_id}}, :get_logs, 5000) do
        {:ok, logs} -> logs
        {:error, _} -> []
      end
    rescue
      _ -> []
    catch
      :exit, _ -> []
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
      _ ->
        %{
          messages_processed: 0,
          errors: 0,
          uptime: 0,
          requests_per_minute: 0
        }
    catch
      :exit, _ ->
        %{
          messages_processed: 0,
          errors: 0,
          uptime: 0,
          requests_per_minute: 0
        }
    end
  end

  defp get_agent_metrics(_) do
    %{
      messages_processed: 0,
      errors: 0,
      uptime: 0,
      requests_per_minute: 0
    }
  end

  defp get_mailbox_size(pid) when is_pid(pid) do
    try do
      {:message_queue_len, len} = Process.info(pid, :message_queue_len)
      len
    rescue
      _ -> 0
    catch
      :exit, _ -> 0
    end
  end

  defp get_mailbox_size(_), do: 0

  defp get_heap_size(pid) when is_pid(pid) do
    try do
      {:heap_size, size} = Process.info(pid, :heap_size)
      # Convert words to KB (8 bytes per word)
      div(size * 8, 1024)
    rescue
      _ -> 0
    catch
      :exit, _ -> 0
    end
  end

  defp get_heap_size(_), do: 0

  defp get_reductions(pid) when is_pid(pid) do
    try do
      {:reductions, reds} = Process.info(pid, :reductions)
      reds
    rescue
      _ -> 0
    catch
      :exit, _ -> 0
    end
  end

  defp get_reductions(_), do: 0

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_datetime(_), do: "unknown"

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(_), do: "unknown"

  defp format_duration(seconds) when is_integer(seconds) do
    cond do
      seconds < 60 ->
        "#{seconds}s"

      seconds < 3600 ->
        minutes = div(seconds, 60)
        "#{minutes}m"

      true ->
        hours = div(seconds, 3600)
        minutes = div(rem(seconds, 3600), 60)
        "#{hours}h #{minutes}m"
    end
  end

  defp format_duration(_), do: "0s"

  defp log_color(:error), do: "background: #fef2f2;"
  defp log_color(:warn), do: "background: #fffbeb;"
  defp log_color(:info), do: "background: #f0f9ff;"
  defp log_color(:debug), do: "background: #f9fafb;"
  defp log_color(_), do: ""

  defp level_color(:error), do: "#dc2626"
  defp level_color(:warn), do: "#d97706"
  defp level_color(:info), do: "#2563eb"
  defp level_color(:debug), do: "#6b7280"
  defp level_color(_), do: "#374151"
end
