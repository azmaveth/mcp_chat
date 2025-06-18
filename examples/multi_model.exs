#!/usr/bin/env elixir

# Multi-Model Chat Example
# Demonstrates switching between different LLM providers and models

IO.puts("""
=== Multi-Model Chat Example ===

This example demonstrates MCP Chat's multi-model capabilities without 
requiring full application dependencies.
""")

defmodule MultiModelExample do
  def run() do
    # Demonstrate model selection concepts
    IO.puts("\n1. Available Model Providers")
    IO.puts("---------------------------")
    
    providers = [
      {"anthropic", "Claude models (Sonnet, Haiku, Opus)"},
      {"openai", "GPT models (GPT-4o, GPT-4o-mini)"},
      {"ollama", "Local models (Llama, Mistral, CodeLlama)"},
      {"gemini", "Google models (Gemini Pro, Flash)"},
      {"bedrock", "AWS Bedrock (Claude, Titan, Jurassic)"}
    ]
    
    Enum.each(providers, fn {provider, description} ->
      IO.puts("  • #{String.pad_trailing(provider, 12)} - #{description}")
    end)
    
    IO.puts("\n2. Model Selection Commands")
    IO.puts("--------------------------")
    
    commands = [
      {"/model list", "Show all available models"},
      {"/model anthropic", "Switch to Anthropic provider"},
      {"/model claude-3-sonnet-20240229", "Use specific Claude model"},
      {"/model openai/gpt-4o", "Switch to GPT-4o"},
      {"/model ollama/llama3.2:latest", "Use local Llama model"},
      {"/model gemini/gemini-1.5-pro", "Switch to Gemini Pro"}
    ]
    
    Enum.each(commands, fn {cmd, desc} ->
      IO.puts("  #{String.pad_trailing(cmd, 30)} - #{desc}")
    end)
    
    IO.puts("\n3. Provider Comparison Demo")
    IO.puts("--------------------------")
    
    sample_models = [
      %{
        provider: "anthropic", 
        model: "claude-3-sonnet-20240229",
        strengths: ["Reasoning", "Code", "Analysis"],
        cost_per_1m_tokens: "$3.00 / $15.00"
      },
      %{
        provider: "openai", 
        model: "gpt-4o",
        strengths: ["General purpose", "Creative writing", "Math"],
        cost_per_1m_tokens: "$5.00 / $15.00"
      },
      %{
        provider: "ollama", 
        model: "llama3.2:latest",
        strengths: ["Privacy", "Local processing", "No API costs"],
        cost_per_1m_tokens: "Free (local)"
      }
    ]
    
    Enum.each(sample_models, fn model ->
      IO.puts("\n  #{model.provider}/#{model.model}")
      IO.puts("    Strengths: #{Enum.join(model.strengths, ", ")}")
      IO.puts("    Cost: #{model.cost_per_1m_tokens} (input/output)")
    end)
    
    IO.puts("\n4. Example Model Switching Session")
    IO.puts("---------------------------------")
    
    session_example = [
      {"User:", "Hello! What model are you?"},
      {"Claude:", "I'm Claude 3 Sonnet, made by Anthropic."},
      {"User:", "/model openai/gpt-4o"},
      {"System:", "✓ Switched to OpenAI GPT-4o"},
      {"User:", "What model are you now?"},
      {"GPT-4o:", "I'm GPT-4o, made by OpenAI."},
      {"User:", "/model ollama/llama3.2:latest"},
      {"System:", "✓ Switched to local Llama 3.2 model"},
      {"User:", "Tell me about yourself"},
      {"Llama:", "I'm Llama 3.2, running locally on your machine."}
    ]
    
    Enum.each(session_example, fn {speaker, message} ->
      case speaker do
        "System:" -> IO.puts("    #{speaker} #{message}")
        _ -> IO.puts("  #{speaker} #{message}")
      end
    end)
    
    IO.puts("\n5. Cost Comparison Example")
    IO.puts("-------------------------")
    
    cost_examples = [
      {"Claude 3 Opus", "$15.00/$75.00", "Highest quality, most expensive"},
      {"Claude 3 Sonnet", "$3.00/$15.00", "Balanced quality and cost"},
      {"Claude 3 Haiku", "$0.25/$1.25", "Fast and economical"},
      {"GPT-4o", "$5.00/$15.00", "General purpose, competitive"},
      {"GPT-4o-mini", "$0.15/$0.60", "Lightweight version"},
      {"Ollama (Local)", "Free", "No API costs, local processing"}
    ]
    
    IO.puts("\nCost per 1M tokens (input/output):")
    Enum.each(cost_examples, fn {model, cost, description} ->
      IO.puts("  #{String.pad_trailing(model, 16)} #{String.pad_trailing(cost, 14)} - #{description}")
    end)
    
    IO.puts("\n6. Streaming Response Demo")
    IO.puts("-------------------------")
    
    streaming_demo = [
      "User: Write a short poem about programming",
      "",
      "Assistant: (streaming response)",
      "Code flows like poetry,",
      "Functions dance in harmony,",
      "Logic becomes art.",
      "",
      "✓ Streaming complete (1,847ms, 23 tokens)"
    ]
    
    Enum.each(streaming_demo, fn line ->
      if String.starts_with?(line, "Assistant:") do
        IO.puts(line)
        Process.sleep(200)
      else
        IO.puts(line)
        if line != "", do: Process.sleep(150)
      end
    end)
    
    IO.puts("\n7. Configuration Example")
    IO.puts("-----------------------")
    
    config_example = """
    # config.toml
    [llm]
    default = "anthropic"
    
    [llm.anthropic]
    api_key = "sk-ant-..."
    model = "claude-3-sonnet-20240229"
    
    [llm.openai]
    api_key = "sk-proj-..."
    model = "gpt-4o"
    
    [llm.ollama]
    api_base = "http://localhost:11434"
    model = "llama3.2:latest"
    """
    
    IO.puts(config_example)
  end
end

# Run the example
MultiModelExample.run()

IO.puts("""

=== Example Complete ===

This example demonstrated:
- Available model providers and their strengths
- Model selection commands and syntax
- Cost comparison between different models
- Example conversation with model switching
- Streaming response display
- Configuration setup for multiple providers

To try these features interactively:
1. Configure providers in your config.toml
2. Set environment variables for API keys
3. Run: ./mcp_chat
4. Use /model commands to switch between providers

Tips:
- Consider cost vs quality tradeoffs
- Use local models (Ollama) for privacy-sensitive content
- Fast models (Haiku, GPT-4o-mini) for quick tasks
- Premium models (Opus, GPT-4o) for complex reasoning
""")

IO.puts("\n✅ Multi-Model example completed successfully!")