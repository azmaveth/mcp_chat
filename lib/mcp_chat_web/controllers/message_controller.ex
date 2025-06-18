defmodule MCPChatWeb.MessageController do
  use MCPChatWeb, :controller

  alias MCPChat.Gateway

  def create(conn, %{"id" => session_id} = params) do
    message = Map.get(params, "message", "")

    case Gateway.send_message(session_id, message) do
      :ok ->
        # Broadcast message event
        Phoenix.PubSub.broadcast(MCPChat.PubSub, "session:#{session_id}", %{
          type: :message_added,
          message: %{
            id: generate_id(),
            role: :user,
            content: message,
            timestamp: DateTime.utc_now()
          }
        })

        json(conn, %{
          message: "Message sent successfully",
          status: "processing"
        })

      {:error, :session_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Session not found"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to send message", reason: inspect(reason)})
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
