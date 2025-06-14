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
          last_attempt: DateTime.t() | nil
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
    last_attempt: nil
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
    %{
      server
      | status: :connected,
        pid: pid,
        monitor_ref: monitor_ref,
        capabilities: normalize_capabilities(capabilities),
        error: nil,
        connected_at: DateTime.utc_now()
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
