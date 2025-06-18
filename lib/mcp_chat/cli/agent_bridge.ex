defmodule MCPChat.CLI.AgentBridge do
  @moduledoc """
  Bridge module that allows the existing CLI to gradually migrate to the agent architecture.
  This provides compatibility layers and helper functions for the transition.
  """

  require Logger

  alias MCPChat.Gateway
  alias MCPChat.CLI.EventSubscriber

  # Session mapping to track CLI sessions with agent sessions
  @session_registry :cli_agent_session_registry

  @doc "Initialize the agent bridge"
  def init do
    # Create ETS table for session mapping if it doesn't exist
    if :ets.info(@session_registry) == :undefined do
      :ets.new(@session_registry, [:set, :public, :named_table])
    end

    :ok
  end

  @doc "Get or create an agent session for the current CLI session"
  def ensure_agent_session(opts \\ []) do
    cli_session_id = get_cli_session_id()

    case lookup_agent_session(cli_session_id) do
      {:ok, agent_session_id} ->
        # Verify the session is still active
        if session_active?(agent_session_id) do
          {:ok, agent_session_id}
        else
          # Session expired, create a new one
          create_agent_session(cli_session_id, opts)
        end

      :error ->
        # No mapping exists, create new session
        create_agent_session(cli_session_id, opts)
    end
  end

  @doc "Execute a tool through the agent architecture"
  def execute_tool_async(tool_name, args, opts \\ []) do
    with {:ok, session_id} <- ensure_agent_session(),
         _result <- maybe_subscribe_to_events(session_id) do
      # Determine server from tool name or options
      server = Keyword.get(opts, :server) || determine_server_for_tool(tool_name)

      # Add server to options
      full_opts = Keyword.put(opts, :server, server)

      # Execute through Gateway
      case Gateway.execute_tool(session_id, tool_name, args, full_opts) do
        {:ok, :async, result} ->
          {:ok, :async, Map.put(result, :session_id, session_id)}

        other ->
          other
      end
    end
  end

  @doc "Send a message through the agent architecture"
  def send_message_async(content, opts \\ []) do
    with {:ok, session_id} <- ensure_agent_session(opts),
         _result <- maybe_subscribe_to_events(session_id) do
      Gateway.send_message(session_id, content)
    end
  end

  @doc "Get the execution status of a tool"
  def get_tool_status(execution_id) do
    with {:ok, session_id} <- get_session_for_execution(execution_id) do
      Gateway.get_tool_execution_status(session_id, execution_id)
    end
  end

  @doc "Cancel a tool execution"
  def cancel_tool_execution(execution_id) do
    with {:ok, session_id} <- get_session_for_execution(execution_id) do
      Gateway.cancel_tool_execution(session_id, execution_id)
    end
  end

  @doc "Export session data through agents"
  def export_session_async(format, options \\ %{}) do
    with {:ok, session_id} <- ensure_agent_session() do
      Gateway.request_export(session_id, format, options)
    end
  end

  @doc "Get system health through the agent architecture"
  def get_system_health do
    Gateway.get_system_health()
  end

  @doc "List active operations for the current session"
  def list_active_operations do
    with {:ok, session_id} <- ensure_agent_session() do
      Gateway.list_session_subagents(session_id)
    else
      _ -> []
    end
  end

  @doc "Clean up agent session when CLI session ends"
  def cleanup_session do
    cli_session_id = get_cli_session_id()

    case lookup_agent_session(cli_session_id) do
      {:ok, agent_session_id} ->
        # Unsubscribe from events
        EventSubscriber.unsubscribe_from_session(agent_session_id)

        # Destroy the agent session
        Gateway.destroy_session(agent_session_id)

        # Remove mapping
        :ets.delete(@session_registry, cli_session_id)

        :ok

      :error ->
        :ok
    end
  end

  # Private functions

  defp get_cli_session_id do
    # Get a unique identifier for the current CLI session
    # This could be based on the process PID or a generated ID
    case Process.get(:cli_session_id) do
      nil ->
        # Generate and store a session ID
        session_id = generate_cli_session_id()
        Process.put(:cli_session_id, session_id)
        session_id

      session_id ->
        session_id
    end
  end

  defp generate_cli_session_id do
    timestamp = System.system_time(:millisecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "cli_#{timestamp}_#{random}"
  end

  defp lookup_agent_session(cli_session_id) do
    case :ets.lookup(@session_registry, cli_session_id) do
      [{^cli_session_id, agent_session_id}] -> {:ok, agent_session_id}
      [] -> :error
    end
  end

  defp create_agent_session(cli_session_id, opts) do
    # Get user ID from current session or use default
    user_id = get_user_id_from_session()

    case Gateway.create_session(user_id, opts) do
      {:ok, agent_session_id} ->
        # Store mapping
        :ets.insert(@session_registry, {cli_session_id, agent_session_id})

        # Subscribe to events
        {:ok, _} = EventSubscriber.subscribe_to_session(agent_session_id)

        {:ok, agent_session_id}

      error ->
        error
    end
  end

  defp session_active?(session_id) do
    case Gateway.get_session_state(session_id) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp maybe_subscribe_to_events(session_id) do
    # Check if already subscribed
    case Registry.lookup(MCPChat.CLI.EventRegistry, {EventSubscriber, session_id}) do
      [] ->
        # Not subscribed, subscribe now
        EventSubscriber.subscribe_to_session(session_id)

      _ ->
        # Already subscribed
        :ok
    end
  end

  defp get_session_for_execution(_execution_id) do
    # Try to find which session owns this execution
    # In a real implementation, this would query the agent architecture

    # For now, just return the current session
    ensure_agent_session()
  end

  defp determine_server_for_tool(_tool_name) do
    # Logic to determine which server provides a tool
    # This could query the MCP server manager or use a registry

    # For now, return a default
    # Any server
    "*"
  end

  defp get_user_id_from_session do
    # TODO: Implement user ID retrieval with Gateway API
    "default_user"
  end

  @doc "Get available commands for a session (stub for web UI)"
  def get_available_commands(session_id) do
    # Return default commands for now
    commands = [
      %{command: "/help", description: "Show available commands"},
      %{command: "/model list", description: "List available models"},
      %{command: "/mcp servers", description: "List MCP servers"},
      %{command: "/cost", description: "Show cost information"},
      %{command: "/context list", description: "Show context files"}
    ]

    {:ok, commands}
  end
end
