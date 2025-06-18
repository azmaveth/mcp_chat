# Multi-Interface Architecture

## Overview

MCP Chat supports multiple interfaces connecting to the same agent sessions simultaneously:

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│                 │     │                 │     │                 │
│   CLI Client    │     │  Web Browser    │     │   Mobile Web    │
│   (Terminal)    │     │  (Phoenix UI)   │     │    (Phone)      │
│                 │     │                 │     │                 │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         │                       │                       │
         └───────────────┬───────┴───────────────────────┘
                         │
                         │ Phoenix.PubSub
                         │ Real-time Events
                         ▼
         ┌───────────────────────────────────┐
         │                                   │
         │         Gateway API               │
         │   (Stateless Abstraction Layer)   │
         │                                   │
         └───────────────┬───────────────────┘
                         │
         ┌───────────────┴───────────────────┐
         │                                   │
         │      OTP Supervision Tree         │
         │                                   │
         │  ┌─────────────┐ ┌─────────────┐ │
         │  │   Agent     │ │   Session   │ │
         │  │ Supervisor  │ │  Manager    │ │
         │  └──────┬──────┘ └──────┬──────┘ │
         │         │               │        │
         │  ┌──────┴──────┐ ┌──────┴──────┐ │
         │  │  LLM Agent  │ │  MCP Agent  │ │
         │  │  (GPT-4)    │ │ (Tools)     │ │
         │  └─────────────┘ └─────────────┘ │
         │                                   │
         └───────────────────────────────────┘
                         │
         ┌───────────────┴───────────────────┐
         │                                   │
         │    Multi-Tiered State Storage     │
         │                                   │
         │  ┌─────────────┐ ┌─────────────┐ │
         │  │  Hot Tier   │ │  Warm Tier  │ │
         │  │   (ETS)     │ │ (Event Log) │ │
         │  └─────────────┘ └─────────────┘ │
         │         ┌─────────────┐          │
         │         │  Cold Tier  │          │
         │         │ (Snapshots) │          │
         │         └─────────────┘          │
         └───────────────────────────────────┘
```

## Key Components

### 1. Multiple Interface Types

- **CLI Client**: Terminal-based interface with rich command support
- **Web Browser**: Phoenix LiveView dashboard with real-time updates
- **Mobile Web**: Responsive web interface for monitoring on the go
- **API Access**: RESTful endpoints for programmatic access

### 2. Real-time Communication

- **Phoenix.PubSub**: Broadcasts events to all connected clients
- **WebSocket**: Persistent connections for instant updates
- **Event Streams**: Tool execution, progress updates, state changes

### 3. Gateway API

Provides a stateless abstraction over OTP internals:
- Session management
- Agent control
- State queries
- Command execution

### 4. Agent Architecture

- **Agent Supervisor**: Manages agent lifecycle
- **Session Manager**: Tracks active sessions
- **LLM Agents**: Handle AI interactions
- **MCP Agents**: Execute tools and integrations

### 5. State Persistence

Three-tier storage strategy:
- **Hot Tier (ETS)**: In-memory for fast access
- **Warm Tier (Event Log)**: Recent events for recovery
- **Cold Tier (Snapshots)**: Long-term storage

## Usage Scenarios

### Solo Developer Workflow
```
1. Start task in CLI
2. Monitor progress on web dashboard
3. Close laptop (CLI disconnects)
4. Check status from phone browser
5. Reconnect CLI at home to see results
```

### Team Collaboration
```
1. Developer A creates session via web
2. Developer B joins via CLI
3. Both see real-time message sync
4. Developer C monitors via dashboard
5. All three collaborate seamlessly
```

### Automation & Monitoring
```
1. CI/CD starts session via API
2. Team monitors via web dashboard
3. Alerts sent on completion
4. Results accessible from any interface
```

## Benefits

1. **Flexibility**: Choose the best interface for each task
2. **Reliability**: Agents persist through interface disconnections
3. **Collaboration**: Multiple users on same session
4. **Accessibility**: Monitor from anywhere with web access
5. **Integration**: API access for automation

## Implementation Details

See the following files for implementation:
- `lib/mcp_chat_web/` - Phoenix web interface
- `lib/mcp_chat/gateway.ex` - Gateway API
- `lib/mcp_chat/agents/` - Agent implementations
- `lib/mcp_chat/cli/` - CLI interface
- `docs/architecture/` - Detailed design docs