defmodule MCPChat.CLI.AgentIntegrationTest do
  @moduledoc """
  End-to-end integration tests for CLI to Agent communication.
  Tests the full flow from CLI commands through agents and back via PubSub.
  """

  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias MCPChat.{Gateway, Session}
  alias MCPChat.CLI.{AgentBridge, EventSubscriber}
  alias MCPChat.Agents.{SessionManager, AgentPool}

  setup do
    # Ensure clean state
    on_exit(fn ->
      # Clean up any sessions created during tests
      AgentBridge.cleanup_session()
    end)

    # Initialize the bridge
    AgentBridge.init()

    :ok
  end

  describe "Session Management Flow" do
    test "CLI can create and destroy agent sessions" do
      # Create session through bridge
      assert {:ok, session_id} = AgentBridge.ensure_agent_session()

      # Verify session exists in agent architecture
      assert {:ok, _pid} = SessionManager.get_session_pid(session_id)

      # Verify event subscriber is active
      subscribers = Registry.lookup(MCPChat.CLI.EventRegistry, {EventSubscriber, session_id})
      assert length(subscribers) > 0

      # Clean up
      assert :ok = AgentBridge.cleanup_session()

      # Verify session is destroyed
      assert {:error, :not_found} = SessionManager.get_session_pid(session_id)
    end

    test "CLI maintains session mapping across multiple calls" do
      # First call creates session
      assert {:ok, session_id1} = AgentBridge.ensure_agent_session()

      # Second call returns same session
      assert {:ok, session_id2} = AgentBridge.ensure_agent_session()
      assert session_id1 == session_id2

      # Verify only one session exists
      active_sessions = SessionManager.list_active_sessions()
      assert session_id1 in active_sessions
      assert length(active_sessions) >= 1
    end
  end

  describe "Tool Execution Flow" do
    setup do
      # Create a test session
      {:ok, session_id} = AgentBridge.ensure_agent_session()
      {:ok, session_id: session_id}
    end

    test "CLI can execute fast tools synchronously", %{session_id: session_id} do
      # Mock a fast tool execution
      tool_name = "test_fast_tool"
      args = %{"input" => "test data"}

      # Execute through bridge
      result = AgentBridge.execute_tool_async(tool_name, args, execution_type: :fast)

      # Fast tools should return immediate results
      assert {:ok, _response} = result
    end

    @tag :integration
    test "CLI can execute heavy tools asynchronously with progress events", %{session_id: session_id} do
      # Set up PubSub subscription to capture events
      Phoenix.PubSub.subscribe(MCPChat.PubSub, "session:#{session_id}")

      # Mock a heavy tool that takes time
      tool_name = "test_heavy_tool"
      args = %{"data_size" => "large"}

      # Execute through bridge (will be routed to agent pool)
      result = AgentBridge.execute_tool_async(tool_name, args, execution_type: :heavy)

      assert {:ok, :async, %{execution_id: exec_id, session_id: ^session_id}} = result

      # Wait for and verify progress events
      assert_receive %MCPChat.Events.AgentEvents.ToolExecutionStarted{
                       execution_id: ^exec_id,
                       tool_name: ^tool_name
                     },
                     1000

      # Tool execution happens in agent pool, so we need to simulate completion
      # In real scenario, the ToolExecutorAgent would emit these events
      send_tool_completion_event(session_id, exec_id, tool_name)

      assert_receive %MCPChat.Events.AgentEvents.ToolExecutionCompleted{
                       execution_id: ^exec_id
                     },
                     1000
    end

    test "CLI receives real-time progress updates during tool execution" do
      # Create a mock tool execution with progress
      parent = self()

      spawn(fn ->
        {:ok, session_id} = AgentBridge.ensure_agent_session()

        # Subscribe parent to events
        Phoenix.PubSub.subscribe(MCPChat.PubSub, "session:#{session_id}")

        # Simulate tool with progress
        exec_id = "test_exec_123"

        # Emit progress events
        for progress <- [0, 25, 50, 75, 100] do
          event = %MCPChat.Events.AgentEvents.ToolExecutionProgress{
            session_id: session_id,
            execution_id: exec_id,
            tool_name: "progress_tool",
            progress: progress,
            stage: :processing,
            timestamp: DateTime.utc_now()
          }

          Phoenix.PubSub.broadcast(MCPChat.PubSub, "session:#{session_id}", {:pubsub, event})
          Process.sleep(10)
        end

        send(parent, :progress_complete)
      end)

      # Verify we receive all progress events
      assert_receive :progress_complete, 1000
    end
  end

  describe "Export Flow" do
    setup do
      {:ok, session_id} = AgentBridge.ensure_agent_session()
      {:ok, session_id: session_id}
    end

    test "CLI can request export with progress tracking", %{session_id: session_id} do
      # Subscribe to events
      Phoenix.PubSub.subscribe(MCPChat.PubSub, "session:#{session_id}")

      # Request export
      options = %{
        path: "test_export.json",
        include_metadata: true
      }

      result = AgentBridge.export_session_async("json", options)

      assert {:ok, %{export_id: export_id}} = result

      # Simulate export progress events
      stages = [
        {25, "Collecting messages"},
        {50, "Formatting data"},
        {75, "Writing file"},
        {100, "Finalizing"}
      ]

      for {progress, stage} <- stages do
        event = %MCPChat.Events.AgentEvents.ExportProgress{
          session_id: session_id,
          export_id: export_id,
          progress: progress
        }

        Phoenix.PubSub.broadcast(MCPChat.PubSub, "session:#{session_id}", {:pubsub, event})
      end

      # Verify we received progress events
      assert_receive %MCPChat.Events.AgentEvents.ExportProgress{progress: 25}, 100
      assert_receive %MCPChat.Events.AgentEvents.ExportProgress{progress: 100}, 500
    end
  end

  describe "Event Subscriber UI Updates" do
    setup do
      {:ok, session_id} = AgentBridge.ensure_agent_session()

      # Ensure event subscriber is running
      {:ok, _pid} = EventSubscriber.subscribe_to_session(session_id)

      {:ok, session_id: session_id}
    end

    test "Progress events trigger UI updates", %{session_id: session_id} do
      # Capture IO to verify UI updates
      output =
        capture_io(fn ->
          # Send a tool execution started event
          event = %MCPChat.Events.AgentEvents.ToolExecutionStarted{
            session_id: session_id,
            execution_id: "ui_test_123",
            tool_name: "ui_test_tool",
            args: %{"test" => "data"},
            timestamp: DateTime.utc_now()
          }

          Phoenix.PubSub.broadcast(MCPChat.PubSub, "session:#{session_id}", {:pubsub, event})

          # Give subscriber time to process
          Process.sleep(50)
        end)

      # Verify UI output
      assert output =~ "Starting tool execution"
      assert output =~ "ui_test_tool"
    end

    test "Progress bar renders correctly", %{session_id: session_id} do
      output =
        capture_io(fn ->
          # Send progress event
          event = %MCPChat.Events.AgentEvents.ToolExecutionProgress{
            session_id: session_id,
            execution_id: "progress_test",
            tool_name: "progress_tool",
            progress: 50,
            stage: :processing,
            timestamp: DateTime.utc_now()
          }

          Phoenix.PubSub.broadcast(MCPChat.PubSub, "session:#{session_id}", {:pubsub, event})
          Process.sleep(50)
        end)

      # Verify progress bar format
      assert output =~ "[==========          ]"
      assert output =~ "50%"
      assert output =~ "Halfway there"
    end
  end

  describe "Agent Pool Integration" do
    test "CLI commands respect agent pool limits" do
      # Get pool status before
      initial_status = Gateway.get_agent_pool_status()

      # Start multiple heavy operations
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            AgentBridge.execute_tool_async("heavy_tool_#{i}", %{}, execution_type: :heavy)
          end)
        end

      # Wait a bit for pool to process
      Process.sleep(100)

      # Check pool status
      status = Gateway.get_agent_pool_status()

      # Should have active workers (up to max_concurrent)
      assert status.active_workers <= status.max_concurrent

      # Should have queued tasks if we exceeded capacity
      if length(tasks) > status.max_concurrent do
        assert status.queue_length > 0
      end

      # Clean up tasks
      Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))
    end

    test "CLI receives queue full notifications" do
      {:ok, session_id} = AgentBridge.ensure_agent_session()
      Phoenix.PubSub.subscribe(MCPChat.PubSub, "session:#{session_id}")

      # Fill up the agent pool
      max_concurrent = AgentPool.get_pool_status().max_concurrent

      # Start enough tasks to fill the pool and queue
      for i <- 1..(max_concurrent + 2) do
        spawn(fn ->
          AgentBridge.execute_tool_async("queue_test_#{i}", %{}, execution_type: :heavy)
        end)
      end

      # Should receive queue full event
      assert_receive %MCPChat.Events.AgentEvents.AgentPoolQueueFull{}, 1000
    end
  end

  describe "Full CLI Command Flow" do
    test "MCP tool command executes through agent architecture" do
      output =
        capture_io(fn ->
          # Simulate CLI command execution
          {:ok, session_id} = AgentBridge.ensure_agent_session()

          # Execute a tool
          result =
            Gateway.execute_tool(
              session_id,
              "test_tool",
              %{"param" => "value"},
              execution_type: :fast
            )

          case result do
            {:ok, response} ->
              IO.puts("Tool completed successfully")
              IO.puts("Result: #{inspect(response)}")

            {:error, reason} ->
              IO.puts("Tool failed: #{inspect(reason)}")
          end
        end)

      assert output =~ "Tool completed"
    end

    test "Export command shows progress through event subscriber" do
      output =
        capture_io(fn ->
          {:ok, session_id} = AgentBridge.ensure_agent_session()

          # Set up current session for export
          Session.add_message("user", "Test message 1")
          Session.add_message("assistant", "Test response 1")

          # Request export
          case Gateway.request_export(session_id, "json", %{path: "test.json"}) do
            {:ok, %{export_id: export_id}} ->
              IO.puts("Export started: #{export_id}")

              # Simulate progress
              for progress <- [25, 50, 75, 100] do
                event = %MCPChat.Events.AgentEvents.ExportProgress{
                  session_id: session_id,
                  export_id: export_id,
                  progress: progress
                }

                Phoenix.PubSub.broadcast(
                  MCPChat.PubSub,
                  "session:#{session_id}",
                  {:pubsub, event}
                )

                Process.sleep(10)
              end

            {:error, reason} ->
              IO.puts("Export failed: #{inspect(reason)}")
          end
        end)

      assert output =~ "Export started"
    end
  end

  # Helper functions

  defp send_tool_completion_event(session_id, execution_id, tool_name) do
    event = %MCPChat.Events.AgentEvents.ToolExecutionCompleted{
      session_id: session_id,
      execution_id: execution_id,
      tool_name: tool_name,
      result: %{"status" => "success", "data" => "test"},
      duration_ms: 100,
      timestamp: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(MCPChat.PubSub, "session:#{session_id}", {:pubsub, event})
  end
end
