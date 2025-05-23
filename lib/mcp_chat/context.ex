defmodule MCPChat.Context do
  @moduledoc """
  Context management for multi-turn conversations.
  
  Handles:
  - Token counting and context window management
  - Message truncation strategies
  - System prompt persistence
  - Context compression
  """
  
  @default_max_tokens 4096
  @reserve_tokens 500  # Reserve for response
  
  @doc """
  Prepare messages for sending to LLM, managing context window.
  
  Options:
  - :max_tokens - Maximum context window size
  - :system_prompt - System prompt to prepend
  - :strategy - Truncation strategy (:sliding_window, :summarize, :smart)
  """
  def prepare_messages(messages, options \\ []) do
    max_tokens = Keyword.get(options, :max_tokens, @default_max_tokens)
    system_prompt = Keyword.get(options, :system_prompt)
    strategy = Keyword.get(options, :strategy, :sliding_window)
    
    # Calculate available tokens for messages
    available_tokens = max_tokens - @reserve_tokens
    
    # Add system prompt if provided
    messages_with_system = if system_prompt do
      system_message = %{role: "system", content: system_prompt}
      [system_message | messages]
    else
      messages
    end
    
    # Apply truncation strategy
    case strategy do
      :sliding_window ->
        sliding_window_truncate(messages_with_system, available_tokens)
      
      :smart ->
        smart_truncate(messages_with_system, available_tokens, system_prompt)
      
      _ ->
        messages_with_system
    end
  end
  
  @doc """
  Estimate token count for a message or text.
  
  Uses a simple heuristic: ~1 token per 4 characters.
  This is a rough estimate that works reasonably well for English text.
  """
  def estimate_tokens(text) when is_binary(text) do
    # Handle empty string
    if text == "" do
      0
    else
      # More accurate estimation based on common patterns
      words = String.split(text, ~r/\s+/)
      word_tokens = length(words) * 1.3  # Average 1.3 tokens per word
      
      # Add extra for punctuation and special characters
      special_chars = String.replace(text, ~r/[a-zA-Z0-9\s]/, "") |> String.length()
      special_tokens = special_chars * 0.5
      
      round(word_tokens + special_tokens)
    end
  end
  
  def estimate_tokens(%{content: content}) do
    estimate_tokens(content)
  end
  
  def estimate_tokens(messages) when is_list(messages) do
    Enum.reduce(messages, 0, fn msg, acc ->
      acc + estimate_tokens(msg) + 3  # Add tokens for role markers
    end)
  end
  
  @doc """
  Get context statistics for current session.
  """
  def get_context_stats(messages, max_tokens \\ @default_max_tokens) do
    total_tokens = estimate_tokens(messages)
    
    %{
      message_count: length(messages),
      estimated_tokens: total_tokens,
      max_tokens: max_tokens,
      tokens_used_percentage: Float.round(total_tokens / max_tokens * 100, 1),
      tokens_remaining: max(0, max_tokens - total_tokens - @reserve_tokens)
    }
  end
  
  @doc """
  Build a context configuration from options.
  """
  def build_context_config(options \\ []) do
    %{
      max_tokens: Keyword.get(options, :max_tokens, @default_max_tokens),
      system_prompt: Keyword.get(options, :system_prompt),
      strategy: Keyword.get(options, :strategy, :sliding_window),
      temperature: Keyword.get(options, :temperature, 0.7),
      summary_prompt: Keyword.get(options, :summary_prompt, default_summary_prompt())
    }
  end
  
  # Private Functions
  
  defp sliding_window_truncate(messages, available_tokens) do
    # Keep messages from the end until we hit token limit
    {kept_messages, _tokens} = 
      messages
      |> Enum.reverse()
      |> Enum.reduce({[], 0}, fn msg, {kept, tokens} ->
        msg_tokens = estimate_tokens(msg)
        
        if tokens + msg_tokens <= available_tokens do
          {[msg | kept], tokens + msg_tokens}
        else
          {kept, tokens}
        end
      end)
    
    kept_messages
  end
  
  defp smart_truncate(messages, available_tokens, _system_prompt) do
    # Smart truncation: keep system prompt, first few messages, and recent messages
    system_messages = Enum.filter(messages, &(&1.role == "system"))
    non_system = Enum.reject(messages, &(&1.role == "system"))
    
    if length(non_system) <= 6 do
      # If few messages, just use sliding window
      sliding_window_truncate(messages, available_tokens)
    else
      # Keep first 2 exchanges and recent messages
      {first_messages, rest} = Enum.split(non_system, 4)
      recent_messages = Enum.take(rest, -10)
      
      # Add a context summary message if we're dropping messages
      dropped_count = length(rest) - length(recent_messages)
      
      summary_message = if dropped_count > 0 do
        %{
          role: "system",
          content: "[Previous #{dropped_count} messages omitted for context management]"
        }
      end
      
      combined = 
        system_messages ++ 
        first_messages ++ 
        (if summary_message, do: [summary_message], else: []) ++
        recent_messages
      
      # Ensure we're within token limits
      sliding_window_truncate(combined, available_tokens)
    end
  end
  
  defp default_summary_prompt do
    """
    The conversation history is being truncated. 
    Previous context has been omitted to stay within token limits.
    Continue the conversation naturally.
    """
  end
end