defmodule MCPChatWeb.SessionLive do
  use MCPChatWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to session events
      Phoenix.PubSub.subscribe(MCPChat.PubSub, "system:sessions")
    end

    {:ok,
     socket
     |> assign(:page_title, "Session Management")
     |> assign(:sessions, get_all_sessions())
     |> assign(:selected_session, nil)
     |> assign(:show_create_form, false)
     |> assign(:new_session_name, "")}
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
  def handle_info({:session_updated, session_id, updates}, socket) do
    sessions = update_session_in_list(socket.assigns.sessions, session_id, updates)
    {:noreply, assign(socket, :sessions, sessions)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_session", %{"session_id" => session_id}, socket) do
    {:noreply, assign(socket, :selected_session, session_id)}
  end

  @impl true
  def handle_event("refresh_sessions", _params, socket) do
    {:noreply, assign(socket, :sessions, get_all_sessions())}
  end

  @impl true
  def handle_event("show_create_form", _params, socket) do
    {:noreply, assign(socket, :show_create_form, true)}
  end

  @impl true
  def handle_event("hide_create_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_create_form, false)
     |> assign(:new_session_name, "")}
  end

  @impl true
  def handle_event("create_session", %{"name" => name}, socket) when name != "" do
    case MCPChat.Gateway.create_session("web_user", source: :web, name: name) do
      {:ok, session_id} ->
        {:noreply,
         socket
         |> assign(:show_create_form, false)
         |> assign(:new_session_name, "")
         |> put_flash(:info, "Session '#{name}' created successfully")
         |> redirect(to: "/sessions/#{session_id}/chat")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create session: #{reason}")}
    end
  end

  @impl true
  def handle_event("create_session", _params, socket) do
    {:noreply, put_flash(socket, :error, "Session name cannot be empty")}
  end

  @impl true
  def handle_event("delete_session", %{"session_id" => session_id}, socket) do
    case MCPChat.Gateway.destroy_session(session_id) do
      :ok ->
        sessions = Enum.reject(socket.assigns.sessions, &(&1.id == session_id))

        {:noreply,
         socket
         |> assign(:sessions, sessions)
         |> put_flash(:info, "Session deleted successfully")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete session: #{reason}")}
    end
  end

  @impl true
  def handle_event("archive_session", %{"session_id" => session_id}, socket) do
    case MCPChat.Gateway.archive_session(session_id) do
      :ok ->
        sessions = update_session_status(socket.assigns.sessions, session_id, :archived)

        {:noreply,
         socket
         |> assign(:sessions, sessions)
         |> put_flash(:info, "Session archived successfully")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to archive session: #{reason}")}
    end
  end

  @impl true
  def handle_event("restore_session", %{"session_id" => session_id}, socket) do
    case MCPChat.Gateway.restore_session(session_id) do
      :ok ->
        sessions = update_session_status(socket.assigns.sessions, session_id, :active)

        {:noreply,
         socket
         |> assign(:sessions, sessions)
         |> put_flash(:info, "Session restored successfully")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to restore session: #{reason}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="session-management">
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
        <h2>Session Management</h2>
        <div style="display: flex; gap: 0.5rem;">
          <button class="btn" phx-click="show_create_form">
            Create New Session
          </button>
          <button class="btn" phx-click="refresh_sessions">
            Refresh
          </button>
        </div>
      </div>

      <!-- Create Session Form -->
      <%= if @show_create_form do %>
        <div class="card" style="margin-bottom: 1rem;">
          <h3>Create New Session</h3>
          <form phx-submit="create_session" style="display: flex; gap: 0.5rem; align-items: end;">
            <div style="flex: 1;">
              <label style="display: block; margin-bottom: 0.25rem; font-weight: bold;">Session Name</label>
              <input 
                type="text" 
                name="name" 
                value={@new_session_name}
                placeholder="Enter session name..."
                style="width: 100%; padding: 0.5rem; border: 1px solid #d1d5db; border-radius: 4px;"
                autocomplete="off"
                required
              />
            </div>
            <button type="submit" class="btn" style="background: #059669;">
              Create
            </button>
            <button type="button" class="btn" phx-click="hide_create_form">
              Cancel
            </button>
          </form>
        </div>
      <% end %>

      <!-- Sessions List -->
      <div class="card">
        <h3>All Sessions (<%= length(@sessions) %>)</h3>
        
        <%= if Enum.empty?(@sessions) do %>
          <p>No sessions found. Create a new one to get started!</p>
        <% else %>
          <div style="display: grid; gap: 1rem;">
            <%= for session <- @sessions do %>
              <div 
                class="session-card"
                style={"border: 1px solid #e5e7eb; border-radius: 4px; padding: 1rem; cursor: pointer; #{if @selected_session == session.id, do: "border-color: #3b82f6; background: #eff6ff;", else: ""}"}
                phx-click="select_session"
                phx-value-session_id={session.id}
              >
                <div style="display: flex; justify-content: space-between; align-items: center;">
                  <div style="flex: 1;">
                    <div style="display: flex; align-items: center; gap: 0.5rem;">
                      <span class={"status-indicator status-#{session.status}"}></span>
                      <strong><%= session.name || session.id %></strong>
                      <span style="font-size: 0.875rem; color: #6b7280;">(ID: <%= session.id %>)</span>
                    </div>
                    
                    <div style="margin-top: 0.5rem; font-size: 0.875rem; color: #6b7280;">
                      <div>Status: <%= session.status %></div>
                      <div>Messages: <%= session.message_count || 0 %></div>
                      <div>Created: <%= format_datetime(session.created_at) %></div>
                      <div>Last Activity: <%= format_datetime(session.last_activity) %></div>
                      <%= if session.current_model do %>
                        <div>Model: <%= session.current_model %></div>
                      <% end %>
                      <%= if session.agent_id do %>
                        <div>Agent: <a href={"/agents/#{session.agent_id}"} style="color: #3b82f6;"><%= session.agent_id %></a></div>
                      <% end %>
                    </div>
                  </div>
                  
                  <div style="display: flex; gap: 0.5rem;">
                    <%= if session.status == :active do %>
                      <a href={"/sessions/#{session.id}/chat"} class="btn">
                        Open Chat
                      </a>
                      <button 
                        class="btn" 
                        style="background: #f59e0b;"
                        phx-click="archive_session"
                        phx-value-session_id={session.id}
                      >
                        Archive
                      </button>
                    <% else %>
                      <button 
                        class="btn" 
                        style="background: #059669;"
                        phx-click="restore_session"
                        phx-value-session_id={session.id}
                      >
                        Restore
                      </button>
                    <% end %>
                    
                    <button 
                      class="btn" 
                      style="background: #ef4444;"
                      phx-click="delete_session"
                      phx-value-session_id={session.id}
                      onclick="return confirm('Are you sure you want to delete this session? This action cannot be undone.')"
                    >
                      Delete
                    </button>
                  </div>
                </div>

                <%= if @selected_session == session.id do %>
                  <div style="margin-top: 1rem; padding-top: 1rem; border-top: 1px solid #e5e7eb;">
                    <h4>Session Details</h4>
                    <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-top: 0.5rem;">
                      <div>
                        <strong>User ID:</strong> <%= session.user_id || "anonymous" %>
                      </div>
                      <div>
                        <strong>Source:</strong> <%= session.source || "unknown" %>
                      </div>
                      <div>
                        <strong>Memory Usage:</strong> <%= session.memory_usage || 0 %>KB
                      </div>
                      <%= if session.context_files do %>
                        <div>
                          <strong>Context Files:</strong> <%= length(session.context_files) %>
                        </div>
                      <% end %>
                      <%= if session.settings do %>
                        <div>
                          <strong>Temperature:</strong> <%= session.settings.temperature || "default" %>
                        </div>
                        <div>
                          <strong>Max Tokens:</strong> <%= session.settings.max_tokens || "default" %>
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

      <!-- Session Statistics -->
      <div class="card">
        <h3>Session Statistics</h3>
        <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 1rem;">
          <div style="text-align: center; padding: 1rem; border: 1px solid #e5e7eb; border-radius: 4px;">
            <div style="font-size: 2rem; font-weight: bold; color: #059669;"><%= count_sessions_by_status(@sessions, :active) %></div>
            <div>Active</div>
          </div>
          <div style="text-align: center; padding: 1rem; border: 1px solid #e5e7eb; border-radius: 4px;">
            <div style="font-size: 2rem; font-weight: bold; color: #d97706;"><%= count_sessions_by_status(@sessions, :archived) %></div>
            <div>Archived</div>
          </div>
          <div style="text-align: center; padding: 1rem; border: 1px solid #e5e7eb; border-radius: 4px;">
            <div style="font-size: 2rem; font-weight: bold; color: #6b7280;"><%= count_sessions_by_status(@sessions, :idle) %></div>
            <div>Idle</div>
          </div>
          <div style="text-align: center; padding: 1rem; border: 1px solid #e5e7eb; border-radius: 4px;">
            <div style="font-size: 2rem; font-weight: bold; color: #4f46e5;"><%= length(@sessions) %></div>
            <div>Total</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions
  defp get_all_sessions do
    try do
      case MCPChat.Gateway.list_active_sessions() do
        {:ok, sessions} -> sessions
        {:error, _} -> []
      end
    rescue
      _ ->
        # Mock data for demonstration
        [
          %{
            id: "session_demo_1",
            name: "Demo Session 1",
            status: :active,
            message_count: 5,
            created_at: DateTime.utc_now() |> DateTime.add(-3600),
            last_activity: DateTime.utc_now() |> DateTime.add(-300),
            current_model: "claude-3-sonnet",
            user_id: "web_user",
            source: :web,
            agent_id: "agent_123",
            memory_usage: 512,
            context_files: ["file1.txt", "file2.py"],
            settings: %{temperature: 0.7, max_tokens: 4000}
          },
          %{
            id: "session_demo_2",
            name: "Demo Session 2",
            status: :archived,
            message_count: 12,
            created_at: DateTime.utc_now() |> DateTime.add(-7200),
            last_activity: DateTime.utc_now() |> DateTime.add(-1800),
            current_model: "gpt-4o",
            user_id: "web_user",
            source: :web,
            agent_id: nil,
            memory_usage: 1024,
            context_files: [],
            settings: %{temperature: 0.5, max_tokens: 2000}
          }
        ]
    end
  end

  defp update_session_in_list(sessions, session_id, updates) do
    Enum.map(sessions, fn session ->
      if session.id == session_id do
        Map.merge(session, updates)
      else
        session
      end
    end)
  end

  defp update_session_status(sessions, session_id, new_status) do
    Enum.map(sessions, fn session ->
      if session.id == session_id do
        %{session | status: new_status}
      else
        session
      end
    end)
  end

  defp count_sessions_by_status(sessions, status) do
    Enum.count(sessions, &(&1.status == status))
  end

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_datetime(_), do: "unknown"
end
