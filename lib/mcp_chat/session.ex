defmodule MCPChat.Session do
  @moduledoc """
  Session agent that manages chat state for a single session.
  This is the main agent that coordinates with LLM, MCP, and other subagents.
  """

  use GenServer
  require Logger

  defstruct [
    :session_id,
    :user_id,
    :llm_backend,
    :context,
    :messages,
    :recovery_id,
    :created_at,
    :updated_at,
    metadata: %{}
  ]

  # Client API

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(session_id))
  end

  defp via_tuple(session_id) do
    MCPChat.Agents.SessionManager.via_tuple(session_id)
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    user_id = Keyword.get(opts, :user_id, "anonymous")
    backend = Keyword.get(opts, :backend, "anthropic")
    source = Keyword.get(opts, :source, :unknown)

    state = %__MODULE__{
      session_id: session_id,
      user_id: user_id,
      llm_backend: backend,
      context: %{
        model: nil,
        system_prompt: nil,
        source: source
      },
      messages: [],
      recovery_id: nil,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    Logger.info("Session agent started", session_id: session_id, user_id: user_id)

    {:ok, state}
  end

  @impl true
  def handle_cast({:send_message, content}, state) do
    # Add user message
    user_message = %{
      role: "user",
      content: content,
      timestamp: DateTime.utc_now()
    }

    new_messages = state.messages ++ [user_message]
    new_state = %{state | messages: new_messages, updated_at: DateTime.utc_now()}

    # TODO: Send to LLM agent and get response
    # For now, just acknowledge
    Logger.debug("User message added to session", session_id: state.session_id)

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_full_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call({:get_messages, opts}, _from, state) do
    limit = Keyword.get(opts, :limit)
    messages = if limit, do: Enum.take(state.messages, -limit), else: state.messages
    {:reply, {:ok, messages}, state}
  end

  def handle_call({:execute_command, command_string}, _from, state) do
    result = execute_session_command(command_string, state)

    case result do
      {:ok, new_state} ->
        {:reply, {:ok, :command_executed}, new_state}

      {:error, _} = error ->
        {:reply, error, state}

      value ->
        # Return value without state change
        {:reply, {:ok, value}, state}
    end
  end

  def handle_call({:execute_tool, tool_name, _args}, _from, state) do
    # TODO: Implement tool execution through MCP
    Logger.info("Tool execution requested",
      session_id: state.session_id,
      tool: tool_name
    )

    {:reply, {:ok, %{result: "Tool execution placeholder"}}, state}
  end

  def handle_call({:connect_mcp_server, server_config}, _from, state) do
    # TODO: Implement MCP server connection
    Logger.info("MCP server connection requested",
      session_id: state.session_id,
      server: server_config
    )

    {:reply, {:ok, :connected}, state}
  end

  def handle_call({:list_mcp_tools, server_name}, _from, state) do
    # TODO: Implement MCP tool listing
    Logger.info("MCP tool listing requested",
      session_id: state.session_id,
      server: server_name
    )

    {:reply, {:ok, []}, state}
  end

  # Private helpers

  defp execute_session_command("set_recovery_id " <> recovery_id, state) do
    {:ok, %{state | recovery_id: recovery_id}}
  end

  defp execute_session_command("clear_recovery_id", state) do
    {:ok, %{state | recovery_id: nil}}
  end

  defp execute_session_command("get_recovery_id", state) do
    state.recovery_id
  end

  defp execute_session_command(command, _state) do
    {:error, {:unknown_command, command}}
  end
end
