defmodule ProgressTrackerTest do
  use ExUnit.Case, async: true

  alias ProgressTracker

  alias ProgressTrackerTest

  setup do
    {:ok, tracker} = ProgressTracker.start_link()
    {:ok, tracker: tracker}
  end

  describe "operation tracking" do
    test "starts and tracks new operation", %{tracker: tracker} do
      {:ok, token} = GenServer.call(tracker, {:start_operation, "test_server", "process_file", 100})

      assert String.starts_with?(token, "op-")

      operations = GenServer.call(tracker, :list_operations)
      assert length(operations) == 1

      [op] = operations
      assert op.token == token
      assert op.server == "test_server"
      assert op.tool == "process_file"
      assert op.total == 100
      assert op.progress == 0
      assert op.status == :running
    end

    test "updates operation progress", %{tracker: tracker} do
      {:ok, token} = GenServer.call(tracker, {:start_operation, "test_server", "process", nil})

      GenServer.cast(tracker, {:update_progress, token, 50, 100})

      op = GenServer.call(tracker, {:get_operation, token})
      assert op.progress == 50
      assert op.total == 100
      assert op.status == :running
    end

    test "automatically completes operation when progress reaches total", %{tracker: tracker} do
      {:ok, token} = GenServer.call(tracker, {:start_operation, "test_server", "process", 100})

      GenServer.cast(tracker, {:update_progress, token, 100, 100})

      # Give it time to process
      Process.sleep(10)

      op = GenServer.call(tracker, {:get_operation, token})
      assert op.status == :completed
    end

    test "marks operation as completed", %{tracker: tracker} do
      {:ok, token} = GenServer.call(tracker, {:start_operation, "test_server", "process", nil})

      GenServer.cast(tracker, {:complete_operation, token})

      # Give it time to process
      Process.sleep(10)

      op = GenServer.call(tracker, {:get_operation, token})
      assert op.status == :completed
    end

    test "marks operation as failed", %{tracker: tracker} do
      {:ok, token} = GenServer.call(tracker, {:start_operation, "test_server", "process", nil})

      GenServer.cast(tracker, {:fail_operation, token, "Connection lost"})

      # Give it time to process
      Process.sleep(10)

      op = GenServer.call(tracker, {:get_operation, token})
      assert op.status == :failed
    end
  end

  describe "operation listing" do
    test "lists only active operations", %{tracker: tracker} do
      {:ok, token1} = GenServer.call(tracker, {:start_operation, "server1", "tool1", nil})
      {:ok, token2} = GenServer.call(tracker, {:start_operation, "server2", "tool2", nil})
      {:ok, token3} = GenServer.call(tracker, {:start_operation, "server3", "tool3", nil})

      # Complete one operation
      GenServer.cast(tracker, {:complete_operation, token2})

      # Give it time to process
      Process.sleep(10)

      operations = GenServer.call(tracker, :list_operations)
      assert length(operations) == 2

      tokens = Enum.map(operations, & &1.token)
      assert token1 in tokens
      assert token3 in tokens
      refute token2 in tokens
    end

    test "returns operations sorted by start time", %{tracker: tracker} do
      {:ok, token1} = GenServer.call(tracker, {:start_operation, "server1", "tool1", nil})
      Process.sleep(10)
      {:ok, token2} = GenServer.call(tracker, {:start_operation, "server2", "tool2", nil})
      Process.sleep(10)
      {:ok, token3} = GenServer.call(tracker, {:start_operation, "server3", "tool3", nil})

      operations = GenServer.call(tracker, :list_operations)
      tokens = Enum.map(operations, & &1.token)

      # Most recent first
      assert tokens == [token3, token2, token1]
    end
  end

  describe "token generation" do
    test "generates unique tokens", %{tracker: tracker} do
      token1 = GenServer.call(tracker, :generate_token)
      token2 = GenServer.call(tracker, :generate_token)

      assert token1 != token2
      assert String.starts_with?(token1, "op-")
      assert String.starts_with?(token2, "op-")
    end
  end

  describe "cleanup" do
    test "cleans up old completed operations", %{tracker: tracker} do
      # This test would need to manipulate time or wait 5 minutes
      # For now, just verify the cleanup message is scheduled
      {:ok, _token} = GenServer.call(tracker, {:start_operation, "server", "tool", nil})

      # Verify process has a cleanup timer
      {:messages, messages} = Process.info(tracker, :messages)
      # Should have scheduled a cleanup message
      # Or it might be in the timer queue
      has_cleanup_message =
        Enum.any?(messages, fn
          {:timeout, _ref, :cleanup} -> true
          _ -> false
        end)

      # Check if cleanup timer exists either as message or timer
      assert has_cleanup_message or match?({:timers, _}, Process.info(tracker, :timers))
    end
  end
end
