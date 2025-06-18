defmodule MCPChatWeb.SessionListLive do
  use MCPChatWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sessions")
     |> assign(:sessions, get_sessions())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="sessions-list">
      <h2>Chat Sessions</h2>
      
      <div class="card">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
          <h3>Active Sessions</h3>
          <button class="btn" phx-click="create_session">
            Create New Session
          </button>
        </div>
        
        <%= if Enum.empty?(@sessions) do %>
          <p>No sessions found. Create a new one to get started!</p>
        <% else %>
          <div style="display: grid; gap: 1rem;">
            <%= for session <- @sessions do %>
              <div style="display: flex; align-items: center; padding: 1rem; border: 1px solid #e5e7eb; border-radius: 4px;">
                <div style="flex: 1;">
                  <strong>Session <%= session.id %></strong>
                  <div style="font-size: 0.875rem; color: #6b7280;">
                    Messages: <%= session.message_count %> | 
                    Created: <%= Calendar.strftime(session.created_at, "%Y-%m-%d %H:%M") %>
                  </div>
                </div>
                <div style="display: flex; gap: 0.5rem;">
                  <a href={"/sessions/#{session.id}/chat"} class="btn">Open Chat</a>
                  <button class="btn" style="background: #ef4444;" phx-click="delete_session" phx-value-id={session.id}>
                    Delete
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("create_session", _params, socket) do
    case MCPChat.Gateway.create_session("web_user", source: :web) do
      {:ok, session_id} ->
        {:noreply, redirect(socket, to: "/sessions/#{session_id}/chat")}

      {:error, _reason} ->
        # Create a demo session for now
        demo_id = "demo_#{:rand.uniform(1000)}"
        {:noreply, redirect(socket, to: "/sessions/#{demo_id}/chat")}
    end
  end

  @impl true
  def handle_event("delete_session", %{"id" => session_id}, socket) do
    # Try to delete session
    MCPChat.Gateway.destroy_session(session_id)

    # Refresh sessions list
    sessions = get_sessions()
    {:noreply, assign(socket, :sessions, sessions)}
  end

  defp get_sessions do
    case MCPChat.Gateway.list_sessions() do
      {:ok, sessions} ->
        sessions

      {:error, _} ->
        # Return demo sessions for now
        [
          %{
            id: "demo_session_1",
            message_count: 5,
            created_at: DateTime.utc_now() |> DateTime.add(-3600)
          },
          %{
            id: "demo_session_2",
            message_count: 12,
            created_at: DateTime.utc_now() |> DateTime.add(-7200)
          }
        ]
    end
  end
end
