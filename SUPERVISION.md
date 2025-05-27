# MCP Chat Supervision Structure

## Current Supervision Tree

```
MCPChat.Application (one_for_one)
├── MCPChat.Config (GenServer)
├── MCPChat.StartupProfiler (if enabled)
├── MCPChat.Session (GenServer)
├── MCPChat.HealthMonitor (GenServer) 
├── MCPChat.CircuitBreaker.LLM (GenServer)
├── MCPChat.ConnectionPoolSupervisor (DynamicSupervisor)
├── MCPChat.ChatSupervisor (GenServer)
├── ExAlias (GenServer)
├── MCPChat.Alias.ExAliasAdapter (GenServer)
├── MCPChat.CLI.ExReadlineAdapter (GenServer)
├── MCPChat.Memory.StoreSupervisor (one_for_one)
│   └── MCPChat.Memory.MessageStore (GenServer, per session)
├── MCPChat.MCP.LazyServerManager (GenServer, if lazy mode)
├── MCPChat.MCP.ServerManager (GenServer)
│   └── MCPChat.MCP.ServerSupervisor (DynamicSupervisor)
│       ├── MCPChat.MCP.ServerWrapper (GenServer, per server)
│       │   └── ExMCP.Client (stdio/SSE transport)
│       └── MCPChat.MCP.ExMCPAdapter (per connection)
├── MCPChat.MCP.Handlers.ComprehensiveNotificationHandler (GenServer)
├── MCPChat.MCP.ResourceCache (GenServer)
├── MCPChat.UI.TUIManager (GenServer)
├── MCPChat.UI.ProgressDisplay (GenServer)
├── MCPChat.UI.ResourceCacheDisplay (GenServer)
├── MCPChat.MCPServer.StdioServer (optional, if stdio_enabled)
└── MCPChat.MCPServer.SSEServer (optional, if sse_enabled)
```

## Supervision Details

### Core Services

**MCPChat.Config** (GenServer)
- Configuration management
- Loads and stores app configuration from TOML files
- Handles environment variable overrides
- Restart: `:permanent`

**MCPChat.Session** (GenServer)
- Session state management
- Tracks messages, context, and token usage
- Persists session data to disk
- Restart: `:permanent`

**MCPChat.Memory.StoreSupervisor**
- Supervises per-session message stores
- Uses `:one_for_one` strategy
- Dynamically creates MessageStore processes

**MCPChat.Memory.MessageStore** (GenServer)
- Hybrid memory/disk storage for messages
- Pagination support to prevent memory bloat
- Configurable memory limits
- Restart: `:temporary`

### Health & Resilience

**MCPChat.HealthMonitor** (GenServer)
- Monitors registered processes for health
- Tracks memory usage and message queue length
- Configurable thresholds and alerts
- Telemetry integration for metrics
- Restart: `:permanent`

**MCPChat.CircuitBreaker.LLM** (GenServer)
- Prevents cascade failures for LLM API calls
- Configurable failure threshold
- Automatic recovery with half-open state
- Integrated into ExLLMAdapter
- Restart: `:permanent`

**MCPChat.ChatSupervisor** (GenServer)
- Supervises main chat process
- Automatic restart on crash
- Session backup and restoration
- User notifications on recovery
- Restart: `:permanent`

**MCPChat.ConnectionPoolSupervisor** (DynamicSupervisor)
- Generic pool implementation
- Health checks for connections
- Automatic replacement of unhealthy connections
- Ready for HTTP client integration

### MCP Management

**MCPChat.MCP.ServerManager** (GenServer)
- Manages MCP client connections
- Contains ServerSupervisor for dynamic supervision
- Handles server discovery and configuration
- Restart: `:permanent`

**MCPChat.MCP.LazyServerManager** (GenServer)
- Optional lazy loading coordinator
- Manages connection timing based on startup mode
- Only started in lazy or background modes
- Restart: `:permanent`

**MCPChat.MCP.ServerSupervisor** (DynamicSupervisor)
- Created by ServerManager on initialization
- Supervises individual MCP client connections
- Uses `:temporary` restart strategy for servers

**MCPChat.MCP.ServerWrapper** (GenServer)
- Wraps each ExMCP.Client instance
- Manages connection lifecycle
- Handles reconnection logic
- Restart: `:temporary`

**MCPChat.MCP.ResourceCache** (GenServer)
- Local caching layer with ETS tables
- Automatic cache invalidation via subscriptions
- LRU eviction and size limits
- Restart: `:permanent`

### Notification & UI

**MCPChat.MCP.Handlers.ComprehensiveNotificationHandler** (GenServer)
- Handles all MCP notification types
- Event history tracking with timestamps
- Notification batching and filtering
- Per-category configuration
- Restart: `:permanent`

**MCPChat.UI.TUIManager** (GenServer)
- Coordinates TUI display components
- Keyboard event handling
- Display state management
- Restart: `:permanent`

**MCPChat.UI.ProgressDisplay** (GenServer)
- Real-time progress bars using Owl
- Tracks multiple concurrent operations
- Configurable update intervals
- Restart: `:permanent`

**MCPChat.UI.ResourceCacheDisplay** (GenServer)
- Visual cache statistics display
- Summary and detailed view modes
- Real-time cache updates
- Restart: `:permanent`

### Optional MCP Servers

**MCPChat.MCPServer.StdioServer**
- Only started if `stdio_enabled: true` in config
- Provides MCP server over stdio
- Restart: `:permanent`

**MCPChat.MCPServer.SSEServer**
- Only started if `sse_enabled: true` in config
- Provides MCP server over Server-Sent Events
- Restart: `:permanent`

### Performance Optimization

**MCPChat.StartupProfiler**
- Only started if profiling is enabled
- Measures startup phase timings
- Stores results in :persistent_term
- Restart: `:temporary`

## What's NOT Supervised

1. **Main Chat Loop** (`MCPChat.CLI.Chat`)
   - Runs in the calling process
   - Not supervised, exits terminate the app
   - Recovery handled by ChatSupervisor

2. **LLM Adapters** (Anthropic, OpenAI, etc.)
   - Stateless modules, no processes to supervise
   - Failures handled by circuit breaker

3. **HTTP Connections**
   - Managed by Req library
   - Temporary connections, not supervised
   - Connection pooling framework ready but not integrated

4. **Port Processes** (stdio connections)
   - Started by ExMCP.Client but not directly supervised
   - Monitored via Process.monitor
   - PortSupervisor created but not yet integrated

## Fault Tolerance Features

### What's Protected
- **State Persistence**: Config, Session, Alias GenServers restart and reload state
- **MCP Connections**: Automatic reconnection with exponential backoff
- **Model Management**: ModelLoader ensures models stay loaded (when using local models)
- **Chat Continuity**: ChatSupervisor restores session on crash
- **API Resilience**: Circuit breaker prevents cascade failures
- **Memory Protection**: Message stores prevent unbounded growth
- **Cache Integrity**: Resource cache handles invalidation gracefully

### Recovery Strategies
- **One-for-One**: Most supervisors use this strategy for isolated failures
- **Temporary Processes**: MCP connections don't restart automatically (managed by ServerManager)
- **Permanent Processes**: Core services always restart on failure
- **Health Monitoring**: Proactive detection of unhealthy processes
- **Graceful Degradation**: Features can fail without crashing the app

## Implementation Status

### ✅ Completed
1. Health Monitoring System
2. Circuit Breaker for LLM APIs  
3. Chat Loop Supervision
4. Connection Pool Framework
5. Port Process Supervisor (created)
6. Startup Profiling
7. Memory Management with MessageStore
8. Lazy Loading for MCP Servers
9. Comprehensive Notification Handler
10. TUI Components (Progress, Cache Display)
11. Resource Caching with auto-invalidation

### 🚧 Integration Needed
1. **Port Supervisor Integration**
   - Update ExMCP to use PortSupervisor for stdio connections
   - Test port crash recovery

2. **Connection Pool Usage**
   - Integrate pools into HTTP-based adapters
   - Configure pools for different services

3. **Telemetry Dashboard**
   - Create monitoring UI or integrate with existing tools
   - Set up alerts for production use

## Supervision Benefits

- **Fault Isolation**: Component failures don't cascade
- **Automatic Recovery**: Most services self-heal
- **State Preservation**: Critical state survives crashes
- **Performance Monitoring**: Health checks prevent degradation
- **Graceful Degradation**: Non-critical features can fail safely
- **Resource Protection**: Memory and connection limits enforced
- **User Experience**: Chat sessions survive most failures