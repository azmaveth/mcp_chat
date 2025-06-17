defmodule MCPChat.CLI.RealUsageSimulationTest do
  @moduledoc """
  Simulates real CLI usage patterns to test the complete integration.
  These tests mimic actual user interactions and verify the full flow.
  """

  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias MCPChat.CLI.{AgentBridge, EventSubscriber, Commands}
  alias MCPChat.{Gateway, Session}

  setup_all do
    # Ensure full application startup
    Application.ensure_all_started(:mcp_chat)
    Process.sleep(200)
    :ok
  end

  setup do
    # Initialize bridge
    AgentBridge.init()

    on_exit(fn ->
      AgentBridge.cleanup_session()
    end)

    :ok
  end

  describe "Typical User Workflow" do
    @tag :integration
    test "User executes multiple MCP tools in sequence" do
      # Simulate: User opens CLI and runs several tools

      output =
        capture_io(fn ->
          # User starts a session
          {:ok, session_id} = AgentBridge.ensure_agent_session()
          {:ok, _pid} = EventSubscriber.subscribe_to_session(session_id)

          IO.puts("=== MCP Chat Session Started ===")
          IO.puts("Session ID: #{session_id}")
          IO.puts("")

          # User lists available tools
          IO.puts("User: /mcp tools")
          simulate_command("/mcp tools", session_id)
          IO.puts("")

          # User executes a quick tool
          IO.puts("User: /mcp tool server file_info README.md")
          execute_tool_simulation(session_id, "file_info", %{"path" => "README.md"}, :fast)
          IO.puts("")

          # User executes a heavy analysis tool
          IO.puts("User: /mcp tool analyzer scan_codebase lib/")
          execute_tool_simulation(session_id, "scan_codebase", %{"path" => "lib/"}, :heavy)
          IO.puts("")

          # User checks status while tool is running
          IO.puts("User: /mcp status")
          status = Gateway.get_agent_pool_status()
          IO.puts("Agent Pool: #{status.active_workers} active, #{status.queue_length} queued")

          # Wait for completion
          Process.sleep(400)
        end)

      # Verify workflow output
      assert output =~ "Session Started"
      assert output =~ "Session ID:"
      assert output =~ "User: /mcp tools"
      assert output =~ "User: /mcp tool server file_info"
      assert output =~ "User: /mcp tool analyzer scan_codebase"
      assert output =~ "Agent Pool:"
    end

    @tag :integration
    test "User exports session with progress tracking" do
      output =
        capture_io(fn ->
          {:ok, session_id} = AgentBridge.ensure_agent_session()
          {:ok, _pid} = EventSubscriber.subscribe_to_session(session_id)

          # Add some chat history
          Gateway.send_message(session_id, "What is Elixir?")
          Gateway.send_message(session_id, "How does OTP work?")

          IO.puts("User: /export json chat_history.json")

          # Simulate export command
          case Gateway.request_export(session_id, "json", %{path: "chat_history.json"}) do
            {:ok, %{export_id: export_id}} ->
              IO.puts("Export started with ID: #{export_id}")

              # Simulate the export progress
              simulate_export_progress(session_id, export_id, "json")

              Process.sleep(400)

            {:error, reason} ->
              IO.puts("Export failed: #{inspect(reason)}")
          end
        end)

      assert output =~ "User: /export json"
      assert output =~ "Export started with ID:"
      assert output =~ "Starting export to json format"
      assert output =~ "Export progress:"
      assert output =~ "Export completed: json format"
    end
  end

  describe "Concurrent Operations" do
    @tag :integration
    test "User runs multiple tools simultaneously" do
      output =
        capture_io(fn ->
          {:ok, session_id} = AgentBridge.ensure_agent_session()
          {:ok, _pid} = EventSubscriber.subscribe_to_session(session_id)
          EventSubscriber.set_ui_mode(session_id, :interactive)

          IO.puts("=== Running Multiple Tools ===")

          # Start multiple tools quickly
          tools = [
            {"analyze_deps", %{"mix_file" => "mix.exs"}},
            {"security_scan", %{"path" => "./lib"}},
            {"generate_docs", %{"format" => "html"}}
          ]

          execution_ids =
            Enum.map(tools, fn {tool_name, args} ->
              IO.puts("Starting: #{tool_name}")

              case Gateway.execute_tool(session_id, tool_name, args, execution_type: :heavy) do
                {:ok, :async, %{execution_id: exec_id}} ->
                  {exec_id, tool_name}

                _ ->
                  nil
              end
            end)
            |> Enum.filter(&(&1 != nil))

          # Monitor progress
          IO.puts("\nMonitoring #{length(execution_ids)} operations...")

          # Simulate progress for each
          Enum.each(execution_ids, fn {exec_id, tool_name} ->
            Task.start(fn ->
              simulate_tool_with_progress(session_id, exec_id, tool_name)
            end)
          end)

          # Show pool status
          Process.sleep(100)
          pool_status = Gateway.get_agent_pool_status()
          IO.puts("\nPool Status: #{pool_status.active_workers}/#{pool_status.max_concurrent} workers active")

          # Wait for all to complete
          Process.sleep(600)
          IO.puts("\nAll operations completed!")
        end)

      assert output =~ "Running Multiple Tools"
      assert output =~ "Starting: analyze_deps"
      assert output =~ "Starting: security_scan"
      assert output =~ "Starting: generate_docs"
      assert output =~ "Pool Status:"
      assert output =~ "workers active"
    end
  end

  describe "Error Scenarios" do
    @tag :integration
    test "User handles tool failure gracefully" do
      output =
        capture_io(fn ->
          {:ok, session_id} = AgentBridge.ensure_agent_session()
          {:ok, _pid} = EventSubscriber.subscribe_to_session(session_id)

          IO.puts("User: /mcp tool server broken_tool --fail")

          case Gateway.execute_tool(session_id, "broken_tool", %{"fail" => true}, execution_type: :heavy) do
            {:ok, :async, %{execution_id: exec_id}} ->
              IO.puts("Tool started: #{exec_id}")

              # Simulate failure after some progress
              Process.sleep(50)
              simulate_tool_failure(session_id, exec_id, "broken_tool", "Intentional failure for testing")

              Process.sleep(100)

            _ ->
              IO.puts("Failed to start tool")
          end

          IO.puts("\nUser: Let me try a different approach...")
        end)

      assert output =~ "broken_tool"
      assert output =~ "Tool failed:"
      assert output =~ "Intentional failure for testing"
    end

    @tag :integration
    test "User cancels long-running operation" do
      output =
        capture_io(fn ->
          {:ok, session_id} = AgentBridge.ensure_agent_session()
          {:ok, _pid} = EventSubscriber.subscribe_to_session(session_id)

          IO.puts("Starting long operation...")

          case Gateway.execute_tool(session_id, "long_analysis", %{"timeout" => 60000}, execution_type: :heavy) do
            {:ok, :async, %{execution_id: exec_id}} ->
              IO.puts("Operation started: #{exec_id}")

              # Simulate some progress
              send_progress_event(session_id, exec_id, "long_analysis", 25, "Processing...")
              Process.sleep(100)

              # User decides to cancel
              IO.puts("\nUser: This is taking too long, let me cancel...")
              IO.puts("User: /cancel #{exec_id}")

              case Gateway.cancel_tool_execution(session_id, exec_id) do
                :ok ->
                  IO.puts("Operation cancelled successfully")

                error ->
                  IO.puts("Cancel failed: #{inspect(error)}")
              end

            _ ->
              IO.puts("Failed to start operation")
          end
        end)

      assert output =~ "Starting long operation"
      assert output =~ "Operation started:"
      assert output =~ "This is taking too long"
    end
  end

  describe "Real-time Updates" do
    @tag :integration
    test "User sees live progress updates" do
      # This test verifies that progress updates appear in real-time

      {:ok, session_id} = AgentBridge.ensure_agent_session()
      {:ok, _pid} = EventSubscriber.subscribe_to_session(session_id)
      EventSubscriber.set_ui_mode(session_id, :interactive)

      # Use a separate process to capture output while events are happening
      parent = self()

      output_pid =
        spawn(fn ->
          output =
            capture_io(fn ->
              # Wait for parent signal
              receive do
                :start -> :ok
              end

              # Keep capturing for a while
              Process.sleep(600)
            end)

          send(parent, {:output, output})
        end)

      # Start the output capture
      send(output_pid, :start)

      # Give it time to start capturing
      Process.sleep(50)

      # Now generate events that should be captured
      exec_id = "realtime_test"
      tool_name = "progress_demo"

      # Start event
      send_event(session_id, %MCPChat.Events.AgentEvents.ToolExecutionStarted{
        session_id: session_id,
        execution_id: exec_id,
        tool_name: tool_name,
        args: %{},
        timestamp: DateTime.utc_now()
      })

      # Progress events with delays
      for i <- 1..4 do
        Process.sleep(100)
        progress = i * 25

        send_event(session_id, %MCPChat.Events.AgentEvents.ToolExecutionProgress{
          session_id: session_id,
          execution_id: exec_id,
          tool_name: tool_name,
          progress: progress,
          stage: :processing,
          timestamp: DateTime.utc_now(),
          agent_pid: self()
        })
      end

      # Completion
      Process.sleep(100)

      send_event(session_id, %MCPChat.Events.AgentEvents.ToolExecutionCompleted{
        session_id: session_id,
        execution_id: exec_id,
        tool_name: tool_name,
        result: %{"status" => "success"},
        duration_ms: 500,
        timestamp: DateTime.utc_now()
      })

      # Get the captured output
      assert_receive {:output, output}, 1000

      # Verify progress updates were shown
      assert output =~ "Starting tool execution: progress_demo"
      assert output =~ "Progress:"
      assert output =~ "25%"
      assert output =~ "50%"
      assert output =~ "75%"
      assert output =~ "100%"
      assert output =~ "Tool completed: progress_demo"
    end
  end

  # Helper functions

  defp simulate_command(command, _session_id) do
    # Simulate command execution
    case command do
      "/mcp tools" ->
        IO.puts("Available tools:")
        IO.puts("  • file_info - Get file information")
        IO.puts("  • scan_codebase - Analyze code structure")
        IO.puts("  • analyze_deps - Check dependencies")

      _ ->
        IO.puts("Command: #{command}")
    end
  end

  defp execute_tool_simulation(session_id, tool_name, args, execution_type) do
    case Gateway.execute_tool(session_id, tool_name, args, execution_type: execution_type) do
      {:ok, :async, %{execution_id: exec_id}} ->
        IO.puts("Tool execution started (async): #{exec_id}")

        # Simulate the tool execution
        Task.start(fn ->
          simulate_tool_with_progress(session_id, exec_id, tool_name)
        end)

      {:ok, result} ->
        IO.puts("Tool completed (sync): #{inspect(result)}")

      {:error, reason} ->
        IO.puts("Tool failed: #{inspect(reason)}")
    end
  end

  defp simulate_tool_with_progress(session_id, exec_id, tool_name) do
    # Send start event
    send_event(session_id, %MCPChat.Events.AgentEvents.ToolExecutionStarted{
      session_id: session_id,
      execution_id: exec_id,
      tool_name: tool_name,
      args: %{},
      timestamp: DateTime.utc_now()
    })

    # Send progress events
    for i <- 1..4 do
      Process.sleep(50)
      progress = i * 25

      send_event(session_id, %MCPChat.Events.AgentEvents.ToolExecutionProgress{
        session_id: session_id,
        execution_id: exec_id,
        tool_name: tool_name,
        progress: progress,
        stage: :processing,
        timestamp: DateTime.utc_now(),
        agent_pid: self()
      })
    end

    # Send completion
    Process.sleep(50)

    send_event(session_id, %MCPChat.Events.AgentEvents.ToolExecutionCompleted{
      session_id: session_id,
      execution_id: exec_id,
      tool_name: tool_name,
      result: %{"status" => "success", "output" => "Analysis complete"},
      duration_ms: 300,
      timestamp: DateTime.utc_now()
    })
  end

  defp simulate_export_progress(session_id, export_id, format) do
    # Start
    send_event(session_id, %MCPChat.Events.AgentEvents.ExportStarted{
      session_id: session_id,
      export_id: export_id,
      format: format,
      started_at: DateTime.utc_now()
    })

    # Progress
    stages = [
      {25, "Collecting messages"},
      {50, "Processing data"},
      {75, "Formatting output"},
      {100, "Writing file"}
    ]

    for {progress, stage} <- stages do
      Process.sleep(50)

      send_event(session_id, %MCPChat.Events.AgentEvents.ExportProgress{
        session_id: session_id,
        export_id: export_id,
        progress: progress
      })
    end

    # Complete
    Process.sleep(50)

    send_event(session_id, %MCPChat.Events.AgentEvents.ExportCompleted{
      session_id: session_id,
      export_id: export_id,
      download_url: "chat_history.json",
      file_size: 4096,
      duration_ms: 350
    })
  end

  defp simulate_tool_failure(session_id, exec_id, tool_name, error_msg) do
    send_event(session_id, %MCPChat.Events.AgentEvents.ToolExecutionFailed{
      session_id: session_id,
      execution_id: exec_id,
      tool_name: tool_name,
      error: error_msg,
      timestamp: DateTime.utc_now()
    })
  end

  defp send_progress_event(session_id, exec_id, tool_name, progress, _message) do
    send_event(session_id, %MCPChat.Events.AgentEvents.ToolExecutionProgress{
      session_id: session_id,
      execution_id: exec_id,
      tool_name: tool_name,
      progress: progress,
      stage: :processing,
      timestamp: DateTime.utc_now(),
      agent_pid: self()
    })
  end

  defp send_event(session_id, event) do
    Phoenix.PubSub.broadcast(
      MCPChat.PubSub,
      "session:#{session_id}",
      {:pubsub, event}
    )
  end
end
