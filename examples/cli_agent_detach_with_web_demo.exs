#!/usr/bin/env elixir

# MCP Chat CLI/Agent Detach Demo with Web Dashboard
# This demo shows how to use both CLI and Web UI to interact with agents

defmodule CLIAgentDetachWithWebDemo do
  @moduledoc """
  Demonstrates CLI/Agent separation with simultaneous Web UI monitoring.
  
  Shows how to:
  1. Start the web dashboard
  2. Create and monitor agents via web UI
  3. Detach CLI while observing agent state in web
  4. Reconnect and see synchronized state
  """

  def run() do
    IO.puts("\n🌐 MCP Chat CLI/Agent Detach Demo with Web Dashboard")
    IO.puts("=" <> String.duplicate("=", 70))
    
    # Start web server
    start_web_server()
    
    # Demo phases
    demo_agent_startup()
    demo_web_monitoring()
    demo_cli_disconnect_with_web()
    demo_background_work_observable()
    demo_cli_reconnect_with_sync()
    demo_multi_interface_interaction()
    
    show_summary()
  end

  defp start_web_server do
    IO.puts("\n📡 Starting Web Server...")
    IO.puts("The Phoenix web server will start on http://localhost:4000")
    
    # In real usage, this is already started by application supervisor
    # Here we just simulate the startup message
    Process.sleep(1000)
    
    IO.puts("""
    ✅ Web server started successfully!
    
    Available endpoints:
    - Dashboard: http://localhost:4000/
    - Sessions: http://localhost:4000/sessions
    - Agents: http://localhost:4000/agents
    - Chat: http://localhost:4000/sessions/:id/chat
    
    Open your browser to http://localhost:4000 to monitor agents
    """)
    
    Process.sleep(2000)
  end

  defp demo_agent_startup do
    IO.puts("\n\n1️⃣  AGENT STARTUP WITH WEB VISIBILITY")
    IO.puts("-" <> String.duplicate("-", 40))
    
    IO.puts("""
    Starting agents that will be visible in both CLI and Web UI...
    """)
    
    # Simulate agent startup
    agent_code = """
    # Start a new agent with session
    {:ok, session_id} = MCPChat.Gateway.create_session("demo_user")
    {:ok, agent_pid} = MCPChat.Agents.AgentSupervisor.start_llm_agent(session_id)
    
    # Agent immediately visible in web dashboard at:
    # http://localhost:4000/agents
    """
    
    IO.puts("\n```elixir")
    IO.puts(agent_code)
    IO.puts("```")
    
    IO.puts("""
    
    💡 Web Dashboard Update:
    - New agent appears in real-time on http://localhost:4000/agents
    - Status indicator shows 'active' (green)
    - Session link available for chat interface
    """)
    
    Process.sleep(3000)
  end

  defp demo_web_monitoring do
    IO.puts("\n\n2️⃣  WEB MONITORING CAPABILITIES")
    IO.puts("-" <> String.duplicate("-", 40))
    
    IO.puts("""
    The web dashboard provides real-time monitoring:
    
    📊 Dashboard (http://localhost:4000/):
    - System statistics (memory, uptime)
    - Active agent count
    - Session overview
    - Quick action buttons
    
    🤖 Agent Monitor (http://localhost:4000/agents):
    - Live agent status updates
    - Performance metrics
    - Start/stop controls
    - Detailed agent inspection
    
    💬 Chat Interface (http://localhost:4000/sessions/:id/chat):
    - Same commands as CLI
    - Real-time message streaming
    - Command auto-completion
    - Session state indicator
    """)
    
    Process.sleep(3000)
  end

  defp demo_cli_disconnect_with_web do
    IO.puts("\n\n3️⃣  CLI DISCONNECT WITH WEB OBSERVATION")
    IO.puts("-" <> String.duplicate("-", 40))
    
    IO.puts("""
    Now disconnecting CLI while keeping web dashboard open...
    """)
    
    disconnect_code = """
    # CLI disconnects
    MCPChat.CLI.EventBridge.disconnect()
    
    # But agent continues running
    # Web dashboard shows:
    # - Agent still active ✅
    # - Session still accessible ✅
    # - Can send commands via web ✅
    """
    
    IO.puts("\n```elixir")
    IO.puts(disconnect_code)
    IO.puts("```")
    
    IO.puts("""
    
    🌐 What you see in Web UI:
    1. Agent status remains "active"
    2. CLI connection indicator shows "disconnected"
    3. Web chat interface still fully functional
    4. Can continue interacting via web while CLI is gone
    """)
    
    # Simulate disconnect
    IO.puts("\n⏳ CLI disconnecting...")
    Process.sleep(1000)
    IO.puts("❌ CLI disconnected")
    IO.puts("✅ Agent still visible and active in web UI!")
    
    Process.sleep(3000)
  end

  defp demo_background_work_observable do
    IO.puts("\n\n4️⃣  BACKGROUND WORK OBSERVABLE IN WEB")
    IO.puts("-" <> String.duplicate("-", 40))
    
    IO.puts("""
    While CLI is disconnected, agent performs background work
    visible in the web dashboard...
    """)
    
    # Simulate background work with web visibility
    background_tasks = [
      {"Processing context files...", 2},
      {"Running analysis agent...", 3},
      {"Executing MCP tool calls...", 2},
      {"Updating session state...", 1}
    ]
    
    IO.puts("\n📊 Live Updates in Web Dashboard:")
    
    for {task, duration} <- background_tasks do
      IO.puts("\n🔄 #{task}")
      
      # Show progress bar for web
      IO.write("   Web UI Progress: ")
      for i <- 1..10 do
        IO.write("█")
        Process.sleep(duration * 100)
      end
      IO.puts(" ✓")
      
      IO.puts("   └─ Real-time updates via Phoenix.PubSub")
      IO.puts("   └─ Progress visible at http://localhost:4000/agents/#{:rand.uniform(1000)}")
    end
    
    IO.puts("""
    
    💡 Web UI Features During Background Work:
    - Live progress indicators
    - Real-time log streaming
    - Performance metrics updates
    - Tool execution visibility
    """)
    
    Process.sleep(2000)
  end

  defp demo_cli_reconnect_with_sync do
    IO.puts("\n\n5️⃣  CLI RECONNECT WITH STATE SYNC")
    IO.puts("-" <> String.duplicate("-", 40))
    
    IO.puts("""
    Reconnecting CLI and synchronizing with web state...
    """)
    
    reconnect_code = """
    # CLI reconnects to existing session
    {:ok, session_state} = MCPChat.CLI.EventBridge.reconnect(session_id)
    
    # State automatically synchronized:
    # - Message history from web interactions
    # - Current model/settings
    # - Context files
    # - Tool execution results
    """
    
    IO.puts("\n```elixir")
    IO.puts(reconnect_code)
    IO.puts("```")
    
    IO.puts("\n⏳ CLI reconnecting...")
    Process.sleep(1000)
    
    IO.puts("""
    ✅ CLI reconnected and synchronized!
    
    🔄 Synchronized State:
    - 15 messages from web chat
    - 3 context files added via web
    - Model switched to gpt-4o
    - 2 tool executions completed
    
    Both CLI and Web now show identical state!
    """)
    
    Process.sleep(3000)
  end

  defp demo_multi_interface_interaction do
    IO.puts("\n\n6️⃣  MULTI-INTERFACE INTERACTION")
    IO.puts("-" <> String.duplicate("-", 40))
    
    IO.puts("""
    Demonstrating simultaneous CLI and Web interaction...
    """)
    
    # Simulate parallel interactions
    interactions = [
      {:cli, "User types in CLI: 'analyze this code'"},
      {:web, "Message appears instantly in web chat"},
      {:web, "Another user types in web: 'explain the architecture'"},
      {:cli, "Message appears instantly in CLI"},
      {:both, "Agent responds, visible in both interfaces"},
      {:web, "Web user clicks 'Stop Generation' button"},
      {:cli, "CLI shows 'Generation stopped by web user'"}
    ]
    
    IO.puts("\n🔄 Real-time Interaction Flow:\n")
    
    for {source, action} <- interactions do
      icon = case source do
        :cli -> "💻"
        :web -> "🌐"
        :both -> "📡"
      end
      
      IO.puts("#{icon} #{action}")
      Process.sleep(1500)
    end
    
    IO.puts("""
    
    ✨ Benefits of Multi-Interface Support:
    - Collaborate with team members
    - Monitor long-running tasks from anywhere
    - Switch between CLI and browser seamlessly
    - Debug issues using web tools while coding in CLI
    """)
    
    Process.sleep(2000)
  end

  defp show_summary do
    IO.puts("\n\n📝 SUMMARY")
    IO.puts("=" <> String.duplicate("=", 70))
    
    IO.puts("""
    This demo showed how MCP Chat supports multiple interfaces:
    
    1. **Web Dashboard** - Real-time monitoring and control
    2. **CLI Interface** - Terminal-based interaction
    3. **State Synchronization** - Seamless switching between interfaces
    4. **Phoenix PubSub** - Real-time updates across all clients
    
    Key Architectural Points:
    - Agents run independently of any interface
    - State persists in OTP processes
    - Multiple clients can connect to same session
    - Real-time updates via PubSub broadcasts
    
    Try it yourself:
    1. Start MCP Chat: `iex -S mix`
    2. Open browser: http://localhost:4000
    3. Create session in web UI
    4. Connect CLI: `MCPChat.main()`
    5. Use `/connect session_id` to join web session
    
    Happy chatting across multiple interfaces! 🎉
    """)
  end
end

# Run the demo
CLIAgentDetachWithWebDemo.run()