# Stdio Process Management in MCPChat

## Overview

The `MCPChat.MCP.StdioProcessManager` module provides robust management of MCP server OS processes for stdio transport. This module separates the concerns of process lifecycle management from the MCP protocol communication, following the proper MCP architecture where servers are external processes.

## Architecture

```
┌─────────────────────┐
│   ServerManager     │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│   ServerWrapper     │
└──────────┬──────────┘
           │
           ├─────────────────────────┐
           │                         │
┌──────────▼──────────┐   ┌─────────▼──────────┐
│ StdioProcessManager │   │ ExMCP.Client or    │
│ (Process Lifecycle) │   │ NotificationClient │
└──────────┬──────────┘   │ (MCP Protocol)     │
           │              └────────────────────┘
           │                         ▲
┌──────────▼──────────┐              │
│   OS Process        │◄─────────────┘
│   (MCP Server)      │    stdio
└─────────────────────┘
```

## Features

### Process Lifecycle Management
- **Start**: Spawns MCP server processes using Erlang's `Port`
- **Stop**: Gracefully terminates processes
- **Restart**: Manual and automatic restart capabilities
- **Monitor**: Tracks process health and exit status

### Automatic Restart
- Configurable maximum restart attempts
- Configurable restart delay
- Prevents restart loops for failing servers

### Environment Variables
- Pass custom environment variables to server processes
- Useful for configuration and debugging

### Command Parsing
- Supports various command formats:
  - String: `"echo hello"`
  - List: `["echo", "hello"]`
  - Command with args: `{command: "echo", args: ["hello"]}`

## Usage

### Direct Usage

```elixir
# Configuration
config = %{
  name: "my-mcp-server",
  command: "npx",
  args: ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/dir"],
  env: %{"DEBUG" => "true"}
}

# Start the process manager
{:ok, manager} = MCPChat.MCP.StdioProcessManager.start_link(config)

# Check status
{:ok, status} = MCPChat.MCP.StdioProcessManager.get_status(manager)
IO.inspect(status)
# => %{
#      status: :running,
#      os_pid: 12345,
#      start_time: ~U[2024-01-20 10:30:00Z],
#      restart_count: 0,
#      config: %{...}
#    }

# Restart the process
:ok = MCPChat.MCP.StdioProcessManager.restart_process(manager)

# Stop the process
:ok = MCPChat.MCP.StdioProcessManager.stop_process(manager)
```

### Through ServerManager (Recommended)

```elixir
# The ServerManager automatically uses StdioProcessManager for stdio transport
config = %{
  name: "my-mcp-server",
  command: "npx",
  args: ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/dir"]
}

# Start server (StdioProcessManager is used internally)
{:ok, _pid} = MCPChat.MCP.ServerManager.start_server(config)

# Use the server normally
{:ok, tools} = MCPChat.MCP.ServerManager.get_tools("my-mcp-server")

# Stop server (also stops the OS process)
:ok = MCPChat.MCP.ServerManager.stop_server("my-mcp-server")
```

## Configuration Options

### Process Manager Options

```elixir
MCPChat.MCP.StdioProcessManager.start_link(config, opts)
```

Options:
- `:max_restarts` - Maximum number of automatic restart attempts (default: 3)
- `:restart_delay` - Delay in milliseconds between restart attempts (default: 1000)

### Server Configuration

```elixir
%{
  name: String.t(),           # Required: Server name
  command: String.t() | list(), # Required: Command to execute
  args: list(),               # Optional: Command arguments
  env: map()                  # Optional: Environment variables
}
```

## Error Handling

### Process Failures

When a process exits unexpectedly:
1. The `StdioProcessManager` detects the exit via port monitoring
2. If within restart limits, attempts automatic restart
3. If restart limit exceeded, marks process as stopped
4. The `ServerWrapper` is notified and can take appropriate action

### Start Failures

If a process fails to start:
- The error is logged
- The `start_link` call returns `{:error, reason}`
- No retries are attempted for start failures

## Best Practices

1. **Use ServerManager**: For most use cases, use `ServerManager.start_server/1` rather than managing `StdioProcessManager` directly.

2. **Configure Restart Limits**: Set appropriate `max_restarts` based on your server's stability:
   ```elixir
   # For stable servers
   opts = [max_restarts: 3, restart_delay: 1000]
   
   # For experimental servers
   opts = [max_restarts: 0]  # No automatic restarts
   ```

3. **Monitor Process Health**: Use `get_status/1` to monitor process health and restart counts.

4. **Handle Environment Variables**: Pass necessary configuration via environment variables:
   ```elixir
   config = %{
     name: "my-server",
     command: "my-mcp-server",
     env: %{
       "MCP_LOG_LEVEL" => "debug",
       "MCP_PORT" => "0",  # Use stdio
       "MCP_CONFIG" => "/path/to/config.json"
     }
   }
   ```

5. **Graceful Shutdown**: Always stop servers properly to ensure clean process termination:
   ```elixir
   # Through ServerManager
   :ok = ServerManager.stop_server("my-server")
   
   # Or directly
   :ok = StdioProcessManager.stop_process(manager)
   ```

## Troubleshooting

### Process Won't Start
- Check the command exists and is executable
- Verify the command path is absolute or in PATH
- Check file permissions
- Review logs for startup errors

### Process Keeps Crashing
- Check server logs (often written to stderr)
- Verify environment variables are set correctly
- Test the command manually in a terminal
- Consider disabling auto-restart during debugging

### Communication Issues
- Ensure the MCP server supports stdio transport
- Check that the server follows the MCP protocol
- Verify the server is actually running (`get_status/1`)
- Check for buffering issues in the server implementation

## Examples

See `examples/stdio_server_example.exs` for complete working examples.