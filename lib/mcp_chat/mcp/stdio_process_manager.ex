defmodule MCPChat.MCP.StdioProcessManager do
  @moduledoc """
  Manages stdio MCP server processes as external OS processes.

  This module handles:
  - Starting MCP servers as OS processes
  - Managing stdio communication channels
  - Process lifecycle (start, stop, restart)
  - Integration with ServerManager

  The key architectural principle is that MCP servers run as independent
  OS processes, and we connect to them via stdio transport.
  """

  use GenServer
  require Logger

  defstruct [
    :port,
    :command,
    :args,
    :env,
    :working_dir,
    :buffer,
    :client_pid,
    restart_count: 0,
    process_status: :stopped,
    last_exit_status: nil
  ]

  @type t :: %__MODULE__{
          port: port() | nil,
          command: String.t(),
          args: list(String.t()),
          env: list({String.t(), String.t()}),
          working_dir: String.t() | nil,
          buffer: binary(),
          client_pid: pid() | nil,
          restart_count: non_neg_integer(),
          process_status: :stopped | :running | :exited | :failed,
          last_exit_status: non_neg_integer() | nil
        }

  # Client API

  @doc """
  Starts a stdio process manager.

  Options:
  - `:command` - The command to run (required)
  - `:args` - Command arguments (default: [])
  - `:env` - Environment variables as {key, value} tuples (default: [])
  - `:working_dir` - Working directory for the process (default: current dir)
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def start_link(config, extra_opts) do
    # Merge config and extra_opts
    opts =
      if is_map(config) do
        Map.to_list(config) ++ extra_opts
      else
        config ++ extra_opts
      end

    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Starts the managed process and returns the port.
  """
  def start_process(manager) do
    GenServer.call(manager, :start_process)
  end

  @doc """
  Stops the managed process.
  """
  def stop_process(manager) do
    GenServer.call(manager, :stop_process)
  end

  @doc """
  Gets the current process status.
  """
  def get_status(manager) do
    GenServer.call(manager, :get_status)
  end

  @doc """
  Sets the client PID that should receive messages from the process.
  """
  def set_client(manager, client_pid) do
    GenServer.call(manager, {:set_client, client_pid})
  end

  @doc """
  Sends data to the managed process via stdin.
  """
  def send_data(manager, data) do
    GenServer.call(manager, {:send_data, data})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    # Convert map to keyword list if needed
    opts =
      if is_map(opts) do
        Map.to_list(opts)
      else
        opts
      end

    command = Keyword.fetch!(opts, :command)
    args = Keyword.get(opts, :args, [])
    env = Keyword.get(opts, :env, [])
    # Convert env map to list if needed
    env = if is_map(env), do: Map.to_list(env), else: env
    working_dir = Keyword.get(opts, :working_dir)

    state = %__MODULE__{
      command: command,
      args: args,
      env: env,
      working_dir: working_dir,
      buffer: <<>>,
      client_pid: nil,
      restart_count: 0,
      process_status: :stopped,
      last_exit_status: nil
    }

    # Don't auto-start for tests - let the caller explicitly start
    # Auto-start only if auto_start option is true
    if Keyword.get(opts, :auto_start, false) do
      case start_port(state) do
        {:ok, port} ->
          {:ok, %{state | port: port, process_status: :running}}

        {:error, reason} ->
          Logger.error("Failed to start process during init: #{inspect(reason)}")
          {:ok, state}
      end
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_call(:start_process, _from, %{port: nil} = state) do
    case start_port(state) do
      {:ok, port} ->
        new_state = %{state | port: port, process_status: :running}
        {:reply, {:ok, port}, new_state}

      {:error, reason} = error ->
        Logger.error("Failed to start process: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  def handle_call(:start_process, _from, %{port: port} = state) when is_port(port) do
    {:reply, {:error, :already_started}, state}
  end

  def handle_call(:stop_process, _from, %{port: nil} = state) do
    {:reply, {:error, :not_started}, state}
  end

  def handle_call(:stop_process, _from, %{port: port} = state) when is_port(port) do
    Port.close(port)
    {:reply, :ok, %{state | port: nil, buffer: <<>>, process_status: :stopped}}
  end

  def handle_call(:get_status, _from, state) do
    status = %{
      status: state.process_status,
      running: state.port != nil,
      command: state.command,
      args: state.args,
      client_pid: state.client_pid,
      restart_count: state.restart_count,
      last_exit_status: state.last_exit_status
    }

    {:reply, {:ok, status}, state}
  end

  def handle_call({:set_client, client_pid}, _from, state) do
    {:reply, :ok, %{state | client_pid: client_pid}}
  end

  def handle_call({:send_data, _data}, _from, %{port: nil} = state) do
    {:reply, {:error, :not_started}, state}
  end

  def handle_call({:send_data, data}, _from, %{port: port} = state) when is_port(port) do
    Port.command(port, data)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    # Forward data to the client if one is set
    if state.client_pid do
      send(state.client_pid, {:stdio_data, data})
    end

    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.info("Process exited with status: #{status}")

    # Determine process status based on exit code
    process_status = if status == 0, do: :exited, else: :failed

    # Notify client if one is set
    if state.client_pid do
      send(state.client_pid, {:stdio_exit, status})
    end

    {:noreply, %{state | port: nil, buffer: <<>>, process_status: process_status, last_exit_status: status}}
  end

  def handle_info({:EXIT, port, reason}, %{port: port} = state) do
    Logger.error("Port crashed: #{inspect(reason)}")

    # Notify client if one is set
    if state.client_pid do
      send(state.client_pid, {:stdio_crash, reason})
    end

    {:noreply, %{state | port: nil, buffer: <<>>, process_status: :failed}}
  end

  # Private Functions

  defp start_port(state) do
    port_opts = [
      :binary,
      :exit_status,
      :use_stdio,
      :stderr_to_stdout,
      {:args, state.args}
    ]

    port_opts =
      if state.env != [] do
        env_list = Enum.map(state.env, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)
        [{:env, env_list} | port_opts]
      else
        port_opts
      end

    port_opts =
      if state.working_dir do
        [{:cd, state.working_dir} | port_opts]
      else
        port_opts
      end

    try do
      port = Port.open({:spawn_executable, find_executable(state.command)}, port_opts)
      {:ok, port}
    rescue
      e ->
        {:error, Exception.message(e)}
    end
  end

  defp find_executable(command) do
    # First try as absolute path
    if File.exists?(command) do
      Path.expand(command)
    else
      # Try to find in PATH
      case System.find_executable(command) do
        # Let Port.open handle the error
        nil -> command
        path -> path
      end
    end
  end
end
