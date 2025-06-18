# Test Live Demo - Run this in an existing iex session
# Start with: iex -S mix phx.server
# Then run: c("test_live_demo.exs")

defmodule TestLiveDemo do
  alias MCPChat.Gateway
  alias MCPChat.Agents.{SessionManager, AgentSupervisor}
  alias Phoenix.PubSub
  
  def run do
    IO.puts """
    
    ==========================================
    🚀 MCP Chat Live Demo Test
    ==========================================
    
    Testing basic functionality...
    """
    
    # Test 1: Create a session
    IO.puts "\n1️⃣ Creating a session..."
    session_id = "test_#{System.system_time(:second)}"
    
    case Gateway.create_session("test_user", session_id: session_id) do
      {:ok, ^session_id} ->
        IO.puts "✅ Session created: #{session_id}"
      error ->
        IO.puts "❌ Failed: #{inspect(error)}"
    end
    
    # Test 2: List agents
    IO.puts "\n2️⃣ Listing agents..."
    case AgentSupervisor.list_agents() do
      {:ok, agents} ->
        IO.puts "✅ Found #{length(agents)} agents:"
        Enum.each(agents, fn {id, _pid, type} ->
          IO.puts "   - #{id} (#{type})"
        end)
      error ->
        IO.puts "❌ Failed: #{inspect(error)}"
    end
    
    # Test 3: Send a message
    IO.puts "\n3️⃣ Sending a message..."
    case Gateway.send_message(session_id, "Hello from test!") do
      :ok ->
        IO.puts "✅ Message sent"
      error ->
        IO.puts "❌ Failed: #{inspect(error)}"
    end
    
    # Test 4: Get session state
    IO.puts "\n4️⃣ Getting session state..."
    case Gateway.get_session(session_id) do
      {:ok, state} ->
        IO.puts "✅ Session has #{length(Map.get(state, :messages, []))} messages"
      error ->
        IO.puts "❌ Failed: #{inspect(error)}"
    end
    
    IO.puts "\n✨ Test complete! Check http://localhost:4000 to see the session"
    IO.puts "Session ID: #{session_id}"
  end
end

TestLiveDemo.run()