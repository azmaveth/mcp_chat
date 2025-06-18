defmodule MCPChat.Persistence.EventIndex do
  @moduledoc """
  Event indexing for fast lookup and stream-based queries.

  This module manages an index of events that allows for efficient
  retrieval by stream ID, event type, and time range without
  scanning the entire event journal.
  """

  require Logger

  @index_file "event_store.idx"
  @index_version 1

  # Index entry structure
  defstruct [
    :event_id,
    :stream_id,
    :event_type,
    :timestamp,
    :wal_offset,
    :wal_size
  ]

  @doc """
  Get events for a specific stream.
  """
  def get_stream_events(event_dir, stream_id, opts \\ []) do
    index_path = Path.join(event_dir, @index_file)

    with {:ok, index_entries} <- read_index_entries(index_path),
         filtered_entries = filter_stream_entries(index_entries, stream_id, opts),
         {:ok, events} <- load_events_from_entries(event_dir, filtered_entries) do
      {:ok, events}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get the last event ID from the index.
  """
  def get_last_event_id(index_path) do
    case read_index_entries(index_path) do
      {:ok, []} ->
        {:ok, 0}

      {:ok, entries} ->
        last_entry = Enum.max_by(entries, & &1.event_id, fn -> nil end)
        {:ok, last_entry.event_id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Add new index entries to the index file.
  """
  def append_index_entries(event_dir, entries) do
    index_path = Path.join(event_dir, @index_file)

    try do
      File.open(index_path, [:append, :binary], fn file ->
        entries_data = encode_index_entries(entries)
        IO.binwrite(file, entries_data)
      end)
    rescue
      error ->
        Logger.error("Failed to append index entries", error: inspect(error))
        {:error, error}
    end
  end

  @doc """
  Find events by event type across all streams.
  """
  def find_events_by_type(event_dir, event_type, opts \\ []) do
    index_path = Path.join(event_dir, @index_file)

    with {:ok, index_entries} <- read_index_entries(index_path),
         filtered_entries = filter_by_event_type(index_entries, event_type, opts),
         {:ok, events} <- load_events_from_entries(event_dir, filtered_entries) do
      {:ok, events}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Find events within a time range.
  """
  def find_events_by_time_range(event_dir, from_time, to_time, opts \\ []) do
    index_path = Path.join(event_dir, @index_file)

    with {:ok, index_entries} <- read_index_entries(index_path),
         filtered_entries = filter_by_time_range(index_entries, from_time, to_time, opts),
         {:ok, events} <- load_events_from_entries(event_dir, filtered_entries) do
      {:ok, events}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get index statistics.
  """
  def get_index_stats(event_dir) do
    index_path = Path.join(event_dir, @index_file)

    if File.exists?(index_path) do
      case read_index_entries(index_path) do
        {:ok, entries} ->
          stream_counts = count_by_stream(entries)
          type_counts = count_by_event_type(entries)

          {:ok,
           %{
             total_events: length(entries),
             streams: map_size(stream_counts),
             stream_distribution: stream_counts,
             event_types: map_size(type_counts),
             type_distribution: type_counts,
             date_range: get_date_range(entries),
             index_file_size: File.stat!(index_path).size
           }}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:ok,
       %{
         total_events: 0,
         streams: 0,
         stream_distribution: %{},
         event_types: 0,
         type_distribution: %{},
         date_range: nil,
         index_file_size: 0
       }}
    end
  end

  @doc """
  Rebuild the index from the event journal.
  """
  def rebuild_index(event_dir) do
    Logger.info("Rebuilding event index")

    alias MCPChat.Persistence.EventJournal

    index_path = Path.join(event_dir, @index_file)
    backup_path = "#{index_path}.backup.#{System.system_time()}"

    # Backup existing index if it exists
    if File.exists?(index_path) do
      File.copy(index_path, backup_path)
    end

    with {:ok, events} <- EventJournal.read_events_since(event_dir, 0),
         index_entries = build_index_entries_from_events(events),
         :ok <- File.rm(index_path),
         :ok <- write_index_entries(index_path, index_entries) do
      Logger.info("Index rebuild completed",
        events_indexed: length(events),
        backup_created: backup_path
      )

      {:ok,
       %{
         events_indexed: length(events),
         backup_file: backup_path
       }}
    else
      {:error, reason} ->
        Logger.error("Index rebuild failed", reason: inspect(reason))
        {:error, reason}
    end
  end

  @doc """
  Compact the index by removing entries for deleted events.
  """
  def compact_index(event_dir, keep_events_after_id) do
    index_path = Path.join(event_dir, @index_file)
    backup_path = "#{index_path}.backup.#{System.system_time()}"

    Logger.info("Compacting event index", keep_after: keep_events_after_id)

    with {:ok, all_entries} <- read_index_entries(index_path),
         :ok <- File.copy(index_path, backup_path),
         entries_to_keep = Enum.filter(all_entries, &(&1.event_id > keep_events_after_id)),
         :ok <- File.rm(index_path),
         :ok <- write_index_entries(index_path, entries_to_keep) do
      Logger.info("Index compaction completed",
        original_entries: length(all_entries),
        kept_entries: length(entries_to_keep),
        removed_entries: length(all_entries) - length(entries_to_keep)
      )

      {:ok,
       %{
         original_entry_count: length(all_entries),
         compacted_entry_count: length(entries_to_keep),
         backup_file: backup_path
       }}
    else
      {:error, reason} ->
        Logger.error("Index compaction failed", reason: inspect(reason))
        {:error, reason}
    end
  end

  # Private functions

  defp read_index_entries(index_path) do
    if File.exists?(index_path) do
      try do
        case File.open(index_path, [:read, :binary]) do
          {:ok, file} ->
            entries = read_entries_from_file(file, [])
            File.close(file)
            {:ok, Enum.reverse(entries)}

          {:error, reason} ->
            {:error, reason}
        end
      rescue
        error ->
          Logger.error("Failed to read index entries", error: inspect(error))
          {:error, {:read_failed, error}}
      end
    else
      {:ok, []}
    end
  end

  defp read_entries_from_file(file, acc) do
    case read_next_index_entry(file) do
      {:ok, entry} ->
        read_entries_from_file(file, [entry | acc])

      :eof ->
        acc

      {:error, reason} ->
        Logger.warning("Error reading index entry", reason: inspect(reason))
        acc
    end
  end

  defp read_next_index_entry(file) do
    case IO.binread(file, 4) do
      <<size::32>> ->
        case IO.binread(file, size) do
          data when byte_size(data) == size ->
            try do
              entry = :erlang.binary_to_term(data)
              {:ok, entry}
            rescue
              error ->
                {:error, {:deserialization_failed, error}}
            end

          data when is_binary(data) ->
            {:error, {:incomplete_read, expected: size, got: byte_size(data)}}

          :eof ->
            :eof
        end

      data when byte_size(data) < 4 ->
        :eof

      :eof ->
        :eof
    end
  end

  defp filter_stream_entries(entries, stream_id, opts) do
    entries
    |> Enum.filter(&(&1.stream_id == stream_id))
    |> apply_common_filters(opts)
  end

  defp filter_by_event_type(entries, event_type, opts) do
    entries
    |> Enum.filter(&(&1.event_type == event_type))
    |> apply_common_filters(opts)
  end

  defp filter_by_time_range(entries, from_time, to_time, opts) do
    entries
    |> Enum.filter(fn entry ->
      entry.timestamp &&
        DateTime.compare(entry.timestamp, from_time) != :lt &&
        DateTime.compare(entry.timestamp, to_time) != :gt
    end)
    |> apply_common_filters(opts)
  end

  defp apply_common_filters(entries, opts) do
    entries
    |> apply_limit(opts[:limit])
    |> apply_offset(opts[:offset])
    |> apply_order(opts[:order])
  end

  defp apply_limit(entries, nil), do: entries
  defp apply_limit(entries, limit), do: Enum.take(entries, limit)

  defp apply_offset(entries, nil), do: entries
  defp apply_offset(entries, offset), do: Enum.drop(entries, offset)

  defp apply_order(entries, :desc), do: Enum.reverse(entries)
  defp apply_order(entries, _), do: entries

  defp load_events_from_entries(event_dir, entries) do
    alias MCPChat.Persistence.EventJournal

    # For now, we'll use a simple approach and load all events
    # In a production system, this would use WAL offsets for direct access
    case EventJournal.read_events_since(event_dir, 0) do
      {:ok, all_events} ->
        event_ids = MapSet.new(entries, & &1.event_id)
        filtered_events = Enum.filter(all_events, &MapSet.member?(event_ids, &1.event_id))
        {:ok, filtered_events}

      {:error, reason} ->
        {:error, reason}
    end
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

  defp write_index_entries(index_path, entries) do
    File.open(index_path, [:write, :binary], fn file ->
      entries_data = encode_index_entries(entries)
      IO.binwrite(file, entries_data)
    end)
  end

  defp build_index_entries_from_events(events) do
    Enum.map(events, fn event ->
      %__MODULE__{
        event_id: event.event_id,
        stream_id: event.stream_id,
        event_type: event.event_type,
        timestamp: event.timestamp,
        # Would be calculated in production
        wal_offset: 0,
        # Would be calculated in production
        wal_size: 0
      }
    end)
  end

  defp count_by_stream(entries) do
    Enum.reduce(entries, %{}, fn entry, acc ->
      Map.update(acc, entry.stream_id, 1, &(&1 + 1))
    end)
  end

  defp count_by_event_type(entries) do
    Enum.reduce(entries, %{}, fn entry, acc ->
      Map.update(acc, entry.event_type, 1, &(&1 + 1))
    end)
  end

  defp get_date_range(entries) do
    timestamps = Enum.map(entries, & &1.timestamp) |> Enum.filter(& &1)

    case timestamps do
      [] ->
        nil

      _ ->
        %{
          earliest: Enum.min(timestamps, DateTime),
          latest: Enum.max(timestamps, DateTime)
        }
    end
  end
end
