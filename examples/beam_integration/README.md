# BEAM Integration Example

This example demonstrates how to integrate MCP Chat with other BEAM processes using Erlang message passing.

## Overview

The BEAM VM allows processes to communicate via message passing. This example shows:

1. Creating a GenServer that acts as an MCP Chat client
2. Sending queries to MCP Chat from other processes
3. Receiving responses asynchronously
4. Building a multi-agent system with BEAM processes

## Running the Example

```bash
# Start the supervised agent system
cd examples/beam_integration
iex -S mix run agent_system.exs

# In another terminal, connect a client
iex -S mix run client.exs
```

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Agent Client   │────▶│  Agent Server   │────▶│    MCP Chat     │
│   (GenServer)   │◀────│   (GenServer)   │◀────│    Instance     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                        │
        │                        │
        ▼                        ▼
┌─────────────────┐     ┌─────────────────┐
│  Other BEAM     │     │   Supervisor    │
│   Processes     │     │                 │
└─────────────────┘     └─────────────────┘
```

## Key Features

- **Async Communication**: Send queries without blocking
- **Supervision**: Automatic restart on failures
- **Multi-Agent**: Multiple agents can collaborate
- **Event Broadcasting**: Agents can notify each other
- **State Sharing**: Agents can share context