defmodule MCPChat.Session do
  @moduledoc """
  Manages chat session state including conversation history and context.
  """
  use GenServer

  defstruct [
    :id,
    :llm_backend,
    :messages,
    :context,
    :created_at,
    :updated_at,
    :token_usage
  ]

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

  def get_current_session() do
    GenServer.call(__MODULE__, :get_current_session)
  end

  def clear_session() do
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

  def list_saved_sessions() do
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
  def get_context_stats() do
    GenServer.call(__MODULE__, :get_context_stats)
  end

  @doc """
  Track token usage for a message exchange.
  """
  def track_token_usage(input_messages, response_content) do
    GenServer.cast(__MODULE__, {:track_token_usage, input_messages, response_content})
  end

  @doc """
  Get session cost information.
  """
  def get_session_cost() do
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
  def init(_opts) do
    state = %{
      current_session: create_new_session(),
      sessions: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:new_session, backend}, _from, state) do
    new_session = create_new_session(backend)
    new_state = %{state | current_session: new_session, sessions: [state.current_session | state.sessions]}
    {:reply, {:ok, new_session}, new_state}
  end

  @impl true
  def handle_call({:add_message, role, content}, _from, state) do
    message = %{
      role: role,
      content: content,
      timestamp: DateTime.utc_now()
    }

    updated_session = %{
      state.current_session
      | messages: [message | state.current_session.messages],
        updated_at: DateTime.utc_now()
    }

    new_state = %{state | current_session: updated_session}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get_messages, limit}, _from, state) do
    messages =
      state.current_session.messages
      |> Enum.reverse()
      |> maybe_limit(limit)

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
    messages = state.current_session.messages |> Enum.reverse()
    max_tokens = get_in(state.current_session.context, [:max_tokens]) || 4_096

    stats = MCPChat.Context.get_context_stats(messages, max_tokens)
    {:reply, stats, state}
  end

  def handle_call(:get_session_cost, _from, state) do
    token_usage = state.current_session.token_usage || %{input_tokens: 0, output_tokens: 0}
    cost_info = MCPChat.Cost.calculate_session_cost(state.current_session, token_usage)
    {:reply, cost_info, state}
  end

  def handle_call({:set_current_session, session}, _from, state) do
    # Save current session to history
    new_state = %{state | current_session: session, sessions: [state.current_session | state.sessions]}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast(:clear_session, state) do
    updated_session = %{state.current_session | messages: [], context: %{}, updated_at: DateTime.utc_now()}

    new_state = %{state | current_session: updated_session}
    {:noreply, new_state}
  end

  def handle_cast({:set_context, context}, state) do
    updated_session = %{state.current_session | context: context, updated_at: DateTime.utc_now()}

    new_state = %{state | current_session: updated_session}
    {:noreply, new_state}
  end

  def handle_cast({:update_context_config, config}, state) do
    updated_context = Map.merge(state.current_session.context, config)
    updated_session = %{state.current_session | context: updated_context, updated_at: DateTime.utc_now()}

    new_state = %{state | current_session: updated_session}
    {:noreply, new_state}
  end

  def handle_cast({:track_token_usage, input_messages, response_content}, state) do
    usage = MCPChat.Cost.track_token_usage(input_messages, response_content)

    # Update or initialize token usage
    current_usage = state.current_session.token_usage || %{input_tokens: 0, output_tokens: 0}

    updated_usage = %{
      input_tokens: current_usage.input_tokens + usage.input_tokens,
      output_tokens: current_usage.output_tokens + usage.output_tokens
    }

    updated_session = %{state.current_session | token_usage: updated_usage, updated_at: DateTime.utc_now()}

    new_state = %{state | current_session: updated_session}
    {:noreply, new_state}
  end

  def handle_cast({:update_session, updates}, state) do
    updated_session = struct(state.current_session, Map.put(updates, :updated_at, DateTime.utc_now()))
    new_state = %{state | current_session: updated_session}
    {:noreply, new_state}
  end

  def handle_cast({:set_system_prompt, prompt}, state) do
    # Add or update system message at the beginning of messages
    messages = state.current_session.messages

    # Remove existing system message if present
    filtered_messages = Enum.reject(messages, fn msg -> msg.role == "system" end)

    # Add new system message
    system_message = %{
      role: "system",
      content: prompt,
      timestamp: DateTime.utc_now()
    }

    updated_messages = [system_message | filtered_messages]

    updated_session = %{
      state.current_session
      | messages: updated_messages,
        updated_at: DateTime.utc_now()
    }

    new_state = %{state | current_session: updated_session}
    {:noreply, new_state}
  end

  # Private Functions

  defp create_new_session(backend \\ nil) do
    backend = backend || get_default_backend()

    %__MODULE__{
      id: generate_session_id(),
      llm_backend: backend,
      messages: [],
      context: %{},
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      token_usage: %{input_tokens: 0, output_tokens: 0}
    }
  end

  defp generate_session_id() do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  defp get_default_backend() do
    MCPChat.Config.get([:llm, :default]) || "anthropic"
  end

  defp maybe_limit(messages, nil), do: messages
  defp maybe_limit(messages, limit), do: Enum.take(messages, limit)
end
