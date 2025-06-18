#!/usr/bin/env elixir

# Getting Started with MCP Chat
# This example demonstrates basic MCP Chat concepts without running the full application

IO.puts("""
=== MCP Chat Getting Started Example ===

This example demonstrates basic MCP Chat concepts and structure.
Note: This is a simplified demo that shows the project structure
without requiring a full application startup.
""")

# Example 1: Project Structure
IO.puts("\n1. Project Structure")
IO.puts("-------------------")

IO.puts("MCP Chat is organized into these main components:")
IO.puts("  - lib/mcp_chat/ - Core application modules")
IO.puts("  - lib/mcp_chat/cli/ - Command-line interface")
IO.puts("  - lib/mcp_chat/agents/ - Agent-based architecture")
IO.puts("  - lib/mcp_chat/mcp/ - Model Context Protocol implementation")
IO.puts("  - examples/ - Demo scripts and examples")
IO.puts("  - config.toml - Configuration file")

# Example 2: Key Features
IO.puts("\n2. Key Features")
IO.puts("--------------")

IO.puts("✓ Multi-LLM Support: Anthropic, OpenAI, Ollama, Gemini, Bedrock")
IO.puts("✓ MCP Integration: Connect to external tools and resources")
IO.puts("✓ Agent Architecture: Specialized agents for different tasks")
IO.puts("✓ Context Management: File uploads, truncation strategies")
IO.puts("✓ Command System: /model, /cost, /context, /mcp commands")
IO.puts("✓ Session Persistence: Save and resume conversations")
IO.puts("✓ Streaming Support: Real-time response display")

# Example 3: Common Commands
IO.puts("\n3. Common Commands")
IO.puts("-----------------")

commands = [
  {"/help", "Show available commands"},
  {"/model", "Show/change current LLM model"},
  {"/cost", "Display usage and cost statistics"}, 
  {"/context add <file>", "Add file to conversation context"},
  {"/mcp servers", "List connected MCP servers"},
  {"/alias add <name> <command>", "Create command alias"},
  {"/export", "Export conversation to file"},
  {"/session save", "Save current session"},
]

Enum.each(commands, fn {cmd, desc} ->
  IO.puts("  #{String.pad_trailing(cmd, 20)} - #{desc}")
end)

# Example 4: Configuration
IO.puts("\n4. Configuration")
IO.puts("---------------")

IO.puts("MCP Chat uses TOML configuration (~/.config/mcp_chat/config.toml):")
IO.puts("""
  [llm]
  default = "anthropic"
  
  [llm.anthropic]
  api_key = "your-key"
  model = "claude-3-sonnet-20240229"
  
  [[mcp.servers]]
  name = "filesystem"
  command = ["python", "server.py"]
""")

# Example 5: Running Examples
IO.puts("\n5. Running Examples")
IO.puts("------------------")

IO.puts("To run interactive examples:")
IO.puts("  • make examples        # Run simple test suite")
IO.puts("  • make acceptance      # Run comprehensive tests")
IO.puts("  • ./mcp_chat          # Start interactive chat")
IO.puts("  • iex -S mix          # Start in development mode")

# Example 6: Demo Servers
IO.puts("\n6. Demo Servers")
IO.puts("--------------")

IO.puts("Python demo servers in examples/demo_servers/:")
IO.puts("  • calculator_server.py - Math operations")
IO.puts("  • time_server.py       - Date/time utilities")
IO.puts("  • data_server.py       - Data generation")

IO.puts("""

=== Example Complete ===

This example showed:
- Project structure and organization
- Key features and capabilities
- Command system overview
- Configuration format
- How to run other examples
- Available demo servers

To try interactive features:
1. Build the project: mix escript.build
2. Run: ./mcp_chat
3. Try commands like /help, /model, /cost

For automated testing: make examples
""")

IO.puts("\n✅ Getting Started example completed successfully!")