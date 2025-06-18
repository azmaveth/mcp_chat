# CLI/Agent Detach and Reattach Example with Web Dashboard

This example demonstrates one of MCP Chat's most powerful features: the ability to start long-running tasks via the CLI, disconnect the CLI safely, and reconnect later to see the results - all while monitoring everything through a real-time web dashboard.

## Overview

MCP Chat uses a sophisticated agent-based architecture where:
- **Agents** persist independently and can work in the background
- **CLI** can connect/disconnect without affecting agent operation  
- **Web Dashboard** provides real-time monitoring and control
- **Sessions** are preserved across CLI disconnections
- **State** is maintained in multiple storage tiers for reliability
- **Multiple Interfaces** can connect to the same session simultaneously

## Files in This Example

- `cli_agent_detach_demo.exs` - Interactive demo showing the workflow concepts
- `cli_agent_detach_with_web_demo.exs` - Enhanced demo with web dashboard integration
- `detach_reattach_workflow.sh` - Shell script demonstrating the complete workflow
- `detach_reattach_with_web_workflow.sh` - Enhanced workflow with web UI integration
- `CLI_AGENT_DETACH_README.md` - This documentation file

## Quick Start

### 1. Run the Conceptual Demo

```bash
# Show the workflow concepts and architecture
elixir examples/cli_agent_detach_demo.exs

# Or with web dashboard integration
elixir examples/cli_agent_detach_with_web_demo.exs
```

### 2. Run the Workflow Simulation

```bash
# Simulate the complete detach/reattach process
./examples/detach_reattach_workflow.sh

# Or with web dashboard monitoring
./examples/detach_reattach_with_web_workflow.sh
```

### 3. Try it Live with Web Dashboard

```bash
# Start MCP Chat with web server
iex -S mix

# In another terminal/browser:
# Open http://localhost:4000

# In IEx, start the CLI:
MCPChat.main()
```

### 4. Try CLI-Only Mode

```bash
# Build MCP Chat first
mix escript.build

# Start a session
./mcp_chat

# Run a long task (in MCP Chat):
/mcp tool analyze_repository repo:my-project

# Disconnect CLI with Ctrl+C (agent continues)

# Reconnect to see results
./mcp_chat -c
```

## Web Dashboard Features

The Phoenix-powered web dashboard provides comprehensive monitoring and control:

### Dashboard Overview (http://localhost:4000)
- **System Statistics**: Real-time memory usage, uptime, active sessions
- **Agent Status**: Live view of all running agents with health indicators
- **Quick Actions**: Create sessions, monitor agents, view recent activity

### Agent Monitor (http://localhost:4000/agents)
- **Live Status Updates**: Real-time agent state changes via Phoenix.PubSub
- **Performance Metrics**: Memory usage, message processing, error rates
- **Control Actions**: Start, stop, restart agents from the web
- **Detailed Inspection**: Click any agent for logs, metrics, and configuration

### Chat Interface (http://localhost:4000/sessions/:id/chat)
- **Full CLI Parity**: Execute all commands available in CLI
- **Real-time Streaming**: See responses as they're generated
- **Multi-User Support**: Multiple people can join the same session
- **Rich UI**: Better formatting, syntax highlighting, progress indicators

### Session Management (http://localhost:4000/sessions)
- **Create/Delete Sessions**: Full session lifecycle management
- **Archive/Restore**: Preserve important sessions for later
- **Session Details**: View metadata, statistics, and configuration
- **Quick Access**: Jump directly to any session's chat interface

## Detailed Workflow

### Step 1: Start Agent Session

```bash
$ ./mcp_chat
🚀 MCP Chat starting...
📊 Loading configuration...
🤖 Creating agent session (ID: session_2024_abc123)
✅ Ready for commands
```

The CLI creates an agent session that runs independently in the OTP supervision tree.

### Step 2: Start Long-Running Task

```
User> /mcp tool analyze_large_repository repo:my-project
Agent> 🔍 Starting repository analysis...
Agent> 📂 Scanning 15,000 files...
Agent> ⏱️  Estimated time: 10 minutes
Agent> 📊 Progress: [██░░░░░░░░░░░░░░░░░░] 10%
```

The agent spawns a subagent to handle the heavy work while maintaining the main session.

### Step 3: Disconnect CLI

Press `Ctrl+C` or close the terminal. The CLI terminates but:
- Agent session remains active in OTP supervision
- Background task continues uninterrupted  
- Session state is persisted to storage
- Progress continues to be tracked

### Step 4: Agent Background Work

While disconnected, the agent:
- Continues processing the repository analysis
- Updates progress tracking
- Accumulates results in session state
- Broadcasts events (no CLI to receive them)
- Periodically saves state to persistent storage

### Step 5: Reconnect CLI

```bash
$ ./mcp_chat -c  # Continue most recent session
🚀 MCP Chat reconnecting...
✅ Found session: session_2024_abc123
🔗 Reconnecting to agent...
📜 Loading conversation history...
✅ CLI reconnected successfully!

Agent> 🎉 Welcome back! Analysis completed while you were away.
Agent> 📊 Repository analysis finished successfully.
```

The new CLI instance:
- Discovers the existing agent session
- Subscribes to PubSub events for real-time updates
- Retrieves full session state and conversation history
- Displays any work completed while disconnected

### Web Dashboard During Workflow

Throughout this entire process, the web dashboard at http://localhost:4000 shows:

1. **During Task Start**: Agent status changes to "active", progress bar appears
2. **During CLI Disconnect**: Agent remains green/active, CLI indicator shows "disconnected"
3. **During Background Work**: Real-time progress updates, log streaming, metrics
4. **During Reconnect**: CLI indicator returns to "connected", sync activity visible

## Multi-Interface Scenarios

### Scenario 1: Team Collaboration
```bash
# Developer A starts code review in CLI
./mcp_chat
> /mcp tool review_pr pr:123

# Developer B monitors progress via web
# http://localhost:4000/sessions/session_123/chat

# Developer B adds context via web chat
# "Focus on security implications in auth module"

# Developer A sees message instantly in CLI
```

### Scenario 2: Mobile Monitoring
```bash
# Start long analysis on workstation
./mcp_chat
> /analyze large_dataset --deep

# Monitor from phone browser
# http://your-ip:4000/agents

# Stop generation from phone if needed
# Click "Stop" button in web UI
```

### Scenario 3: Distributed Team
```bash
# Remote team member starts via web
# Creates session at http://localhost:4000/sessions

# Local developer connects CLI
./mcp_chat -r session_from_web

# Both collaborate in real-time
# Messages, files, and state sync instantly
```

## Session Management Commands

### CLI Arguments
- `./mcp_chat` - Start new session or resume recent
- `./mcp_chat -l` - List all active agent sessions  
- `./mcp_chat -r <session_id>` - Resume specific session
- `./mcp_chat -c` - Continue most recent session
- `./mcp_chat -k <session_id>` - Terminate specific session

### In-Chat Commands
- `/session save <name>` - Save current session with name
- `/session list` - List all saved sessions
- `/session load <name>` - Load a saved session
- `/session info` - Show current session details

## Architecture Details

### Agent Persistence
- **OTP Supervision**: Agents run in supervised processes
- **Session Registry**: Central registry tracks all active sessions
- **State Management**: Multi-tiered storage (Hot/Warm/Cold)
- **Fault Tolerance**: Automatic restart on failures

### CLI/Agent Communication  
- **Gateway API**: Stateless API layer abstracts OTP internals
- **Agent Bridge**: Maps CLI sessions to agent sessions
- **Event System**: Real-time updates via Phoenix.PubSub
- **State Sync**: Full session state retrieval on reconnect

### Storage Tiers
- **Hot Tier (ETS)**: Complete session state in memory
- **Warm Tier (Event Log)**: Critical events journaled
- **Cold Tier (Snapshots)**: Periodic full state snapshots

## Use Cases

### 1. Long-Running Analysis
```bash
# Start analysis
./mcp_chat
> /mcp tool analyze_large_codebase

# Disconnect, close laptop
Ctrl+C

# Hours later, reconnect to see results  
./mcp_chat -c
```

### 2. Distributed Development
```bash
# Team member A starts code review
./mcp_chat
> /mcp tool review_pull_request pr:123

# Pass session ID to team member B
./mcp_chat -l  # Get session ID

# Team member B joins same session
./mcp_chat -r session_abc123
```

### 3. Resilient Workflows
```bash
# Start complex task
./mcp_chat
> /mcp tool multi_step_analysis

# Network interruption disconnects CLI
# Agent continues work unaffected

# CLI auto-reconnects when network returns
./mcp_chat -c
```

### 4. Background Processing
```bash
# Queue multiple tasks
./mcp_chat
> /mcp tool process_dataset_1
> /mcp tool process_dataset_2  
> /mcp tool process_dataset_3

# Disconnect and let them run
Ctrl+C

# Check progress periodically
./mcp_chat -c
```

## Implementation Files

Key files in the MCP Chat codebase that enable this functionality:

- `lib/mcp_chat/cli/agent_bridge.ex` - CLI/Agent session mapping
- `lib/mcp_chat/agents/session_manager.ex` - Session lifecycle management  
- `lib/mcp_chat/gateway.ex` - Stateless API over OTP internals
- `lib/mcp_chat/cli/event_subscriber.ex` - Real-time event handling
- `docs/architecture/STATE_PERSISTENCE_DESIGN.md` - Storage architecture

## Troubleshooting

### Session Not Found
```bash
# List active sessions to verify
./mcp_chat -l

# Check if session expired or was terminated
# Sessions auto-expire after configurable timeout
```

### Agent Not Responding
```bash
# Check system logs for OTP supervisor restarts
# Agent may have crashed and restarted, losing state

# Verify ETS storage and persistence layer
```

### CLI Connection Issues
```bash
# Verify PubSub subscription
# Check network connectivity for distributed setups
# Ensure proper permissions for socket files
```

## Configuration

Configure session behavior in `~/.config/mcp_chat/config.toml`:

```toml
[session]
# Session auto-save interval
auto_save_interval_ms = 30000

# Session expiration timeout  
idle_timeout_ms = 3600000  # 1 hour

# Maximum concurrent sessions per user
max_sessions = 10

[storage]
# Enable persistent storage
persistence_enabled = true

# Storage location
data_dir = "~/.local/share/mcp_chat"

# Snapshot frequency
snapshot_interval_ms = 300000  # 5 minutes
```

## Advanced Features

### Session Sharing
```bash
# Export session for sharing
./mcp_chat -r session_123
> /session export session_123.json

# Import on another machine
./mcp_chat
> /session import session_123.json
```

### Monitoring
```bash
# Watch session activity
./mcp_chat -l --watch

# Get detailed session info
./mcp_chat -r session_123
> /session info --verbose
```

### Automation
```bash
# Script session management
#!/bin/bash
SESSION_ID=$(./mcp_chat -l --format=json | jq -r '.[0].id')
./mcp_chat -r "$SESSION_ID" --batch < commands.txt
```

This architecture makes MCP Chat uniquely suited for long-running tasks, collaborative workflows, and resilient operation in distributed environments.