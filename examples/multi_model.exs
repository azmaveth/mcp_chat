#!/usr/bin/env elixir

# Multi-Model Chat Example
# Demonstrates switching between different LLM providers and models

# Add mcp_chat to path
Code.append_path("_build/dev/lib/mcp_chat/ebin")
Code.append_path("_build/dev/lib/ex_mcp/ebin")
Code.append_path("_build/dev/lib/ex_llm/ebin")
Code.append_path("_build/dev/lib/ex_alias/ebin")
Code.append_path("_build/dev/lib/ex_readline/ebin")

# Start the application
{:ok, _} = Application.ensure_all_started(:mcp_chat)
Process.sleep(500)

IO.puts("""
=== Multi-Model Chat Example ===

This example shows how to work with multiple LLM providers and models.
""")

defmodule MultiModelExample do
  def run() do
    # Get available models
    IO.puts("\n1. Available Models")
    IO.puts("------------------")
    
    case MCPChat.LLM.ExLLMAdapter.list_models() do
      {:ok, models} ->
        IO.puts("Found #{length(models)} models:")
        Enum.each(models, fn model ->
          IO.puts("  - #{model}")
        end)
      _ ->
        IO.puts("No models available. Please configure at least one LLM provider.")
        System.halt(1)
    end
    
    # Example prompt to test with different models
    test_prompt = "Write a haiku about Elixir programming."
    
    # Test with Anthropic if available
    test_with_provider(:anthropic, "claude-3-haiku-20240307", test_prompt)
    
    # Test with OpenAI if available  
    test_with_provider(:openai, "gpt-3.5-turbo", test_prompt)
    
    # Test with Ollama if available
    test_with_provider(:ollama, "llama2", test_prompt)
    
    # Compare costs
    compare_costs()
    
    # Test streaming
    test_streaming()
  end
  
  defp test_with_provider(provider, model, prompt) do
    IO.puts("\n2. Testing #{provider} - #{model}")
    IO.puts(String.duplicate("-", 40))
    
    # Check if provider is configured
    if MCPChat.LLM.ExLLMAdapter.configured?(provider: provider) do
      # Clear session for clean test
      MCPChat.Session.new_session()
      
      # Set the model
      MCPChat.Session.update_session(%{
        llm_config: %{
          provider: provider,
          model: model
        }
      })
      
      # Add user message
      MCPChat.Session.add_message("user", prompt)
      
      # Get response
      start_time = System.monotonic_time(:millisecond)
      
      case MCPChat.LLM.ExLLMAdapter.chat(
        MCPChat.Session.get_current_session().messages,
        provider: provider,
        model: model
      ) do
        {:ok, response} ->
          elapsed = System.monotonic_time(:millisecond) - start_time
          
          IO.puts("Response (#{elapsed}ms):")
          IO.puts(response.content)
          
          if response.usage do
            IO.puts("\nTokens: input=#{response.usage.input_tokens}, output=#{response.usage.output_tokens}")
          end
          
          # Calculate cost
          session = MCPChat.Session.get_current_session()
          cost_info = MCPChat.Cost.calculate_cost(session.messages, session.llm_config)
          IO.puts("Cost: $#{cost_info.total_cost}")
          
        {:error, reason} ->
          IO.puts("Error: #{inspect(reason)}")
      end
    else
      IO.puts("Provider #{provider} is not configured. Skipping...")
    end
  end
  
  defp compare_costs() do
    IO.puts("\n3. Cost Comparison")
    IO.puts("------------------")
    
    # Sample message for cost calculation
    messages = [
      %{role: "user", content: "Write a 500 word essay about artificial intelligence."}
    ]
    
    providers = [
      {:anthropic, "claude-3-opus-20240229", "Claude 3 Opus"},
      {:anthropic, "claude-3-sonnet-20240229", "Claude 3 Sonnet"},
      {:anthropic, "claude-3-haiku-20240307", "Claude 3 Haiku"},
      {:openai, "gpt-4", "GPT-4"},
      {:openai, "gpt-3.5-turbo", "GPT-3.5 Turbo"},
      {:ollama, "llama2", "Llama 2 (Local)"}
    ]
    
    IO.puts("Estimated costs for a 500-word response:")
    
    Enum.each(providers, fn {provider, model, name} ->
      config = %{provider: provider, model: model}
      
      # Estimate output tokens (roughly 375 tokens for 500 words)
      mock_response = %{role: "assistant", content: String.duplicate("word ", 500)}
      cost_info = MCPChat.Cost.calculate_cost(messages ++ [mock_response], config)
      
      IO.puts("  #{String.pad_trailing(name, 20)} $#{Float.round(cost_info.total_cost, 6)}")
    end)
  end
  
  defp test_streaming() do
    IO.puts("\n4. Streaming Response")
    IO.puts("--------------------")
    
    # Find a configured provider
    provider = cond do
      MCPChat.LLM.ExLLMAdapter.configured?(provider: :anthropic) -> :anthropic
      MCPChat.LLM.ExLLMAdapter.configured?(provider: :openai) -> :openai
      true -> nil
    end
    
    if provider do
      IO.puts("Testing streaming with #{provider}...")
      
      messages = [%{role: "user", content: "Count from 1 to 10 slowly."}]
      
      case MCPChat.LLM.ExLLMAdapter.stream_chat(messages, provider: provider) do
        {:ok, stream} ->
          IO.write("Response: ")
          
          Enum.each(stream, fn chunk ->
            if chunk.content do
              IO.write(chunk.content)
              # Simulate real-time display
              Process.sleep(50)
            end
          end)
          
          IO.puts("\n\nStreaming complete!")
          
        {:error, reason} ->
          IO.puts("Streaming error: #{inspect(reason)}")
      end
    else
      IO.puts("No providers configured for streaming test.")
    end
  end
end

# Run the example
MultiModelExample.run()

IO.puts("""

=== Example Complete ===

This example demonstrated:
- Listing available models
- Switching between providers and models
- Comparing response times and costs
- Streaming responses

Tips:
- Configure multiple providers in your config.toml
- Use environment variables for API keys
- Consider cost vs quality tradeoffs
- Use streaming for better UX with long responses
""")

# System.halt(0)