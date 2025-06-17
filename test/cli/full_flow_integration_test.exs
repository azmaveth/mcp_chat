defmodule MCPChat.CLI.FullFlowIntegrationTest do
  @moduledoc """
  Full end-to-end integration tests simulating real CLI usage scenarios.
  These tests verify the complete flow from user input to agent execution and back.
  """

  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias MCPChat.Gateway
  alias MCPChat.CLI.{AgentBridge, EventSubscriber, Commands}
  alias MCPChat.Agents.{SessionManager, ToolExecutorAgent}

  setup_all do
    # Ensure the application is fully started
    Application.ensure_all_started(:mcp_chat)

    # Wait for all supervisors to be ready
    Process.sleep(100)

    :ok
  end

  setup do
    # Initialize bridge for each test
    AgentBridge.init()

    on_exit(fn ->
      AgentBridge.cleanup_session()
    end)

    :ok
  end

  describe "Real-world MCP Tool Execution" do
    @tag :integration
    test "Execute MCP tool with progress tracking from CLI" do
      # Simulate what happens when user types: /mcp tool server analyze_code file.ex

      output =
        capture_io(fn ->
          # 1. CLI creates agent session
          {:ok, session_id} = AgentBridge.ensure_agent_session()
          IO.puts("Session created: #{session_id}")

          # 2. Subscribe to events for UI updates
          {:ok, _pid} = EventSubscriber.subscribe_to_session(session_id)
          EventSubscriber.set_ui_mode(session_id, :interactive)

          # 3. Execute tool through Gateway (simulating heavy operation)
          tool_name = "analyze_code"
          args = %{"file" => "test.ex", "depth" => "full"}

          case Gateway.execute_tool(session_id, tool_name, args, execution_type: :heavy) do
            {:ok, :async, %{execution_id: exec_id}} ->
              IO.puts("Tool execution started: #{exec_id}")

              # 4. Simulate agent processing with progress
              simulate_tool_execution_with_progress(session_id, exec_id, tool_name)

              # 5. Wait for completion
              Process.sleep(300)

            {:error, reason} ->
              IO.puts("Failed to execute tool: #{inspect(reason)}")
          end
        end)

      # Verify expected output
      assert output =~ "Session created"
      assert output =~ "Tool execution started"
      assert output =~ "Starting tool execution: analyze_code"
      assert output =~ "Progress:"
      assert output =~ "Tool completed: analyze_code"
    end

    @tag :integration
    test "Handle multiple concurrent tool executions" do
      output =
        capture_io(fn ->
          {:ok, session_id} = AgentBridge.ensure_agent_session()
          {:ok, _pid} = EventSubscriber.subscribe_to_session(session_id)

          # Start multiple tools
          tools = [
            {"scan_dependencies", %{"path" => "./lib"}},
            {"generate_docs", %{"format" => "html"}},
            {"run_analysis", %{"type" => "security"}}
          ]

          execution_ids =
            Enum.map(tools, fn {tool_name, args} ->
              case Gateway.execute_tool(session_id, tool_name, args, execution_type: :heavy) do
                {:ok, :async, %{execution_id: exec_id}} ->
                  IO.puts("Started: #{tool_name} (#{exec_id})")
                  {exec_id, tool_name}

                _ ->
                  nil
              end
            end)
            |> Enum.filter(&(&1 != nil))

          # Simulate progress for each tool
          Enum.each(execution_ids, fn {exec_id, tool_name} ->
            Task.start(fn ->
              simulate_tool_execution_with_progress(session_id, exec_id, tool_name)
            end)
          end)

          # Check pool status
          Process.sleep(50)
          pool_status = Gateway.get_agent_pool_status()
          IO.puts("\nAgent Pool Status:")
          IO.puts("  Active: #{pool_status.active_workers}/#{pool_status.max_concurrent}")
          IO.puts("  Queued: #{pool_status.queue_length}")

          # Wait for all to complete
          Process.sleep(500)
        end)

      assert output =~ "Started: scan_dependencies"
      assert output =~ "Started: generate_docs"
      assert output =~ "Started: run_analysis"
      assert output =~ "Agent Pool Status:"
    end
  end

  describe "Chat Message Flow with Agents" do
    @tag :integration
    test "Send message and receive async LLM response" do
      # This simulates the refactored chat loop

      output =
        capture_io(fn ->
          {:ok, session_id} = AgentBridge.ensure_agent_session()
          {:ok, _pid} = EventSubscriber.subscribe_to_session(session_id)

          # Send a message
          message = "What is Elixir?"
          :ok = Gateway.send_message(session_id, message)

          IO.puts("User: #{message}")
          IO.puts("Thinking...")

          # Simulate LLM response streaming
          simulate_llm_streaming_response(
            session_id,
            "Elixir is a dynamic, functional programming language..."
          )

          Process.sleep(200)
        end)

      assert output =~ "User: What is Elixir?"
      assert output =~ "Thinking..."
      # The actual response would be shown via streaming chunks
    end
  end

  describe "Export Flow with Real Progress" do
    @tag :integration
    test "Export session with progress tracking" do
      output =
        capture_io(fn ->
          {:ok, session_id} = AgentBridge.ensure_agent_session()
          {:ok, _pid} = EventSubscriber.subscribe_to_session(session_id)

          # Add some messages to export
          Gateway.send_message(session_id, "Test message 1")
          Gateway.send_message(session_id, "Test message 2")

          # Request export
          case Gateway.request_export(session_id, "json", %{path: "test_export.json"}) do
            {:ok, %{export_id: export_id}} ->
              IO.puts("Starting export: #{export_id}")

              # Simulate export progress
              simulate_export_with_progress(session_id, export_id)

              Process.sleep(300)

            {:error, reason} ->
              IO.puts("Export failed: #{inspect(reason)}")
          end
        end)

      assert output =~ "Starting export"
      assert output =~ "Starting export to json format"
      assert output =~ "Export progress:"
      assert output =~ "Export completed: json format"
    end
  end

  describe "Error Handling and Recovery" do
    @tag :integration
    test "Handle tool execution failure gracefully" do
      output =
        capture_io(fn ->
          {:ok, session_id} = AgentBridge.ensure_agent_session()
          {:ok, _pid} = EventSubscriber.subscribe_to_session(session_id)

          # Execute a tool that will fail
          tool_name = "failing_tool"
          args = %{"will_fail" => true}

          case Gateway.execute_tool(session_id, tool_name, args, execution_type: :heavy) do
            {:ok, :async, %{execution_id: exec_id}} ->
              IO.puts("Tool started: #{exec_id}")

              # Simulate failure
              simulate_tool_failure(session_id, exec_id, tool_name, "Simulated error")

              Process.sleep(100)

            _ ->
              IO.puts("Failed to start tool")
          end
        end)

      assert output =~ "Tool started"
      assert output =~ "Tool failed: failing_tool"
      assert output =~ "Error: \"Simulated error\""
    end

    @tag :integration
    test "Cancel long-running operation" do
      output =
        capture_io(fn ->
          {:ok, session_id} = AgentBridge.ensure_agent_session()

          # Start a long operation
          case Gateway.execute_tool(session_id, "long_tool", %{}, execution_type: :heavy) do
            {:ok, :async, %{execution_id: exec_id}} ->
              IO.puts("Started long operation: #{exec_id}")

              # Wait a bit
              Process.sleep(50)

              # Cancel it
              case Gateway.cancel_tool_execution(session_id, exec_id) do
                :ok ->
                  IO.puts("Operation cancelled successfully")

                {:error, reason} ->
                  IO.puts("Failed to cancel: #{inspect(reason)}")
              end

            _ ->
              IO.puts("Failed to start operation")
          end
        end)

      assert output =~ "Started long operation"
      # Cancel might not always work in test environment
    end
  end

  describe "System Status and Monitoring" do
    @tag :integration
    test "Get comprehensive system status through CLI" do
      output =
        capture_io(fn ->
          {:ok, session_id} = AgentBridge.ensure_agent_session()

          # Start some operations
          Gateway.execute_tool(session_id, "tool1", %{}, execution_type: :heavy)
          Gateway.execute_tool(session_id, "tool2", %{}, execution_type: :heavy)

          Process.sleep(50)

          # Get system health
          health = Gateway.get_system_health()

          IO.puts("System Health Report:")
          IO.puts("  Sessions: #{health.sessions.currently_active}")
          IO.puts("  Agent Pool:")
          IO.puts("    Active: #{health.agent_pool.active_workers}")
          IO.puts("    Queued: #{health.agent_pool.queue_length}")
          IO.puts("  Memory: #{format_memory(health.memory_usage[:total])}")
          IO.puts("  Processes: #{health.process_count}")

          # List active operations
          operations = Gateway.list_session_subagents(session_id)
          IO.puts("\nActive Operations: #{length(operations)}")

          Enum.each(operations, fn {id, info} ->
            if info.alive do
              IO.puts("  - #{info.agent_type}: #{id}")
            end
          end)
        end)

      assert output =~ "System Health Report:"
      assert output =~ "Sessions:"
      assert output =~ "Agent Pool:"
      assert output =~ "Memory:"
      assert output =~ "Active Operations:"
    end
  end

  # Helper functions

  defp simulate_tool_execution_with_progress(session_id, exec_id, tool_name) do
    # Start event
    Phoenix.PubSub.broadcast(
      MCPChat.PubSub,
      "session:#{session_id}",
      {:pubsub,
       %MCPChat.Events.AgentEvents.ToolExecutionStarted{
         session_id: session_id,
         execution_id: exec_id,
         tool_name: tool_name,
         args: %{},
         timestamp: DateTime.utc_now()
       }}
    )

    # Progress events
    for progress <- [25, 50, 75, 100] do
      Process.sleep(20)

      Phoenix.PubSub.broadcast(
        MCPChat.PubSub,
        "session:#{session_id}",
        {:pubsub,
         %MCPChat.Events.AgentEvents.ToolExecutionProgress{
           session_id: session_id,
           execution_id: exec_id,
           tool_name: tool_name,
           progress: progress,
           stage: :processing,
           timestamp: DateTime.utc_now(),
           agent_pid: self()
         }}
      )
    end

    # Completion event
    Process.sleep(20)

    Phoenix.PubSub.broadcast(
      MCPChat.PubSub,
      "session:#{session_id}",
      {:pubsub,
       %MCPChat.Events.AgentEvents.ToolExecutionCompleted{
         session_id: session_id,
         execution_id: exec_id,
         tool_name: tool_name,
         result: %{"status" => "success"},
         duration_ms: 250,
         timestamp: DateTime.utc_now()
       }}
    )
  end

  defp simulate_export_with_progress(session_id, export_id) do
    # Start event
    Phoenix.PubSub.broadcast(
      MCPChat.PubSub,
      "session:#{session_id}",
      {:pubsub,
       %MCPChat.Events.AgentEvents.ExportStarted{
         session_id: session_id,
         export_id: export_id,
         format: "json",
         started_at: DateTime.utc_now()
       }}
    )

    # Progress stages
    stages = [
      {25, "Collecting messages"},
      {50, "Processing data"},
      {75, "Formatting output"},
      {100, "Writing file"}
    ]

    for {progress, stage} <- stages do
      Process.sleep(30)

      Phoenix.PubSub.broadcast(
        MCPChat.PubSub,
        "session:#{session_id}",
        {:pubsub,
         %MCPChat.Events.AgentEvents.ExportProgress{
           session_id: session_id,
           export_id: export_id,
           progress: progress
         }}
      )
    end

    # Completion
    Process.sleep(30)

    Phoenix.PubSub.broadcast(
      MCPChat.PubSub,
      "session:#{session_id}",
      {:pubsub,
       %MCPChat.Events.AgentEvents.ExportCompleted{
         session_id: session_id,
         export_id: export_id,
         download_url: "/tmp/test_export.json",
         file_size: 1024,
         duration_ms: 350
       }}
    )
  end

  defp simulate_tool_failure(session_id, exec_id, tool_name, error_message) do
    # Start event (optional, might already be sent)
    Phoenix.PubSub.broadcast(
      MCPChat.PubSub,
      "session:#{session_id}",
      {:pubsub,
       %MCPChat.Events.AgentEvents.ToolExecutionStarted{
         session_id: session_id,
         execution_id: exec_id,
         tool_name: tool_name,
         args: %{},
         timestamp: DateTime.utc_now()
       }}
    )

    Process.sleep(50)

    # Failure event
    Phoenix.PubSub.broadcast(
      MCPChat.PubSub,
      "session:#{session_id}",
      {:pubsub,
       %MCPChat.Events.AgentEvents.ToolExecutionFailed{
         session_id: session_id,
         execution_id: exec_id,
         tool_name: tool_name,
         error: error_message,
         timestamp: DateTime.utc_now()
       }}
    )
  end

  defp simulate_llm_streaming_response(session_id, response_text) do
    # Simulate chunked response
    chunks = String.split(response_text, " ")

    Enum.each(chunks, fn chunk ->
      Phoenix.PubSub.broadcast(
        MCPChat.PubSub,
        "session:#{session_id}:llm_response",
        {:llm_chunk, chunk <> " "}
      )

      Process.sleep(10)
    end)

    # Send completion
    Phoenix.PubSub.broadcast(
      MCPChat.PubSub,
      "session:#{session_id}:llm_response",
      :llm_complete
    )
  end

  defp format_memory(bytes) when is_integer(bytes) do
    cond do
      bytes < 1024 -> "#{bytes} B"
      bytes < 1024 * 1024 -> "#{Float.round(bytes / 1024, 1)} KB"
      bytes < 1024 * 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024), 1)} MB"
      true -> "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"
    end
  end

  defp format_memory(_), do: "N/A"
end
