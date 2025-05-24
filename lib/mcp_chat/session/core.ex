defmodule MCPChat.Session.Core do
  @moduledoc """
  Functional core for session operations without process state.

  This module provides pure functions for manipulating session data structures,
  making it suitable for library usage without requiring GenServer supervision.

  Example usage:

      # Create a new session
      session = MCPChat.Session.Core.new_session("anthropic")

      # Add messages
      session = MCPChat.Session.Core.add_message(session, "user", "Hello")
      session = MCPChat.Session.Core.add_message(session, "assistant", "Hi there!")

      # Get messages
      messages = MCPChat.Session.Core.get_messages(session)
  """

  alias MCPChat.Types.Session

  @doc """
  Create a new session with the specified backend.

  ## Parameters
  - `backend` - LLM backend to use (default: uses path provider to get default)
  - `opts` - Options including `:config_provider` and `:path_provider`

  ## Returns
  A new Session struct.
  """
  def new_session(backend \\ nil, opts \\ []) do
    config_provider = Keyword.get(opts, :config_provider, MCPChat.ConfigProvider.Default)
    backend = backend || get_default_backend(config_provider)

    %Session{
      id: generate_session_id(),
      llm_backend: backend,
      messages: [],
      context: %{},
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      token_usage: %{input_tokens: 0, output_tokens: 0}
    }
  end

  @doc """
  Add a message to the session.

  ## Parameters
  - `session` - Session struct
  - `role` - Message role ("user", "assistant", "system")
  - `content` - Message content

  ## Returns
  Updated session struct.
  """
  def add_message(session, role, content) do
    message = %{
      role: role,
      content: content,
      timestamp: DateTime.utc_now()
    }

    updated_messages = session.messages ++ [message]

    %{session | messages: updated_messages, updated_at: DateTime.utc_now()}
  end

  @doc """
  Get messages from the session with optional limit.

  ## Parameters
  - `session` - Session struct
  - `limit` - Optional limit on number of messages (nil for all)

  ## Returns
  List of messages.
  """
  def get_messages(session, limit \\ nil) do
    maybe_limit(session.messages, limit)
  end

  @doc """
  Set the context for the session.

  ## Parameters
  - `session` - Session struct
  - `context` - Context map

  ## Returns
  Updated session struct.
  """
  def set_context(session, context) do
    %{session | context: context, updated_at: DateTime.utc_now()}
  end

  @doc """
  Update the context for the session by merging with existing context.

  ## Parameters
  - `session` - Session struct
  - `updates` - Map of context updates

  ## Returns
  Updated session struct.
  """
  def update_context(session, updates) do
    updated_context = Map.merge(session.context, updates)
    %{session | context: updated_context, updated_at: DateTime.utc_now()}
  end

  @doc """
  Clear all messages from the session.

  ## Parameters
  - `session` - Session struct

  ## Returns
  Updated session struct with empty messages.
  """
  def clear_messages(session) do
    %{session | messages: [], updated_at: DateTime.utc_now()}
  end

  @doc """
  Track token usage for the session.

  ## Parameters
  - `session` - Session struct
  - `usage` - Token usage map with :input_tokens and :output_tokens

  ## Returns
  Updated session struct.
  """
  def track_token_usage(session, usage) do
    current_usage = session.token_usage || %{input_tokens: 0, output_tokens: 0}

    # Handle both string and atom keys for compatibility
    current_input = Map.get(current_usage, :input_tokens) || Map.get(current_usage, "input_tokens", 0)
    current_output = Map.get(current_usage, :output_tokens) || Map.get(current_usage, "output_tokens", 0)

    usage_input = Map.get(usage, :input_tokens) || Map.get(usage, "input_tokens", 0)
    usage_output = Map.get(usage, :output_tokens) || Map.get(usage, "output_tokens", 0)

    updated_usage = %{
      input_tokens: current_input + usage_input,
      output_tokens: current_output + usage_output
    }

    %{session | token_usage: updated_usage, updated_at: DateTime.utc_now()}
  end

  @doc """
  Update session fields.

  ## Parameters
  - `session` - Session struct
  - `updates` - Map of field updates

  ## Returns
  Updated session struct.
  """
  def update_session(session, updates) do
    updates_with_timestamp = Map.put(updates, :updated_at, DateTime.utc_now())
    struct(session, updates_with_timestamp)
  end

  @doc """
  Set the system prompt for the session.

  This adds a system message at the beginning of the message list,
  removing any existing system message first.

  ## Parameters
  - `session` - Session struct
  - `prompt` - System prompt string

  ## Returns
  Updated session struct.
  """
  def set_system_prompt(session, prompt) do
    # Remove existing system message if present
    filtered_messages = Enum.reject(session.messages, fn msg -> msg.role == "system" end)

    # Add new system message at the beginning
    system_message = %{
      role: "system",
      content: prompt,
      timestamp: DateTime.utc_now()
    }

    updated_messages = [system_message | filtered_messages]

    %{session | messages: updated_messages, updated_at: DateTime.utc_now()}
  end

  @doc """
  Get context statistics for the session.

  ## Parameters
  - `session` - Session struct

  ## Returns
  Map with context statistics.
  """
  def get_context_stats(session) do
    message_count = length(session.messages)
    estimated_tokens = MCPChat.Context.estimate_tokens(session.messages)
    max_tokens = Map.get(session.context, :max_tokens, 4_096)

    %{
      message_count: message_count,
      estimated_tokens: estimated_tokens,
      max_tokens: max_tokens,
      tokens_used_percentage: min(estimated_tokens / max_tokens * 100, 100),
      tokens_remaining: max(max_tokens - estimated_tokens, 0)
    }
  end

  @doc """
  Calculate session cost using the Cost module.

  ## Parameters
  - `session` - Session struct
  - `opts` - Options including `:config_provider`

  ## Returns
  Cost information map or error.
  """
  def get_session_cost(session, opts \\ []) do
    if session.token_usage do
      MCPChat.Cost.calculate_session_cost(session, session.token_usage, opts)
    else
      {:error, "No token usage data"}
    end
  end

  # Private helper functions

  defp generate_session_id() do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  defp get_default_backend(config_provider) do
    case config_provider do
      MCPChat.ConfigProvider.Default ->
        MCPChat.Config.get([:llm, :default]) || "anthropic"

      provider when is_pid(provider) ->
        # Static provider (Agent pid)
        MCPChat.ConfigProvider.Static.get(provider, [:llm, :default]) || "anthropic"

      provider ->
        # Custom provider module
        provider.get([:llm, :default]) || "anthropic"
    end
  end

  defp maybe_limit(messages, nil), do: messages
  defp maybe_limit(messages, limit), do: Enum.take(messages, limit)
end
