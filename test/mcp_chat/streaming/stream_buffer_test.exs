defmodule StreamBufferTest do
  use ExUnit.Case
  alias StreamBuffer

  alias StreamBufferTest

  describe "new/1" do
    test "creates a buffer with specified capacity" do
      buffer = StreamBuffer.new(10)
      assert buffer.capacity == 10
      assert buffer.size == 0
      assert StreamBuffer.empty?(buffer)
    end
  end

  describe "push/2" do
    test "pushes chunks into buffer" do
      buffer = StreamBuffer.new(3)

      {:ok, buffer} = StreamBuffer.push(buffer, "chunk1")
      assert buffer.size == 1

      {:ok, buffer} = StreamBuffer.push(buffer, "chunk2")
      assert buffer.size == 2

      {:ok, buffer} = StreamBuffer.push(buffer, "chunk3")
      assert buffer.size == 3
      assert StreamBuffer.full?(buffer)
    end

    test "returns overflow when buffer is full" do
      buffer = StreamBuffer.new(2)

      {:ok, buffer} = StreamBuffer.push(buffer, "chunk1")
      {:ok, buffer} = StreamBuffer.push(buffer, "chunk2")

      assert {:overflow, buffer} = StreamBuffer.push(buffer, "chunk3")
      assert buffer.overflow_count == 1
    end
  end

  describe "push!/2" do
    test "overwrites oldest chunk when full" do
      buffer = StreamBuffer.new(2)

      buffer = StreamBuffer.push!(buffer, "chunk1")
      buffer = StreamBuffer.push!(buffer, "chunk2")
      # Overwrites chunk1
      buffer = StreamBuffer.push!(buffer, "chunk3")

      assert buffer.size == 2
      assert buffer.overflow_count == 1

      # Pop should return chunk2 first (oldest remaining)
      {:ok, chunk, _buffer} = StreamBuffer.pop(buffer)
      assert chunk == "chunk2"
    end
  end

  describe "pop/1" do
    test "pops chunks in FIFO order" do
      buffer = StreamBuffer.new(3)

      buffer =
        buffer
        |> StreamBuffer.push!("chunk1")
        |> StreamBuffer.push!("chunk2")
        |> StreamBuffer.push!("chunk3")

      {:ok, chunk1, buffer} = StreamBuffer.pop(buffer)
      assert chunk1 == "chunk1"
      assert buffer.size == 2

      {:ok, chunk2, buffer} = StreamBuffer.pop(buffer)
      assert chunk2 == "chunk2"
      assert buffer.size == 1

      {:ok, chunk3, buffer} = StreamBuffer.pop(buffer)
      assert chunk3 == "chunk3"
      assert buffer.size == 0
      assert StreamBuffer.empty?(buffer)
    end

    test "returns empty when buffer is empty" do
      buffer = StreamBuffer.new(3)
      assert {:empty, ^buffer} = StreamBuffer.pop(buffer)
    end
  end

  describe "pop_many/2" do
    test "pops multiple chunks at once" do
      buffer = StreamBuffer.new(5)

      buffer =
        buffer
        |> StreamBuffer.push!("chunk1")
        |> StreamBuffer.push!("chunk2")
        |> StreamBuffer.push!("chunk3")
        |> StreamBuffer.push!("chunk4")

      {chunks, buffer} = StreamBuffer.pop_many(buffer, 2)
      assert chunks == ["chunk1", "chunk2"]
      assert buffer.size == 2

      {chunks, buffer} = StreamBuffer.pop_many(buffer, 3)
      assert chunks == ["chunk3", "chunk4"]
      assert buffer.size == 0
    end
  end

  describe "fill_percentage/1" do
    test "calculates buffer fill percentage" do
      buffer = StreamBuffer.new(4)

      assert StreamBuffer.fill_percentage(buffer) == 0.0

      buffer = StreamBuffer.push!(buffer, "chunk1")
      assert StreamBuffer.fill_percentage(buffer) == 25.0

      buffer = StreamBuffer.push!(buffer, "chunk2")
      assert StreamBuffer.fill_percentage(buffer) == 50.0

      buffer = StreamBuffer.push!(buffer, "chunk3")
      assert StreamBuffer.fill_percentage(buffer) == 75.0

      buffer = StreamBuffer.push!(buffer, "chunk4")
      assert StreamBuffer.fill_percentage(buffer) == 100.0
    end
  end

  describe "stats/1" do
    test "returns buffer statistics" do
      buffer =
        StreamBuffer.new(10)
        |> StreamBuffer.push!("chunk1")
        |> StreamBuffer.push!("chunk2")
        |> StreamBuffer.push!("chunk3")

      stats = StreamBuffer.stats(buffer)

      assert stats.size == 3
      assert stats.capacity == 10
      assert stats.fill_percentage == 30.0
      assert stats.overflow_count == 0
      assert stats.available_space == 7
    end
  end

  describe "to_list/1" do
    test "converts buffer contents to list" do
      buffer =
        StreamBuffer.new(5)
        |> StreamBuffer.push!("a")
        |> StreamBuffer.push!("b")
        |> StreamBuffer.push!("c")

      assert StreamBuffer.to_list(buffer) == ["a", "b", "c"]
    end

    test "handles circular buffer correctly" do
      buffer =
        StreamBuffer.new(3)
        |> StreamBuffer.push!("a")
        |> StreamBuffer.push!("b")
        |> StreamBuffer.push!("c")
        # Overwrites "a"
        |> StreamBuffer.push!("d")
        # Overwrites "b"
        |> StreamBuffer.push!("e")

      assert StreamBuffer.to_list(buffer) == ["c", "d", "e"]
    end
  end
end
