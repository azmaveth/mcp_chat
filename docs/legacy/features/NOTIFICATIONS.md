# MCP Notifications and Progress Tracking

MCP Chat now supports the advanced notification features introduced in ex_mcp v0.2.0, providing real-time updates and progress tracking for MCP server operations.

## Overview

The notification system enables:
- **Real-time updates** when server capabilities change
- **Progress tracking** for long-running operations
- **Change notifications** for resources, tools, and prompts
- **Server-side LLM generation** via the sampling API

## Enabling Notifications

Notifications are enabled by default when MCP Chat starts. You can control them with:

```bash
# Enable notifications
/mcp notify on

# Disable notifications
/mcp notify off

# Check notification status
/mcp notify status
```

## Progress Tracking

### For Tool Execution

Track progress of long-running tool operations:

```bash
# Execute a tool with progress tracking
/mcp tool server_name process_large_file path=/data/huge.csv --progress

# The UI will show a progress bar:
# 📊 [server_name] process_large_file: [██████████░░░░░░░░░░] 50% (500/1000)
```

### Viewing Active Operations

Check all currently running operations:

```bash
/mcp progress

# Output:
# Active Operations:
# ────────────────────────────────────────────────────
# 📊 filesystem/process_file (op-1-123)
#    Progress: [████████████████░░░░] 80%
#    Duration: 2m 15s
```

## Change Notifications

MCP Chat automatically responds to server capability changes:

### Resource Changes
- **List Changed**: Notifies when the available resources change
- **Resource Updated**: Notifies when a specific resource is modified

```
📋 Resources updated for server: filesystem
Use /mcp resources filesystem to see the updated list

📝 Resource updated: file:///config.yaml
```

### Tool Changes
Notifies when available tools are added, removed, or modified:

```
🔧 Tools updated for server: calculator
Use /mcp tools calculator to see the updated list
```

### Prompt Changes
Notifies when prompt templates are updated:

```
📄 Prompts updated for server: writing-assistant
Use /mcp prompts writing-assistant to see the updated list
```

## Server-Side LLM Generation

Use MCP servers that support the sampling API for text generation:

```bash
# Basic usage
/mcp sample server_name "Write a haiku about coding"

# With parameters
/mcp sample server_name "Explain quantum computing" --temperature 0.7 --max-tokens 500

# Specify a model preference
/mcp sample server_name "Generate code" --model claude-3-haiku
```

### Checking Sampling Support

View which servers support sampling:

```bash
/mcp capabilities

# Output shows sampling support:
# Server: writing-assistant
#   Tools: supported
#   Resources: supported
#   Prompts: supported
#   Sampling/LLM: supported ✨
```

## Notification Handlers

MCP Chat uses a modular handler system for processing notifications:

1. **ResourceChangeHandler** - Updates cached resource lists and alerts users
2. **ToolChangeHandler** - Refreshes tool lists when changes occur
3. **ProgressHandler** - Displays progress bars and tracks operations
4. **PromptChangeHandler** - Updates prompt template caches

## Architecture

### Notification Flow

```
MCP Server → Notification → NotificationRegistry → Handler → UI Update
                                ↓
                          Dispatch to registered handlers
```

### Key Components

- **NotificationRegistry**: Central dispatcher for all notifications
- **ProgressTracker**: Manages active operations and their progress
- **NotificationClient**: Extended MCP client with notification support
- **Handlers**: Modular processors for each notification type

## Configuration

### Runtime Settings

Configure notification behavior:

```elixir
# In config.toml
[notifications]
enabled = true
show_progress_bars = true
log_changes = true
```

### Per-Server Configuration

Some servers may send many notifications. You can filter them:

```elixir
# Future enhancement - not yet implemented
[notifications.filters]
"chatty-server" = ["progress"]  # Only show progress notifications
```

## Best Practices

1. **Progress Tokens**: When implementing MCP servers, use meaningful progress tokens that identify the operation

2. **Notification Frequency**: Servers should batch notifications to avoid overwhelming the client

3. **Resource Updates**: Use specific resource update notifications rather than list_changed when possible

4. **Error Handling**: The notification system is resilient - handler failures don't crash the client

## Troubleshooting

### Notifications Not Appearing

1. Check if notifications are enabled: `/mcp notify status`
2. Verify the server supports notifications: `/mcp capabilities server_name`
3. Check the logs for notification errors

### Progress Not Updating

1. Ensure the tool supports progress tracking
2. Use the `--progress` flag when calling tools
3. Check if the server is sending progress notifications

### Too Many Notifications

1. Disable notifications temporarily: `/mcp notify off`
2. Restart the problematic server connection
3. Report excessive notifications to the server maintainer

## Examples

### Complete Workflow Example

```bash
# 1. Check server capabilities
/mcp capabilities data-processor

# 2. Start a long operation with progress
/mcp tool data-processor analyze_dataset file=/data/sales.csv --progress

# 3. Monitor progress
/mcp progress

# 4. React to completion notification
# The system will notify when complete

# 5. Check if resources were updated
/mcp resources data-processor
```

### Multi-Server Coordination

```bash
# Server A generates data
/mcp sample ml-server "Generate test dataset" --max-tokens 1000

# Progress tracked automatically
# 📊 [ml-server] sampling: [████████████░░░░░░░░] 60%

# Server B processes the data (notified of new resource)
# 📋 Resources updated for server: ml-server

# Use the new resource
/mcp tool analyzer process_data source=ml-server:dataset
```

## Future Enhancements

- Notification filtering and routing
- Custom notification handlers via plugins
- Notification history and replay
- Cross-server notification correlation
- Webhook integration for external notifications