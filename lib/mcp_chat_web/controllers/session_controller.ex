defmodule MCPChatWeb.SessionController do
  use MCPChatWeb, :controller

  alias MCPChat.Gateway

  def index(conn, _params) do
    case Gateway.list_active_sessions() do
      {:ok, sessions} ->
        # Transform sessions for JSON response
        sessions_data =
          Enum.map(sessions, fn session ->
            %{
              id: session.session_id,
              user_id: session.user_id,
              status: session.status,
              message_count: length(Map.get(session, :messages, [])),
              created_at: Map.get(session, :created_at, DateTime.utc_now()),
              current_model: get_in(session, [:settings, :llm_backend]),
              agent_id: Map.get(session, :agent_id)
            }
          end)

        json(conn, %{sessions: sessions_data})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to list sessions", reason: inspect(reason)})
    end
  end

  def create(conn, params) do
    user_id = Map.get(params, "user_id", "web_user")

    opts = [
      source: :web,
      name: Map.get(params, "name", "Web Session"),
      settings: Map.get(params, "settings", %{})
    ]

    case Gateway.create_session(user_id, opts) do
      {:ok, session_id} ->
        # Broadcast session creation
        Phoenix.PubSub.broadcast(
          MCPChat.PubSub,
          "system:sessions",
          {:session_created,
           %{
             id: session_id,
             user_id: user_id,
             created_at: DateTime.utc_now()
           }}
        )

        conn
        |> put_status(:created)
        |> json(%{
          session_id: session_id,
          message: "Session created successfully"
        })

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to create session", reason: inspect(reason)})
    end
  end

  def show(conn, %{"id" => session_id}) do
    case Gateway.get_session_state(session_id) do
      {:ok, session_state} ->
        json(conn, %{session: format_session_state(session_state)})

      {:error, :session_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Session not found"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to get session", reason: inspect(reason)})
    end
  end

  def delete(conn, %{"id" => session_id}) do
    case Gateway.destroy_session(session_id) do
      :ok ->
        # Broadcast session deletion
        Phoenix.PubSub.broadcast(MCPChat.PubSub, "system:sessions", {:session_ended, session_id})

        json(conn, %{message: "Session deleted successfully"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to delete session", reason: inspect(reason)})
    end
  end

  # Helper to format session state for API response
  defp format_session_state(state) do
    %{
      session_id: state.session_id,
      user_id: Map.get(state, :user_id, "unknown"),
      status: Map.get(state, :status, :active),
      messages: Enum.map(Map.get(state, :messages, []), &format_message/1),
      context_files: Map.get(state, :context_files, []),
      settings: Map.get(state, :settings, %{}),
      created_at: Map.get(state, :created_at, DateTime.utc_now()),
      last_activity: Map.get(state, :last_activity, DateTime.utc_now())
    }
  end

  defp format_message(message) do
    %{
      id: Map.get(message, :id, generate_id()),
      role: message.role,
      content: message.content,
      timestamp: Map.get(message, :timestamp, DateTime.utc_now())
    }
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
