defmodule MCPChat.CLI.ChatAgentIntegration do
  @moduledoc """
  Integration module showing how to handle async agent responses in the chat loop.
  This demonstrates the pattern for migrating from synchronous to async operations.
  """

  require Logger

  alias MCPChat.CLI.{AgentBridge, EventSubscriber, Renderer}
  alias MCPChat.Gateway

  @doc """
  Example of handling LLM responses through the agent architecture.
  This shows how to integrate async streaming with the existing chat loop.
  """
  def handle_llm_with_agents(message, opts \\ []) do
    # Ensure we have an agent session
    case AgentBridge.ensure_agent_session() do
      {:ok, session_id} ->
        # Set up event handling for this response
        setup_response_handling(session_id)

        # Send message through agent architecture
        execute_llm_request(session_id, message, opts)

      {:error, reason} ->
        Renderer.show_error("Failed to create agent session: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Example of handling tool execution with real-time progress.
  """
  def execute_tool_with_progress(tool_name, args, opts \\ []) do
    case AgentBridge.execute_tool_async(tool_name, args, opts) do
      {:ok, :async, %{execution_id: exec_id, session_id: session_id}} ->
        # Tool is running async, wait for completion
        wait_for_tool_completion(session_id, exec_id, opts)

      {:ok, result} ->
        # Synchronous result
        {:ok, result}

      error ->
        error
    end
  end

  @doc """
  Demonstrates the pattern for migrating commands to use agents.
  """
  def migrate_command_to_agents(command_fn, args) do
    # Wrap the existing command function with agent support
    case AgentBridge.ensure_agent_session() do
      {:ok, session_id} ->
        # Subscribe to events for this session
        EventSubscriber.set_ui_mode(session_id, :interactive)

        # Execute the command
        result = command_fn.(args)

        # Handle any async operations that were started
        handle_pending_operations(session_id)

        result

      error ->
        error
    end
  end

  # Private functions

  defp setup_response_handling(session_id) do
    # Create a dedicated process to handle the streaming response
    parent = self()

    spawn_link(fn ->
      # Subscribe to LLM response events
      Phoenix.PubSub.subscribe(MCPChat.PubSub, "session:#{session_id}:llm")

      # Collect and display chunks
      response = collect_llm_response()

      # Send complete response back to parent
      send(parent, {:llm_response, response})
    end)
  end

  defp execute_llm_request(session_id, message, opts) do
    # This would integrate with the actual LLM execution through agents
    # For now, we show the pattern

    Renderer.show_thinking()

    # In a real implementation, this would:
    # 1. Route the request through Gateway to the appropriate agent
    # 2. Handle streaming responses via PubSub
    # 3. Update the UI in real-time

    # Wait for the response
    receive do
      {:llm_response, response} ->
        # TODO: Add to session history with Gateway API
        # Assistant messages will be tracked automatically by the Gateway
        Renderer.show_assistant_message(response)
        {:ok, response}
    after
      60_000 ->
        Renderer.show_error("Response timeout")
        {:error, :timeout}
    end
  end

  defp collect_llm_response(acc \\ "") do
    receive do
      %{event: "chunk", data: chunk} ->
        # Display chunk immediately
        Renderer.show_stream_chunk(chunk)
        collect_llm_response(acc <> chunk)

      %{event: "complete"} ->
        Renderer.end_stream()
        acc

      %{event: "error", error: error} ->
        Renderer.show_error("Stream error: #{inspect(error)}")
        acc
    after
      30_000 ->
        # Timeout for individual chunks
        acc
    end
  end

  defp wait_for_tool_completion(session_id, execution_id, opts) do
    # 5 minutes default
    timeout = Keyword.get(opts, :timeout, 300_000)

    # Subscribe to completion events
    Phoenix.PubSub.subscribe(MCPChat.PubSub, "session:#{session_id}:tool:#{execution_id}")

    receive do
      %{event: "completed", result: result} ->
        {:ok, result}

      %{event: "failed", error: error} ->
        {:error, error}
    after
      timeout ->
        # Try to cancel the execution
        AgentBridge.cancel_tool_execution(execution_id)
        {:error, :timeout}
    end
  end

  defp handle_pending_operations(session_id) do
    # Check for any pending async operations
    operations = Gateway.list_session_subagents(session_id)

    active_ops = Enum.filter(operations, fn {_id, info} -> info.alive end)

    if length(active_ops) > 0 do
      Renderer.show_info("\n🔄 #{length(active_ops)} operation(s) running in background")
      Renderer.show_info("They will complete asynchronously with progress updates.")
    end
  end

  @doc """
  Example usage in the chat loop to demonstrate the integration pattern.
  """
  def example_chat_loop_integration do
    # This shows how the existing chat loop could be modified
    # to support agent-based async operations

    # Original synchronous pattern:
    # case get_llm_response(message) do
    #   {:ok, response} -> handle_response(response)
    #   {:error, reason} -> handle_error(reason)
    # end

    # New async pattern with agents:
    # case handle_llm_with_agents(message) do
    #   {:ok, response} -> 
    #     # Response already displayed via streaming
    #     :continue
    #   {:error, reason} -> 
    #     Renderer.show_error("Failed: #{inspect(reason)}")
    #     :continue
    # end

    :ok
  end
end
