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
    :updated_at
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

  def get_current_session do
    GenServer.call(__MODULE__, :get_current_session)
  end

  def clear_session do
    GenServer.cast(__MODULE__, :clear_session)
  end

  def set_context(context) do
    GenServer.cast(__MODULE__, {:set_context, context})
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
    new_state = %{state | 
      current_session: new_session,
      sessions: [state.current_session | state.sessions]
    }
    {:reply, {:ok, new_session}, new_state}
  end

  @impl true
  def handle_call({:add_message, role, content}, _from, state) do
    message = %{
      role: role,
      content: content,
      timestamp: DateTime.utc_now()
    }
    
    updated_session = %{state.current_session | 
      messages: [message | state.current_session.messages],
      updated_at: DateTime.utc_now()
    }
    
    new_state = %{state | current_session: updated_session}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get_messages, limit}, _from, state) do
    messages = state.current_session.messages
    |> Enum.reverse()
    |> maybe_limit(limit)
    
    {:reply, messages, state}
  end

  @impl true
  def handle_call(:get_current_session, _from, state) do
    {:reply, state.current_session, state}
  end

  @impl true
  def handle_cast(:clear_session, state) do
    updated_session = %{state.current_session | 
      messages: [],
      context: %{},
      updated_at: DateTime.utc_now()
    }
    
    new_state = %{state | current_session: updated_session}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:set_context, context}, state) do
    updated_session = %{state.current_session | 
      context: context,
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
      updated_at: DateTime.utc_now()
    }
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  defp get_default_backend do
    MCPChat.Config.get([:llm, :default]) || "anthropic"
  end

  defp maybe_limit(messages, nil), do: messages
  defp maybe_limit(messages, limit), do: Enum.take(messages, limit)
end