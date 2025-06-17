# CLI Agent Architecture Integration

This document describes how the CLI has been refactored to use the new agent architecture, enabling real-time progress updates and asynchronous operations.

## Overview

The refactoring introduces several new components that bridge the existing CLI with the agent architecture:

1. **Event Subscriber** - Receives real-time updates via Phoenix.PubSub
2. **Agent Bridge** - Manages session mapping between CLI and agents
3. **Refactored Commands** - Route operations through the Gateway API
4. **Progress Indicators** - Show real-time status for long-running operations

## Key Components

### 1. CLI Event Subscriber (`lib/mcp_chat/cli/event_subscriber.ex`)

Subscribes to Phoenix.PubSub events and displays real-time updates:

- Tool execution progress
- Export progress
- Agent pool status
- Operation completion/failure notifications

```elixir
# Subscribe to a session
EventSubscriber.subscribe_to_session(session_id)

# Set UI mode
EventSubscriber.set_ui_mode(session_id, :interactive)
```

### 2. Agent Bridge (`lib/mcp_chat/cli/agent_bridge.ex`)

Provides compatibility layer for gradual migration:

- Maps CLI sessions to agent sessions
- Routes tool executions through agents
- Handles async operation tracking

```elixir
# Execute tool asynchronously
AgentBridge.execute_tool_async(tool_name, args, opts)

# Export with progress
AgentBridge.export_session_async(format, options)
```

### 3. Refactored Chat Module (`lib/mcp_chat/cli/chat_refactored.ex`)

Demonstrates how to use Gateway API:

- Creates sessions through Gateway
- Sends messages via agents
- Receives responses through PubSub

### 4. Integration Examples

#### Tool Execution with Progress

```elixir
# Old synchronous way
ServerManager.call_tool(server, tool, args)

# New async way with progress
case Gateway.execute_tool(session_id, tool, args) do
  {:ok, :async, %{execution_id: id}} ->
    # Progress updates come via PubSub
    # UI updates automatically
  {:ok, result} ->
    # Fast tool, synchronous result
end
```

#### Export with Real-time Updates

```elixir
# Request export
case Gateway.request_export(session_id, "pdf", options) do
  {:ok, %{export_id: id}} ->
    # Progress events:
    # - ExportStarted
    # - ExportProgress (with percentage)
    # - ExportCompleted (with file path)
end
```

## Migration Strategy

### Phase 1: Add Infrastructure (Completed)
- ✅ Event subscriber for PubSub updates
- ✅ Agent bridge for session management
- ✅ Progress display components

### Phase 2: Gradual Command Migration
- Start with heavy operations (tools, exports)
- Add async support to existing commands
- Maintain backward compatibility

### Phase 3: Full Integration
- Route all operations through agents
- Remove direct GenServer calls
- Unified async/progress handling

## Usage Examples

### 1. Running MCP Tools with Progress

```bash
# Execute a long-running tool
/mcp tool github analyze_repository repo:elixir-lang/elixir

# Output:
🔧 Starting tool execution: analyze_repository
   Parameters: repo=elixir-lang/elixir
🔧 Progress: [======              ] 30% - Analyzing commits...
✅ Tool completed: analyze_repository (45.2s)
```

### 2. Export with Progress Tracking

```bash
# Export session to PDF
/export pdf report.pdf

# Output:
📦 Starting export to pdf format...
📦 Export progress: [==========          ] 50% - Generating pages
✅ Export completed: pdf format (12.3s)
   Saved to: report.pdf
```

### 3. Monitoring Active Operations

```bash
# Check status of running operations
/mcp status

# Output:
Agent Pool Status:
  Active workers: 2/3
  Queued tasks: 1

Active operations:
  Tool execution (subagent_123_abc): running for 15.2s
  Export (subagent_456_def): running for 8.7s
```

## Benefits

1. **Real-time Feedback**: Users see progress for long operations
2. **Non-blocking**: CLI remains responsive during heavy tasks
3. **Resource Management**: Agent pool prevents overload
4. **Cancellation**: Can cancel long-running operations
5. **Better UX**: Clear indication of what's happening

## Technical Details

### Event Flow

1. CLI sends command → Gateway
2. Gateway routes to appropriate agent
3. Agent broadcasts events via PubSub
4. Event subscriber updates UI in real-time
5. Completion/failure events finalize operation

### Session Management

- Each CLI instance gets an agent session
- Sessions are mapped via ETS table
- Automatic cleanup on exit
- Supports multiple concurrent operations

### Progress Rendering

- ASCII progress bars for terminal
- Throttled updates (100ms minimum)
- Carriage return for in-place updates
- Clear status messages

## Future Enhancements

1. **Batch Operations**: Queue multiple tools/exports
2. **Priority Handling**: Urgent vs background tasks
3. **Resource Limits**: Per-session quotas
4. **Progress Persistence**: Resume interrupted operations
5. **Rich UI**: TUI with panels for active operations

## Testing

The refactored components include:

- Unit tests for event handling
- Integration tests for agent communication
- Mock PubSub for testing progress updates
- Simulated long-running operations

## Conclusion

This refactoring provides a foundation for more sophisticated CLI features while maintaining compatibility with existing code. The agent architecture enables better resource management, real-time feedback, and a more responsive user experience.