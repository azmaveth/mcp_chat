defmodule MCPChatWeb.CommandController do
  use MCPChatWeb, :controller

  alias MCPChat.Gateway

  def execute(conn, %{"id" => session_id} = params) do
    command = Map.get(params, "command", "")

    case Gateway.execute_command(session_id, command) do
      {:ok, result} ->
        json(conn, %{
          command: command,
          result: result,
          status: "success"
        })

      {:error, :session_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Session not found"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to execute command", reason: inspect(reason)})
    end
  end
end
