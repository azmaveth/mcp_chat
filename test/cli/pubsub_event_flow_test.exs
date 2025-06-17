defmodule MCPChat.CLI.PubSubEventFlowTest do
  @moduledoc """
  Tests the Phoenix.PubSub event flow between CLI and agents.
  Verifies that events are properly published, routed, and received.
  """

  use ExUnit.Case, async: false

  alias MCPChat.Events.AgentEvents
  alias Phoenix.PubSub

  @pubsub MCPChat.PubSub

  setup do
    # Generate unique session ID for each test
    session_id = "test_session_#{:rand.uniform(10000)}"
    {:ok, session_id: session_id}
  end

  describe "Event Broadcasting" do
    test "Events are properly broadcast to session topics", %{session_id: session_id} do
      # Subscribe to session topic
      PubSub.subscribe(@pubsub, "session:#{session_id}")

      # Broadcast an event
      event = %AgentEvents.ToolExecutionStarted{
        session_id: session_id,
        execution_id: "test_exec_1",
        tool_name: "test_tool",
        args: %{"test" => "data"},
        timestamp: DateTime.utc_now()
      }

      PubSub.broadcast(@pubsub, "session:#{session_id}", {:pubsub, event})

      # Verify reception
      assert_receive {:pubsub, %AgentEvents.ToolExecutionStarted{execution_id: "test_exec_1"}}, 100
    end

    test "Multiple subscribers receive the same event", %{session_id: session_id} do
      # Create multiple subscriber processes
      parent = self()

      subscribers =
        for i <- 1..3 do
          spawn(fn ->
            PubSub.subscribe(@pubsub, "session:#{session_id}")

            receive do
              {:pubsub, event} ->
                send(parent, {:received, i, event})
            after
              1000 -> send(parent, {:timeout, i})
            end
          end)
        end

      # Give subscribers time to set up
      Process.sleep(50)

      # Broadcast event
      event = %AgentEvents.ExportStarted{
        session_id: session_id,
        export_id: "test_export_1",
        format: "json",
        started_at: DateTime.utc_now()
      }

      PubSub.broadcast(@pubsub, "session:#{session_id}", {:pubsub, event})

      # Verify all subscribers received it
      for i <- 1..3 do
        assert_receive {:received, ^i, %AgentEvents.ExportStarted{export_id: "test_export_1"}}, 200
      end

      # Clean up
      Enum.each(subscribers, &Process.exit(&1, :kill))
    end
  end

  describe "Event Types and Routing" do
    test "Tool execution events flow correctly", %{session_id: session_id} do
      PubSub.subscribe(@pubsub, "session:#{session_id}")

      exec_id = "tool_flow_test"
      tool_name = "analyzer"

      # Simulate complete tool execution flow
      events = [
        %AgentEvents.ToolExecutionStarted{
          session_id: session_id,
          execution_id: exec_id,
          tool_name: tool_name,
          args: %{"depth" => "full"},
          timestamp: DateTime.utc_now()
        },
        %AgentEvents.ToolExecutionProgress{
          session_id: session_id,
          execution_id: exec_id,
          tool_name: tool_name,
          progress: 50,
          message: "Analyzing...",
          timestamp: DateTime.utc_now()
        },
        %AgentEvents.ToolExecutionCompleted{
          session_id: session_id,
          execution_id: exec_id,
          tool_name: tool_name,
          result: %{"lines" => 100, "issues" => 0},
          duration_ms: 1500,
          timestamp: DateTime.utc_now()
        }
      ]

      # Broadcast each event
      Enum.each(events, fn event ->
        PubSub.broadcast(@pubsub, "session:#{session_id}", {:pubsub, event})
      end)

      # Verify reception in order
      assert_receive {:pubsub, %AgentEvents.ToolExecutionStarted{}}, 100
      assert_receive {:pubsub, %AgentEvents.ToolExecutionProgress{progress: 50}}, 100
      assert_receive {:pubsub, %AgentEvents.ToolExecutionCompleted{result: result}}, 100

      assert result["lines"] == 100
    end

    test "Export events flow correctly", %{session_id: session_id} do
      PubSub.subscribe(@pubsub, "session:#{session_id}")

      export_id = "export_flow_test"

      # Complete export flow
      events = [
        %AgentEvents.ExportStarted{
          session_id: session_id,
          export_id: export_id,
          format: "pdf",
          options: %{"include_metadata" => true},
          timestamp: DateTime.utc_now()
        },
        %AgentEvents.ExportProgress{
          session_id: session_id,
          export_id: export_id,
          progress: 33,
          stage: "Collecting data",
          timestamp: DateTime.utc_now()
        },
        %AgentEvents.ExportProgress{
          session_id: session_id,
          export_id: export_id,
          progress: 66,
          stage: "Generating PDF",
          timestamp: DateTime.utc_now()
        },
        %AgentEvents.ExportCompleted{
          session_id: session_id,
          export_id: export_id,
          format: "pdf",
          file_path: "/tmp/export.pdf",
          size_bytes: 2048,
          duration_ms: 2500,
          timestamp: DateTime.utc_now()
        }
      ]

      Enum.each(events, &PubSub.broadcast(@pubsub, "session:#{session_id}", {:pubsub, &1}))

      # Verify all events received
      assert_receive {:pubsub, %AgentEvents.ExportStarted{format: "pdf"}}, 100
      assert_receive {:pubsub, %AgentEvents.ExportProgress{progress: 33}}, 100
      assert_receive {:pubsub, %AgentEvents.ExportProgress{progress: 66}}, 100
      assert_receive {:pubsub, %AgentEvents.ExportCompleted{file_path: path}}, 100

      assert path == "/tmp/export.pdf"
    end

    test "Agent pool events flow correctly", %{session_id: session_id} do
      PubSub.subscribe(@pubsub, "system:agents")

      # Pool events are broadcast to system topic
      events = [
        %AgentEvents.AgentPoolWorkerStarted{
          worker_id: "worker_1",
          task_id: "task_1",
          timestamp: DateTime.utc_now()
        },
        %AgentEvents.AgentPoolQueueFull{
          queue_length: 5,
          max_queue_size: 10,
          timestamp: DateTime.utc_now()
        },
        %AgentEvents.AgentPoolWorkerCompleted{
          worker_id: "worker_1",
          task_id: "task_1",
          duration_ms: 1000,
          timestamp: DateTime.utc_now()
        }
      ]

      Enum.each(events, &PubSub.broadcast(@pubsub, "system:agents", {:pubsub, &1}))

      assert_receive {:pubsub, %AgentEvents.AgentPoolWorkerStarted{worker_id: "worker_1"}}, 100
      assert_receive {:pubsub, %AgentEvents.AgentPoolQueueFull{queue_length: 5}}, 100
      assert_receive {:pubsub, %AgentEvents.AgentPoolWorkerCompleted{duration_ms: 1000}}, 100
    end
  end

  describe "Event Filtering and Subscription" do
    test "Session-specific events are isolated", %{session_id: session_id} do
      other_session = "other_session_123"

      # Subscribe only to our session
      PubSub.subscribe(@pubsub, "session:#{session_id}")

      # Broadcast to different sessions
      our_event = %AgentEvents.ToolExecutionStarted{
        session_id: session_id,
        execution_id: "our_exec",
        tool_name: "our_tool",
        args: %{},
        timestamp: DateTime.utc_now()
      }

      other_event = %AgentEvents.ToolExecutionStarted{
        session_id: other_session,
        execution_id: "other_exec",
        tool_name: "other_tool",
        args: %{},
        timestamp: DateTime.utc_now()
      }

      PubSub.broadcast(@pubsub, "session:#{session_id}", {:pubsub, our_event})
      PubSub.broadcast(@pubsub, "session:#{other_session}", {:pubsub, other_event})

      # Should only receive our event
      assert_receive {:pubsub, %AgentEvents.ToolExecutionStarted{execution_id: "our_exec"}}, 100
      refute_receive {:pubsub, %AgentEvents.ToolExecutionStarted{execution_id: "other_exec"}}, 100
    end

    test "System events are received by all sessions" do
      # Subscribe to both session and system topics
      PubSub.subscribe(@pubsub, "session:test_session")
      PubSub.subscribe(@pubsub, "system:agents")

      # Broadcast system event
      system_event = %AgentEvents.MaintenanceStarted{
        task_type: :cleanup,
        scheduled_at: DateTime.utc_now(),
        timestamp: DateTime.utc_now()
      }

      PubSub.broadcast(@pubsub, "system:agents", {:pubsub, system_event})

      # Should receive on system subscription
      assert_receive {:pubsub, %AgentEvents.MaintenanceStarted{task_type: :cleanup}}, 100
    end
  end

  describe "Event Serialization" do
    test "Events maintain structure through PubSub", %{session_id: session_id} do
      PubSub.subscribe(@pubsub, "session:#{session_id}")

      # Create event with nested data
      complex_result = %{
        "data" => %{
          "files" => ["file1.ex", "file2.ex"],
          "metrics" => %{
            "lines" => 500,
            "functions" => 25,
            "modules" => 5
          }
        },
        "metadata" => %{
          "version" => "1.0",
          "timestamp" => DateTime.utc_now()
        }
      }

      event = %AgentEvents.ToolExecutionCompleted{
        session_id: session_id,
        execution_id: "complex_test",
        tool_name: "analyzer",
        result: complex_result,
        duration_ms: 2000,
        timestamp: DateTime.utc_now()
      }

      PubSub.broadcast(@pubsub, "session:#{session_id}", {:pubsub, event})

      assert_receive {:pubsub, received_event}, 100

      # Verify nested structure is preserved
      assert received_event.result["data"]["metrics"]["lines"] == 500
      assert length(received_event.result["data"]["files"]) == 2
      assert received_event.duration_ms == 2000
    end
  end

  describe "Event Timing and Order" do
    test "Events are received in broadcast order", %{session_id: session_id} do
      PubSub.subscribe(@pubsub, "session:#{session_id}")

      # Broadcast multiple events rapidly
      for i <- 1..10 do
        event = %AgentEvents.ToolExecutionProgress{
          session_id: session_id,
          execution_id: "timing_test",
          tool_name: "sequencer",
          progress: i * 10,
          message: "Step #{i}",
          timestamp: DateTime.utc_now()
        }

        PubSub.broadcast(@pubsub, "session:#{session_id}", {:pubsub, event})
      end

      # Verify order
      for i <- 1..10 do
        assert_receive {:pubsub, %AgentEvents.ToolExecutionProgress{progress: progress}}, 100
        assert progress == i * 10
      end
    end

    test "Late subscribers don't receive past events" do
      exec_id = "late_sub_test"

      # Broadcast event before subscribing
      event = %AgentEvents.ToolExecutionStarted{
        session_id: "late_session",
        execution_id: exec_id,
        tool_name: "early_tool",
        args: %{},
        timestamp: DateTime.utc_now()
      }

      PubSub.broadcast(@pubsub, "session:late_session", {:pubsub, event})

      # Subscribe after broadcast
      PubSub.subscribe(@pubsub, "session:late_session")

      # Should not receive the past event
      refute_receive {:pubsub, %AgentEvents.ToolExecutionStarted{execution_id: ^exec_id}}, 100
    end
  end
end
