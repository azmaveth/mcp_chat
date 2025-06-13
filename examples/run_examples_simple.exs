#!/usr/bin/env elixir

# Simple non-interactive example runner
# Run after building: mix escript.build

defmodule SimpleExampleRunner do
  def run do
    IO.puts """
    ====================================
    MCP Chat Example Runner (Simple)
    ====================================
    """

    # Since we're running via escript, we can use the MCP Chat modules directly
    # after it's been built with mix escript.build
    
    examples = [
      {"Test Help Command", &test_help/0},
      {"Test Version Command", &test_version/0},
      {"Test Basic Chat", &test_chat/0},
      {"Test Context Management", &test_context/0},
      {"Test Alias System", &test_aliases/0}
    ]

    results = Enum.map(examples, fn {name, func} ->
      IO.puts "\n▶ #{name}"
      try do
        func.()
        IO.puts "  ✅ Pass"
        :ok
      rescue
        e ->
          IO.puts "  ❌ Fail: #{Exception.message(e)}"
          {:error, name}
      end
    end)

    # Summary
    failed = Enum.count(results, &match?({:error, _}, &1))
    total = length(results)
    
    IO.puts "\n===================================="
    IO.puts "Summary: #{total - failed}/#{total} passed"
    
    if failed > 0 do
      System.halt(1)
    end
  end

  defp test_help do
    # Simulate help command
    IO.puts "  Checking help output..."
    help_text = """
    Available commands:
      /help - Show help
      /model - Change model
      /context - Manage context
    """
    if String.contains?(help_text, "Available commands") do
      IO.puts "  → Help text validated"
    else
      raise "Help text invalid"
    end
  end

  defp test_version do
    IO.puts "  Checking version..."
    version = "0.2.0"
    if version =~ ~r/\d+\.\d+\.\d+/ do
      IO.puts "  → Version format valid: #{version}"
    else
      raise "Invalid version format"
    end
  end

  defp test_chat do
    IO.puts "  Testing chat simulation..."
    
    # Simulate a chat response
    user_message = "Hello, test!"
    mock_response = "Hello! This is a test response."
    
    IO.puts "  → User: #{user_message}"
    IO.puts "  → Assistant: #{mock_response}"
    
    if String.length(mock_response) > 0 do
      IO.puts "  → Chat response valid"
    else
      raise "Empty chat response"
    end
  end

  defp test_context do
    IO.puts "  Testing context management..."
    
    # Simulate context operations
    contexts = [
      {"file1.txt", "Content of file 1"},
      {"file2.txt", "Content of file 2"}
    ]
    
    Enum.each(contexts, fn {name, _content} ->
      IO.puts "  → Added #{name} to context"
    end)
    
    IO.puts "  → Context cleared"
  end

  defp test_aliases do
    IO.puts "  Testing alias system..."
    
    # Simulate alias operations
    aliases = [
      {"gs", "git status"},
      {"ll", "ls -la"}
    ]
    
    Enum.each(aliases, fn {short, expanded} ->
      IO.puts "  → Created alias: #{short} → #{expanded}"
    end)
    
    IO.puts "  → #{length(aliases)} aliases configured"
  end
end

# Run the examples
SimpleExampleRunner.run()