#!/usr/bin/env elixir

# Test script for OpenAI adapter
Mix.install([
  {:mcp_chat, path: "."}
])

defmodule TestOpenAI do
  def run do
    IO.puts("Testing OpenAI adapter...")
    
    # Start the application
    {:ok, _} = Application.ensure_all_started(:mcp_chat)
    
    # Check if configured
    if MCPChat.LLM.OpenAI.configured?() do
      IO.puts("✓ OpenAI is configured")
      
      # Test list models
      case MCPChat.LLM.OpenAI.list_models() do
        {:ok, models} ->
          IO.puts("✓ Available models: #{Enum.join(models, ", ")}")
        _ ->
          IO.puts("✗ Failed to list models")
      end
      
      # Test chat
      messages = [
        %{role: "user", content: "Say 'Hello from OpenAI!' and nothing else."}
      ]
      
      IO.puts("\nTesting chat completion...")
      case MCPChat.LLM.OpenAI.chat(messages, model: "gpt-3.5-turbo", max_tokens: 50) do
        {:ok, response} ->
          IO.puts("✓ Response: #{response.content}")
        {:error, reason} ->
          IO.puts("✗ Chat failed: #{inspect(reason)}")
      end
      
      # Test streaming
      IO.puts("\nTesting streaming...")
      case MCPChat.LLM.OpenAI.stream_chat(messages, model: "gpt-3.5-turbo", max_tokens: 50) do
        {:ok, stream} ->
          IO.write("✓ Streaming: ")
          try do
            stream
            |> Enum.each(fn chunk ->
              IO.write(chunk.delta)
            end)
            IO.puts("")
          rescue
            e -> IO.puts("\n✗ Stream error: #{Exception.message(e)}")
          end
        {:error, reason} ->
          IO.puts("✗ Stream failed: #{inspect(reason)}")
      end
      
    else
      IO.puts("✗ OpenAI is not configured")
      IO.puts("  Please set OPENAI_API_KEY environment variable or add it to config.toml")
    end
  end
end

TestOpenAI.run()