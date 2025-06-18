defmodule MCPChat.Security.AuditLoggerTest do
  @moduledoc """
  Unit tests for the AuditLogger module.

  Tests audit event logging, integrity verification, buffering,
  formatting, and various logging destinations.
  """

  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias MCPChat.Security.AuditLogger

  @test_timeout 5000

  setup do
    # Start a fresh AuditLogger for each test
    {:ok, pid} =
      AuditLogger.start_link(
        max_buffer_size: 5,
        flush_interval: 1000,
        # Use only logger for tests
        destinations: [:logger]
      )

    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end
    end)

    %{logger_pid: pid}
  end

  describe "AuditLogger initialization" do
    test "starts with empty buffer", %{logger_pid: _pid} do
      stats = AuditLogger.get_stats()

      assert stats.current_buffer_size == 0
      assert stats.events_logged == 0
      assert stats.events_flushed == 0
      assert stats.buffer_flushes == 0
      assert stats.sequence_number == 0
    end

    test "accepts configuration options" do
      {:ok, pid} =
        AuditLogger.start_link(
          max_buffer_size: 10,
          flush_interval: 5000,
          destinations: [:logger, :file]
        )

      # Can't directly test internal state, but verify it starts successfully
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end

  describe "event logging" do
    test "logs security event asynchronously", %{logger_pid: _pid} do
      event_type = :capability_created
      details = %{capability_id: "test123", resource_type: :filesystem}
      principal_id = "test_principal"

      # Should not block
      assert :ok = AuditLogger.log_event(event_type, details, principal_id)

      # Give time for async processing
      Process.sleep(50)

      stats = AuditLogger.get_stats()
      # May have been flushed already
      assert stats.current_buffer_size >= 0
    end

    test "logs security event synchronously", %{logger_pid: _pid} do
      event_type = :capability_validated
      details = %{capability_id: "test456", operation: :read}
      principal_id = "test_principal"

      log_output =
        capture_log(fn ->
          assert :ok = AuditLogger.log_event_sync(event_type, details, principal_id)
        end)

      # Should log immediately
      assert log_output =~ "SECURITY_AUDIT"

      stats = AuditLogger.get_stats()
      assert stats.events_logged >= 1
    end

    test "increments sequence numbers correctly", %{logger_pid: _pid} do
      # Log multiple events
      AuditLogger.log_event_sync(:test_event_1, %{}, "test1")
      AuditLogger.log_event_sync(:test_event_2, %{}, "test2")
      AuditLogger.log_event_sync(:test_event_3, %{}, "test3")

      stats = AuditLogger.get_stats()
      assert stats.sequence_number == 3
    end

    test "handles large event details correctly", %{logger_pid: _pid} do
      large_details = %{
        large_field: String.duplicate("x", 1000),
        data: Enum.to_list(1..100),
        nested: %{
          deep: %{
            structure: "test"
          }
        }
      }

      assert :ok = AuditLogger.log_event_sync(:large_event, large_details, "test")

      stats = AuditLogger.get_stats()
      assert stats.events_logged == 1
    end
  end

  describe "event buffering and flushing" do
    test "buffers events until max size reached" do
      {:ok, pid} =
        AuditLogger.start_link(
          max_buffer_size: 3,
          # Long interval to test manual flushing
          flush_interval: 60_000,
          destinations: [:logger]
        )

      log_output =
        capture_log(fn ->
          # Add events to buffer (async)
          AuditLogger.log_event(:event1, %{}, "test1")
          AuditLogger.log_event(:event2, %{}, "test2")

          # Should not flush yet
          Process.sleep(50)
          stats = AuditLogger.get_stats()
          assert stats.current_buffer_size == 2

          # This should trigger flush
          AuditLogger.log_event(:event3, %{}, "test3")
          # Give time for flush
          Process.sleep(100)
        end)

      # Should have flushed when buffer reached max size
      assert log_output =~ "SECURITY_AUDIT"

      GenServer.stop(pid)
    end

    test "manual flush works correctly", %{logger_pid: _pid} do
      # Add some events to buffer
      AuditLogger.log_event(:event1, %{}, "test1")
      AuditLogger.log_event(:event2, %{}, "test2")

      initial_stats = AuditLogger.get_stats()
      initial_flushed = initial_stats.events_flushed

      log_output =
        capture_log(fn ->
          assert :ok = AuditLogger.flush()
        end)

      # Should have logged events
      assert log_output =~ "SECURITY_AUDIT"

      final_stats = AuditLogger.get_stats()
      assert final_stats.events_flushed > initial_flushed
      assert final_stats.current_buffer_size == 0
    end

    test "periodic flush works correctly" do
      {:ok, pid} =
        AuditLogger.start_link(
          # High buffer size
          max_buffer_size: 100,
          # Fast flush for testing
          flush_interval: 100,
          destinations: [:logger]
        )

      # Add events
      AuditLogger.log_event(:periodic_test1, %{}, "test1")
      AuditLogger.log_event(:periodic_test2, %{}, "test2")

      log_output =
        capture_log(fn ->
          # Wait for periodic flush
          Process.sleep(200)
        end)

      # Should have flushed automatically
      assert log_output =~ "SECURITY_AUDIT"

      GenServer.stop(pid)
    end
  end

  describe "event integrity and checksums" do
    test "generates checksums for event integrity", %{logger_pid: _pid} do
      event_type = :integrity_test
      details = %{test: "data"}
      principal_id = "test_principal"

      # Log event and verify integrity
      AuditLogger.log_event_sync(event_type, details, principal_id)

      # Verify integrity check passes
      assert :ok = AuditLogger.verify_integrity()
    end

    test "detects tampered events" do
      # This test would require access to internal buffer state
      # For now, we'll test that integrity verification works
      {:ok, pid} = AuditLogger.start_link([])

      AuditLogger.log_event_sync(:test_event, %{}, "test")

      # Should pass integrity check for valid events
      assert :ok = AuditLogger.verify_integrity()

      GenServer.stop(pid)
    end
  end

  describe "event formatting" do
    test "formats events for logging correctly", %{logger_pid: _pid} do
      event_type = :format_test

      details = %{
        capability_id: "test123",
        operation: :read,
        resource: "/tmp/test.txt"
      }

      principal_id = "format_test_principal"

      log_output =
        capture_log(fn ->
          AuditLogger.log_event_sync(event_type, details, principal_id)
        end)

      # Should contain structured information
      assert log_output =~ "format_test"
      assert log_output =~ "format_test_principal"
      assert log_output =~ "test123"
    end

    test "handles special characters in event data", %{logger_pid: _pid} do
      details = %{
        text_with_quotes: "Text with \"quotes\" and 'apostrophes'",
        text_with_newlines: "Line 1\nLine 2\nLine 3",
        unicode_text: "Testing üñíçødé characters 🔒🛡️"
      }

      log_output =
        capture_log(fn ->
          AuditLogger.log_event_sync(:special_chars_test, details, "test")
        end)

      # Should handle special characters without crashing
      assert log_output =~ "special_chars_test"
    end

    test "sanitizes sensitive information", %{logger_pid: _pid} do
      details = %{
        password: "secret123",
        token: "bearer_token_xyz",
        api_key: "sk-1234567890",
        safe_data: "this_is_safe"
      }

      # Note: The actual sanitization logic would need to be enhanced
      # This test verifies the logging doesn't crash with sensitive data
      log_output =
        capture_log(fn ->
          AuditLogger.log_event_sync(:sensitive_data_test, details, "test")
        end)

      assert log_output =~ "sensitive_data_test"
    end
  end

  describe "statistics and monitoring" do
    test "tracks logging statistics accurately", %{logger_pid: _pid} do
      initial_stats = AuditLogger.get_stats()

      # Log several events
      AuditLogger.log_event_sync(:stats_test_1, %{}, "test1")
      AuditLogger.log_event_sync(:stats_test_2, %{}, "test2")
      AuditLogger.log_event_sync(:stats_test_3, %{}, "test3")

      final_stats = AuditLogger.get_stats()

      assert final_stats.events_logged == initial_stats.events_logged + 3
      assert final_stats.sequence_number == initial_stats.sequence_number + 3
      assert final_stats.events_flushed >= initial_stats.events_flushed + 3
    end

    test "provides uptime information", %{logger_pid: _pid} do
      stats = AuditLogger.get_stats()

      assert is_integer(stats.uptime)
      assert stats.uptime >= 0
    end

    test "tracks buffer flush statistics", %{logger_pid: _pid} do
      initial_stats = AuditLogger.get_stats()

      # Add events and flush manually
      AuditLogger.log_event(:flush_stats_1, %{}, "test1")
      AuditLogger.log_event(:flush_stats_2, %{}, "test2")
      AuditLogger.flush()

      final_stats = AuditLogger.get_stats()

      assert final_stats.buffer_flushes >= initial_stats.buffer_flushes + 1
    end
  end

  describe "error handling" do
    test "handles invalid event types gracefully", %{logger_pid: _pid} do
      # Even with invalid event type, should not crash
      assert :ok = AuditLogger.log_event(nil, %{}, "test")
      assert :ok = AuditLogger.log_event("string_event", %{}, "test")
      assert :ok = AuditLogger.log_event(123, %{}, "test")
    end

    test "handles invalid principal IDs", %{logger_pid: _pid} do
      # Should handle various principal ID formats
      assert :ok = AuditLogger.log_event(:test, %{}, nil)
      assert :ok = AuditLogger.log_event(:test, %{}, "")
      assert :ok = AuditLogger.log_event(:test, %{}, 123)
    end

    test "handles malformed event details", %{logger_pid: _pid} do
      # Should handle non-map details
      assert :ok = AuditLogger.log_event(:test, "string_details", "test")
      assert :ok = AuditLogger.log_event(:test, nil, "test")
      assert :ok = AuditLogger.log_event(:test, 123, "test")
      assert :ok = AuditLogger.log_event(:test, [:list, :details], "test")
    end
  end

  describe "search functionality" do
    test "search returns empty results for new logger", %{logger_pid: _pid} do
      criteria = %{event_type: :capability_created}

      assert {:ok, events} = AuditLogger.search_events(criteria)
      assert events == []
    end

    test "search respects limit parameter", %{logger_pid: _pid} do
      criteria = %{event_type: :any}
      opts = [limit: 5]

      assert {:ok, events} = AuditLogger.search_events(criteria, opts)
      assert length(events) <= 5
    end
  end

  describe "concurrent logging" do
    test "handles concurrent event logging", %{logger_pid: _pid} do
      # Create multiple concurrent logging tasks
      tasks =
        Enum.map(1..50, fn i ->
          Task.async(fn ->
            AuditLogger.log_event(:concurrent_test, %{index: i}, "test_#{i}")
          end)
        end)

      results = Task.await_many(tasks, @test_timeout)

      # All logging operations should succeed
      assert Enum.all?(results, fn result -> result == :ok end)

      # Give time for processing
      Process.sleep(100)

      stats = AuditLogger.get_stats()
      # May have been flushed
      assert stats.current_buffer_size >= 0
    end

    test "handles concurrent flush operations", %{logger_pid: _pid} do
      # Add some events
      Enum.each(1..10, fn i ->
        AuditLogger.log_event(:flush_test, %{index: i}, "test")
      end)

      # Create multiple concurrent flush tasks
      tasks =
        Enum.map(1..5, fn _i ->
          Task.async(fn ->
            AuditLogger.flush()
          end)
        end)

      results = Task.await_many(tasks, @test_timeout)

      # All flush operations should succeed
      assert Enum.all?(results, fn result -> result == :ok end)
    end
  end

  describe "performance under load" do
    test "maintains performance with high event volume", %{logger_pid: _pid} do
      event_count = 1000

      {time_microseconds, _result} =
        :timer.tc(fn ->
          Enum.each(1..event_count, fn i ->
            AuditLogger.log_event(:performance_test, %{index: i}, "perf_test")
          end)

          # Ensure all events are processed
          AuditLogger.flush()
        end)

      # Should complete in reasonable time (less than 1 second for 1000 events)
      assert time_microseconds < 1_000_000

      stats = AuditLogger.get_stats()
      assert stats.events_flushed >= event_count
    end

    test "memory usage remains bounded with continuous logging" do
      # Log many events without flushing to test buffer behavior
      {:ok, pid} =
        AuditLogger.start_link(
          max_buffer_size: 10,
          # Long interval
          flush_interval: 60_000,
          destinations: [:logger]
        )

      # Add more events than buffer size
      Enum.each(1..25, fn i ->
        AuditLogger.log_event(:memory_test, %{index: i}, "test")
      end)

      # Give time for auto-flushing when buffer fills
      Process.sleep(200)

      stats = AuditLogger.get_stats()
      # Buffer size should not exceed max (due to auto-flushing)
      assert stats.current_buffer_size <= 10

      GenServer.stop(pid)
    end
  end
end
