defmodule MCPChat.AgentTestHelpers do
  @moduledoc """
  Helper functions for testing agent architecture integration.
  """

  alias MCPChat.Events.AgentEvents
  alias Phoenix.PubSub

  @pubsub MCPChat.PubSub

  @doc "Waits for a specific event type with timeout"
  def assert_event_received(event_type, session_id, timeout \\ 1000) do
    receive do
      {:pubsub, %{__struct__: ^event_type} = event} ->
        {:ok, event}
    after
      timeout ->
        {:error, :timeout}
    end
  end

  @doc "Broadcasts an event to a session"
  def broadcast_event(session_id, event) do
    PubSub.broadcast(@pubsub, "session:#{session_id}", {:pubsub, event})
  end

  @doc "Simulates a complete tool execution flow"
  def simulate_tool_execution(session_id, tool_name, opts \\ []) do
    exec_id = Keyword.get(opts, :execution_id, generate_exec_id())
    duration = Keyword.get(opts, :duration, 200)
    progress_steps = Keyword.get(opts, :progress_steps, 4)
    should_fail = Keyword.get(opts, :should_fail, false)

    # Start
    broadcast_event(session_id, %AgentEvents.ToolExecutionStarted{
      session_id: session_id,
      execution_id: exec_id,
      tool_name: tool_name,
      args: Keyword.get(opts, :args, %{}),
      timestamp: DateTime.utc_now()
    })

    # Progress
    unless should_fail do
      step_delay = div(duration, progress_steps + 1)

      for i <- 1..progress_steps do
        Process.sleep(step_delay)
        progress = div(i * 100, progress_steps)

        broadcast_event(session_id, %AgentEvents.ToolExecutionProgress{
          session_id: session_id,
          execution_id: exec_id,
          tool_name: tool_name,
          progress: progress,
          stage: :processing,
          timestamp: DateTime.utc_now()
        })
      end
    end

    Process.sleep(50)

    # Complete or fail
    if should_fail do
      broadcast_event(session_id, %AgentEvents.ToolExecutionFailed{
        session_id: session_id,
        execution_id: exec_id,
        tool_name: tool_name,
        error: Keyword.get(opts, :error, "Simulated failure"),
        timestamp: DateTime.utc_now()
      })
    else
      broadcast_event(session_id, %AgentEvents.ToolExecutionCompleted{
        session_id: session_id,
        execution_id: exec_id,
        tool_name: tool_name,
        result: Keyword.get(opts, :result, %{"status" => "success"}),
        duration_ms: duration,
        timestamp: DateTime.utc_now()
      })
    end

    exec_id
  end

  @doc "Simulates a complete export flow"
  def simulate_export(session_id, format, opts \\ []) do
    export_id = Keyword.get(opts, :export_id, generate_export_id())
    duration = Keyword.get(opts, :duration, 300)

    # Start
    broadcast_event(session_id, %AgentEvents.ExportStarted{
      session_id: session_id,
      export_id: export_id,
      format: format,
      started_at: DateTime.utc_now()
    })

    # Progress stages
    stages = [
      {25, "Collecting data"},
      {50, "Processing"},
      {75, "Formatting"},
      {100, "Finalizing"}
    ]

    stage_delay = div(duration, length(stages))

    for {progress, stage} <- stages do
      Process.sleep(stage_delay)

      broadcast_event(session_id, %AgentEvents.ExportProgress{
        session_id: session_id,
        export_id: export_id,
        progress: progress
      })
    end

    # Complete
    Process.sleep(50)

    broadcast_event(session_id, %AgentEvents.ExportCompleted{
      session_id: session_id,
      export_id: export_id,
      download_url: Keyword.get(opts, :download_url, "/tmp/export.#{format}"),
      file_size: Keyword.get(opts, :file_size, 1024),
      duration_ms: duration
    })

    export_id
  end

  @doc "Waits for agent pool to be ready"
  def wait_for_agent_pool(timeout \\ 5000) do
    wait_until(
      fn ->
        case Process.whereis(MCPChat.Agents.AgentPool) do
          nil -> false
          pid -> Process.alive?(pid)
        end
      end,
      timeout
    )
  end

  @doc "Waits for a condition to be true"
  def wait_until(condition_fn, timeout \\ 5000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    wait_until_loop(condition_fn, deadline)
  end

  defp wait_until_loop(condition_fn, deadline) do
    if condition_fn.() do
      :ok
    else
      now = System.monotonic_time(:millisecond)

      if now < deadline do
        Process.sleep(50)
        wait_until_loop(condition_fn, deadline)
      else
        {:error, :timeout}
      end
    end
  end

  defp generate_exec_id do
    "test_exec_#{:rand.uniform(99999)}"
  end

  defp generate_export_id do
    "test_export_#{:rand.uniform(99999)}"
  end
end
