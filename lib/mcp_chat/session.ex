defmodule MCPChat.Session do
  @moduledoc """
  Manages chat session state including conversation history and context.

  This is a GenServer that maintains the current session state. The session
  data structure is defined in MCPChat.Types.Session.
  """
  use GenServer

  alias MCPChat.Session.Autosave
  alias MCPChat.Session.ExLLMSessionAdapter, as: SessionCore

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def new_session(backend \\ nil) do
    GenServer.call(__MODULE__, {:new_session, backend})
  end

  def add_message(role, content) do
    GenServer.call(__MODULE__, {:add_message, role, content})
  end

  def get_messages(limit \\ nil) do
    GenServer.call(__MODULE__, {:get_messages, limit})
  end

  def get_current_session do
    GenServer.call(__MODULE__, :get_current_session)
  end

  def clear_session do
    GenServer.cast(__MODULE__, :clear_session)
  end

  def set_context(context) do
    GenServer.cast(__MODULE__, {:set_context, context})
  end

  def save_session(name \\ nil) do
    GenServer.call(__MODULE__, {:save_session, name})
  end

  def load_session(identifier) do
    GenServer.call(__MODULE__, {:load_session, identifier})
  end

  def set_last_recovery_id(recovery_id) do
    GenServer.cast(__MODULE__, {:set_last_recovery_id, recovery_id})
  end

  def get_last_recovery_id do
    GenServer.call(__MODULE__, :get_last_recovery_id)
  end

  def clear_last_recovery_id do
    GenServer.cast(__MODULE__, :clear_last_recovery_id)
  end

  def list_saved_sessions do
    GenServer.call(__MODULE__, :list_saved_sessions)
  end

  @doc """
  Export the current session in the specified format.
  """
  def export_session(format \\ :json, path \\ nil) do
    GenServer.call(__MODULE__, {:export_session, format, path})
  end

  def restore_session(session) do
    GenServer.call(__MODULE__, {:restore_session, session})
  end

  @doc """
  Get messages prepared for LLM with context management.
  """
  def get_messages_for_llm(options \\ []) do
    GenServer.call(__MODULE__, {:get_messages_for_llm, options})
  end

  @doc """
  Update context configuration.
  """
  def update_context_config(config) do
    GenServer.cast(__MODULE__, {:update_context_config, config})
  end

  @doc """
  Get context statistics.
  """
  def get_context_stats do
    GenServer.call(__MODULE__, :get_context_stats)
  end

  @doc """
  Get context files from the current session.
  """
  def get_context_files(pid \\ __MODULE__) do
    session = GenServer.call(pid, :get_current_session)
    files = session.context[:files] || %{}
    {:ok, files}
  end

  @doc """
  Track token usage for a message exchange.
  """
  def track_token_usage(input_messages, response_content) do
    GenServer.cast(__MODULE__, {:track_token_usage, input_messages, response_content})
  end

  @doc """
  Track cost from ExLLM response.
  """
  def track_cost(response_or_cost) do
    GenServer.cast(__MODULE__, {:track_cost, response_or_cost})
  end

  @doc """
  Get session cost information.
  """
  def get_session_cost do
    GenServer.call(__MODULE__, :get_session_cost)
  end

  @doc """
  Set the current session to the provided session.
  """
  def set_current_session(session) do
    GenServer.call(__MODULE__, {:set_current_session, session})
  end

  @doc """
  Update specific fields of the current session.
  """
  def update_session(updates) do
    GenServer.cast(__MODULE__, {:update_session, updates})
  end

  @doc """
  Set the system prompt for the current session.
  """
  def set_system_prompt(prompt) do
    GenServer.cast(__MODULE__, {:set_system_prompt, prompt})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config_provider = Keyword.get(opts, :config_provider, MCPChat.ConfigProvider.Default)

    state = %{
      current_session: SessionCore.new_session(nil, config_provider: config_provider),
      sessions: [],
      config_provider: config_provider,
      last_recovery_id: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:new_session, backend}, _from, state) do
    new_session = SessionCore.new_session(backend, config_provider: state.config_provider)
    new_state = %{state | current_session: new_session, sessions: [state.current_session | state.sessions]}
    {:reply, {:ok, new_session}, new_state}
  end

  @impl true
  def handle_call({:add_message, role, content}, _from, state) do
    updated_session = SessionCore.add_message(state.current_session, role, content)
    new_state = %{state | current_session: updated_session}

    # Trigger autosave on message addition
    if Process.whereis(Autosave) do
      Autosave.trigger_save()
    end

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get_messages, limit}, _from, state) do
    messages = SessionCore.get_messages(state.current_session, limit)
    {:reply, messages, state}
  end

  def handle_call(:get_current_session, _from, state) do
    {:reply, state.current_session, state}
  end

  def handle_call({:save_session, name}, _from, state) do
    result = MCPChat.Persistence.save_session(state.current_session, name)
    {:reply, result, state}
  end

  def handle_call({:load_session, identifier}, _from, state) do
    case MCPChat.Persistence.load_session(identifier) do
      {:ok, session} ->
        # Save current session to history
        new_state = %{state | current_session: session, sessions: [state.current_session | state.sessions]}
        {:reply, {:ok, session}, new_state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call(:list_saved_sessions, _from, state) do
    result = MCPChat.Persistence.list_sessions()
    {:reply, result, state}
  end

  def handle_call({:restore_session, session}, _from, state) do
    # Save current session to history
    new_state = %{state | current_session: session, sessions: [state.current_session | state.sessions]}
    {:reply, :ok, new_state}
  end

  def handle_call({:export_session, format, path}, _from, state) do
    result =
      if path do
        MCPChat.Persistence.export_session(state.current_session, format, path)
      else
        # Generate a default path
        timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)
        ext = if format == :json, do: "json", else: "md"
        default_path = "chat_export_#{timestamp}.#{ext}"
        MCPChat.Persistence.export_session(state.current_session, format, default_path)
      end

    {:reply, result, state}
  end

  def handle_call({:get_messages_for_llm, options}, _from, state) do
    messages = state.current_session.messages |> Enum.reverse()

    # Merge context config with options
    context_config =
      Map.merge(
        state.current_session.context,
        Enum.into(options, %{})
      )

    # Prepare messages with context management
    prepared_messages =
      MCPChat.Context.prepare_messages(
        messages,
        Map.to_list(context_config)
      )

    {:reply, prepared_messages, state}
  end

  def handle_call(:get_context_stats, _from, state) do
    stats = SessionCore.get_context_stats(state.current_session)
    {:reply, stats, state}
  end

  def handle_call(:get_session_cost, _from, state) do
    cost_info = SessionCore.get_session_cost(state.current_session, config_provider: state.config_provider)
    {:reply, cost_info, state}
  end

  def handle_call({:set_current_session, session}, _from, state) do
    # Save current session to history
    new_state = %{state | current_session: session, sessions: [state.current_session | state.sessions]}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_last_recovery_id, _from, state) do
    {:reply, state.last_recovery_id, state}
  end

  @impl true
  def handle_cast(:clear_session, state) do
    updated_session = SessionCore.clear_messages(state.current_session)
    updated_session = SessionCore.set_context(updated_session, %{})

    # Reset cost tracking when clearing session
    updated_session = %{updated_session | accumulated_cost: nil, cost_session: nil}

    new_state = %{state | current_session: updated_session}
    {:noreply, new_state}
  end

  def handle_cast({:set_context, context}, state) do
    updated_session = SessionCore.set_context(state.current_session, context)
    new_state = %{state | current_session: updated_session}
    {:noreply, new_state}
  end

  def handle_cast({:update_context_config, config}, state) do
    updated_session = SessionCore.update_context(state.current_session, config)
    new_state = %{state | current_session: updated_session}
    {:noreply, new_state}
  end

  def handle_cast({:track_token_usage, input_messages, response_content}, state) do
    usage = MCPChat.Cost.track_token_usage(input_messages, response_content)
    updated_session = SessionCore.track_token_usage(state.current_session, usage)
    new_state = %{state | current_session: updated_session}
    {:noreply, new_state}
  end

  def handle_cast({:track_cost, response_or_cost}, state) do
    updated_session = SessionCore.track_cost(state.current_session, response_or_cost)
    new_state = %{state | current_session: updated_session}
    {:noreply, new_state}
  end

  def handle_cast({:update_session, updates}, state) do
    updated_session = SessionCore.update_session(state.current_session, updates)
    new_state = %{state | current_session: updated_session}
    {:noreply, new_state}
  end

  def handle_cast({:set_system_prompt, prompt}, state) do
    updated_session = SessionCore.set_system_prompt(state.current_session, prompt)
    new_state = %{state | current_session: updated_session}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:set_last_recovery_id, recovery_id}, state) do
    {:noreply, %{state | last_recovery_id: recovery_id}}
  end

  @impl true
  def handle_cast(:clear_last_recovery_id, state) do
    {:noreply, %{state | last_recovery_id: nil}}
  end

  # Private Functions - only those specific to GenServer behavior

  # Note: Session operations are handled by ExLLMSessionAdapter which wraps ExLLM.Session
end
