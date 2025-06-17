defmodule MCPChat.Session.ExLLMSessionAdapter do
  @moduledoc """
  Adapter that wraps ExLLM.Session to maintain backward compatibility
  while adding MCPChat-specific functionality.
  """

  alias ExLLM.Session, as: ExLLMSession
  alias ExLLM.Session.Types.Session, as: ExLLMSessionType
  alias MCPChat.{Config, ConfigProvider, Context, Cost}
  alias MCPChat.Types.Session, as: MCPChatSessionType

  @doc """
  Create a new session with the specified backend.

  Maintains backward compatibility with MCPChat's config provider system.
  """
  def new_session(backend \\ nil, opts \\ []) do
    config_provider = Keyword.get(opts, :config_provider, ConfigProvider.Default)
    backend = backend || get_default_backend(config_provider)

    # Create ExLLM session
    ex_llm_session = ExLLMSession.new(backend, opts)

    # Convert to MCPChat session type and initialize cost session
    mcp_session = to_mcp_chat_session(ex_llm_session)

    # Initialize ExLLM cost session for comprehensive tracking
    cost_session = ExLLM.Cost.Session.new(mcp_session.id)

    %{mcp_session | cost_session: cost_session}
  end

  @doc """
  Add a message to the session.
  """
  def add_message(session, role, content) do
    # Preserve MCPChat-specific fields
    original_accumulated_cost = session.accumulated_cost
    original_cost_session = session.cost_session
    original_metadata = session.metadata

    updated_session =
      session
      |> to_ex_llm_session()
      |> ExLLMSession.add_message(role, content)
      |> to_mcp_chat_session()

    # Restore MCPChat-specific fields
    %{
      updated_session
      | accumulated_cost: original_accumulated_cost,
        cost_session: original_cost_session,
        metadata: original_metadata
    }
  end

  @doc """
  Get messages from the session with optional limit.

  Note: MCPChat takes first N messages, ExLLM takes last N.
  We maintain MCPChat behavior here.
  """
  def get_messages(session, limit \\ nil) do
    ex_llm_session = to_ex_llm_session(session)

    case limit do
      nil ->
        ex_llm_session.messages

      n when is_integer(n) and n > 0 ->
        Enum.take(ex_llm_session.messages, n)

      _ ->
        ex_llm_session.messages
    end
  end

  @doc """
  Set the context for the session.
  """
  def set_context(session, context) do
    # Preserve MCPChat-specific fields
    original_accumulated_cost = session.accumulated_cost
    original_cost_session = session.cost_session
    original_metadata = session.metadata

    updated_session =
      session
      |> to_ex_llm_session()
      |> ExLLMSession.set_context(context)
      |> to_mcp_chat_session()

    # Restore MCPChat-specific fields
    %{
      updated_session
      | accumulated_cost: original_accumulated_cost,
        cost_session: original_cost_session,
        metadata: original_metadata
    }
  end

  @doc """
  Update the context for the session by merging with existing context.

  MCPChat-specific functionality not in ExLLM.
  """
  def update_context(session, updates) do
    # Preserve MCPChat-specific fields
    original_accumulated_cost = session.accumulated_cost
    original_cost_session = session.cost_session
    original_metadata = session.metadata

    ex_llm_session = to_ex_llm_session(session)
    updated_context = Map.merge(ex_llm_session.context, updates)

    updated_session =
      ex_llm_session
      |> ExLLMSession.set_context(updated_context)
      |> to_mcp_chat_session()

    # Restore MCPChat-specific fields
    %{
      updated_session
      | accumulated_cost: original_accumulated_cost,
        cost_session: original_cost_session,
        metadata: original_metadata
    }
  end

  @doc """
  Clear all messages from the session.
  """
  def clear_messages(session) do
    # Preserve MCPChat-specific fields
    original_accumulated_cost = session.accumulated_cost
    original_cost_session = session.cost_session
    original_metadata = session.metadata

    updated_session =
      session
      |> to_ex_llm_session()
      |> ExLLMSession.clear_messages()
      |> to_mcp_chat_session()

    # Restore MCPChat-specific fields
    %{
      updated_session
      | accumulated_cost: original_accumulated_cost,
        cost_session: original_cost_session,
        metadata: original_metadata
    }
  end

  @doc """
  Track token usage for the session.

  Handles both string and atom keys for backward compatibility.
  """
  def track_token_usage(session, usage) do
    # Preserve MCPChat-specific fields
    original_accumulated_cost = session.accumulated_cost
    original_cost_session = session.cost_session
    original_metadata = session.metadata

    # Normalize usage to atom keys
    normalized_usage = %{
      input_tokens: Map.get(usage, :input_tokens) || Map.get(usage, "input_tokens", 0),
      output_tokens: Map.get(usage, :output_tokens) || Map.get(usage, "output_tokens", 0)
    }

    updated_session =
      session
      |> to_ex_llm_session()
      |> ExLLMSession.update_token_usage(normalized_usage)
      |> to_mcp_chat_session()

    # Restore MCPChat-specific fields
    %{
      updated_session
      | accumulated_cost: original_accumulated_cost,
        cost_session: original_cost_session,
        metadata: original_metadata
    }
  end

  @doc """
  Track cost for the session from ExLLM response.
  Uses both simple accumulated cost and ExLLM's comprehensive cost session.
  """
  def track_cost(session, response) when is_map(response) do
    # Update simple accumulated cost for backward compatibility
    current_cost = session.accumulated_cost || 0.0
    response_cost = get_response_total_cost(response)
    updated_cost = current_cost + response_cost

    # Update ExLLM cost session for comprehensive tracking
    updated_cost_session =
      if session.cost_session do
        ExLLM.Cost.Session.add_response(session.cost_session, response)
      else
        # Initialize cost session if not present (for backward compatibility)
        ExLLM.Cost.Session.new(session.id)
        |> ExLLM.Cost.Session.add_response(response)
      end

    %{session | accumulated_cost: updated_cost, cost_session: updated_cost_session, updated_at: DateTime.utc_now()}
  end

  def track_cost(session, cost) when is_number(cost) do
    # Legacy support for raw cost numbers
    current_cost = session.accumulated_cost || 0.0
    updated_cost = current_cost + cost

    # Preserve cost_session and ensure it's initialized
    updated_cost_session =
      if session.cost_session do
        session.cost_session
      else
        # Initialize cost session if not present (for backward compatibility)
        ExLLM.Cost.Session.new(session.id)
      end

    %{session | accumulated_cost: updated_cost, cost_session: updated_cost_session, updated_at: DateTime.utc_now()}
  end

  def track_cost(session, _cost), do: session

  # Helper to extract total cost from response
  defp get_response_total_cost(response) do
    cond do
      Map.has_key?(response, :cost) && is_map(response.cost) && Map.has_key?(response.cost, :total_cost) ->
        response.cost.total_cost

      Map.has_key?(response, :cost) && is_number(response.cost) ->
        response.cost

      true ->
        0.0
    end
  end

  @doc """
  Update session fields.
  """
  def update_session(session, updates) do
    ex_llm_session = to_ex_llm_session(session)

    # Handle field updates manually since ExLLM doesn't have generic update
    updated =
      Enum.reduce(updates, ex_llm_session, fn
        {:name, value}, acc ->
          %{acc | name: value}

        {:context, value}, acc ->
          %{acc | context: value}

        {:llm_backend, value}, acc ->
          %{acc | llm_backend: value}

        {:metadata, _value}, acc ->
          # ExLLM doesn't have metadata, so we'll handle it in conversion
          acc

        # Ignore unknown fields
        {_key, _value}, acc ->
          acc
      end)

    result =
      %{updated | updated_at: DateTime.utc_now()}
      |> to_mcp_chat_session()

    # Apply metadata updates after conversion
    if updates[:metadata] do
      %{result | metadata: updates[:metadata]}
    else
      result
    end
  end

  @doc """
  Set the system prompt for the session.

  MCPChat-specific functionality that manages system messages specially.
  """
  def set_system_prompt(session, prompt) do
    ex_llm_session = to_ex_llm_session(session)

    # Remove existing system message if present
    filtered_messages = Enum.reject(ex_llm_session.messages, fn msg -> msg.role == "system" end)

    # Add new system message at the beginning
    system_message = %{
      role: "system",
      content: prompt,
      timestamp: DateTime.utc_now()
    }

    updated_messages = [system_message | filtered_messages]

    %{ex_llm_session | messages: updated_messages, updated_at: DateTime.utc_now()}
    |> to_mcp_chat_session()
  end

  @doc """
  Get context statistics for the session.

  MCPChat-specific functionality.
  """
  def get_context_stats(session) do
    ex_llm_session = to_ex_llm_session(session)
    message_count = length(ex_llm_session.messages)
    estimated_tokens = Context.estimate_tokens(ex_llm_session.messages)
    max_tokens = Map.get(ex_llm_session.context, :max_tokens, 4_096)

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

  MCPChat-specific functionality.
  """
  def get_session_cost(session, opts \\ []) do
    ex_llm_session = to_ex_llm_session(session)

    if ex_llm_session.token_usage do
      # Convert to MCPChat session for cost calculation
      mcp_chat_session = to_mcp_chat_session(ex_llm_session)
      Cost.calculate_session_cost(mcp_chat_session, ex_llm_session.token_usage, opts)
    else
      {:error, :no_token_usage}
    end
  end

  # Conversion helpers

  defp to_ex_llm_session(%MCPChatSessionType{} = session) do
    # Normalize token_usage to ensure atom keys for ExLLM compatibility
    normalized_token_usage =
      case session.token_usage do
        %{"input_tokens" => input, "output_tokens" => output} ->
          %{input_tokens: input, output_tokens: output}

        %{input_tokens: _, output_tokens: _} = usage ->
          usage

        _ ->
          %{input_tokens: 0, output_tokens: 0}
      end

    %ExLLMSessionType{
      id: session.id,
      llm_backend: session.llm_backend,
      messages: session.messages,
      context: session.context || %{},
      created_at: session.created_at,
      updated_at: session.updated_at,
      token_usage: normalized_token_usage,
      # MCPChat sessions don't have names
      name: nil
    }
  end

  defp to_ex_llm_session(%ExLLMSessionType{} = session), do: session

  defp to_mcp_chat_session(%ExLLMSessionType{} = session) do
    %MCPChatSessionType{
      id: session.id,
      llm_backend: session.llm_backend,
      messages: session.messages,
      context: session.context,
      created_at: session.created_at,
      updated_at: session.updated_at,
      token_usage: session.token_usage,
      # ExLLM doesn't track accumulated cost yet
      accumulated_cost: nil,
      # Will be initialized separately
      cost_session: nil,
      # ExLLM doesn't have metadata
      metadata: nil
    }
  end

  defp to_mcp_chat_session(%MCPChatSessionType{} = session), do: session

  # Serialization support

  @doc """
  Serialize session to JSON.

  Converts MCPChat session to ExLLM session for serialization.
  """
  def to_json(session) do
    session
    |> to_ex_llm_session()
    |> ExLLMSession.to_json()
  end

  @doc """
  Deserialize session from JSON.

  Returns MCPChat session type.
  """
  def from_json(json_string) do
    case ExLLMSession.from_json(json_string) do
      {:ok, ex_llm_session} ->
        {:ok, to_mcp_chat_session(ex_llm_session)}

      error ->
        error
    end
  end

  # Helper to get default backend
  defp get_default_backend(config_provider) do
    case config_provider do
      ConfigProvider.Default ->
        Config.get([:llm, :default]) || "anthropic"

      provider when is_pid(provider) ->
        # Static provider (Agent pid)
        ConfigProvider.Static.get(provider, [:llm, :default]) || "anthropic"

      provider ->
        # Custom provider module
        provider.get([:llm, :default]) || "anthropic"
    end
  end
end
