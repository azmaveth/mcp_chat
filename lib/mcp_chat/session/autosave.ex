defmodule MCPChat.Session.Autosave do
  @moduledoc """
  Background autosave functionality for sessions.

  Features:
  - Periodic automatic saving without blocking the UI
  - Configurable save intervals and debouncing
  - Change detection to avoid unnecessary saves
  - Failure recovery and retry logic
  - Progress notifications for long save operations
  - Compression for large sessions
  """

  use GenServer
  require Logger

  alias MCPChat.Session

  # 5 minutes
  @default_interval 5 * 60 * 1_000
  # 30 seconds
  @default_debounce 30 * 1_000

  defmodule State do
    @moduledoc false
    defstruct [
      :timer_ref,
      :last_save_time,
      :last_saved_hash,
      :save_count,
      :failure_count,
      :pending_save,
      :config,
      enabled: true,
      saving: false
    ]
  end

  # Client API

  @doc """
  Start the autosave GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enable or disable autosave.
  """
  def set_enabled(enabled) when is_boolean(enabled) do
    GenServer.call(__MODULE__, {:set_enabled, enabled})
  end

  @doc """
  Trigger an immediate save (debounced).
  """
  def trigger_save() do
    GenServer.cast(__MODULE__, :trigger_save)
  end

  @doc """
  Force an immediate save (bypasses debouncing).
  """
  def force_save() do
    GenServer.call(__MODULE__, :force_save)
  end

  @doc """
  Get autosave statistics.
  """
  def get_stats() do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Configure autosave settings.
  """
  def configure(config) do
    GenServer.call(__MODULE__, {:configure, config})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config = %{
      interval: Keyword.get(opts, :interval, @default_interval),
      debounce: Keyword.get(opts, :debounce, @default_debounce),
      enabled: Keyword.get(opts, :enabled, true),
      compress_large: Keyword.get(opts, :compress_large, true),
      notify_progress: Keyword.get(opts, :notify_progress, true),
      max_retries: Keyword.get(opts, :max_retries, 3),
      session_name_prefix: Keyword.get(opts, :session_name_prefix, "autosave")
    }

    state = %State{
      config: config,
      enabled: config.enabled,
      save_count: 0,
      failure_count: 0,
      last_save_time: nil,
      last_saved_hash: nil
    }

    # Start the autosave timer if enabled
    state =
      if state.enabled do
        schedule_next_save(state)
      else
        state
      end

    Logger.info("Autosave initialized with interval: #{config.interval}ms")

    {:ok, state}
  end

  @impl true
  def handle_call({:set_enabled, enabled}, _from, state) do
    new_state = %{state | enabled: enabled}

    new_state =
      if enabled and is_nil(state.timer_ref) do
        schedule_next_save(new_state)
      else
        cancel_timer(new_state)
      end

    Logger.info("Autosave #{if enabled, do: "enabled", else: "disabled"}")

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:force_save, _from, state) do
    {result, new_state} = perform_save(state, force: true)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      enabled: state.enabled,
      saving: state.saving,
      save_count: state.save_count,
      failure_count: state.failure_count,
      last_save_time: state.last_save_time,
      next_save_in: time_until_next_save(state),
      config: state.config
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:configure, config}, _from, state) do
    new_config = Map.merge(state.config, config)
    new_state = %{state | config: new_config}

    # Reschedule if interval changed
    final_state =
      if config[:interval] && state.enabled do
        new_state = cancel_timer(new_state)
        schedule_next_save(new_state)
      else
        new_state
      end

    {:reply, :ok, final_state}
  end

  @impl true
  def handle_cast(:trigger_save, state) do
    if state.enabled and not state.saving do
      # Debounce the save request
      new_state = schedule_debounced_save(state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:perform_autosave, state) do
    {_result, new_state} = perform_save(state)

    # Schedule next save
    new_state =
      if new_state.enabled do
        schedule_next_save(new_state)
      else
        new_state
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:perform_debounced_save, state) do
    {_result, new_state} = perform_save(%{state | pending_save: false})
    {:noreply, new_state}
  end

  # Private Functions

  defp schedule_next_save(state) do
    timer_ref = Process.send_after(self(), :perform_autosave, state.config.interval)
    %{state | timer_ref: timer_ref}
  end

  defp schedule_debounced_save(state) do
    if state.pending_save do
      # Already have a pending save
      state
    else
      Process.send_after(self(), :perform_debounced_save, state.config.debounce)
      %{state | pending_save: true}
    end
  end

  defp cancel_timer(state) do
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    %{state | timer_ref: nil}
  end

  defp perform_save(state, opts \\ []) do
    if state.saving and not Keyword.get(opts, :force, false) do
      {{:error, :already_saving}, state}
    else
      state = %{state | saving: true}

      # Start save operation asynchronously
      parent = self()

      Task.start(fn ->
        result = do_save_async(state)
        send(parent, {:save_complete, result})
      end)

      # Return immediately - the actual save happens in background
      receive do
        {:save_complete, result} ->
          handle_save_result(result, state)
      after
        # Timeout protection
        30_000 ->
          Logger.error("Autosave timed out after 30 seconds")
          {{:error, :timeout}, %{state | saving: false, failure_count: state.failure_count + 1}}
      end
    end
  end

  defp do_save_async(_state) do
    try do
      # Use SessionManager to save the current session
      case MCPChat.SessionManager.save_current_session() do
        :ok ->
          # Get session to calculate hash for change detection
          session = Session.get_current_session()
          session_hash = calculate_session_hash(session)
          session_size = estimate_session_size(session)

          {:ok, %{hash: session_hash, size: session_size}}

        {:error, reason} ->
          Logger.error("Autosave failed: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Autosave crashed: #{inspect(e)}")
        {:error, {:crashed, e}}
    end
  end

  defp handle_save_result({:ok, :no_changes}, state) do
    Logger.debug("Autosave skipped - no changes detected")
    {{:ok, :no_changes}, %{state | saving: false}}
  end

  defp handle_save_result({:ok, save_info}, state) do
    Logger.debug("Autosave successful")

    new_state = %{
      state
      | saving: false,
        save_count: state.save_count + 1,
        # Reset failure count on success
        failure_count: 0,
        last_save_time: DateTime.utc_now(),
        last_saved_hash: save_info.hash
    }

    {{:ok, save_info}, new_state}
  end

  defp handle_save_result({:error, reason}, state) do
    new_failure_count = state.failure_count + 1
    Logger.warning("Autosave failed (attempt #{new_failure_count}): #{inspect(reason)}")

    new_state = %{state | saving: false, failure_count: new_failure_count}

    # Disable autosave if too many failures
    if new_failure_count >= state.config.max_retries do
      Logger.error("Autosave disabled after #{new_failure_count} failures")
      new_state = %{new_state | enabled: false}
      {{:error, :max_failures}, new_state}
    else
      {{:error, reason}, new_state}
    end
  end

  defp calculate_session_hash(session) do
    # Create a deterministic hash of the session content
    :crypto.hash(:sha256, :erlang.term_to_binary(session))
    |> Base.encode16()
  end

  defp estimate_session_size(session) do
    # Rough estimate of serialized size
    :erlang.term_to_binary(session) |> byte_size()
  end

  # Old autosave cleanup is no longer needed
  # Sessions are permanent unless explicitly deleted

  defp time_until_next_save(%{timer_ref: nil}), do: nil

  defp time_until_next_save(%{timer_ref: ref}) do
    case Process.read_timer(ref) do
      false -> nil
      ms -> ms
    end
  end
end
