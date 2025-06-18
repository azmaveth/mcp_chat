defmodule MCPChat.Persistence.EventStore do
  @moduledoc """
  Event Store for MCP Chat state persistence.

  This module provides durable event logging with write-ahead logging (WAL),
  event replay capabilities, and snapshot integration for complete state recovery.

  Features:
  - Write-ahead logging for durability
  - Event indexing for fast retrieval
  - Stream-based event processing
  - Snapshot coordination
  - Automatic cleanup and archival
  """

  use GenServer
  require Logger

  alias MCPChat.Persistence.{EventJournal, EventIndex, SnapshotManager}
  alias MCPChat.Events.{AgentEvents, SystemEvents}

  @event_store_dir "~/.mcp_chat/events"
  @wal_file "event_store.wal"
  @index_file "event_store.idx"
  @batch_size 100
  # 5 seconds
  @flush_interval 5_000

  # Event store state
  defstruct [
    :wal_fd,
    :index_fd,
    :event_counter,
    :pending_events,
    :last_snapshot_event,
    :flush_timer,
    :event_dir,
    :subscribers,
    :batch_buffer
  ]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Append an event to the event store.
  Returns the event ID for future reference.
  """
  def append_event(event) do
    GenServer.call(__MODULE__, {:append_event, event})
  end

  @doc """
  Append multiple events atomically.
  """
  def append_events(events) when is_list(events) do
    GenServer.call(__MODULE__, {:append_events, events})
  end

  @doc """
  Get events from a specific point in time.
  """
  def get_events_since(event_id) do
    GenServer.call(__MODULE__, {:get_events_since, event_id})
  end

  @doc """
  Get events for a specific stream (e.g., session, agent).
  """
  def get_stream_events(stream_id, opts \\ []) do
    GenServer.call(__MODULE__, {:get_stream_events, stream_id, opts})
  end

  @doc """
  Subscribe to new events.
  """
  def subscribe(subscriber_pid, filter \\ :all) do
    GenServer.call(__MODULE__, {:subscribe, subscriber_pid, filter})
  end

  @doc """
  Unsubscribe from events.
  """
  def unsubscribe(subscriber_pid) do
    GenServer.call(__MODULE__, {:unsubscribe, subscriber_pid})
  end

  @doc """
  Get the current event store statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Force a flush of pending events to disk.
  """
  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  @doc """
  Replay events from a specific point to rebuild state.
  """
  def replay_events(from_event_id, handler_fn) do
    GenServer.call(__MODULE__, {:replay_events, from_event_id, handler_fn}, :infinity)
  end

  @doc """
  Create a snapshot reference point.
  """
  def create_snapshot_marker(snapshot_data) do
    GenServer.call(__MODULE__, {:create_snapshot_marker, snapshot_data})
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    event_dir = expand_event_dir(opts[:event_dir] || @event_store_dir)

    Logger.info("Starting Event Store", event_dir: event_dir)

    # Ensure directory exists
    File.mkdir_p!(event_dir)

    # Initialize state
    state = %__MODULE__{
      event_dir: event_dir,
      event_counter: 0,
      pending_events: [],
      subscribers: %{},
      batch_buffer: []
    }

    case initialize_event_store(state) do
      {:ok, initialized_state} ->
        # Start flush timer
        timer = Process.send_after(self(), :flush_events, @flush_interval)
        final_state = %{initialized_state | flush_timer: timer}

        Logger.info("Event Store initialized",
          event_count: final_state.event_counter,
          last_snapshot: final_state.last_snapshot_event
        )

        {:ok, final_state}

      {:error, reason} ->
        Logger.error("Failed to initialize Event Store", reason: inspect(reason))
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:append_event, event}, _from, state) do
    case append_single_event(event, state) do
      {:ok, event_id, new_state} ->
        {:reply, {:ok, event_id}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:append_events, events}, _from, state) do
    case append_multiple_events(events, state) do
      {:ok, event_ids, new_state} ->
        {:reply, {:ok, event_ids}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_events_since, event_id}, _from, state) do
    result = EventJournal.read_events_since(state.event_dir, event_id)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_stream_events, stream_id, opts}, _from, state) do
    result = EventIndex.get_stream_events(state.event_dir, stream_id, opts)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:subscribe, subscriber_pid, filter}, _from, state) do
    # Monitor the subscriber
    Process.monitor(subscriber_pid)

    new_subscribers = Map.put(state.subscribers, subscriber_pid, filter)
    new_state = %{state | subscribers: new_subscribers}

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:unsubscribe, subscriber_pid}, _from, state) do
    new_subscribers = Map.delete(state.subscribers, subscriber_pid)
    new_state = %{state | subscribers: new_subscribers}

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      total_events: state.event_counter,
      pending_events: length(state.pending_events),
      batch_buffer_size: length(state.batch_buffer),
      subscribers: map_size(state.subscribers),
      last_snapshot_event: state.last_snapshot_event,
      event_dir: state.event_dir
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    case flush_pending_events(state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:replay_events, from_event_id, handler_fn}, _from, state) do
    result = replay_events_from_storage(state.event_dir, from_event_id, handler_fn)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:create_snapshot_marker, snapshot_data}, _from, state) do
    snapshot_event = create_snapshot_event(state.event_counter, snapshot_data)

    case append_single_event(snapshot_event, state) do
      {:ok, event_id, new_state} ->
        updated_state = %{new_state | last_snapshot_event: event_id}
        {:reply, {:ok, event_id}, updated_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:flush_events, state) do
    # Flush pending events
    new_state =
      case flush_pending_events(state) do
        {:ok, flushed_state} ->
          flushed_state

        {:error, reason} ->
          Logger.error("Failed to flush events", reason: inspect(reason))
          state
      end

    # Schedule next flush
    timer = Process.send_after(self(), :flush_events, @flush_interval)
    final_state = %{new_state | flush_timer: timer}

    {:noreply, final_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, subscriber_pid, _reason}, state) do
    # Remove dead subscriber
    new_subscribers = Map.delete(state.subscribers, subscriber_pid)
    new_state = %{state | subscribers: new_subscribers}

    {:noreply, new_state}
  end

  # Private functions

  defp initialize_event_store(state) do
    wal_path = Path.join(state.event_dir, @wal_file)
    index_path = Path.join(state.event_dir, @index_file)

    with {:ok, wal_fd} <- File.open(wal_path, [:append, :binary]),
         {:ok, index_fd} <- File.open(index_path, [:append, :binary]),
         {:ok, event_count} <- recover_event_count(state.event_dir),
         {:ok, last_snapshot} <- recover_last_snapshot(state.event_dir) do
      {:ok,
       %{state | wal_fd: wal_fd, index_fd: index_fd, event_counter: event_count, last_snapshot_event: last_snapshot}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp append_single_event(event, state) do
    event_id = state.event_counter + 1
    timestamped_event = add_event_metadata(event, event_id)

    # Add to batch buffer
    new_batch = [timestamped_event | state.batch_buffer]
    new_state = %{state | batch_buffer: new_batch, event_counter: event_id}

    # If batch is full, flush immediately
    if length(new_batch) >= @batch_size do
      case flush_batch_buffer(new_state) do
        {:ok, flushed_state} ->
          # Notify subscribers
          notify_subscribers(timestamped_event, flushed_state)
          {:ok, event_id, flushed_state}

        {:error, reason} ->
          {:error, reason}
      end
    else
      # Notify subscribers
      notify_subscribers(timestamped_event, new_state)
      {:ok, event_id, new_state}
    end
  end

  defp append_multiple_events(events, state) do
    {event_ids, new_state} =
      events
      |> Enum.reduce({[], state}, fn event, {ids, current_state} ->
        event_id = current_state.event_counter + 1
        timestamped_event = add_event_metadata(event, event_id)

        new_batch = [timestamped_event | current_state.batch_buffer]
        updated_state = %{current_state | batch_buffer: new_batch, event_counter: event_id}

        {[event_id | ids], updated_state}
      end)

    # Flush if batch is large enough
    final_state =
      if length(new_state.batch_buffer) >= @batch_size do
        case flush_batch_buffer(new_state) do
          {:ok, flushed_state} -> flushed_state
          {:error, _reason} -> new_state
        end
      else
        new_state
      end

    # Notify subscribers of all events
    Enum.each(final_state.batch_buffer, fn event ->
      notify_subscribers(event, final_state)
    end)

    {:ok, Enum.reverse(event_ids), final_state}
  end

  defp flush_pending_events(state) do
    if length(state.batch_buffer) > 0 do
      flush_batch_buffer(state)
    else
      {:ok, state}
    end
  end

  defp flush_batch_buffer(state) do
    try do
      # Write events to WAL
      events_to_write = Enum.reverse(state.batch_buffer)
      wal_data = encode_events_for_wal(events_to_write)
      :ok = IO.binwrite(state.wal_fd, wal_data)
      :ok = :file.sync(state.wal_fd)

      # Update index
      index_entries = create_index_entries(events_to_write)
      index_data = encode_index_entries(index_entries)
      :ok = IO.binwrite(state.index_fd, index_data)
      :ok = :file.sync(state.index_fd)

      # Clear batch buffer
      new_state = %{state | batch_buffer: []}

      Logger.debug("Flushed batch to disk",
        event_count: length(events_to_write),
        total_events: state.event_counter
      )

      {:ok, new_state}
    rescue
      error ->
        Logger.error("Failed to flush batch", error: inspect(error))
        {:error, error}
    end
  end

  defp add_event_metadata(event, event_id) do
    Map.merge(event, %{
      event_id: event_id,
      timestamp: DateTime.utc_now(),
      stream_id: extract_stream_id(event),
      event_version: 1
    })
  end

  defp extract_stream_id(event) do
    cond do
      Map.has_key?(event, :session_id) -> "session:#{event.session_id}"
      Map.has_key?(event, :agent_id) -> "agent:#{event.agent_id}"
      Map.has_key?(event, :workflow_id) -> "workflow:#{event.workflow_id}"
      true -> "system"
    end
  end

  defp notify_subscribers(event, state) do
    Enum.each(state.subscribers, fn {subscriber_pid, filter} ->
      if event_matches_filter(event, filter) do
        send(subscriber_pid, {:event_store_event, event})
      end
    end)
  end

  defp event_matches_filter(_event, :all), do: true
  defp event_matches_filter(event, {:stream, stream_id}), do: event.stream_id == stream_id
  defp event_matches_filter(event, {:event_type, event_type}), do: event.event_type == event_type
  defp event_matches_filter(_event, _filter), do: false

  defp encode_events_for_wal(events) do
    events
    |> Enum.map(&:erlang.term_to_binary/1)
    |> Enum.map(fn serialized ->
      size = byte_size(serialized)
      <<size::32, serialized::binary>>
    end)
    |> IO.iodata_to_binary()
  end

  defp create_index_entries(events) do
    Enum.map(events, fn event ->
      %{
        event_id: event.event_id,
        stream_id: event.stream_id,
        event_type: event.event_type,
        timestamp: event.timestamp,
        offset: calculate_wal_offset(event)
      }
    end)
  end

  defp encode_index_entries(entries) do
    entries
    |> Enum.map(&:erlang.term_to_binary/1)
    |> Enum.map(fn serialized ->
      size = byte_size(serialized)
      <<size::32, serialized::binary>>
    end)
    |> IO.iodata_to_binary()
  end

  defp calculate_wal_offset(_event) do
    # In a real implementation, this would track WAL file positions
    # For now, return a placeholder
    0
  end

  defp recover_event_count(event_dir) do
    # Read existing index to determine last event ID
    index_path = Path.join(event_dir, @index_file)

    if File.exists?(index_path) do
      EventIndex.get_last_event_id(index_path)
    else
      {:ok, 0}
    end
  end

  defp recover_last_snapshot(event_dir) do
    # Find the most recent snapshot marker
    case EventJournal.find_last_snapshot(event_dir) do
      {:ok, snapshot_event_id} -> {:ok, snapshot_event_id}
      {:error, :not_found} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp replay_events_from_storage(event_dir, from_event_id, handler_fn) do
    case EventJournal.read_events_since(event_dir, from_event_id) do
      {:ok, events} ->
        try do
          Enum.each(events, handler_fn)
          {:ok, length(events)}
        rescue
          error -> {:error, {:replay_failed, error}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_snapshot_event(event_id, snapshot_data) do
    %{
      event_type: :snapshot_created,
      snapshot_id: "snapshot_#{event_id}",
      snapshot_data: snapshot_data,
      created_at: DateTime.utc_now()
    }
  end

  defp expand_event_dir(path) do
    Path.expand(path)
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Event Store shutting down", reason: inspect(reason))

    # Flush any remaining events
    case flush_pending_events(state) do
      {:ok, _} -> Logger.debug("Final flush completed")
      {:error, error} -> Logger.error("Final flush failed", error: inspect(error))
    end

    # Close file descriptors
    if state.wal_fd, do: File.close(state.wal_fd)
    if state.index_fd, do: File.close(state.index_fd)

    # Cancel timer
    if state.flush_timer, do: Process.cancel_timer(state.flush_timer)

    :ok
  end
end
