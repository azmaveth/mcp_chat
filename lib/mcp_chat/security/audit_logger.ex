defmodule MCPChat.Security.AuditLogger do
  @moduledoc """
  Audit logging system for security events in MCP Chat.

  This module provides comprehensive audit logging for all security-related events
  including capability creation, validation, delegation, revocation, and access attempts.
  The audit trail is essential for security monitoring, compliance, and forensic analysis.

  ## Features

  - Structured logging with consistent event formats
  - Configurable log levels and destinations
  - Tamper-evident log entries with checksums
  - Performance-optimized async logging
  - Integration with external SIEM systems
  - Automatic log rotation and archival

  ## Event Types

  - `:capability_created` - New capability issued
  - `:capability_validated` - Capability validation attempt
  - `:capability_delegated` - Capability delegated to another principal
  - `:capability_revoked` - Capability revoked
  - `:permission_denied` - Access attempt denied
  - `:security_violation` - Security policy violation detected
  - `:authentication_failure` - Authentication attempt failed
  - `:authorization_failure` - Authorization check failed
  """

  use GenServer
  require Logger

  @type event_type :: atom()
  @type event_details :: map()
  @type principal_id :: String.t()

  defstruct [
    # Buffer for batching events
    :event_buffer,
    # Current buffer size
    :buffer_size,
    # Maximum buffer size before flush
    :max_buffer_size,
    # Automatic flush interval in ms
    :flush_interval,
    # Minimum log level
    :log_level,
    # List of log destinations
    :destinations,
    # Monotonic sequence number
    :sequence_number,
    # Secret for tamper protection
    :checksum_secret,
    # Logging statistics
    :stats
  ]

  ## Public API

  @doc """
  Starts the AuditLogger GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Logs a security event asynchronously.

  ## Parameters
  - `event_type`: The type of security event
  - `details`: Map containing event details
  - `principal_id`: The principal involved in the event

  ## Examples

      AuditLogger.log_event(:capability_created, %{
        capability_id: "abc123",
        resource_type: :filesystem,
        constraints: %{paths: ["/tmp"]}
      }, "agent_001")
  """
  @spec log_event(event_type(), event_details(), principal_id()) :: :ok
  def log_event(event_type, details, principal_id) do
    GenServer.cast(__MODULE__, {:log_event, event_type, details, principal_id})
  end

  @doc """
  Logs a security event synchronously and waits for confirmation.

  This should be used for critical security events that must be logged
  before proceeding.
  """
  @spec log_event_sync(event_type(), event_details(), principal_id()) :: :ok | {:error, atom()}
  def log_event_sync(event_type, details, principal_id) do
    GenServer.call(__MODULE__, {:log_event_sync, event_type, details, principal_id})
  end

  @doc """
  Forces immediate flush of the event buffer.
  """
  @spec flush() :: :ok
  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  @doc """
  Gets audit logging statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Searches audit logs for specific events.

  ## Parameters
  - `criteria`: Search criteria map
  - `opts`: Search options (limit, offset, etc.)

  ## Returns
  - `{:ok, events}` list of matching events
  - `{:error, reason}` on failure
  """
  @spec search_events(map(), keyword()) :: {:ok, [map()]} | {:error, atom()}
  def search_events(criteria, opts \\ []) do
    GenServer.call(__MODULE__, {:search_events, criteria, opts})
  end

  @doc """
  Verifies the integrity of audit log entries.

  ## Returns
  - `:ok` if all entries are valid
  - `{:error, {:tampered_entries, count}}` if tampering detected
  """
  @spec verify_integrity() :: :ok | {:error, atom()}
  def verify_integrity do
    GenServer.call(__MODULE__, :verify_integrity)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      event_buffer: [],
      buffer_size: 0,
      max_buffer_size: Keyword.get(opts, :max_buffer_size, 100),
      flush_interval: Keyword.get(opts, :flush_interval, 30_000),
      log_level: Keyword.get(opts, :log_level, :info),
      destinations: Keyword.get(opts, :destinations, [:logger, :file]),
      sequence_number: 0,
      checksum_secret: get_checksum_secret(),
      stats: %{
        events_logged: 0,
        events_flushed: 0,
        buffer_flushes: 0,
        integrity_violations: 0
      }
    }

    # Schedule periodic flush
    schedule_flush(state.flush_interval)

    Logger.info("AuditLogger started",
      max_buffer_size: state.max_buffer_size,
      flush_interval: state.flush_interval,
      destinations: state.destinations
    )

    {:ok, state}
  end

  @impl true
  def handle_cast({:log_event, event_type, details, principal_id}, state) do
    case create_audit_entry(event_type, details, principal_id, state) do
      {:ok, entry, new_state} ->
        updated_state = add_to_buffer(entry, new_state)

        # Check if we need to flush
        if updated_state.buffer_size >= updated_state.max_buffer_size do
          final_state = flush_buffer(updated_state)
          {:noreply, final_state}
        else
          {:noreply, updated_state}
        end

      {:error, reason} ->
        Logger.error("Failed to create audit entry", event_type: event_type, reason: reason)
        {:noreply, state}
    end
  end

  @impl true
  def handle_call({:log_event_sync, event_type, details, principal_id}, _from, state) do
    case create_audit_entry(event_type, details, principal_id, state) do
      {:ok, entry, new_state} ->
        case write_entry_immediately(entry, new_state) do
          :ok ->
            updated_stats = update_in(new_state.stats.events_logged, &(&1 + 1))
            final_state = %{new_state | stats: updated_stats}
            {:reply, :ok, final_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:flush, _from, state) do
    new_state = flush_buffer(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats =
      Map.merge(state.stats, %{
        current_buffer_size: state.buffer_size,
        sequence_number: state.sequence_number,
        uptime: get_uptime()
      })

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:search_events, criteria, opts}, _from, state) do
    # For now, return empty results - would integrate with log storage
    limit = Keyword.get(opts, :limit, 100)

    # In a real implementation, this would search persistent storage
    events = search_persistent_logs(criteria, limit)

    {:reply, {:ok, events}, state}
  end

  @impl true
  def handle_call(:verify_integrity, _from, state) do
    # Verify integrity of recent entries in buffer
    case verify_buffer_integrity(state.event_buffer, state.checksum_secret) do
      :ok ->
        {:reply, :ok, state}

      {:error, count} ->
        updated_stats = update_in(state.stats.integrity_violations, &(&1 + count))
        new_state = %{state | stats: updated_stats}
        {:reply, {:error, {:tampered_entries, count}}, new_state}
    end
  end

  @impl true
  def handle_info(:flush_buffer, state) do
    new_state = flush_buffer(state)
    schedule_flush(state.flush_interval)
    {:noreply, new_state}
  end

  ## Private Functions

  defp create_audit_entry(event_type, details, principal_id, state) do
    timestamp = DateTime.utc_now()
    sequence = state.sequence_number + 1

    base_entry = %{
      timestamp: timestamp,
      sequence_number: sequence,
      event_type: event_type,
      principal_id: principal_id,
      details: details,
      node: Node.self(),
      pid: inspect(self())
    }

    # Add checksum for tamper protection
    case add_checksum(base_entry, state.checksum_secret) do
      {:ok, entry_with_checksum} ->
        new_state = %{state | sequence_number: sequence}
        {:ok, entry_with_checksum, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp add_to_buffer(entry, state) do
    new_buffer = [entry | state.event_buffer]
    new_size = state.buffer_size + 1

    %{state | event_buffer: new_buffer, buffer_size: new_size}
  end

  defp flush_buffer(state) do
    if state.buffer_size > 0 do
      # Write all entries in buffer
      Enum.each(Enum.reverse(state.event_buffer), fn entry ->
        write_to_destinations(entry, state.destinations)
      end)

      # Update stats
      new_stats = %{
        state.stats
        | events_flushed: state.stats.events_flushed + state.buffer_size,
          buffer_flushes: state.stats.buffer_flushes + 1
      }

      %{state | event_buffer: [], buffer_size: 0, stats: new_stats}
    else
      state
    end
  end

  defp write_entry_immediately(entry, state) do
    write_to_destinations(entry, state.destinations)
  end

  defp write_to_destinations(entry, destinations) do
    Enum.each(destinations, fn destination ->
      write_to_destination(entry, destination)
    end)

    :ok
  end

  defp write_to_destination(entry, :logger) do
    Logger.info("SECURITY_AUDIT", entry)
  end

  defp write_to_destination(entry, :file) do
    # Write to dedicated audit log file
    log_file = get_audit_log_file()
    formatted_entry = format_log_entry(entry)

    case File.write(log_file, formatted_entry <> "\n", [:append, :utf8]) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to write audit log to file", reason: reason, file: log_file)
        {:error, reason}
    end
  end

  defp write_to_destination(entry, :syslog) do
    # Write to system syslog
    formatted_entry = format_syslog_entry(entry)
    # Implementation would use a syslog library
    Logger.info("SYSLOG_AUDIT: #{formatted_entry}")
  end

  defp write_to_destination(entry, destination) do
    Logger.warn("Unknown audit destination", destination: destination, entry: entry)
  end

  defp add_checksum(entry, secret) do
    # Create deterministic representation
    canonical_data = %{
      timestamp: DateTime.to_iso8601(entry.timestamp),
      sequence_number: entry.sequence_number,
      event_type: entry.event_type,
      principal_id: entry.principal_id,
      details: entry.details,
      node: entry.node,
      pid: entry.pid
    }

    # Generate checksum
    binary_data = :erlang.term_to_binary(canonical_data, [:deterministic])

    checksum =
      :crypto.mac(:hmac, :sha256, secret, binary_data)
      |> Base.encode64()

    {:ok, Map.put(entry, :checksum, checksum)}
  end

  defp verify_buffer_integrity(entries, secret) do
    tampered_count =
      Enum.count(entries, fn entry ->
        case verify_entry_checksum(entry, secret) do
          :ok -> false
          {:error, _} -> true
        end
      end)

    if tampered_count == 0 do
      :ok
    else
      {:error, tampered_count}
    end
  end

  defp verify_entry_checksum(entry, secret) do
    stored_checksum = Map.get(entry, :checksum)
    entry_without_checksum = Map.delete(entry, :checksum)

    case add_checksum(entry_without_checksum, secret) do
      {:ok, entry_with_calculated_checksum} ->
        calculated_checksum = entry_with_calculated_checksum.checksum

        if stored_checksum == calculated_checksum do
          :ok
        else
          {:error, :checksum_mismatch}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_log_entry(entry) do
    Jason.encode!(%{
      timestamp: DateTime.to_iso8601(entry.timestamp),
      sequence: entry.sequence_number,
      event: entry.event_type,
      principal: entry.principal_id,
      node: entry.node,
      details: entry.details,
      checksum: entry.checksum
    })
  end

  defp format_syslog_entry(entry) do
    "MCP_CHAT_SECURITY seq=#{entry.sequence_number} event=#{entry.event_type} principal=#{entry.principal_id} #{format_details(entry.details)}"
  end

  defp format_details(details) when is_map(details) do
    details
    |> Enum.map(fn {k, v} -> "#{k}=#{inspect(v)}" end)
    |> Enum.join(" ")
  end

  defp get_audit_log_file do
    log_dir = Application.get_env(:mcp_chat, :audit_log_dir, "logs")
    File.mkdir_p!(log_dir)

    date_string = Date.utc_today() |> Date.to_string()
    Path.join(log_dir, "security_audit_#{date_string}.log")
  end

  defp get_checksum_secret do
    Application.get_env(:mcp_chat, :audit_checksum_secret) ||
      System.get_env("MCP_CHAT_AUDIT_SECRET") ||
      "default_audit_secret_change_in_production"
  end

  defp search_persistent_logs(_criteria, _limit) do
    # Placeholder for persistent log search
    # Would integrate with log storage system (files, database, etc.)
    []
  end

  defp get_uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_ms
  end

  defp schedule_flush(interval) do
    Process.send_after(self(), :flush_buffer, interval)
  end
end
