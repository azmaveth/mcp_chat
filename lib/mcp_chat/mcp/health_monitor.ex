defmodule MCPChat.MCP.HealthMonitor do
  @moduledoc """
  Monitors the health of MCP servers by periodically pinging them
  and tracking response times and success rates.

  Automatically disables unhealthy servers and provides health metrics.
  """

  use GenServer
  alias MCPChat.MCP.{ServerManager, ServerWrapper}
  alias MCPChat.MCP.ServerManager.Server
  require Logger

  # 30 seconds
  @ping_interval 30_000
  # 5 seconds
  @health_check_timeout 5_000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets health metrics for all servers.
  """
  def get_health_metrics do
    GenServer.call(__MODULE__, :get_health_metrics)
  end

  @doc """
  Forces a health check for all connected servers.
  """
  def force_health_check do
    GenServer.cast(__MODULE__, :force_health_check)
  end

  @doc """
  Records a successful operation for a server.
  """
  def record_success(server_name, response_time_ms) do
    GenServer.cast(__MODULE__, {:record_success, server_name, response_time_ms})
  end

  @doc """
  Records a failed operation for a server.
  """
  def record_failure(server_name) do
    GenServer.cast(__MODULE__, {:record_failure, server_name})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Schedule periodic health checks
    schedule_health_check()
    {:ok, %{}}
  end

  @impl true
  def handle_call(:get_health_metrics, _from, state) do
    metrics = collect_health_metrics()
    {:reply, metrics, state}
  end

  @impl true
  def handle_cast(:force_health_check, state) do
    perform_health_checks()
    {:noreply, state}
  end

  @impl true
  def handle_cast({:record_success, server_name, response_time_ms}, state) do
    ServerManager.record_server_success(server_name, response_time_ms)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:record_failure, server_name}, state) do
    ServerManager.record_server_failure(server_name)
    check_server_health(server_name)
    {:noreply, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    perform_health_checks()
    schedule_health_check()
    {:noreply, state}
  end

  # Private functions

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @ping_interval)
  end

  defp perform_health_checks do
    case ServerManager.list_servers_with_status() do
      servers when is_list(servers) ->
        servers
        |> Enum.filter(fn %{server: server} -> server.status == :connected end)
        |> Enum.each(&ping_server/1)

      _ ->
        Logger.debug("No servers to health check")
    end
  end

  defp ping_server(%{name: name, server: server}) do
    if server.pid do
      start_time = System.monotonic_time(:millisecond)

      # Simple ping by listing tools (lightweight operation)
      case ServerWrapper.get_tools(server.pid) do
        {:ok, _tools} ->
          response_time = System.monotonic_time(:millisecond) - start_time
          record_success(name, response_time)

        {:error, reason} ->
          Logger.warning("Health check failed for server '#{name}': #{inspect(reason)}")
          record_failure(name)
      end
    end
  end

  defp check_server_health(server_name) do
    case ServerManager.get_server_info(server_name) do
      {:ok, server} ->
        case Server.health_status(server) do
          :unhealthy ->
            Logger.warning("Server '#{server_name}' marked as unhealthy, auto-disabling")
            ServerManager.disable_unhealthy_server(server_name)

          _ ->
            :ok
        end

      {:error, _} ->
        :ok
    end
  end

  defp collect_health_metrics do
    case ServerManager.list_servers_with_status() do
      servers when is_list(servers) ->
        Enum.map(servers, fn %{name: name, server: server} ->
          %{
            name: name,
            status: server.status,
            health_status: Server.health_status(server),
            uptime_seconds: Server.uptime_seconds(server),
            success_rate: Server.success_rate(server),
            avg_response_time: server.health.avg_response_time,
            total_requests: server.health.total_requests,
            consecutive_failures: server.health.consecutive_failures,
            last_ping: server.health.last_ping
          }
        end)

      _ ->
        []
    end
  end
end
