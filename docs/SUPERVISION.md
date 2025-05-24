# MCP Chat Supervision Tree

## Current Supervision Structure

### Main Application Supervisor
The root supervisor (`MCPChat.Supervisor`) uses `:one_for_one` strategy and supervises:

1. **MCPChat.Config** (GenServer)
   - Configuration management
   - Loads and stores app configuration

2. **MCPChat.Session** (GenServer)
   - Session state management
   - Tracks messages, context, and token usage

3. **MCPChat.Alias** (GenServer)
   - Command alias management
   - Stores and expands user-defined aliases

4. **MCPChat.LLM.ModelLoader** (GenServer)
   - Local model loading/unloading
   - Manages Bumblebee models in memory

5. **MCPChat.CLI.SimpleLineReader** (GenServer)
   - Command line input handling
   - History management

6. **MCPChat.MCP.ServerManager** (GenServer)
   - Manages MCP client connections
   - Contains its own DynamicSupervisor for MCP servers

7. **MCPChat.MCPServer.StdioServer** (Optional)
   - Only started if `stdio_enabled: true` in config
   - Provides MCP server over stdio

8. **MCPChat.MCPServer.SSEServer** (Optional)
   - Only started if `sse_enabled: true` in config
   - Provides MCP server over Server-Sent Events

### Dynamic Supervision

**MCPChat.MCP.ServerSupervisor** (DynamicSupervisor)
- Created by ServerManager on initialization
- Supervises individual MCP client connections:
  - **MCPChat.MCP.Server** processes (one per connection)
  - Each Server can spawn:
    - Port process (for stdio connections)
    - SSEClient process (for SSE connections)
  - Uses `:temporary` restart strategy

## What's NOT Supervised

1. **Main Chat Loop** (`MCPChat.CLI.Chat`)
   - Runs in the calling process
   - Not supervised, exits terminate the app

2. **LLM Adapters** (Anthropic, OpenAI, etc.)
   - Stateless modules, no processes to supervise

3. **HTTP Connections**
   - Managed by Req library
   - Temporary connections, not supervised

4. **Port Processes** (stdio connections)
   - Started by MCP.Server but not directly supervised
   - Monitored via Process.monitor instead

## Supervision Benefits

- **Config/Session/Alias persistence**: These GenServers restart and reload state
- **MCP connections**: Can reconnect automatically if configured
- **Model management**: ModelLoader ensures models stay loaded
- **Fault isolation**: MCP server crashes don't affect the main app

## Potential Improvements

1. **Add supervision for Port processes**
   - Currently only monitored, not supervised
   - Could use a custom supervisor for better control

2. **Supervise the main chat loop**
   - Could restart on crashes
   - Would need to handle terminal state properly

3. **Add circuit breakers for LLM APIs**
   - Prevent cascading failures
   - Implement retry logic with backoff

4. **Connection pooling for HTTP clients**
   - Reuse connections for better performance
   - Add supervision for connection pools