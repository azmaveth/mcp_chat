#!/usr/bin/env elixir

# Script to test ExReadline behavior with agent command examples
IO.puts("Starting ExReadline agent command test...")

# Start ExReadline
{:ok, _pid} = ExReadline.start_link()

IO.puts("ExReadline started with agent architecture support.")
IO.puts("Try these enhanced agent commands:")
IO.puts("  /help              - Show all available commands and agents")
IO.puts("  /model recommend   - Get AI-powered model recommendations (LLM Agent)")
IO.puts("  /mcp discover      - Discover available MCP servers (MCP Agent)")
IO.puts("  /stats             - Show enhanced session statistics (Analysis Agent)")
IO.puts("  /export json       - Export session data (Export Agent)")
IO.puts("  /concurrent        - Show concurrent tool capabilities (Tool Agent)")
IO.puts("")
IO.puts("Type a command and press Enter (or Ctrl+D to exit):")

# Read multiple lines to test agent commands
loop_test = fn loop_test ->
  case ExReadline.read_line("Agent Test › ") do
    :eof ->
      IO.puts("Got EOF - exiting")
    
    line when is_binary(line) ->
      trimmed = String.trim(line)
      IO.puts("Command entered: #{inspect(trimmed)}")
      
      # Provide agent routing feedback
      cond do
        String.starts_with?(trimmed, "/model") or String.starts_with?(trimmed, "/backend") ->
          IO.puts("→ This would route to LLM Agent")
        
        String.starts_with?(trimmed, "/mcp") ->
          IO.puts("→ This would route to MCP Agent")
        
        String.starts_with?(trimmed, "/stats") or String.starts_with?(trimmed, "/cost") ->
          IO.puts("→ This would route to Analysis Agent")
        
        String.starts_with?(trimmed, "/export") ->
          IO.puts("→ This would route to Export Agent")
        
        String.starts_with?(trimmed, "/concurrent") ->
          IO.puts("→ This would route to Tool Agent")
        
        String.starts_with?(trimmed, "/help") ->
          IO.puts("→ This would discover available commands from all agents")
        
        trimmed == "exit" or trimmed == "/exit" ->
          IO.puts("Exiting test...")
          :exit
        
        true ->
          IO.puts("→ This would be handled locally or route to appropriate agent")
      end
      
      if trimmed != "exit" and trimmed != "/exit" do
        IO.puts("Enter another command (or 'exit' to quit):")
        loop_test.(loop_test)
      end
  end
end

loop_test.(loop_test)

IO.puts("Agent command test complete.")