defmodule MCPChat.Persistence.EventJournal do
  @moduledoc """
  Low-level event journal for reading and writing events to disk.

  This module handles the actual file I/O for event persistence,
  including write-ahead logging format and event serialization.
  """

  require Logger

  @wal_file "event_store.wal"
  # 1MB chunks
  @journal_chunk_size 1_000_000

  @doc """
  Read all events since a specific event ID.
  """
  def read_events_since(event_dir, from_event_id) do
    wal_path = Path.join(event_dir, @wal_file)

    if File.exists?(wal_path) do
      read_wal_events(wal_path, from_event_id)
    else
      {:ok, []}
    end
  end

  @doc """
  Read events in a specific range.
  """
  def read_events_range(event_dir, from_event_id, to_event_id) do
    case read_events_since(event_dir, from_event_id) do
      {:ok, events} ->
        filtered_events =
          Enum.filter(events, fn event ->
            event.event_id <= to_event_id
          end)

        {:ok, filtered_events}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Find the last snapshot marker in the event journal.
  """
  def find_last_snapshot(event_dir) do
    case read_events_since(event_dir, 0) do
      {:ok, events} ->
        snapshot_events =
          Enum.filter(events, fn event ->
            event.event_type == :snapshot_created
          end)

        case Enum.max_by(snapshot_events, & &1.event_id, fn -> nil end) do
          nil -> {:error, :not_found}
          snapshot_event -> {:ok, snapshot_event.event_id}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Append events to the journal file.
  This is used for recovery and maintenance operations.
  """
  def append_events_to_journal(event_dir, events) do
    wal_path = Path.join(event_dir, @wal_file)

    File.open(wal_path, [:append, :binary], fn file ->
      events_data = encode_events_for_wal(events)
      IO.binwrite(file, events_data)
    end)
  end

  @doc """
  Get journal statistics and health information.
  """
  def get_journal_stats(event_dir) do
    wal_path = Path.join(event_dir, @wal_file)

    if File.exists?(wal_path) do
      case File.stat(wal_path) do
        {:ok, %File.Stat{size: size}} ->
          {:ok,
           %{
             journal_file_size: size,
             estimated_event_count: estimate_event_count(size),
             journal_path: wal_path,
             last_modified: File.stat!(wal_path).mtime
           }}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:ok,
       %{
         journal_file_size: 0,
         estimated_event_count: 0,
         journal_path: wal_path,
         last_modified: nil
       }}
    end
  end

  @doc """
  Compact the journal by removing old events before a snapshot.
  """
  def compact_journal(event_dir, keep_events_after_id) do
    wal_path = Path.join(event_dir, @wal_file)
    backup_path = "#{wal_path}.backup.#{System.system_time()}"

    Logger.info("Compacting journal",
      keep_after: keep_events_after_id,
      backup_path: backup_path
    )

    with {:ok, all_events} <- read_events_since(event_dir, 0),
         :ok <- File.copy(wal_path, backup_path),
         events_to_keep = Enum.filter(all_events, &(&1.event_id > keep_events_after_id)),
         :ok <- File.rm(wal_path),
         :ok <- append_events_to_journal(event_dir, events_to_keep) do
      Logger.info("Journal compaction completed",
        original_events: length(all_events),
        kept_events: length(events_to_keep),
        removed_events: length(all_events) - length(events_to_keep)
      )

      {:ok,
       %{
         original_event_count: length(all_events),
         compacted_event_count: length(events_to_keep),
         backup_file: backup_path
       }}
    else
      {:error, reason} ->
        Logger.error("Journal compaction failed", reason: inspect(reason))
        {:error, reason}
    end
  end

  @doc """
  Verify journal integrity by reading all events.
  """
  def verify_journal_integrity(event_dir) do
    Logger.info("Verifying journal integrity")

    case read_events_since(event_dir, 0) do
      {:ok, events} ->
        issues = check_event_integrity(events)

        if Enum.empty?(issues) do
          Logger.info("Journal integrity verified", event_count: length(events))

          {:ok,
           %{
             status: :healthy,
             event_count: length(events),
             issues: []
           }}
        else
          Logger.warning("Journal integrity issues found", issues: issues)

          {:ok,
           %{
             status: :issues_found,
             event_count: length(events),
             issues: issues
           }}
        end

      {:error, reason} ->
        Logger.error("Journal integrity check failed", reason: inspect(reason))
        {:error, reason}
    end
  end

  # Private functions

  defp read_wal_events(wal_path, from_event_id) do
    try do
      case File.open(wal_path, [:read, :binary]) do
        {:ok, file} ->
          events = read_events_from_file(file, from_event_id, [])
          File.close(file)
          {:ok, Enum.reverse(events)}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Failed to read WAL events", error: inspect(error))
        {:error, {:read_failed, error}}
    end
  end

  defp read_events_from_file(file, from_event_id, acc) do
    case read_next_event(file) do
      {:ok, event} ->
        if event.event_id >= from_event_id do
          read_events_from_file(file, from_event_id, [event | acc])
        else
          read_events_from_file(file, from_event_id, acc)
        end

      :eof ->
        acc

      {:error, reason} ->
        Logger.warning("Error reading event from file", reason: inspect(reason))
        acc
    end
  end

  defp read_next_event(file) do
    case IO.binread(file, 4) do
      <<size::32>> ->
        case IO.binread(file, size) do
          data when byte_size(data) == size ->
            try do
              event = :erlang.binary_to_term(data)
              {:ok, event}
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

  defp encode_events_for_wal(events) do
    events
    |> Enum.map(&:erlang.term_to_binary/1)
    |> Enum.map(fn serialized ->
      size = byte_size(serialized)
      <<size::32, serialized::binary>>
    end)
    |> IO.iodata_to_binary()
  end

  defp estimate_event_count(file_size) do
    # Rough estimate: average event size is ~200 bytes
    # Plus 4 bytes for size header
    div(file_size, 204)
  end

  defp check_event_integrity(events) do
    issues = []

    # Check for sequential event IDs
    issues = check_sequential_ids(events, issues)

    # Check for required fields
    issues = check_required_fields(events, issues)

    # Check for timestamp ordering
    issues = check_timestamp_ordering(events, issues)

    issues
  end

  defp check_sequential_ids(events, issues) do
    sorted_events = Enum.sort_by(events, & &1.event_id)

    {_, new_issues} =
      Enum.reduce(sorted_events, {nil, issues}, fn event, {last_id, acc_issues} ->
        if last_id && event.event_id != last_id + 1 do
          issue = {:missing_event_id, expected: last_id + 1, found: event.event_id}
          {event.event_id, [issue | acc_issues]}
        else
          {event.event_id, acc_issues}
        end
      end)

    new_issues
  end

  defp check_required_fields(events, issues) do
    required_fields = [:event_id, :event_type, :timestamp]

    Enum.reduce(events, issues, fn event, acc_issues ->
      missing_fields =
        Enum.filter(required_fields, fn field ->
          not Map.has_key?(event, field)
        end)

      if Enum.empty?(missing_fields) do
        acc_issues
      else
        issue = {:missing_fields, event_id: event.event_id, fields: missing_fields}
        [issue | acc_issues]
      end
    end)
  end

  defp check_timestamp_ordering(events, issues) do
    sorted_events = Enum.sort_by(events, & &1.event_id)

    {_, new_issues} =
      Enum.reduce(sorted_events, {nil, issues}, fn event, {last_timestamp, acc_issues} ->
        if last_timestamp && event.timestamp &&
             DateTime.compare(event.timestamp, last_timestamp) == :lt do
          issue =
            {:timestamp_out_of_order,
             event_id: event.event_id, timestamp: event.timestamp, previous_timestamp: last_timestamp}

          {event.timestamp, [issue | acc_issues]}
        else
          {event.timestamp, acc_issues}
        end
      end)

    new_issues
  end
end
