defmodule MCPChatWeb.ChatLive do
  use MCPChatWeb, :live_view

  @impl true
  def mount(%{"session_id" => session_id}, _session, socket) do
    if connected?(socket) do
      # Subscribe to session events
      Phoenix.PubSub.subscribe(MCPChat.PubSub, "session:#{session_id}")
    end

    # Try to get session state or create new session
    {session_data, commands} = get_or_create_session(session_id)

    {:ok,
     socket
     |> assign(:page_title, "Chat Session #{session_id}")
     |> assign(:session_id, session_id)
     |> assign(:messages, session_data.messages || [])
     |> assign(:session_state, session_data.state || :idle)
     |> assign(:available_commands, commands)
     |> assign(:new_message, "")
     |> assign(:command_input, "")
     |> assign(:show_commands, false)}
  end

  @impl true
  def handle_event("send_message", %{"message" => content}, socket) when content != "" do
    session_id = socket.assigns.session_id

    # Add user message immediately for responsiveness
    user_message = %{
      id: generate_id(),
      role: :user,
      content: content,
      timestamp: DateTime.utc_now()
    }

    messages = socket.assigns.messages ++ [user_message]

    # Send to backend
    case MCPChat.Gateway.send_message(session_id, content) do
      :ok ->
        {:noreply,
         socket
         |> assign(:messages, messages)
         |> assign(:new_message, "")
         |> assign(:session_state, :thinking)}

      {:error, :session_not_found} ->
        # Try to create session and retry
        create_session_and_send(session_id, content)

        {:noreply,
         socket
         |> assign(:messages, messages)
         |> assign(:new_message, "")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to send message: #{reason}")}
    end
  end

  @impl true
  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("execute_command", %{"command" => command}, socket) when command != "" do
    session_id = socket.assigns.session_id

    case MCPChat.Gateway.execute_command(session_id, command) do
      :ok ->
        {:noreply,
         socket
         |> assign(:command_input, "")
         |> assign(:session_state, :executing)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Command failed: #{reason}")}
    end
  end

  @impl true
  def handle_event("execute_command", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_commands", _params, socket) do
    {:noreply, assign(socket, :show_commands, !socket.assigns.show_commands)}
  end

  @impl true
  def handle_event("clear_session", _params, socket) do
    {:noreply,
     socket
     |> assign(:messages, [])
     |> assign(:session_state, :idle)}
  end

  # Handle real-time updates from the backend
  @impl true
  def handle_info(%{type: :message_added, message: message}, socket) do
    messages = socket.assigns.messages ++ [message]
    {:noreply, assign(socket, :messages, messages)}
  end

  @impl true
  def handle_info(%{type: :stream_chunk, chunk: chunk, message_id: message_id}, socket) do
    # Update the message with the new chunk
    messages = update_message_content(socket.assigns.messages, message_id, chunk)
    {:noreply, assign(socket, :messages, messages)}
  end

  @impl true
  def handle_info(%{type: :session_state_changed, new_state: state}, socket) do
    {:noreply, assign(socket, :session_state, state)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="chat-interface">
      <div class="card">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
          <h2>Chat Session: <%= @session_id %></h2>
          <div>
            <span class={"status-indicator status-#{@session_state}"}></span>
            <span style="text-transform: capitalize;"><%= @session_state %></span>
          </div>
        </div>

        <!-- Messages Area -->
        <div class="messages-container" style="height: 400px; overflow-y: auto; border: 1px solid #e5e7eb; border-radius: 4px; padding: 1rem; margin-bottom: 1rem; background: #fafafa;">
          <%= if Enum.empty?(@messages) do %>
            <div style="text-align: center; color: #6b7280; margin-top: 2rem;">
              <p>No messages yet. Start a conversation!</p>
            </div>
          <% else %>
            <%= for message <- @messages do %>
              <div class={"chat-message #{message.role}-message"}>
                <div style="font-weight: bold; margin-bottom: 0.25rem;">
                  <%= String.capitalize(to_string(message.role)) %>
                  <span style="font-weight: normal; font-size: 0.75rem; color: #6b7280;">
                    <%= format_time(message.timestamp) %>
                  </span>
                </div>
                <div style="white-space: pre-wrap;"><%= message.content %></div>
              </div>
            <% end %>
          <% end %>
        </div>

        <!-- Message Input -->
        <form phx-submit="send_message" style="display: flex; gap: 0.5rem;">
          <input 
            type="text" 
            name="message" 
            value={@new_message}
            phx-change="update_message"
            placeholder="Type your message..."
            style="flex: 1; padding: 0.5rem; border: 1px solid #d1d5db; border-radius: 4px;"
            autocomplete="off"
          />
          <button type="submit" class="btn" disabled={@session_state == :thinking}>
            <%= if @session_state == :thinking, do: "Thinking...", else: "Send" %>
          </button>
        </form>
      </div>

      <!-- Commands Panel -->
      <div class="card">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
          <h3>Commands</h3>
          <button class="btn" phx-click="toggle_commands">
            <%= if @show_commands, do: "Hide Commands", else: "Show Commands" %>
          </button>
        </div>

        <%= if @show_commands do %>
          <form phx-submit="execute_command" style="margin-bottom: 1rem;">
            <div style="display: flex; gap: 0.5rem;">
              <input 
                type="text" 
                name="command" 
                value={@command_input}
                placeholder="Enter command (e.g., /model list, /mcp servers)"
                style="flex: 1; padding: 0.5rem; border: 1px solid #d1d5db; border-radius: 4px;"
                autocomplete="off"
              />
              <button type="submit" class="btn">Execute</button>
            </div>
          </form>

          <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 0.5rem;">
            <%= for command <- @available_commands do %>
              <button 
                class="btn" 
                style="text-align: left; background: #f3f4f6; color: #374151;"
                phx-click="execute_command"
                phx-value-command={command.command}
              >
                <div style="font-weight: bold;"><%= command.command %></div>
                <div style="font-size: 0.75rem; opacity: 0.8;"><%= command.description %></div>
              </button>
            <% end %>
          </div>
        <% end %>

        <div style="margin-top: 1rem;">
          <button class="btn" phx-click="clear_session" style="background: #ef4444;">
            Clear Session
          </button>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions
  defp get_or_create_session(session_id) do
    case MCPChat.Gateway.get_session_state(session_id) do
      {:ok, session_data} ->
        commands = get_available_commands(session_id)
        {session_data, commands}

      {:error, :not_found} ->
        # Create new session
        case MCPChat.Gateway.create_session("web_user", source: :web) do
          {:ok, new_session_id} ->
            session_data = %{messages: [], state: :idle}
            commands = get_available_commands(new_session_id)
            {session_data, commands}

          {:error, _} ->
            # Return empty session as fallback
            {%{messages: [], state: :idle}, get_default_commands()}
        end

      {:error, _} ->
        {%{messages: [], state: :idle}, get_default_commands()}
    end
  end

  defp get_available_commands(session_id) do
    # Try to get dynamic commands from agents
    try do
      case MCPChat.CLI.AgentBridge.get_available_commands(session_id) do
        {:ok, commands} -> commands
        {:error, _} -> get_default_commands()
      end
    rescue
      _ -> get_default_commands()
    end
  end

  defp get_default_commands do
    [
      %{command: "/help", description: "Show available commands"},
      %{command: "/model list", description: "List available models"},
      %{command: "/mcp servers", description: "List MCP servers"},
      %{command: "/mcp tools", description: "List available tools"},
      %{command: "/cost", description: "Show cost information"},
      %{command: "/context list", description: "Show context files"},
      %{command: "/sessions", description: "List sessions"},
      %{command: "/clear", description: "Clear conversation"}
    ]
  end

  defp create_session_and_send(session_id, content) do
    with {:ok, new_session_id} <- MCPChat.Gateway.create_session("web_user", source: :web),
         :ok <- MCPChat.Gateway.send_message(new_session_id, content) do
      :ok
    else
      error -> error
    end
  end

  defp update_message_content(messages, message_id, chunk) do
    Enum.map(messages, fn message ->
      if message.id == message_id do
        current_content = message.content || ""
        %{message | content: current_content <> chunk}
      else
        message
      end
    end)
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(_), do: ""
end
