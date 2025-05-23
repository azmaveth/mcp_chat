defmodule MCPChat.MCP.Server do
  @moduledoc """
  Manages MCP server connections, supporting both stdio and SSE transports.
  """
  use GenServer

  alias MCPChat.MCP.StdioClient
  alias MCPChat.MCP.SSEClient

  require Logger

  defstruct [:name, :transport, :command, :url, :env, :port, :pid, :client_pid, :status, :capabilities]

  # Client API

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(name))
  end

  def connect(name) do
    GenServer.call(via_tuple(name), :connect)
  end

  def disconnect(name) do
    GenServer.call(via_tuple(name), :disconnect)
  end

  def get_status(name) do
    GenServer.call(via_tuple(name), :get_status)
  end

  def get_tools(name) do
    GenServer.call(via_tuple(name), :get_tools)
  end

  def call_tool(name, tool_name, arguments) do
    GenServer.call(via_tuple(name), {:call_tool, tool_name, arguments}, 30_000)
  end

  def get_resources(name) do
    GenServer.call(via_tuple(name), :get_resources)
  end

  def read_resource(name, uri) do
    GenServer.call(via_tuple(name), {:read_resource, uri}, 30_000)
  end

  def get_prompts(name) do
    GenServer.call(via_tuple(name), :get_prompts)
  end

  def get_prompt(name, prompt_name, arguments \\ %{}) do
    GenServer.call(via_tuple(name), {:get_prompt, prompt_name, arguments})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    transport = determine_transport(opts)

    state = %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      transport: transport,
      command: Keyword.get(opts, :command),
      url: Keyword.get(opts, :url),
      env: Keyword.get(opts, :env, %{}),
      port: nil,
      pid: nil,
      client_pid: nil,
      status: :disconnected,
      capabilities: %{}
    }

    # Auto-connect if requested
    if Keyword.get(opts, :auto_connect, true) do
      send(self(), :connect)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:connect, _from, %{status: :connected} = state) do
    {:reply, {:ok, :already_connected}, state}
  end

  @impl true
  def handle_call(:connect, _from, state) do
    case start_server_process(state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:disconnect, _from, state) do
    new_state = stop_server_process(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      name: state.name,
      transport: state.transport,
      status: state.status,
      capabilities: state.capabilities
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:get_tools, _from, %{status: :connected, client_pid: client, transport: transport} = state) do
    result =
      case transport do
        :stdio ->
          StdioClient.list_tools(client)

        :sse ->
          SSEClient.list_tools(client)
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_tools, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_call(
        {:call_tool, tool_name, arguments},
        _from,
        %{status: :connected, client_pid: client, transport: transport} = state
      ) do
    result =
      case transport do
        :stdio ->
          StdioClient.call_tool(client, tool_name, arguments)

        :sse ->
          SSEClient.call_tool(client, tool_name, arguments)
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:call_tool, _, _}, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_call(:get_resources, _from, %{status: :connected, client_pid: client, transport: transport} = state) do
    result =
      case transport do
        :stdio ->
          StdioClient.list_resources(client)

        :sse ->
          SSEClient.list_resources(client)
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_resources, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_call({:read_resource, uri}, _from, %{status: :connected, client_pid: client, transport: transport} = state) do
    result =
      case transport do
        :stdio ->
          StdioClient.read_resource(client, uri)

        :sse ->
          SSEClient.read_resource(client, uri)
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:read_resource, _}, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_call(:get_prompts, _from, %{status: :connected, client_pid: client, transport: transport} = state) do
    result =
      case transport do
        :stdio ->
          StdioClient.list_prompts(client)

        :sse ->
          SSEClient.list_prompts(client)
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_prompts, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_call(
        {:get_prompt, prompt_name, arguments},
        _from,
        %{status: :connected, client_pid: client, transport: transport} = state
      ) do
    result =
      case transport do
        :stdio ->
          StdioClient.get_prompt(client, prompt_name, arguments)

        :sse ->
          SSEClient.get_prompt(client, prompt_name, arguments)
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_prompt, _, _}, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case start_server_process(state) do
      {:ok, new_state} ->
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to auto-connect MCP server #{state.name}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:mcp_disconnected, client, reason}, %{client_pid: client} = state) do
    Logger.warning("MCP server #{state.name} disconnected: #{inspect(reason)}")
    new_state = stop_server_process(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:mcp_result, client, result, _id}, %{client_pid: client} = state) do
    # Results are now handled synchronously in the StdioClient
    Logger.debug("Unexpected MCP result from #{state.name}: #{inspect(result)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:mcp_notification, client, method, params}, %{client_pid: client} = state) do
    Logger.debug("MCP notification from #{state.name}: #{method} - #{inspect(params)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:mcp_error, client, error, _id}, %{client_pid: client} = state) do
    Logger.error("MCP error from #{state.name}: #{inspect(error)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{pid: pid} = state) do
    Logger.warning("MCP server process #{state.name} died: #{inspect(reason)}")
    new_state = %{state | pid: nil, client_pid: nil, status: :disconnected}
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{client_pid: pid} = state) do
    Logger.warning("MCP client process for #{state.name} died: #{inspect(reason)}")
    new_state = stop_server_process(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port, client_pid: client} = state) when is_port(port) do
    # Forward data from server to client (stdio only)
    send(client, {port, {:data, data}})
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) when is_port(port) do
    Logger.warning("MCP server #{state.name} exited with status: #{status}")
    new_state = stop_server_process(state)
    {:noreply, new_state}
  end

  # Private Functions

  defp via_tuple(name) do
    {:via, Registry, {MCPChat.MCP.ServerRegistry, name}}
  end

  defp determine_transport(opts) do
    cond do
      Keyword.has_key?(opts, :url) -> :sse
      Keyword.has_key?(opts, :command) -> :stdio
      true -> raise ArgumentError, "Either :url or :command must be provided"
    end
  end

  defp start_server_process(%{transport: :stdio} = state) do
    # Start the stdio client first
    case StdioClient.start_link(callback_pid: self()) do
      {:ok, client_pid} ->
        Process.monitor(client_pid)

        # Start the server process
        case start_server_command(state.command, state.env) do
          {:ok, port} ->
            # Ports don't need explicit monitoring - they send exit_status messages

            # Connect the port to the client
            StdioClient.set_port(client_pid, port)

            # Initialize the connection
            client_info = %{
              name: "mcp_chat",
              version: "0.1.0"
            }

            # Initialize will be handled synchronously now
            case StdioClient.initialize(client_pid, client_info) do
              {:ok, init_result} ->
                new_state = %{
                  state
                  | port: port,
                    # We don't have OS PID easily
                    pid: nil,
                    client_pid: client_pid,
                    status: :connected,
                    server_info: init_result.server_info,
                    capabilities: init_result.capabilities
                }

                {:ok, new_state}

              {:error, reason} ->
                # Clean up
                Port.close(port)
                Process.exit(client_pid, :shutdown)
                {:error, {:initialization_failed, reason}}
            end

          {:error, reason} ->
            # Clean up the client
            Process.exit(client_pid, :shutdown)
            {:error, {:server_start_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:client_start_failed, reason}}
    end
  end

  defp start_server_process(%{transport: :sse} = state) do
    # Start the SSE client
    case SSEClient.start_link(name: state.name, url: state.url) do
      {:ok, client_pid} ->
        Process.monitor(client_pid)

        # Initialize the connection
        case SSEClient.initialize(client_pid) do
          {:ok, _} ->
            new_state = %{state | client_pid: client_pid, status: :connected}

            {:ok, new_state}

          {:error, reason} ->
            Process.exit(client_pid, :shutdown)
            {:error, {:initialization_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:client_start_failed, reason}}
    end
  end

  defp stop_server_process(state) do
    # Stop the client
    if state.client_pid do
      Process.exit(state.client_pid, :shutdown)
    end

    # Stop the server process (stdio only)
    if state.port do
      Port.close(state.port)
    end

    %{state | port: nil, pid: nil, client_pid: nil, status: :disconnected, capabilities: %{}}
  end

  defp start_server_command([cmd | args], env) do
    # Convert env map to list of {"KEY", "VALUE"} tuples
    env_list = Enum.map(env, fn {k, v} -> {to_string(k), to_string(v)} end)

    # Find the executable
    case System.find_executable(cmd) do
      nil ->
        {:error, {:executable_not_found, cmd}}

      executable ->
        # Start the port
        port_opts = [
          :binary,
          :exit_status,
          :stream,
          # Capture stderr as well
          :stderr_to_stdout,
          {:env, env_list},
          {:args, args}
        ]

        try do
          port = Port.open({:spawn_executable, executable}, port_opts)
          {:ok, port}
        catch
          :error, reason ->
            {:error, reason}
        end
    end
  end
end
