# Migrating from MCP Chat to Arbor

This guide helps you transition from MCP Chat to Arbor, the next-generation distributed agent orchestration system.

## Overview

Arbor evolved from MCP Chat to address production scalability, distributed operations, and enterprise security requirements. While maintaining the core conversational AI capabilities, Arbor introduces:

- **Distributed Architecture**: Multi-node deployment with automatic failover
- **Capability-Based Security**: Fine-grained permission model
- **Event-Driven Design**: Asynchronous operations with real-time updates
- **Production Observability**: Comprehensive monitoring and tracing

## Key Concept Mappings

| MCP Chat Concept | Arbor Equivalent | Key Differences |
|------------------|------------------|-----------------|
| `MCPChat.Session` | Coordinator Agent | Distributed, fault-tolerant, event-sourced |
| Direct tool execution | Worker Agents | Isolated processes with capability constraints |
| Session state | Event-sourced persistence | Recoverable with full audit trail |
| Simple permissions | Capability delegation | Fine-grained, delegatable permissions |
| Single-node | Horde cluster | Multi-node with automatic failover |
| UI-coupled logic | Gateway abstraction | Multi-client support (CLI, Web, API) |

## Architecture Changes

### From Session-Based to Agent-Based

**MCP Chat**:
```elixir
defmodule MCPChat.Session do
  def handle_message(message, state) do
    # Direct processing in session
    result = execute_tool(message.tool, message.args)
    {:reply, result, state}
  end
end
```

**Arbor**:
```elixir
defmodule Arbor.Core.CoordinatorAgent do
  def handle_message(message, state) do
    # Spawn worker agent with constrained capabilities
    {:ok, worker_id} = spawn_worker_agent(message.tool, message.args)
    # Async execution with progress tracking
    {:reply, {:async, execution_id}, state}
  end
end
```

### From Direct Calls to Event-Driven

**MCP Chat**:
```elixir
# Synchronous, blocking
{:ok, result} = MCPChat.execute_command(command)
```

**Arbor**:
```elixir
# Asynchronous, non-blocking
{:ok, execution_id} = Arbor.Core.Gateway.execute_command(session_id, command)
# Subscribe to progress events
Phoenix.PubSub.subscribe("execution:#{execution_id}")
```

## Configuration Migration

### Environment Variables

| MCP Chat | Arbor | Notes |
|----------|-------|-------|
| `MCP_DATA_DIR` | `ARBOR_DATA_DIR` | Data directory location |
| `MCP_LOG_LEVEL` | `ARBOR_LOG_LEVEL` | Logging configuration |
| N/A | `ARBOR_NODE_NAME` | New: Erlang node name for clustering |
| N/A | `ARBOR_COOKIE` | New: Erlang distribution cookie |

### Configuration File Changes

**MCP Chat** (`config.toml`):
```toml
[llm]
default_backend = "anthropic"

[mcp.servers]
filesystem = { command = "mcp-server-filesystem" }
```

**Arbor** (`config/config.exs`):
```elixir
config :arbor_core,
  llm_provider: Arbor.LLM.Anthropic,
  
config :arbor_core, :mcp_servers,
  filesystem: %{
    command: "mcp-server-filesystem",
    capabilities: [:read_files, :write_files]
  }
```

## API Migration

### Client Initialization

**MCP Chat**:
```elixir
{:ok, session} = MCPChat.start_session()
MCPChat.send_message(session, message)
```

**Arbor**:
```elixir
{:ok, session_id} = Arbor.Core.Gateway.create_session(client_id)
{:ok, execution_id} = Arbor.Core.Gateway.send_message(session_id, message)
```

### Tool Execution

**MCP Chat**:
```elixir
# Tools executed directly in session context
result = session.execute_tool("read_file", %{path: "/tmp/file.txt"})
```

**Arbor**:
```elixir
# Tools executed by worker agents with capabilities
{:ok, capability} = Arbor.Security.grant_capability(agent_id, %{
  resource_uri: "file:///tmp/file.txt",
  operation: :read
})
{:ok, execution_id} = Arbor.Core.execute_tool(agent_id, "read_file", args)
```

## Security Model Changes

### Capability-Based Permissions

Arbor introduces fine-grained capabilities that must be explicitly granted:

```elixir
# Define required capabilities
capabilities = [
  %{resource_uri: "file:///home/*", operation: :read},
  %{resource_uri: "http://api.example.com/*", operation: :call},
  %{resource_uri: "llm://anthropic/*", operation: :query}
]

# Grant capabilities to agent
{:ok, granted} = Arbor.Security.grant_capabilities(agent_id, capabilities)
```

### Audit Trail

All operations are now audited:

```elixir
# Query audit log
{:ok, events} = Arbor.Security.query_audit_log(%{
  agent_id: agent_id,
  time_range: {~U[2025-06-01 00:00:00Z], ~U[2025-06-19 23:59:59Z]},
  event_types: [:capability_granted, :resource_accessed]
})
```

## Deployment Changes

### Single Node to Cluster

**MCP Chat** (single node):
```bash
mix run --no-halt
```

**Arbor** (cluster-ready):
```bash
# Node 1
ARBOR_NODE_NAME=arbor1@host1 mix run --no-halt

# Node 2
ARBOR_NODE_NAME=arbor2@host2 mix run --no-halt

# Nodes auto-discover and form cluster
```

### Monitoring Integration

Arbor includes built-in observability:

```elixir
# Prometheus metrics endpoint
GET /metrics

# Health check endpoint
GET /health

# Distributed tracing with OpenTelemetry
config :opentelemetry,
  processors: [
    otel_batch_processor: %{
      exporter: {:opentelemetry_exporter, %{endpoints: ["http://jaeger:14250"]}}
    }
  ]
```

## Data Migration

### Session State Migration

Use the provided migration tool to convert MCP Chat sessions to Arbor format:

```bash
mix arbor.migrate.sessions --source /path/to/mcp_chat/data --target /path/to/arbor/data
```

### Configuration Migration

```bash
mix arbor.migrate.config --input config.toml --output config/runtime.exs
```

## Breaking Changes

### Removed Features
- Direct session manipulation (replaced by event-driven API)
- Synchronous tool execution (all operations now async)
- Global state access (replaced by capability-constrained access)

### Changed Behaviors
- All operations return execution IDs instead of direct results
- Progress tracking via PubSub instead of callbacks
- Structured audit logging for all security-relevant operations

## Migration Checklist

- [ ] Update environment variables from `MCP_*` to `ARBOR_*`
- [ ] Migrate configuration from TOML to Elixir config
- [ ] Update client code to use async Gateway API
- [ ] Implement event handlers for progress tracking
- [ ] Define and grant necessary capabilities
- [ ] Set up monitoring and observability
- [ ] Test in single-node mode before enabling clustering
- [ ] Migrate existing session data
- [ ] Update deployment scripts for multi-node operation

## Getting Help

- Review the [Architecture Overview](../arbor/01-overview/architecture-overview.md)
- See [Implementation Guide](../arbor/07-implementation/getting-started.md)
- Check [API Reference](../arbor/08-reference/api-reference.md)

For specific migration issues, please open an issue with the `migration` label.