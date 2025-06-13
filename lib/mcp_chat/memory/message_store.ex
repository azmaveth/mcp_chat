defmodule MCPChat.Memory.MessageStore do
  @moduledoc """
  Efficient message storage with pagination support.
  Manages chat history to optimize memory usage while maintaining
  quick access to recent messages and supporting full history retrieval.

  Features:
  - In-memory cache for recent messages
  - Disk-based storage for older messages
  - Configurable memory limits
  - Pagination support for history retrieval
  - Automatic cleanup of old sessions
  """

  use GenServer
  require Logger

  # Keep last N messages in memory
  @default_memory_limit 100
  # Messages per page when loading
  @default_page_size 50
  # Max messages to keep on disk per session
  @default_max_disk_size 10_000

  defstruct [
    :session_id,
    :memory_limit,
    :page_size,
    :max_disk_size,
    # Recent messages in memory
    :memory_cache,
    # Path to disk storage
    :disk_path,
    # Total message count
    :message_count,
    # For cleanup
    :last_accessed
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  def add_message(store \\ __MODULE__, message) do
    GenServer.call(store, {:add_message, message})
  end

  def get_recent_messages(store \\ __MODULE__, count \\ nil) do
    GenServer.call(store, {:get_recent, count})
  end

  def get_page(store \\ __MODULE__, page_number \\ 1) do
    GenServer.call(store, {:get_page, page_number})
  end

  def get_all_messages(store \\ __MODULE__) do
    # Longer timeout for large histories
    GenServer.call(store, :get_all, 30_000)
  end

  def clear_session(store \\ __MODULE__, session_id) do
    GenServer.call(store, {:clear_session, session_id})
  end

  def get_stats(store \\ __MODULE__) do
    GenServer.call(store, :get_stats)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    session_id = opts[:session_id] || "default"
    memory_limit = opts[:memory_limit] || config_value(:memory_limit, @default_memory_limit)
    page_size = opts[:page_size] || config_value(:page_size, @default_page_size)
    max_disk_size = opts[:max_disk_size] || config_value(:max_disk_size, @default_max_disk_size)

    storage_dir = Path.expand("~/.config/mcp_chat/message_store")
    File.mkdir_p!(storage_dir)
    disk_path = Path.join(storage_dir, "#{session_id}.msgpack")

    state = %__MODULE__{
      session_id: session_id,
      memory_limit: memory_limit,
      page_size: page_size,
      max_disk_size: max_disk_size,
      memory_cache: [],
      disk_path: disk_path,
      message_count: load_message_count(disk_path),
      last_accessed: System.system_time(:second)
    }

    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup_check, :timer.hours(1))

    {:ok, state}
  end

  @impl true
  def handle_call({:add_message, message}, _from, state) do
    # Add timestamp if not present
    message = Map.put_new(message, :timestamp, DateTime.utc_now())

    # Update memory cache
    new_cache = [message | state.memory_cache]

    # Trim cache if needed
    {kept_cache, overflow} =
      if length(new_cache) > state.memory_limit do
        Enum.split(new_cache, state.memory_limit)
      else
        {new_cache, []}
      end

    # Write overflow to disk
    new_state =
      if overflow != [] do
        write_to_disk(state, overflow)
      else
        state
      end

    new_state = %{
      new_state
      | memory_cache: kept_cache,
        message_count: state.message_count + 1,
        last_accessed: System.system_time(:second)
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get_recent, count}, _from, state) do
    messages =
      if count do
        Enum.take(state.memory_cache, count)
      else
        state.memory_cache
      end

    state = %{state | last_accessed: System.system_time(:second)}
    {:reply, {:ok, Enum.reverse(messages)}, state}
  end

  @impl true
  def handle_call({:get_page, page_number}, _from, state) do
    offset = (page_number - 1) * state.page_size
    disk_message_count = state.message_count - length(state.memory_cache)

    messages =
      cond do
        # All messages for this page are on disk
        offset + state.page_size <= disk_message_count ->
          load_page_from_disk(state, offset, state.page_size)

        # Page spans disk and memory
        offset < disk_message_count ->
          disk_messages = load_page_from_disk(state, offset, disk_message_count - offset)
          memory_needed = state.page_size - length(disk_messages)

          memory_messages =
            state.memory_cache
            |> Enum.reverse()
            |> Enum.take(memory_needed)

          disk_messages ++ memory_messages

        # All messages for this page are in memory
        true ->
          memory_offset = offset - disk_message_count

          state.memory_cache
          |> Enum.reverse()
          |> Enum.drop(memory_offset)
          |> Enum.take(state.page_size)
      end

    total_pages = ceil(state.message_count / state.page_size)

    result = %{
      messages: messages,
      page: page_number,
      total_pages: total_pages,
      total_messages: state.message_count,
      has_next: page_number < total_pages,
      has_prev: page_number > 1
    }

    state = %{state | last_accessed: System.system_time(:second)}
    {:reply, {:ok, result}, state}
  end

  @impl true
  def handle_call(:get_all, _from, state) do
    # Load all messages from both memory and disk
    memory_messages = Enum.reverse(state.memory_cache)
    disk_messages = load_all_from_disk(state)
    all_messages = memory_messages ++ disk_messages

    state = %{state | last_accessed: System.system_time(:second)}
    {:reply, {:ok, all_messages}, state}
  end

  @impl true
  def handle_call({:clear_session, session_id}, _from, state) do
    if state.session_id == session_id do
      # Clear memory and disk
      File.rm(state.disk_path)
      new_state = %{state | memory_cache: [], message_count: 0, last_accessed: System.system_time(:second)}
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :wrong_session}, state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    disk_size =
      case File.stat(state.disk_path) do
        {:ok, %{size: size}} -> size
        _ -> 0
      end

    stats = %{
      session_id: state.session_id,
      messages_in_memory: length(state.memory_cache),
      total_messages: state.message_count,
      memory_limit: state.memory_limit,
      disk_size_bytes: disk_size,
      last_accessed: DateTime.from_unix!(state.last_accessed)
    }

    {:reply, {:ok, stats}, state}
  end

  @impl true
  def handle_info(:cleanup_check, state) do
    # Check if session hasn't been accessed in 24 hours
    now = System.system_time(:second)
    # 24 hours
    if now - state.last_accessed > 86_400 do
      Logger.info("Cleaning up idle message store for session: #{state.session_id}")
      # Could implement auto-cleanup here
    end

    # Schedule next check
    Process.send_after(self(), :cleanup_check, :timer.hours(1))
    {:noreply, state}
  end

  # Private functions

  defp config_value(key, default) do
    case MCPChat.Config.get([:memory, key]) do
      {:ok, value} -> value
      _ -> default
    end
  end

  defp load_message_count(disk_path) do
    case File.exists?(disk_path) do
      true ->
        case File.read(disk_path) do
          {:ok, content} ->
            # Simple line count for now
            content
            |> String.split("\n", trim: true)
            |> length()

          _ ->
            0
        end

      false ->
        0
    end
  end

  defp write_to_disk(state, messages) do
    # Append messages to disk file
    content =
      messages
      # Maintain chronological order
      |> Enum.reverse()
      |> Enum.map_join("\n", &Jason.encode!/1)

    case File.open(state.disk_path, [:append]) do
      {:ok, file} ->
        IO.puts(file, content)
        File.close(file)

        # Check if we need to trim old messages
        maybe_trim_disk_file(state)

      {:error, reason} ->
        Logger.error("Failed to write messages to disk: #{inspect(reason)}")
    end

    state
  end

  defp load_page_from_disk(state, offset, limit) do
    case File.read(state.disk_path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.drop(offset)
        |> Enum.take(limit)
        |> Enum.map(&decode_message/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp load_all_from_disk(state) do
    case File.read(state.disk_path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.map(&decode_message/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp decode_message(line) do
    case Jason.decode(line) do
      {:ok, message} ->
        # Convert string keys to atoms for consistency
        message
        |> Enum.map(fn
          {k, v} when is_binary(k) ->
            # Safely convert known keys to atoms
            key =
              case k do
                "role" -> :role
                "content" -> :content
                "timestamp" -> :timestamp
                _ -> k
              end

            {key, v}

          {k, v} ->
            {k, v}
        end)
        |> Map.new()

      _ ->
        nil
    end
  end

  defp maybe_trim_disk_file(state) do
    if state.message_count > state.max_disk_size do
      # Keep only the most recent messages
      keep_count = state.max_disk_size - state.memory_limit

      case File.read(state.disk_path) do
        {:ok, content} ->
          lines = String.split(content, "\n", trim: true)

          if length(lines) > keep_count do
            trimmed =
              lines
              |> Enum.take(-keep_count)
              |> Enum.join("\n")

            File.write!(state.disk_path, trimmed <> "\n")
          end

        _ ->
          :ok
      end
    end
  end
end
