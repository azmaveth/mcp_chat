defmodule MCPChat.Streaming.StreamManager do
  @moduledoc """
  Manages streaming responses with buffering, backpressure, and async processing.

  Features:
  - Configurable buffer size with backpressure
  - Async chunk processing to handle slow consumers
  - Chunk batching to reduce I/O operations
  - Graceful handling of consumer slowdowns
  - Metrics tracking for performance monitoring
  """

  use GenServer
  require Logger

  alias MCPChat.CLI.Renderer

  @default_buffer_size 50
  @default_batch_size 5
  # ms
  @default_batch_timeout 50
  # ms
  @default_consumer_timeout 5_000

  defmodule State do
    @moduledoc false
    defstruct [
      :stream,
      :consumer_pid,
      :buffer,
      :batch,
      :batch_timer,
      :buffer_size,
      :batch_size,
      :batch_timeout,
      :consumer_timeout,
      :stats,
      :paused,
      :done
    ]
  end

  # Client API

  @doc """
  Starts a stream manager for handling a streaming response.

  Options:
  - `:buffer_size` - Maximum buffer size before applying backpressure (default: 50)
  - `:batch_size` - Number of chunks to batch before writing (default: 5)
  - `:batch_timeout` - Max time to wait for batch to fill (default: 50ms)
  - `:consumer_timeout` - Max time to wait for consumer (default: 5000ms)
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Processes a stream with managed buffering and backpressure.

  Returns the accumulated response and statistics.
  """
  def process_stream(manager, stream) do
    GenServer.call(manager, {:process_stream, stream}, :infinity)
  end

  @doc """
  Gets current statistics for the stream processing.
  """
  def get_stats(manager) do
    GenServer.call(manager, :get_stats)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %State{
      buffer: :queue.new(),
      batch: [],
      buffer_size: Keyword.get(opts, :buffer_size, @default_buffer_size),
      batch_size: Keyword.get(opts, :batch_size, @default_batch_size),
      batch_timeout: Keyword.get(opts, :batch_timeout, @default_batch_timeout),
      consumer_timeout: Keyword.get(opts, :consumer_timeout, @default_consumer_timeout),
      stats: %{
        chunks_received: 0,
        chunks_processed: 0,
        batches_written: 0,
        buffer_overflows: 0,
        consumer_slowdowns: 0,
        total_bytes: 0,
        start_time: System.monotonic_time(:millisecond)
      },
      paused: false,
      done: false
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:process_stream, stream}, {consumer_pid, _}, state) do
    # Start async producer
    producer_task =
      Task.async(fn ->
        produce_chunks(self(), stream)
      end)

    # Start async consumer
    consumer_task =
      Task.async(fn ->
        consume_chunks(self(), consumer_pid)
      end)

    state = %{state | stream: stream, consumer_pid: consumer_pid}

    # Wait for both to complete
    try do
      Task.await(producer_task, :infinity)
      response = Task.await(consumer_task, :infinity)

      stats = finalize_stats(state.stats)
      {:reply, {:ok, response, stats}, state}
    catch
      :exit, reason ->
        Logger.error("Stream processing failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end

  @impl true
  def handle_cast({:chunk, chunk}, state) do
    state = update_stats(state, :chunks_received, chunk)

    # Check buffer capacity
    buffer_size = :queue.len(state.buffer)

    state =
      if buffer_size >= state.buffer_size do
        # Apply backpressure
        Logger.debug("Buffer full, applying backpressure")
        update_stats(state, :buffer_overflows)
      else
        # Add to buffer
        buffer = :queue.in(chunk, state.buffer)
        %{state | buffer: buffer}
      end

    # Try to process buffer
    state = process_buffer(state)

    {:noreply, state}
  end

  @impl true
  def handle_cast(:stream_done, state) do
    # Flush remaining chunks
    state = flush_batch(state)
    state = flush_buffer(state)

    {:noreply, %{state | done: true}}
  end

  @impl true
  def handle_cast(:request_chunk, state) do
    state = process_buffer(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:batch_timeout, state) do
    state = flush_batch(state)
    {:noreply, state}
  end

  # Private Functions

  defp produce_chunks(manager, stream) do
    stream
    |> Stream.each(fn chunk ->
      GenServer.cast(manager, {:chunk, chunk})
      # Simple backpressure - wait a bit if we're producing too fast
      Process.sleep(1)
    end)
    |> Stream.run()

    GenServer.cast(manager, :stream_done)
  end

  defp consume_chunks(manager, consumer_pid) do
    consume_loop(manager, consumer_pid, "")
  end

  defp consume_loop(manager, consumer_pid, acc) do
    GenServer.cast(manager, :request_chunk)

    receive do
      {:chunk_batch, chunks} ->
        # Process batch of chunks
        text = Enum.join(chunks, "")

        # Send to renderer with timeout handling
        case send_to_renderer(text, consumer_pid) do
          :ok ->
            new_acc = acc <> text
            consume_loop(manager, consumer_pid, new_acc)

          {:error, :timeout} ->
            Logger.warn("Consumer timeout, slowing down")
            Process.sleep(100)
            consume_loop(manager, consumer_pid, acc)
        end

      :stream_complete ->
        acc
    after
      5_000 ->
        Logger.error("Consumer timeout waiting for chunks")
        acc
    end
  end

  defp process_buffer(state) do
    if :queue.len(state.buffer) > 0 and not state.paused do
      case :queue.out(state.buffer) do
        {{:value, chunk}, new_buffer} ->
          state = %{state | buffer: new_buffer}
          state = update_stats(state, :chunks_processed)

          # Add to batch
          new_batch = [chunk | state.batch]

          cond do
            # Batch is full
            length(new_batch) >= state.batch_size ->
              flush_batch(%{state | batch: new_batch})

            # First chunk in batch, start timer
            Enum.empty?(state.batch) ->
              timer = Process.send_after(self(), :batch_timeout, state.batch_timeout)
              %{state | batch: new_batch, batch_timer: timer}

            # Add to existing batch
            true ->
              %{state | batch: new_batch}
          end

        {:empty, _} ->
          state
      end
    else
      state
    end
  end

  defp flush_batch(%{batch: []} = state), do: state

  defp flush_batch(state) do
    # Cancel timer if exists
    if state.batch_timer do
      Process.cancel_timer(state.batch_timer)
    end

    # Send batch to consumer
    chunks = Enum.reverse(state.batch)
    send(state.consumer_pid, {:chunk_batch, chunks})

    state
    |> update_stats(:batches_written)
    |> Map.put(:batch, [])
    |> Map.put(:batch_timer, nil)
  end

  defp flush_buffer(state) do
    if :queue.len(state.buffer) > 0 do
      state
      |> flush_batch()
      |> process_buffer()
      |> flush_buffer()
    else
      # Signal completion
      send(state.consumer_pid, :stream_complete)
      state
    end
  end

  defp send_to_renderer(text, consumer_pid) do
    task =
      Task.async(fn ->
        send(consumer_pid, {:render_chunk, text})
        :ok
      end)

    case Task.yield(task, 100) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end

  defp update_stats(state, key, chunk \\ nil) do
    stats =
      case key do
        :chunks_received when not is_nil(chunk) ->
          bytes = byte_size(chunk.delta || "")

          state.stats
          |> Map.update!(key, &(&1 + 1))
          |> Map.update!(:total_bytes, &(&1 + bytes))

        _ ->
          Map.update!(state.stats, key, &(&1 + 1))
      end

    %{state | stats: stats}
  end

  defp finalize_stats(stats) do
    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - stats.start_time

    stats
    |> Map.put(:duration_ms, duration_ms)
    |> Map.put(:throughput_bytes_per_sec, stats.total_bytes * 1_000 / max(duration_ms, 1))
    |> Map.put(:avg_batch_size, stats.chunks_processed / max(stats.batches_written, 1))
  end
end
