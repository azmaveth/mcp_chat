defmodule MCPChatWeb.AgentController do
  use MCPChatWeb, :controller

  alias MCPChat.Agents.AgentSupervisor
  alias MCPChat.Agents.SessionManager

  def index(conn, _params) do
    case AgentSupervisor.list_agents() do
      {:ok, agents} ->
        agents_data =
          Enum.map(agents, fn {id, pid, type} ->
            %{
              id: id,
              type: type,
              pid: inspect(pid),
              status: get_agent_status(pid),
              session_id: get_agent_session_id(pid),
              started_at: get_agent_start_time(pid),
              last_activity: DateTime.utc_now(),
              memory_usage: get_memory_usage(pid),
              metrics: get_agent_metrics(pid)
            }
          end)

        json(conn, %{agents: agents_data})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to list agents", reason: inspect(reason)})
    end
  end

  def show(conn, %{"id" => agent_id}) do
    case AgentSupervisor.get_agent(agent_id) do
      {:ok, {pid, type}} ->
        agent_data = %{
          id: agent_id,
          type: type,
          pid: inspect(pid),
          status: get_agent_status(pid),
          session_id: get_agent_session_id(pid),
          started_at: get_agent_start_time(pid),
          last_activity: DateTime.utc_now(),
          memory_usage: get_memory_usage(pid),
          metrics: get_agent_metrics(pid),
          config: get_agent_config(pid)
        }

        json(conn, %{agent: agent_data})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Agent not found"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to get agent", reason: inspect(reason)})
    end
  end

  def status(conn, %{"id" => agent_id}) do
    case AgentSupervisor.get_agent(agent_id) do
      {:ok, {pid, _type}} ->
        status = %{
          agent_id: agent_id,
          alive: Process.alive?(pid),
          status: get_agent_status(pid),
          memory_usage: get_memory_usage(pid),
          message_queue_length: get_message_queue_length(pid),
          last_activity: DateTime.utc_now()
        }

        json(conn, status)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Agent not found"})
    end
  end

  # Helper functions
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

  defp get_memory_usage(pid) when is_pid(pid) do
    try do
      {:memory, memory} = Process.info(pid, :memory)
      # Convert to KB
      div(memory, 1024)
    rescue
      _ -> 0
    catch
      :exit, _ -> 0
    end
  end

  defp get_memory_usage(_), do: 0

  defp get_message_queue_length(pid) when is_pid(pid) do
    try do
      {:message_queue_len, len} = Process.info(pid, :message_queue_len)
      len
    rescue
      _ -> 0
    catch
      :exit, _ -> 0
    end
  end

  defp get_message_queue_length(_), do: 0

  defp get_agent_metrics(pid) when is_pid(pid) do
    try do
      GenServer.call(pid, :get_metrics, 1000)
    rescue
      _ -> %{messages_processed: 0, errors: 0}
    catch
      :exit, _ -> %{messages_processed: 0, errors: 0}
    end
  end

  defp get_agent_metrics(_), do: %{messages_processed: 0, errors: 0}

  defp get_agent_config(pid) when is_pid(pid) do
    try do
      GenServer.call(pid, :get_config, 1000)
    rescue
      _ -> %{}
    catch
      :exit, _ -> %{}
    end
  end

  defp get_agent_config(_), do: %{}
end
