defmodule MCPChat.MCP.StdioProcessSupervisor do
  @moduledoc """
  OTP Supervisor for managing stdio process lifecycles with restart logic.

  This supervisor manages StdioProcessManager processes and provides:
  - Automatic restart on failure
  - Configurable restart strategies
  - Restart counting and backoff
  - Integration with ServerWrapper
  """

  use GenServer
  require Logger

  alias MCPChat.MCP.StdioProcessManager

  @default_max_restarts 3
  @default_max_seconds 60
  @default_restart_delay 1_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start a supervised stdio process manager.

  Options:
  - `:max_restarts` - Maximum restarts within max_seconds (default: 3)
  - `:max_seconds` - Time window for restart counting (default: 60)
  - `:restart_delay` - Delay between restarts in ms (default: 1_000)
  - All other options are passed to StdioProcessManager
  """
  def start_process(config, opts \\ []) do
    GenServer.call(__MODULE__, {:start_process, config, opts})
  end

  @doc """
  Stop a supervised stdio process.
  """
  def stop_process(pid) when is_pid(pid) do
    GenServer.call(__MODULE__, {:stop_process, pid})
  end

  @doc """
  Get restart statistics for a supervised process.
  """
  def get_restart_stats(pid) when is_pid(pid) do
    GenServer.call(__MODULE__, {:get_restart_stats, pid})
  end

  @impl true
  def init(_opts) do
    # State holds managed processes and their configurations
    state = %{
      # pid -> %{config: ..., restart_config: ...}
      processes: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start_process, config, opts}, _from, state) do
    # Extract supervisor options
    max_restarts = Keyword.get(opts, :max_restarts, @default_max_restarts)
    max_seconds = Keyword.get(opts, :max_seconds, @default_max_seconds)
    restart_delay = Keyword.get(opts, :restart_delay, @default_restart_delay)

    # Prepare manager options
    manager_opts = Keyword.drop(opts, [:max_restarts, :max_seconds, :restart_delay])

    case StdioProcessManager.start_link(config, manager_opts) do
      {:ok, pid} ->
        # Monitor the process
        Process.monitor(pid)

        # Store process info
        process_info = %{
          config: config,
          manager_opts: manager_opts,
          restart_config: %{
            max_restarts: max_restarts,
            max_seconds: max_seconds,
            restart_delay: restart_delay,
            restart_count: 0,
            restart_times: []
          }
        }

        new_state = put_in(state.processes[pid], process_info)
        {:reply, {:ok, pid}, new_state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:stop_process, pid}, _from, state) do
    case Map.get(state.processes, pid) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _process_info ->
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end

        new_state = %{state | processes: Map.delete(state.processes, pid)}
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:get_restart_stats, pid}, _from, state) do
    case get_in(state.processes, [pid, :restart_config]) do
      nil -> {:reply, {:error, :not_found}, state}
      restart_config -> {:reply, {:ok, restart_config}, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    Logger.warning("Supervised stdio process #{inspect(pid)} died: #{inspect(reason)}")

    case Map.get(state.processes, pid) do
      nil ->
        # Not a managed process, just remove it
        {:noreply, state}

      process_info ->
        updated_restart_config = update_restart_stats(process_info.restart_config, reason)

        if should_restart?(updated_restart_config, reason) do
          # Schedule restart after delay
          Process.send_after(
            self(),
            {:restart_process, pid, process_info, updated_restart_config},
            updated_restart_config.restart_delay
          )

          # Update state with new restart config
          new_process_info = %{process_info | restart_config: updated_restart_config}
          new_state = put_in(state.processes[pid], new_process_info)
          {:noreply, new_state}
        else
          Logger.error("Max restarts exceeded for process #{inspect(pid)}")
          # Remove from managed processes
          new_state = %{state | processes: Map.delete(state.processes, pid)}
          {:noreply, new_state}
        end
    end
  end

  def handle_info({:restart_process, old_pid, process_info, restart_config}, state) do
    Logger.info("Restarting stdio process after delay")

    # Start new process
    case StdioProcessManager.start_link(process_info.config, process_info.manager_opts) do
      {:ok, new_pid} ->
        # Monitor the new process
        Process.monitor(new_pid)

        # Update process info with new PID and restart config
        new_process_info = %{process_info | restart_config: restart_config}

        # Remove old PID and add new one
        new_processes =
          state.processes
          |> Map.delete(old_pid)
          |> Map.put(new_pid, new_process_info)

        new_state = %{state | processes: new_processes}
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to restart process: #{inspect(reason)}")
        # Remove from managed processes
        new_state = %{state | processes: Map.delete(state.processes, old_pid)}
        {:noreply, new_state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp update_restart_stats(config, _reason) do
    now = System.system_time(:millisecond)

    # Add current restart time
    new_restart_times = [now | config.restart_times]

    # Remove restart times outside the window
    cutoff_time = now - config.max_seconds * 1_000
    filtered_times = Enum.filter(new_restart_times, &(&1 >= cutoff_time))

    %{config | restart_count: config.restart_count + 1, restart_times: filtered_times}
  end

  defp should_restart?(config, reason) do
    # Don't restart if it was a normal shutdown
    reason != :normal and
      reason != :shutdown and
      length(config.restart_times) < config.max_restarts
  end
end
