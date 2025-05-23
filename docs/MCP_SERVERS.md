# MCP Servers Guide

This guide explains how to use Model Context Protocol (MCP) servers with MCP Chat to extend its functionality.

## What are MCP Servers?

MCP servers provide tools, resources, and prompts that enhance your chat experience by giving the LLM access to external capabilities like:
- File system access
- Database queries
- API integrations
- Code execution
- And much more

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

## Using MCP Servers

### Connecting to Servers

1. List available servers:
   ```
   /servers
   ```

2. Connect to a server:
   ```
   /connect filesystem
   ```

3. Disconnect when done:
   ```
   /disconnect filesystem
   ```

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

## Additional Resources

- [MCP Specification](https://modelcontextprotocol.io)
- [Official MCP Servers](https://github.com/modelcontextprotocol)
- [MCP Chat Configuration Guide](USER_GUIDE.md#mcp-server-configuration)
- [Creating MCP Servers Tutorial](https://modelcontextprotocol.io/tutorials)