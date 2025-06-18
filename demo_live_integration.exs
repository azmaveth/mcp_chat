#!/usr/bin/env elixir

# Live Demo: CLI/Agent Detach with Web Dashboard Integration
# This demonstrates the working system with real agents and sessions

defmodule LiveDemo do
  alias MCPChat.Gateway
  alias MCPChat.Agents.{SessionManager, AgentSupervisor}
  alias Phoenix.PubSub
  
  def run do
    IO.puts """
    
    ==========================================
    🚀 MCP Chat Live Demo
    ==========================================
    
    This demo shows:
    1. Creating sessions via CLI
    2. Monitoring via web dashboard
    3. Agent detach/reattach functionality
    4. Real-time synchronization
    
    Make sure the web server is running at http://localhost:4000
    Press Enter to continue...
    """
    
    IO.gets("")
    
    # Step 1: Create a session
    IO.puts "\n📝 Step 1: Creating a new session..."
    session_id = "demo_session_#{System.system_time(:second)}"
    
    case Gateway.create_session("demo_user", session_id: session_id) do
      {:ok, ^session_id} ->
        IO.puts "✅ Session created: #{session_id}"
        
        # Broadcast for web UI
        PubSub.broadcast(MCPChat.PubSub, "system:sessions", 
          {:session_created, %{id: session_id, user_id: "demo_user"}})
        
      error ->
        IO.puts "❌ Failed to create session: #{inspect(error)}"
        exit(:session_creation_failed)
    end
    
    Process.sleep(1000)
    
    # Step 2: Send a message
    IO.puts "\n💬 Step 2: Sending a message to the session..."
    Gateway.send_message(session_id, "Hello from the live demo!")
    
    # Broadcast message event
    PubSub.broadcast(MCPChat.PubSub, "session:#{session_id}", %{
      type: :message_added,
      message: %{
        id: generate_id(),
        role: :user,
        content: "Hello from the live demo!",
        timestamp: DateTime.utc_now()
      }
    })
    
    Process.sleep(1000)
    
    # Step 3: Check agent status
    IO.puts "\n🔍 Step 3: Checking agent status..."
    case AgentSupervisor.list_agents() do
      {:ok, agents} ->
        IO.puts "Active agents:"
        Enum.each(agents, fn {id, pid, type} ->
          IO.puts "  - #{id} (#{type}): #{inspect(pid)}"
        end)
      _ ->
        IO.puts "No agents found"
    end
    
    Process.sleep(1000)
    
    # Step 4: Simulate CLI disconnect
    IO.puts "\n🔌 Step 4: Simulating CLI disconnect..."
    IO.puts "The session remains active in the background"
    IO.puts "Check the web dashboard to see the session is still running"
    
    Process.sleep(2000)
    
    # Step 5: Send another message while "disconnected"
    IO.puts "\n📨 Step 5: Sending message while 'disconnected'..."
    Gateway.send_message(session_id, "This message was sent while the CLI was disconnected")
    
    PubSub.broadcast(MCPChat.PubSub, "session:#{session_id}", %{
      type: :message_added,
      message: %{
        id: generate_id(),
        role: :user,
        content: "This message was sent while the CLI was disconnected",
        timestamp: DateTime.utc_now()
      }
    })
    
    Process.sleep(1000)
    
    # Step 6: Simulate reconnect
    IO.puts "\n🔄 Step 6: Simulating CLI reconnect..."
    case Gateway.get_session(session_id) do
      {:ok, session} ->
        IO.puts "✅ Reconnected to session"
        IO.puts "Session has #{length(session.messages)} messages"
      error ->
        IO.puts "❌ Failed to reconnect: #{inspect(error)}"
    end
    
    Process.sleep(1000)
    
    # Step 7: Multi-interface interaction
    IO.puts "\n🌐 Step 7: Demonstrating multi-interface interaction..."
    IO.puts "You can now:"
    IO.puts "  - Send messages from the web UI"
    IO.puts "  - Execute commands from either interface"
    IO.puts "  - See real-time updates in both places"
    
    IO.puts "\n✨ Demo complete! Check http://localhost:4000 to interact with the session"
    IO.puts "Session ID: #{session_id}"
  end
  
  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end

# Make sure the application is started
Code.require_file("mix.exs")
Mix.start()
Mix.shell(Mix.Shell.Process)
{:ok, _} = Application.ensure_all_started(:mcp_chat)

# Wait for application to fully start
Process.sleep(1000)

# Run the demo
LiveDemo.run()