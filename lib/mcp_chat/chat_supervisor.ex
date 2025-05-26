defmodule MCPChat.ChatSupervisor do
  @moduledoc """
  Supervises the main chat loop, providing crash recovery and session preservation.
  """
  use GenServer
  require Logger

  defstruct [:chat_task, :session_backup, :restart_count, :max_restarts]

  @max_restarts 3
  # 5 minutes
  @restart_window 300_000

  # Client API

  @doc """
  Starts the chat supervisor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts a supervised chat session.
  """
  def start_chat(opts \\ []) do
    GenServer.call(__MODULE__, {:start_chat, opts})
  end

  @doc """
  Stops the current chat session gracefully.
  """
  def stop_chat() do
    GenServer.call(__MODULE__, :stop_chat)
  end

  @doc """
  Gets the current chat status.
  """
  def get_status() do
    GenServer.call(__MODULE__, :get_status)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      chat_task: nil,
      session_backup: nil,
      restart_count: 0,
      max_restarts: opts[:max_restarts] || @max_restarts
    }

    # Trap exits to handle chat process crashes
    Process.flag(:trap_exit, true)

    {:ok, state}
  end

  @impl true
  def handle_call({:start_chat, opts}, _from, state) do
    if state.chat_task do
      {:reply, {:error, :chat_already_running}, state}
    else
      # Backup current session before starting
      session_backup = backup_session()

      # Start the chat in a supervised task
      task =
        Task.async(fn ->
          try do
            MCPChat.CLI.Chat.start(opts)
          catch
            :exit, :normal ->
              :normal

            kind, reason ->
              Logger.error("Chat crashed: #{kind} - #{inspect(reason)}")
              {:error, {kind, reason}}
          end
        end)

      new_state = %{state | chat_task: task, session_backup: session_backup}

      {:reply, {:ok, task.pid}, new_state}
    end
  end

  def handle_call(:stop_chat, _from, state) do
    new_state = stop_chat_task(state)
    {:reply, :ok, new_state}
  end

  def handle_call(:get_status, _from, state) do
    status = %{
      running: state.chat_task != nil,
      pid: state.chat_task && state.chat_task.pid,
      restart_count: state.restart_count,
      has_backup: state.session_backup != nil
    }

    {:reply, status, state}
  end

  @impl true
  def handle_info({ref, result}, %{chat_task: %Task{ref: ref}} = state) do
    # Chat task completed normally
    Process.demonitor(ref, [:flush])

    case result do
      :normal ->
        Logger.info("Chat session ended normally")

      {:error, reason} ->
        Logger.error("Chat session ended with error: #{inspect(reason)}")
    end

    new_state = %{state | chat_task: nil, restart_count: 0}
    {:noreply, new_state}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, %{chat_task: %Task{ref: ref}} = state) do
    # Chat task crashed
    Logger.error("Chat process #{inspect(pid)} crashed: #{inspect(reason)}")

    new_state = %{state | chat_task: nil}

    # Attempt restart if within limits
    if should_restart?(new_state) do
      case restart_chat(new_state) do
        {:ok, restarted_state} ->
          notify_user_of_restart()
          {:noreply, restarted_state}

        {:error, _reason} ->
          notify_user_of_failure()
          {:noreply, new_state}
      end
    else
      Logger.error("Max restarts exceeded, not restarting chat")
      notify_user_of_failure()
      {:noreply, new_state}
    end
  end

  def handle_info(:reset_restart_count, state) do
    {:noreply, %{state | restart_count: 0}}
  end

  def handle_info({:EXIT, pid, reason}, state) do
    if state.chat_task && state.chat_task.pid == pid do
      handle_info({state.chat_task.ref, {:error, {:exit, reason}}}, state)
    else
      {:noreply, state}
    end
  end

  # Private Functions

  defp backup_session() do
    try do
      session = MCPChat.Session.get_current_session()

      %{
        messages: session.messages,
        context: session.context,
        timestamp: DateTime.utc_now()
      }
    catch
      _, _ ->
        nil
    end
  end

  defp restore_session(nil), do: :ok

  defp restore_session(backup) do
    try do
      # Restore messages
      Enum.each(backup.messages, fn msg ->
        MCPChat.Session.add_message(msg.role, msg.content)
      end)

      # Restore context
      MCPChat.Session.update_session(%{context: backup.context})

      Logger.info("Session restored from backup")
      :ok
    catch
      _, reason ->
        Logger.error("Failed to restore session: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp should_restart?(%{restart_count: count, max_restarts: max}) do
    count < max
  end

  defp restart_chat(state) do
    Logger.info("Attempting to restart chat session...")

    # Brief delay before restart
    Process.sleep(1_000)

    # Restore session if available
    if state.session_backup do
      restore_session(state.session_backup)
    end

    # Start new chat task
    task =
      Task.async(fn ->
        try do
          MCPChat.CLI.Chat.start([])
        catch
          kind, reason ->
            {:error, {kind, reason}}
        end
      end)

    # Schedule restart count reset
    Process.send_after(self(), :reset_restart_count, @restart_window)

    new_state = %{state | chat_task: task, restart_count: state.restart_count + 1}

    {:ok, new_state}
  end

  defp stop_chat_task(%{chat_task: nil} = state), do: state

  defp stop_chat_task(%{chat_task: task} = state) do
    # Try graceful shutdown first
    send(task.pid, :shutdown)

    case Task.yield(task, 5_000) || Task.shutdown(task) do
      {:ok, _} ->
        Logger.info("Chat task stopped gracefully")

      nil ->
        Logger.warning("Chat task did not stop gracefully, killed")
    end

    %{state | chat_task: nil}
  end

  defp notify_user_of_restart() do
    IO.puts("""

    ⚠️  The chat session crashed but has been automatically restarted.
    Your conversation history has been preserved.
    """)
  end

  defp notify_user_of_failure() do
    IO.puts("""

    ❌ The chat session crashed and could not be restarted.
    Please restart the application manually.
    """)
  end
end
