defmodule MCPChat.Streaming.StreamBuffer do
  @moduledoc """
  Efficient circular buffer implementation for stream chunk management.
  
  Features:
  - Fixed-size circular buffer to prevent unbounded memory growth
  - O(1) push and pop operations
  - Overflow detection and handling
  - Buffer state monitoring
  """
  
  defstruct [
    :data,
    :capacity,
    :size,
    :head,
    :tail,
    :overflow_count
  ]
  
  @doc """
  Creates a new stream buffer with the given capacity.
  """
  def new(capacity) when capacity > 0 do
    %__MODULE__{
      data: :array.new(capacity, default: nil),
      capacity: capacity,
      size: 0,
      head: 0,
      tail: 0,
      overflow_count: 0
    }
  end
  
  @doc """
  Pushes a chunk into the buffer.
  
  Returns {:ok, buffer} if successful, or {:overflow, buffer} if buffer is full.
  """
  def push(buffer, chunk) do
    if full?(buffer) do
      {:overflow, %{buffer | overflow_count: buffer.overflow_count + 1}}
    else
      data = :array.set(buffer.tail, chunk, buffer.data)
      new_tail = rem(buffer.tail + 1, buffer.capacity)
      new_buffer = %{buffer | 
        data: data,
        tail: new_tail,
        size: buffer.size + 1
      }
      {:ok, new_buffer}
    end
  end
  
  @doc """
  Pushes a chunk, overwriting oldest if buffer is full.
  """
  def push!(buffer, chunk) do
    if full?(buffer) do
      # Overwrite oldest
      data = :array.set(buffer.tail, chunk, buffer.data)
      new_tail = rem(buffer.tail + 1, buffer.capacity)
      new_head = rem(buffer.head + 1, buffer.capacity)
      %{buffer | 
        data: data,
        tail: new_tail,
        head: new_head,
        overflow_count: buffer.overflow_count + 1
      }
    else
      {:ok, new_buffer} = push(buffer, chunk)
      new_buffer
    end
  end
  
  @doc """
  Pops a chunk from the buffer.
  
  Returns {:ok, chunk, buffer} or {:empty, buffer}.
  """
  def pop(buffer) do
    if empty?(buffer) do
      {:empty, buffer}
    else
      chunk = :array.get(buffer.head, buffer.data)
      new_head = rem(buffer.head + 1, buffer.capacity)
      new_buffer = %{buffer |
        head: new_head,
        size: buffer.size - 1
      }
      {:ok, chunk, new_buffer}
    end
  end
  
  @doc """
  Pops up to n chunks from the buffer.
  
  Returns {chunks, buffer} where chunks is a list of at most n chunks.
  """
  def pop_many(buffer, n) when n > 0 do
    pop_many_acc(buffer, n, [])
  end
  
  defp pop_many_acc(buffer, 0, acc) do
    {Enum.reverse(acc), buffer}
  end
  
  defp pop_many_acc(buffer, n, acc) do
    case pop(buffer) do
      {:ok, chunk, new_buffer} ->
        pop_many_acc(new_buffer, n - 1, [chunk | acc])
      {:empty, _} ->
        {Enum.reverse(acc), buffer}
    end
  end
  
  @doc """
  Returns the current size of the buffer.
  """
  def size(buffer), do: buffer.size
  
  @doc """
  Returns true if the buffer is empty.
  """
  def empty?(buffer), do: buffer.size == 0
  
  @doc """
  Returns true if the buffer is full.
  """
  def full?(buffer), do: buffer.size == buffer.capacity
  
  @doc """
  Returns the fill percentage of the buffer (0-100).
  """
  def fill_percentage(buffer) do
    buffer.size * 100.0 / buffer.capacity
  end
  
  @doc """
  Returns buffer statistics.
  """
  def stats(buffer) do
    %{
      size: buffer.size,
      capacity: buffer.capacity,
      fill_percentage: fill_percentage(buffer),
      overflow_count: buffer.overflow_count,
      available_space: buffer.capacity - buffer.size
    }
  end
  
  @doc """
  Converts buffer contents to a list (for debugging).
  """
  def to_list(buffer) do
    if empty?(buffer) do
      []
    else
      to_list_acc(buffer, buffer.head, buffer.size, [])
    end
  end
  
  defp to_list_acc(_buffer, _index, 0, acc) do
    Enum.reverse(acc)
  end
  
  defp to_list_acc(buffer, index, remaining, acc) do
    chunk = :array.get(index, buffer.data)
    next_index = rem(index + 1, buffer.capacity)
    to_list_acc(buffer, next_index, remaining - 1, [chunk | acc])
  end
end