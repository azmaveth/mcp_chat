# MCP Servers Guide

This comprehensive guide covers both using MCP Chat as a client to connect to MCP servers, and running MCP Chat as an MCP server itself.

## Table of Contents

1. [Overview](#overview)
2. [MCP Client Features](#mcp-client-features)
3. [MCP Server Mode](#mcp-server-mode)
4. [Available MCP Servers](#available-mcp-servers)
5. [Configuration](#configuration)
6. [Usage](#usage)
7. [Creating Custom Servers](#creating-custom-mcp-servers)
8. [Troubleshooting](#troubleshooting)

## Overview

### What are MCP Servers?

MCP servers provide tools, resources, and prompts that enhance your chat experience by giving the LLM access to external capabilities like:
- File system access
- Database queries
- API integrations
- Code execution
- Browser automation
- And much more

### MCP Chat Dual Functionality

MCP Chat can function as both:
1. **MCP Client** - Connect to and use other MCP servers
2. **MCP Server** - Expose chat functionality to other MCP clients

## MCP Client Features

MCP Chat includes a full-featured MCP client that can connect to any MCP server:

- **Tool Discovery & Execution**: Automatically discover and execute tools from connected MCP servers
- **Resource Management**: List and read resources exposed by MCP servers
- **Prompt Templates**: Access and use prompt templates from MCP servers
- **Multiple Transports**: Support for both stdio (local) and SSE (remote) MCP servers
- **Synchronous Operations**: Request/response correlation for reliable tool execution
- **Auto-reconnect**: Persistent server connections that reconnect on startup

## MCP Server Mode

When running as an MCP server, MCP Chat provides:

### Tools
- `chat` - Send a message to the AI chat and get a response
- `new_session` - Start a new chat session
- `get_history` - Retrieve chat history
- `clear_history` - Clear the current chat history

### Resources
- `chat://history` - Access to the current chat history
- `chat://session` - Information about the current session

### Prompts
- `chat` - Start an interactive chat session
- `summarize` - Summarize the current conversation
- `analyze` - Analyze the conversation for insights

## Available MCP Servers

### Official Servers

1. **Filesystem Server**
   - Read/write files
   - List directories
   - Search files
   ```bash
   npm install -g @modelcontextprotocol/server-filesystem
   ```

2. **GitHub Server**
   - Search repositories
   - Read files from repos
   - Access issues and PRs
   ```bash
   npm install -g @modelcontextprotocol/server-github
   ```

3. **GitLab Server**
   - Similar to GitHub server for GitLab
   ```bash
   npm install -g @modelcontextprotocol/server-gitlab
   ```

4. **PostgreSQL Server**
   - Query PostgreSQL databases
   - Execute SQL commands
   ```bash
   npm install -g @modelcontextprotocol/server-postgres
   ```

5. **Puppeteer Server**
   - Web scraping
   - Browser automation
   ```bash
   npm install -g @modelcontextprotocol/server-puppeteer
   ```

### Community Servers

Check the MCP registry for community-contributed servers:
- Time/date utilities
- Weather information
- Cryptocurrency data
- Custom integrations

## Configuration

### Transport Types

MCP Chat supports two transport types for connecting to servers:

#### Stdio Transport (Local Servers)
For local MCP servers that communicate via standard input/output:
```toml
[[mcp.servers]]
name = "filesystem"
command = ["npx", "-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
```

#### SSE Transport (Remote Servers)
For remote MCP servers accessible via HTTP/Server-Sent Events:
```toml
[[mcp.servers]]
name = "remote-tools"
url = "http://example.com:8080"
```

When connecting to an SSE server, MCP Chat:
1. Establishes an SSE connection to `{url}/sse` for receiving events
2. Sends JSON-RPC messages to `{url}/message` via HTTP POST
3. Maintains the connection with automatic reconnection on failure

### Running MCP Chat as a Server

Configure server mode in `config.toml`:

```toml
[mcp_server]
# Enable stdio server (for use with other MCP clients via stdio)
stdio_enabled = true

# Enable SSE server (for use with other MCP clients via HTTP/SSE)
sse_enabled = true
sse_port = 8080
```

To run as an stdio MCP server:
```bash
./mcp_server
```

Or configure it in another MCP client:
```json
{
  "mcpServers": {
    "mcp-chat": {
      "command": "/path/to/mcp_chat/mcp_server"
    }
  }
}
```

## Quick Setup

### Automatic Discovery

The easiest way to set up MCP servers:

```
# In MCP Chat
/discover
```

This will:
1. Scan for installed MCP servers
2. Check common npm packages
3. Offer quick setup options

### Manual Configuration

Add servers to your `~/.config/mcp_chat/config.toml`:

```toml
[mcp]
servers = [
  {
    name = "filesystem",
    command = ["npx", "-y", "@modelcontextprotocol/server-filesystem", "/home/user"],
    description = "Local file access"
  },
  {
    name = "github",
    command = ["npx", "-y", "@modelcontextprotocol/server-github"],
    env = { GITHUB_TOKEN = "ghp_xxxxxxxxxxxx" },
    description = "GitHub integration"
  }
]
```

## Usage

### Connecting to Servers

1. List available servers:
   ```
   /servers
   ```

2. List saved server connections:
   ```
   /saved
   ```

3. Connect to a server:
   ```
   /connect filesystem
   ```
   Servers are automatically saved and will reconnect on startup.

4. Disconnect when done:
   ```
   /disconnect filesystem
   ```
   This also removes the server from auto-reconnect list.

### Using Tools

1. List available tools:
   ```
   /tools filesystem
   ```

2. Execute a tool:
   ```
   /tool filesystem read_file path=/home/user/document.txt
   ```

3. Tools can also be invoked automatically during conversation:
   ```
   You: Can you read the contents of /tmp/config.json?
   Assistant: I'll read that file for you...
   [Automatically executes filesystem read_file tool]
   ```

### Accessing Resources

1. List resources:
   ```
   /resources github
   ```

2. Read a resource:
   ```
   /resource github repo://owner/repository
   ```

### Using Prompts

1. List available prompts:
   ```
   /prompts filesystem
   ```

2. Get a prompt:
   ```
   /prompt filesystem analyze_code path=/src/main.py
   ```

## Server Configuration Examples

### Filesystem Server

Basic setup for home directory access:
```toml
{
  name = "filesystem",
  command = ["npx", "-y", "@modelcontextprotocol/server-filesystem", "$HOME"],
  description = "Access home directory"
}
```

With multiple directories:
```toml
{
  name = "filesystem",
  command = ["npx", "-y", "@modelcontextprotocol/server-filesystem", "/home/user", "/tmp", "/var/log"],
  description = "Access multiple directories"
}
```

### GitHub Server

With authentication:
```toml
{
  name = "github",
  command = ["npx", "-y", "@modelcontextprotocol/server-github"],
  env = { 
    GITHUB_TOKEN = "ghp_xxxxxxxxxxxx",
    GITHUB_API_URL = "https://api.github.com"  # For GitHub Enterprise
  },
  description = "GitHub with auth"
}
```

### PostgreSQL Server

```toml
{
  name = "postgres",
  command = ["npx", "-y", "@modelcontextprotocol/server-postgres"],
  env = {
    DATABASE_URL = "postgresql://user:pass@localhost:5432/dbname"
  },
  description = "Production database"
}
```

## Advanced Usage

### Server Environment Variables

Pass environment variables to servers:

```toml
{
  name = "custom-server",
  command = ["node", "/path/to/server.js"],
  env = {
    API_KEY = "xxx",
    DEBUG = "true",
    CUSTOM_OPTION = "value"
  }
}
```

### Working Directory

Set working directory for server:

```toml
{
  name = "project-server",
  command = ["npm", "start"],
  working_dir = "/home/user/my-project"
}
```

### Transport Options

Configure transport (stdio or SSE):

```toml
{
  name = "remote-server",
  transport = "sse",
  url = "http://localhost:8080/sse"
}
```

## Creating Custom MCP Servers

### Basic Server Structure

```javascript
// my-server.js
import { Server } from '@modelcontextprotocol/server';

const server = new Server({
  name: 'my-custom-server',
  version: '1.0.0',
});

// Define tools
server.setRequestHandler('tools/list', async () => {
  return {
    tools: [{
      name: 'my_tool',
      description: 'Does something useful',
      inputSchema: {
        type: 'object',
        properties: {
          param: { type: 'string' }
        }
      }
    }]
  };
});

// Handle tool execution
server.setRequestHandler('tools/call', async (request) => {
  if (request.params.name === 'my_tool') {
    // Tool implementation
    return { result: 'Tool executed!' };
  }
});

// Start server
server.start();
```

### Package and Install

```json
// package.json
{
  "name": "my-mcp-server",
  "version": "1.0.0",
  "type": "module",
  "bin": {
    "my-mcp-server": "./my-server.js"
  },
  "dependencies": {
    "@modelcontextprotocol/server": "^1.0.0"
  }
}
```

Install globally:
```bash
npm install -g ./my-mcp-server
```

## Best Practices

### 1. Security

- **Limit file access**: Only grant access to necessary directories
- **Use authentication**: Configure API tokens for external services
- **Validate inputs**: Servers should validate all tool inputs
- **Audit usage**: Monitor which tools are being called

### 2. Performance

- **Connect on demand**: Don't connect all servers at startup
- **Disconnect when done**: Free resources by disconnecting unused servers
- **Cache responses**: Some servers support response caching
- **Batch operations**: Use bulk operations when available

### 3. Error Handling

- **Check connection status**: Verify server is connected before use
- **Handle failures gracefully**: Tools may fail due to permissions, network, etc.
- **Provide feedback**: Use server descriptions to explain capabilities
- **Test configurations**: Verify servers work before relying on them

### 4. Health Monitoring

MCP Chat automatically monitors the health of connected servers:

- **Background Health Checks**: Servers are pinged every 30 seconds to verify responsiveness
- **Health Metrics**: Track uptime, success rate, average response time, and consecutive failures
- **Auto-Disable**: Servers are automatically disabled after 3 consecutive health check failures
- **Real-time Status**: Use `/mcp servers` to view current health status:
  - ✓ HEALTHY - Server is responding normally
  - ⚠ UNHEALTHY - Server has failed recent health checks
  - Connection status and performance metrics are also displayed

Health monitoring helps ensure reliable server connections and prevents hanging on unresponsive servers.

## Troubleshooting

### Server Won't Start

1. Check if command exists:
   ```bash
   which npx
   npm list -g @modelcontextprotocol/server-filesystem
   ```

2. Test command manually:
   ```bash
   npx -y @modelcontextprotocol/server-filesystem /tmp
   ```

3. Check logs:
   ```
   /servers
   # Look for error messages
   ```

### Connection Issues

1. **"Server not found"**
   - Ensure server is in config.toml
   - Restart MCP Chat after config changes

2. **"Failed to connect"**
   - Check server command is correct
   - Verify required environment variables
   - Try running server manually

3. **"Tool execution failed"**
   - Check tool parameters
   - Verify permissions (file access, API limits)
   - Review server logs

### Performance Issues

1. **Slow responses**
   - Check network connectivity
   - Verify server resources
   - Consider caching options

2. **High memory usage**
   - Disconnect unused servers
   - Restart problematic servers
   - Check for memory leaks

## Examples

### File Management Session

```
You: I need to organize my documents folder

/connect filesystem

You: Can you list all PDF files in my Documents folder?
Assistant: I'll search for PDF files in your Documents folder.
[Uses filesystem tool to list PDFs]

You: Create a new folder called "Archives" and move old PDFs there
Assistant: I'll create the Archives folder and move the old PDF files.
[Uses filesystem tools to create directory and move files]
```

### Code Analysis Session

```
/connect filesystem
/connect github

You: Analyze the structure of the anthropic/sdk repository
Assistant: I'll examine the repository structure for you.
[Uses GitHub tool to explore repository]

You: Compare it with my local project structure
Assistant: Let me check your local project structure.
[Uses filesystem tool to analyze local files]
```

### Database Query Session

```
/connect postgres

You: Show me the top 10 users by activity in the last week
Assistant: I'll query the database for the most active users.
[Uses postgres tool to execute SQL query]

You: Export the results to a CSV file
Assistant: I'll export the query results to a CSV file.
[Generates CSV format and saves using filesystem tool]
```

## Testing and Development

### Testing SSE Connections

You can test SSE connections using curl:

```bash
# Connect to the SSE stream
curl -N http://localhost:8080/sse

# In another terminal, send a request
curl -X POST http://localhost:8080/message \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/list",
    "params": {},
    "id": 1
  }'
```

### Connecting MCP Chat Instances

You can connect two MCP Chat instances where one acts as server:

**Server Instance (config.toml):**
```toml
[mcp_server]
sse_enabled = true
sse_port = 8080
```

**Client Instance (config.toml):**
```toml
[[mcp.servers]]
name = "chat-server"
url = "http://localhost:8080"
```

Now the client can use chat tools from the server instance!

### Using MCP Chat Server Tools

When connected to an MCP Chat server, you can:

```json
// Send a chat message
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "chat",
    "arguments": {
      "message": "What is the capital of France?"
    }
  },
  "id": 1
}

// Get chat history
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "get_history",
    "arguments": {
      "limit": 10
    }
  },
  "id": 2
}
```

## Security Considerations

When using MCP servers:

### For Stdio Transport
- Be cautious with file system operations
- Limit directory access in server commands
- Validate tool outputs before using in production

### For SSE Transport
- Use HTTPS in production to encrypt communications
- Implement authentication if exposing servers publicly
- Configure CORS appropriately for browser-based clients
- Use firewall rules to restrict access to trusted clients

### General Security
- Use environment variables for sensitive configuration
- Limit server permissions appropriately
- Audit tool usage and access patterns
- Rotate API keys and tokens regularly

## Additional Resources

- [MCP Specification](https://modelcontextprotocol.io)
- [Official MCP Servers](https://github.com/modelcontextprotocol)
- [MCP Chat Configuration Guide](CONFIGURATION.md)
- [Creating MCP Servers Tutorial](https://modelcontextprotocol.io/tutorials)