defmodule MCPChat.Persistence.EventStoreTest do
  use ExUnit.Case, async: false

  alias MCPChat.Persistence.{EventStore, EventJournal, EventIndex, SnapshotManager}
  alias MCPChat.Events.{AgentEvents, SystemEvents}

  @test_event_dir "/tmp/mcp_chat_test_events"

  setup do
    # Clean up test directory
    if File.exists?(@test_event_dir) do
      File.rm_rf!(@test_event_dir)
    end

    File.mkdir_p!(@test_event_dir)

    # Start the event store with test configuration
    {:ok, _pid} = EventStore.start_link(event_dir: @test_event_dir)

    on_exit(fn ->
      GenServer.stop(EventStore, :normal, 1000)
      File.rm_rf!(@test_event_dir)
    end)

    :ok
  end

  describe "event appending" do
    test "can append single events" do
      event = %{
        event_type: :test_event,
        data: "test data",
        session_id: "test_session"
      }

      assert {:ok, event_id} = EventStore.append_event(event)
      assert is_integer(event_id)
      assert event_id > 0
    end

    test "can append multiple events atomically" do
      events = [
        %{event_type: :test_event_1, data: "data 1", session_id: "session_1"},
        %{event_type: :test_event_2, data: "data 2", session_id: "session_1"},
        %{event_type: :test_event_3, data: "data 3", session_id: "session_2"}
      ]

      assert {:ok, event_ids} = EventStore.append_events(events)
      assert length(event_ids) == 3
      assert Enum.all?(event_ids, &is_integer/1)

      # Event IDs should be sequential
      [id1, id2, id3] = event_ids
      assert id2 == id1 + 1
      assert id3 == id2 + 1
    end

    test "events are automatically timestamped and assigned stream IDs" do
      event = %{
        event_type: :test_event,
        data: "test data",
        session_id: "test_session"
      }

      {:ok, event_id} = EventStore.append_event(event)

      # Retrieve the event to check metadata
      {:ok, events} = EventStore.get_events_since(event_id)
      stored_event = List.first(events)

      assert stored_event.event_id == event_id
      assert stored_event.stream_id == "session:test_session"
      assert %DateTime{} = stored_event.timestamp
      assert stored_event.event_version == 1
    end
  end

  describe "event retrieval" do
    test "can retrieve events since a specific event ID" do
      # Add some events
      events = [
        %{event_type: :event_1, data: "data 1"},
        %{event_type: :event_2, data: "data 2"},
        %{event_type: :event_3, data: "data 3"}
      ]

      {:ok, _event_ids} = EventStore.append_events(events)

      # Get events since the beginning
      {:ok, retrieved_events} = EventStore.get_events_since(0)
      assert length(retrieved_events) == 3

      # Get events since event 2
      {:ok, partial_events} = EventStore.get_events_since(2)
      assert length(partial_events) == 2
    end

    test "can retrieve events for a specific stream" do
      # Add events from different streams
      events = [
        %{event_type: :event_1, session_id: "session_1"},
        %{event_type: :event_2, session_id: "session_2"},
        %{event_type: :event_3, session_id: "session_1"},
        %{event_type: :event_4, agent_id: "agent_1"}
      ]

      {:ok, _event_ids} = EventStore.append_events(events)

      # Get events for session_1 stream
      {:ok, session_events} = EventStore.get_stream_events("session:session_1")
      assert length(session_events) == 2

      # Get events for agent_1 stream
      {:ok, agent_events} = EventStore.get_stream_events("agent:agent_1")
      assert length(agent_events) == 1
    end
  end

  describe "event subscriptions" do
    test "can subscribe to and receive new events" do
      test_pid = self()

      # Subscribe to all events
      :ok = EventStore.subscribe(test_pid, :all)

      # Add an event
      event = %{event_type: :test_event, data: "test data"}
      {:ok, _event_id} = EventStore.append_event(event)

      # Should receive the event
      assert_receive {:event_store_event, received_event}, 1000
      assert received_event.event_type == :test_event
      assert received_event.data == "test data"
    end

    test "can subscribe to specific event types" do
      test_pid = self()

      # Subscribe only to specific event type
      :ok = EventStore.subscribe(test_pid, {:event_type, :important_event})

      # Add events of different types
      {:ok, _} = EventStore.append_event(%{event_type: :normal_event})
      {:ok, _} = EventStore.append_event(%{event_type: :important_event})

      # Should only receive the important event
      assert_receive {:event_store_event, received_event}, 1000
      assert received_event.event_type == :important_event

      # Should not receive another event
      refute_receive {:event_store_event, _}, 500
    end

    test "can unsubscribe from events" do
      test_pid = self()

      # Subscribe and then unsubscribe
      :ok = EventStore.subscribe(test_pid, :all)
      :ok = EventStore.unsubscribe(test_pid)

      # Add an event
      {:ok, _} = EventStore.append_event(%{event_type: :test_event})

      # Should not receive the event
      refute_receive {:event_store_event, _}, 500
    end
  end

  describe "event replay" do
    test "can replay events with a handler function" do
      # Add some events
      events = [
        %{event_type: :event_1, data: 1},
        %{event_type: :event_2, data: 2},
        %{event_type: :event_3, data: 3}
      ]

      {:ok, _event_ids} = EventStore.append_events(events)

      # Replay events and collect data
      collected_data = []

      handler_fn = fn event ->
        send(self(), {:replayed_event, event.data})
      end

      {:ok, replay_count} = EventStore.replay_events(0, handler_fn)
      assert replay_count == 3

      # Collect all replayed events
      replayed_data =
        for _ <- 1..3 do
          receive do
            {:replayed_event, data} -> data
          after
            1000 -> nil
          end
        end

      assert replayed_data == [1, 2, 3]
    end

    test "can replay events from a specific point" do
      # Add events
      {:ok, [id1, id2, id3]} =
        EventStore.append_events([
          %{event_type: :event_1, data: 1},
          %{event_type: :event_2, data: 2},
          %{event_type: :event_3, data: 3}
        ])

      # Replay from the second event
      handler_fn = fn event ->
        send(self(), {:replayed_event, event.data})
      end

      {:ok, replay_count} = EventStore.replay_events(id2, handler_fn)
      assert replay_count == 2

      # Should only receive data 2 and 3
      replayed_data =
        for _ <- 1..2 do
          receive do
            {:replayed_event, data} -> data
          after
            1000 -> nil
          end
        end

      assert replayed_data == [2, 3]
    end
  end

  describe "snapshots" do
    test "can create snapshot markers" do
      # Add some events first
      {:ok, _} =
        EventStore.append_events([
          %{event_type: :event_1},
          %{event_type: :event_2}
        ])

      # Create a snapshot
      snapshot_data = %{
        session_states: %{},
        agent_states: %{},
        counters: %{events: 2}
      }

      {:ok, snapshot_event_id} = EventStore.create_snapshot_marker(snapshot_data)
      assert is_integer(snapshot_event_id)

      # Verify snapshot event was created
      {:ok, events} = EventStore.get_events_since(snapshot_event_id)
      snapshot_event = List.first(events)

      assert snapshot_event.event_type == :snapshot_created
      assert snapshot_event.snapshot_data == snapshot_data
    end
  end

  describe "statistics and monitoring" do
    test "provides accurate statistics" do
      # Initial stats
      initial_stats = EventStore.get_stats()
      assert initial_stats.total_events == 0
      assert initial_stats.subscribers == 0

      # Add some events
      {:ok, _} =
        EventStore.append_events([
          %{event_type: :event_1},
          %{event_type: :event_2}
        ])

      # Subscribe a process
      :ok = EventStore.subscribe(self(), :all)

      # Check updated stats
      updated_stats = EventStore.get_stats()
      assert updated_stats.total_events == 2
      assert updated_stats.subscribers == 1
    end

    test "can force flush pending events" do
      # Add an event (but don't fill the batch)
      {:ok, _} = EventStore.append_event(%{event_type: :test_event})

      stats = EventStore.get_stats()
      assert stats.batch_buffer_size > 0

      # Force flush
      :ok = EventStore.flush()

      # Buffer should be empty after flush
      updated_stats = EventStore.get_stats()
      assert updated_stats.batch_buffer_size == 0
    end
  end

  describe "error handling" do
    test "handles invalid events gracefully" do
      # Try to append an invalid event (missing required fields)
      invalid_event = %{invalid: "event"}

      # Should still work, as the event store is flexible
      assert {:ok, _event_id} = EventStore.append_event(invalid_event)
    end

    test "handles large batches correctly" do
      # Create a large batch of events
      large_batch =
        for i <- 1..200 do
          %{event_type: :batch_event, data: i}
        end

      assert {:ok, event_ids} = EventStore.append_events(large_batch)
      assert length(event_ids) == 200

      # Verify all events were stored
      {:ok, stored_events} = EventStore.get_events_since(0)
      assert length(stored_events) == 200
    end
  end

  describe "persistence and recovery" do
    test "events persist across event store restarts" do
      # Add some events
      events = [
        %{event_type: :persistent_event_1, data: "data 1"},
        %{event_type: :persistent_event_2, data: "data 2"}
      ]

      {:ok, _event_ids} = EventStore.append_events(events)

      # Force flush to ensure data is written
      :ok = EventStore.flush()

      # Stop the event store
      GenServer.stop(EventStore, :normal, 1000)

      # Start a new event store instance
      {:ok, _pid} = EventStore.start_link(event_dir: @test_event_dir)

      # Events should still be available
      {:ok, recovered_events} = EventStore.get_events_since(0)
      assert length(recovered_events) == 2

      recovered_types = Enum.map(recovered_events, & &1.event_type)
      assert :persistent_event_1 in recovered_types
      assert :persistent_event_2 in recovered_types
    end
  end
end
