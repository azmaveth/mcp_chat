defmodule MCPChat.MCP.ServerManager.Server do
  @moduledoc """
  Represents an MCP server with connection status and capabilities.

  Provides a structured way to track server state throughout the connection lifecycle,
  supporting background connections and proper status visibility.
  """

  @type status :: :connecting | :connected | :failed | :disconnected

  @type t :: %__MODULE__{
          name: String.t(),
          config: map(),
          pid: pid() | nil,
          monitor_ref: reference() | nil,
          status: status(),
          capabilities: map(),
          error: term() | nil,
          connected_at: DateTime.t() | nil,
          last_attempt: DateTime.t() | nil,
          health: map()
        }

  defstruct [
    :name,
    :config,
    :pid,
    :monitor_ref,
    status: :connecting,
    capabilities: %{tools: [], resources: [], prompts: []},
    error: nil,
    connected_at: nil,
    last_attempt: nil,
    health: %{
      uptime_start: nil,
      total_requests: 0,
      successful_requests: 0,
      failed_requests: 0,
      avg_response_time: 0.0,
      last_ping: nil,
      consecutive_failures: 0,
      is_healthy: true
    }
  ]

  @doc """
  Creates a new Server struct from configuration.
  """
  @spec new(String.t(), map()) :: t()
  def new(name, config) do
    %__MODULE__{
      name: name,
      config: config,
      status: :connecting,
      last_attempt: DateTime.utc_now()
    }
  end

  @doc """
  Marks server as connected and caches capabilities.
  """
  @spec mark_connected(t(), pid(), reference(), map()) :: t()
  def mark_connected(server, pid, monitor_ref, capabilities \\ %{}) do
    now = DateTime.utc_now()

    %{
      server
      | status: :connected,
        pid: pid,
        monitor_ref: monitor_ref,
        capabilities: normalize_capabilities(capabilities),
        error: nil,
        connected_at: now,
        health:
          Map.merge(server.health, %{
            uptime_start: now,
            consecutive_failures: 0,
            is_healthy: true
          })
    }
  end

  @doc """
  Marks server as failed with error information.
  """
  @spec mark_failed(t(), term()) :: t()
  def mark_failed(server, error) do
    %{
      server
      | status: :failed,
        error: error,
        pid: nil,
        monitor_ref: nil,
        capabilities: %{tools: [], resources: [], prompts: []}
    }
  end

  @doc """
  Marks server as disconnected (was connected but lost connection).
  """
  @spec mark_disconnected(t()) :: t()
  def mark_disconnected(server) do
    %{
      server
      | status: :disconnected,
        pid: nil,
        monitor_ref: nil,
        capabilities: %{tools: [], resources: [], prompts: []}
    }
  end

  @doc """
  Checks if server is ready to handle requests.
  """
  @spec connected?(t()) :: boolean()
  def connected?(%__MODULE__{status: :connected, pid: pid}) when is_pid(pid), do: true
  def connected?(_), do: false

  @doc """
  Gets a displayable status string for the server.
  """
  @spec status_display(t()) :: String.t()
  def status_display(%__MODULE__{status: :connecting}), do: "[CONNECTING]"
  def status_display(%__MODULE__{status: :connected}), do: "[CONNECTED]"
  def status_display(%__MODULE__{status: :failed, error: error}), do: "[FAILED: #{format_error(error)}]"
  def status_display(%__MODULE__{status: :disconnected}), do: "[DISCONNECTED]"

  @doc """
  Gets tools from a connected server.
  """
  @spec get_tools(t()) :: list()
  def get_tools(%__MODULE__{status: :connected, capabilities: %{tools: tools}}), do: tools
  def get_tools(_), do: []

  @doc """
  Gets resources from a connected server.
  """
  @spec get_resources(t()) :: list()
  def get_resources(%__MODULE__{status: :connected, capabilities: %{resources: resources}}), do: resources
  def get_resources(_), do: []

  @doc """
  Gets prompts from a connected server.
  """
  @spec get_prompts(t()) :: list()
  def get_prompts(%__MODULE__{status: :connected, capabilities: %{prompts: prompts}}), do: prompts
  def get_prompts(_), do: []

  @doc """
  Records a successful request for health tracking.
  """
  @spec record_success(t(), non_neg_integer()) :: t()
  def record_success(server, response_time_ms) do
    health = server.health
    total = health.total_requests + 1
    successful = health.successful_requests + 1

    # Calculate new average response time
    current_avg = health.avg_response_time
    new_avg = (current_avg * health.total_requests + response_time_ms) / total

    new_health = %{
      health
      | total_requests: total,
        successful_requests: successful,
        avg_response_time: new_avg,
        last_ping: DateTime.utc_now(),
        consecutive_failures: 0,
        is_healthy: true
    }

    %{server | health: new_health}
  end

  @doc """
  Records a failed request for health tracking.
  """
  @spec record_failure(t()) :: t()
  def record_failure(server) do
    health = server.health
    total = health.total_requests + 1
    failed = health.failed_requests + 1
    consecutive = health.consecutive_failures + 1

    # Mark as unhealthy if too many consecutive failures
    is_healthy = consecutive < 3

    new_health = %{
      health
      | total_requests: total,
        failed_requests: failed,
        consecutive_failures: consecutive,
        is_healthy: is_healthy
    }

    %{server | health: new_health}
  end

  @doc """
  Gets server health status.
  """
  @spec health_status(t()) :: :healthy | :unhealthy | :unknown
  def health_status(%__MODULE__{status: :connected, health: %{is_healthy: true}}), do: :healthy
  def health_status(%__MODULE__{status: :connected, health: %{is_healthy: false}}), do: :unhealthy
  def health_status(_), do: :unknown

  @doc """
  Gets server uptime in seconds.
  """
  @spec uptime_seconds(t()) :: non_neg_integer() | nil
  def uptime_seconds(%__MODULE__{health: %{uptime_start: nil}}), do: nil

  def uptime_seconds(%__MODULE__{health: %{uptime_start: start_time}}) do
    DateTime.diff(DateTime.utc_now(), start_time, :second)
  end

  @doc """
  Gets success rate as a percentage.
  """
  @spec success_rate(t()) :: float()
  def success_rate(%__MODULE__{health: %{total_requests: 0}}), do: 0.0

  def success_rate(%__MODULE__{health: %{total_requests: total, successful_requests: successful}}) do
    successful / total * 100.0
  end

  # Private helpers

  defp normalize_capabilities(capabilities) when is_map(capabilities) do
    %{
      tools: Map.get(capabilities, :tools, Map.get(capabilities, "tools", [])),
      resources: Map.get(capabilities, :resources, Map.get(capabilities, "resources", [])),
      prompts: Map.get(capabilities, :prompts, Map.get(capabilities, "prompts", []))
    }
  end

  defp normalize_capabilities(_), do: %{tools: [], resources: [], prompts: []}

  defp format_error(error) when is_atom(error), do: to_string(error)
  defp format_error(error) when is_binary(error), do: error
  defp format_error({:error, reason}), do: format_error(reason)
  defp format_error(error), do: inspect(error)
end
