# MCP Chat Live Demo Guide

This guide demonstrates the working implementation of MCP Chat with simultaneous CLI and Web interface support.

## Prerequisites

1. Ensure you have Elixir and Phoenix installed
2. Dependencies installed: `mix deps.get`
3. Node dependencies (if needed): `cd assets && npm install`

## Starting the System

### Method 1: Phoenix Server Mode (Recommended for Web UI)
```bash
# Start with Phoenix server
MIX_ENV=dev iex -S mix phx.server

# The web server will start on http://localhost:4000
```

### Method 2: Standard IEx Mode
```bash
# Start standard IEx session
iex -S mix

# Then manually start the endpoint
MCPChatWeb.Endpoint.start_link()
```

## Running the Demo

### Quick Test
Once in IEx with the server running:

```elixir
# Run the test demo
c("test_live_demo.exs")
```

This will:
1. Create a new session
2. List all active agents
3. Send a test message
4. Display session state

### Manual Testing

1. **Create a Session via IEx**:
```elixir
{:ok, session_id} = MCPChat.Gateway.create_session("demo_user")
```

2. **Open Web Dashboard**:
- Navigate to http://localhost:4000
- You'll see the session in the Sessions list
- Click on it to open the chat interface

3. **Send Messages from CLI**:
```elixir
MCPChat.Gateway.send_message(session_id, "Hello from CLI!")
```

4. **Watch Real-time Updates**:
- The message appears instantly in the web UI
- No page refresh needed

5. **Send from Web UI**:
- Type a message in the web interface
- See it reflected in the session state

6. **Check Session State**:
```elixir
{:ok, state} = MCPChat.Gateway.get_session(session_id)
IO.inspect(state.messages, label: "Messages")
```

## Key Features Demonstrated

### 1. Agent Persistence
- Sessions remain active even when CLI disconnects
- Agents supervised by OTP supervisors
- Automatic restart on crashes

### 2. Multi-Interface Support
- CLI and Web can access same session simultaneously
- Real-time updates via Phoenix PubSub
- Commands work from both interfaces

### 3. Real Implementation
- Actual SessionManager tracking sessions
- AgentSupervisor managing agent lifecycle
- Phoenix controllers handling HTTP requests
- LiveView for real-time web updates

## Architecture Components

### Backend
- `MCPChat.Gateway` - Unified API for all operations
- `MCPChat.Agents.SessionManager` - Manages session lifecycle
- `MCPChat.Agents.AgentSupervisor` - Supervises all agents
- Phoenix.PubSub - Real-time event broadcasting

### Web Interface
- `MCPChatWeb.SessionController` - REST API for sessions
- `MCPChatWeb.ChatLive` - LiveView chat interface
- `MCPChatWeb.DashboardLive` - System overview
- `MCPChatWeb.AgentMonitorLive` - Agent monitoring

## Troubleshooting

### Web Server Not Starting
- Check no other process is using port 4000
- Ensure Phoenix endpoint configuration is correct
- Try: `lsof -i :4000` to check port usage

### PubSub Not Working
- Verify MCPChat.PubSub is started in supervision tree
- Check subscriptions in LiveView mount callbacks
- Monitor PubSub with: `Phoenix.PubSub.subscribe(MCPChat.PubSub, "system:sessions")`

### Sessions Not Persisting
- Ensure SessionManager is running: `Process.whereis(MCPChat.Agents.SessionManager)`
- Check agent supervisor: `Supervisor.which_children(MCPChat.Agents.AgentSupervisor)`

## Next Steps

1. **Add More Features**:
   - File attachments
   - Tool execution monitoring
   - Export functionality

2. **Enhance UI**:
   - Better styling
   - Mobile responsive design
   - Keyboard shortcuts

3. **Production Readiness**:
   - Authentication/authorization
   - Rate limiting
   - Proper error handling
   - Deployment configuration