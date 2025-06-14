# IEx configuration for MCP Chat

# Alias commonly used modules
alias MCPChat.{Session, Config}
alias MCPChat.CLI.{Commands, Renderer}

# Helper function to start the chat
defmodule IExHelpers do
  def chat do
    MCPChat.main()
  end
  
  def help do
    IO.puts """
    MCP Chat IEx Helpers:
    
    IExHelpers.chat()    - Start the chat client
    MCPChat.main()       - Start the chat client (same as above)
    
    Useful modules:
    MCPChat.Session      - Manage chat sessions
    MCPChat.Config       - Configuration access
    """
  end
end

# Print startup message
IO.puts "\n🚀 MCP Chat loaded in IEx!"
IO.puts "Type `IExHelpers.chat()` or `MCPChat.main()` to start chatting"
IO.puts "Type `IExHelpers.help()` for more options\n"