defmodule MCPChat.PortSupervisor do
  @moduledoc """
  Supervises Port processes for stdio connections.
  Provides automatic restart and health monitoring for ports.
  """
  use GenServer
  require Logger

  defstruct [:port, :command, :args, :env, :monitor_ref, :restart_count, :max_restarts]

  @max_restarts 3
  # 1 minute
  @restart_window 60_000

  # Client API

  @doc """
  Starts a supervised port process.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Opens a supervised port with the given command and options.
  """
  def open(supervisor, command, args, opts \\ []) do
    GenServer.call(supervisor, {:open, command, args, opts})
  end

  @doc """
  Sends data to the supervised port.
  """
  def send_data(supervisor, data) do
    GenServer.call(supervisor, {:send, data})
  end

  @doc """
  Closes the supervised port.
  """
  def close(supervisor) do
    GenServer.call(supervisor, :close)
  end

  @doc """
  Gets the current port reference.
  """
  def get_port(supervisor) do
    GenServer.call(supervisor, :get_port)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      command: nil,
      args: [],
      env: [],
      port: nil,
      monitor_ref: nil,
      restart_count: 0,
      max_restarts: opts[:max_restarts] || @max_restarts
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:open, command, args, opts}, _from, state) do
    env = opts[:env] || []

    case open_port(command, args, env) do
      {:ok, port} ->
        # Monitor the port
        monitor_ref = Port.monitor(port)

        new_state = %{
          state
          | port: port,
            command: command,
            args: args,
            env: env,
            monitor_ref: monitor_ref,
            restart_count: 0
        }

        {:reply, {:ok, port}, new_state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:send, _data}, _from, %{port: nil} = state) do
    {:reply, {:error, :port_not_open}, state}
  end

  def handle_call({:send, data}, _from, %{port: port} = state) do
    try do
      Port.command(port, data)
      {:reply, :ok, state}
    catch
      :error, :badarg ->
        # Port is dead
        {:reply, {:error, :port_closed}, state}
    end
  end

  def handle_call(:close, _from, %{port: nil} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:close, _from, %{port: port, monitor_ref: ref} = state) do
    if ref, do: Port.demonitor(ref, [:flush])
    Port.close(port)

    new_state = %{state | port: nil, monitor_ref: nil}
    {:reply, :ok, new_state}
  end

  def handle_call(:get_port, _from, state) do
    {:reply, state.port, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :port, port, reason}, %{monitor_ref: ref} = state) do
    Logger.warning("Port #{inspect(port)} died: #{inspect(reason)}")

    # Check if we should restart
    if should_restart?(state) do
      case restart_port(state) do
        {:ok, new_state} ->
          Logger.info("Successfully restarted port")
          {:noreply, new_state}

        {:error, reason} ->
          Logger.error("Failed to restart port: #{inspect(reason)}")
          {:noreply, %{state | port: nil, monitor_ref: nil}}
      end
    else
      Logger.error("Max restarts (#{state.max_restarts}) exceeded, not restarting port")
      {:noreply, %{state | port: nil, monitor_ref: nil}}
    end
  end

  def handle_info({port, {:data, data}}, %{port: port} = state) do
    # Forward port data to the owner process
    send(self(), {:port_data, data})
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug("PortSupervisor received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp open_port(command, args, env) do
    try do
      port_opts = [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        args: args
      ]

      port_opts =
        if env != [] do
          [{:env, env} | port_opts]
        else
          port_opts
        end

      port = Port.open({:spawn_executable, command}, port_opts)
      {:ok, port}
    catch
      :error, reason ->
        {:error, reason}
    end
  end

  defp should_restart?(%{restart_count: count, max_restarts: max}) do
    count < max
  end

  defp restart_port(state) do
    # Clean restart window tracking could be added here
    # Brief delay before restart
    Process.sleep(1_000)

    case open_port(state.command, state.args, state.env) do
      {:ok, port} ->
        monitor_ref = Port.monitor(port)

        new_state = %{state | port: port, monitor_ref: monitor_ref, restart_count: state.restart_count + 1}

        # Schedule restart count reset
        Process.send_after(self(), :reset_restart_count, @restart_window)

        {:ok, new_state}

      error ->
        error
    end
  end
end
