defmodule MCPChat.Streaming.EnhancedConsumer do
  @moduledoc """
  Enhanced streaming consumer with buffering and flow control.

  This module provides a better streaming experience by:
  - Handling backpressure from slow terminals
  - Batching small chunks to reduce I/O operations
  - Providing smooth output even with variable chunk sizes
  - Collecting metrics for performance monitoring
  """

  use GenServer
  require Logger

  alias MCPChat.Streaming.{StreamBuffer, StreamManager}
  alias MCPChat.CLI.Renderer

  defmodule State do
    @moduledoc false
    defstruct [
      :renderer_pid,
      :accumulated_response,
      :buffer,
      :write_timer,
      :config,
      :metrics
    ]
  end

  @default_config %{
    buffer_capacity: 100,
    # ms - how often to flush buffer
    write_interval: 25,
    # minimum chunks to batch
    min_batch_size: 3,
    # maximum chunks per write
    max_batch_size: 10,
    # ms - when to consider consumer slow
    slow_consumer_threshold: 50
  }

  # Client API

  @doc """
  Starts an enhanced consumer for streaming responses.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Consumes a stream with enhanced buffering and rendering.

  Returns {:ok, response, metrics} on success.
  """
  def consume_stream(consumer, stream, opts \\ []) do
    GenServer.call(consumer, {:consume_stream, stream, opts}, :infinity)
  end

  @doc """
  Processes a stream using the StreamManager for advanced flow control.
  """
  def process_with_manager(stream, opts \\ []) do
    {:ok, manager} = StreamManager.start_link(opts)

    try do
      StreamManager.process_stream(manager, stream)
    after
      GenServer.stop(manager)
    end
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config = Map.merge(@default_config, Map.new(opts))

    state = %State{
      # Can be overridden
      renderer_pid: self(),
      accumulated_response: "",
      buffer: StreamBuffer.new(config.buffer_capacity),
      config: config,
      metrics: init_metrics()
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:consume_stream, stream, opts}, _from, state) do
    state = %{state | renderer_pid: Keyword.get(opts, :renderer_pid, self()), metrics: init_metrics()}

    # Start write timer
    {:ok, timer} = :timer.send_interval(state.config.write_interval, :flush_buffer)
    state = %{state | write_timer: timer}

    # Process stream
    result =
      try do
        _updated_state =
          stream
          |> Stream.each(fn chunk ->
            GenServer.cast(self(), {:chunk, chunk})
          end)
          |> Stream.run()

        # Final flush
        GenServer.call(self(), :finalize, 5_000)
      catch
        kind, reason ->
          Logger.error("Stream processing error: #{kind} #{inspect(reason)}")
          {:error, {kind, reason}}
      after
        :timer.cancel(timer)
      end

    case result do
      {:ok, response, metrics} ->
        {:reply, {:ok, response, metrics}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:finalize, _from, state) do
    # Flush any remaining chunks
    state = flush_buffer(state)

    # Finalize metrics
    metrics = finalize_metrics(state.metrics)

    # End stream in renderer
    Renderer.end_stream()

    {:reply, {:ok, state.accumulated_response, metrics}, state}
  end

  @impl true
  def handle_cast({:chunk, chunk}, state) do
    # Update metrics
    state = update_chunk_metrics(state, chunk)

    # Add to buffer
    case StreamBuffer.push(state.buffer, chunk) do
      {:ok, new_buffer} ->
        state = %{state | buffer: new_buffer}

        # Check if we should flush eagerly
        if should_flush_eagerly?(state) do
          {:noreply, flush_buffer(state)}
        else
          {:noreply, state}
        end

      {:overflow, new_buffer} ->
        # Buffer full - flush immediately
        Logger.debug("Buffer overflow, flushing")
        state = %{state | buffer: new_buffer}
        state = update_metric(state, :buffer_overflows)
        {:noreply, flush_buffer(state)}
    end
  end

  @impl true
  def handle_info(:flush_buffer, state) do
    if StreamBuffer.empty?(state.buffer) do
      {:noreply, state}
    else
      {:noreply, flush_buffer(state)}
    end
  end

  @impl true
  def handle_info({:render_chunk, text}, state) do
    # Handle renderer callback
    Renderer.show_stream_chunk(text)
    {:noreply, state}
  end

  # Private Functions

  defp init_metrics do
    %{
      start_time: System.monotonic_time(:microsecond),
      chunks_received: 0,
      chunks_written: 0,
      bytes_received: 0,
      bytes_written: 0,
      write_operations: 0,
      buffer_overflows: 0,
      slow_writes: 0,
      min_chunk_size: nil,
      max_chunk_size: nil,
      total_chunk_size: 0
    }
  end

  defp update_chunk_metrics(state, chunk) do
    chunk_size = byte_size(chunk.delta || "")

    metrics =
      state.metrics
      |> Map.update!(:chunks_received, &(&1 + 1))
      |> Map.update!(:bytes_received, &(&1 + chunk_size))
      |> Map.update!(:total_chunk_size, &(&1 + chunk_size))
      |> update_min_max_chunk_size(chunk_size)

    %{state | metrics: metrics}
  end

  defp update_min_max_chunk_size(metrics, size) do
    metrics
    |> Map.update!(:min_chunk_size, fn
      nil -> size
      min -> min(min, size)
    end)
    |> Map.update!(:max_chunk_size, fn
      nil -> size
      max -> max(max, size)
    end)
  end

  defp update_metric(state, key, increment \\ 1) do
    metrics = Map.update!(state.metrics, key, &(&1 + increment))
    %{state | metrics: metrics}
  end

  defp should_flush_eagerly?(state) do
    buffer_size = StreamBuffer.size(state.buffer)

    # Flush if we have enough chunks or buffer is getting full
    buffer_size >= state.config.min_batch_size or
      StreamBuffer.fill_percentage(state.buffer) > 75
  end

  defp flush_buffer(state) do
    buffer_size = StreamBuffer.size(state.buffer)

    if buffer_size > 0 do
      # Pop batch of chunks
      batch_size = min(buffer_size, state.config.max_batch_size)
      {chunks, new_buffer} = StreamBuffer.pop_many(state.buffer, batch_size)

      # Combine chunks
      text =
        chunks
        |> Enum.map_join(&(&1.delta || ""))

      # Write with timing
      write_start = System.monotonic_time(:microsecond)
      write_to_renderer(text)
      write_duration = System.monotonic_time(:microsecond) - write_start

      # Update metrics
      state = %{state | buffer: new_buffer, accumulated_response: state.accumulated_response <> text}

      state =
        state
        |> update_metric(:chunks_written, length(chunks))
        |> update_metric(:bytes_written, byte_size(text))
        |> update_metric(:write_operations)

      # Check for slow write
      if write_duration > state.config.slow_consumer_threshold * 1_000 do
        _updated_state = update_metric(state, :slow_writes)
        Logger.debug("Slow write detected: #{write_duration}μs")
      end

      state
    else
      state
    end
  end

  defp write_to_renderer(text) do
    # Could be made async with timeout handling
    Renderer.show_stream_chunk(text)
  end

  defp finalize_metrics(metrics) do
    end_time = System.monotonic_time(:microsecond)
    duration_us = end_time - metrics.start_time

    avg_chunk_size =
      if metrics.chunks_received > 0 do
        metrics.total_chunk_size / metrics.chunks_received
      else
        0
      end

    metrics
    |> Map.put(:duration_ms, duration_us / 1_000)
    |> Map.put(:throughput_bytes_per_sec, metrics.bytes_written * 1_000_000 / max(duration_us, 1))
    |> Map.put(:avg_chunk_size, avg_chunk_size)
    |> Map.put(:write_efficiency, metrics.bytes_written / max(metrics.write_operations, 1))
    # Internal metric
    |> Map.delete(:total_chunk_size)
  end
end
