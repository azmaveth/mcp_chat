defmodule MCPChat.Memory.SessionMemoryAdapter do
  @moduledoc """
  Adapter that integrates MessageStore with Session for efficient memory management.

  This module provides methods to:
  - Store messages in the paginated MessageStore
  - Retrieve messages for LLM context with configurable limits
  - Manage memory usage transparently
  """

  alias MCPChat.Memory.MessageStore

  @doc """
  Initialize a new message store for a session.
  """
  def init_session_store(session_id, opts \\ []) do
    # Start a supervised message store for this session
    case DynamicSupervisor.start_child(
           MCPChat.Memory.StoreSupervisor,
           {MessageStore, Keyword.merge([name: store_name(session_id), session_id: session_id], opts)}
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  @doc """
  Add a message to the store and return updated session.
  """
  def add_message_with_store(session, role, content) do
    store = store_name(session.id)

    # Create message structure
    message = %{
      role: role,
      content: content,
      timestamp: DateTime.utc_now()
    }

    # Store in MessageStore
    :ok = MessageStore.add_message(store, message)

    # Update session with lightweight reference
    # Keep only recent messages in session for quick access
    recent_limit = get_session_memory_limit()
    {:ok, recent_messages} = MessageStore.get_recent_messages(store, recent_limit)

    %{session | messages: recent_messages}
  end

  @doc """
  Get messages for LLM context with smart pagination.
  """
  def get_messages_for_context(session, opts \\ []) do
    store = store_name(session.id)

    case Keyword.get(opts, :mode, :recent) do
      :recent ->
        # Get recent messages up to token limit
        limit = Keyword.get(opts, :limit, 50)
        {:ok, messages} = MessageStore.get_recent_messages(store, limit)
        messages

      :page ->
        # Get specific page
        page = Keyword.get(opts, :page, 1)
        {:ok, page_data} = MessageStore.get_page(store, page)
        page_data.messages

      :all ->
        # Get all messages (use with caution)
        {:ok, messages} = MessageStore.get_all_messages(store)
        messages

      :smart ->
        # Smart retrieval based on token budget
        get_smart_context(store, opts)
    end
  end

  @doc """
  Get memory statistics for monitoring.
  """
  def get_memory_stats(session) do
    store = store_name(session.id)
    MessageStore.get_stats(store)
  end

  @doc """
  Clear session memory when done.
  """
  def clear_session_memory(session_id) do
    store = store_name(session_id)
    MessageStore.clear_session(store, session_id)
  end

  # Private functions

  defp store_name(session_id) do
    :"message_store_#{session_id}"
  end

  defp get_session_memory_limit() do
    case MCPChat.Config.get([:memory, :session_cache_size]) do
      {:ok, limit} -> limit
      # Default to keeping 20 recent messages in session
      _ -> 20
    end
  end

  defp get_smart_context(store, opts) do
    token_budget = Keyword.get(opts, :token_budget, 4_000)
    include_system = Keyword.get(opts, :include_system, true)

    # Get recent messages first
    {:ok, recent} = MessageStore.get_recent_messages(store, 10)

    # Calculate token usage
    recent_tokens = estimate_tokens(recent)

    if recent_tokens < token_budget do
      # We have room for more context
      remaining_budget = token_budget - recent_tokens

      # Get important older messages (like system prompts)
      older_messages = get_important_older_messages(store, remaining_budget, include_system)

      # Combine with proper ordering
      older_messages ++ recent
    else
      # Need to trim even recent messages
      trim_to_token_budget(recent, token_budget)
    end
  end

  defp estimate_tokens(messages) do
    # Simple estimation: ~4 characters per token
    messages
    |> Enum.map(fn msg ->
      String.length(msg.content || "") + String.length(to_string(msg.role))
    end)
    |> Enum.sum()
    |> div(4)
  end

  defp get_important_older_messages(store, token_budget, include_system) do
    # Get first page of messages (oldest)
    {:ok, page_data} = MessageStore.get_page(store, 1)

    page_data.messages
    |> Enum.filter(fn msg ->
      # Keep system messages and tool responses
      (include_system && msg.role == :system) ||
        msg.role == :tool
    end)
    |> trim_to_token_budget(token_budget)
  end

  defp trim_to_token_budget(messages, budget) do
    messages
    |> Enum.reduce_while({[], 0}, fn msg, {acc, tokens} ->
      msg_tokens = estimate_tokens([msg])

      if tokens + msg_tokens <= budget do
        {:cont, {[msg | acc], tokens + msg_tokens}}
      else
        {:halt, {acc, tokens}}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end
end
