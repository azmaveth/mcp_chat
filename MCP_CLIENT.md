# MCP Client Functionality

MCP Chat includes a full-featured MCP (Model Context Protocol) client that can connect to any MCP server and use its tools, resources, and prompts.

## Features

- **Tool Discovery & Execution**: Automatically discover and execute tools from connected MCP servers
- **Resource Management**: List and read resources exposed by MCP servers
- **Prompt Templates**: Access and use prompt templates from MCP servers
- **Multiple Transports**: Support for both stdio (local) and SSE (remote) MCP servers
- **Synchronous Operations**: Request/response correlation for reliable tool execution

## Configuration

### Stdio Transport (Local Servers)

For local MCP servers that communicate via stdio:

```toml
[[mcp_servers]]
name = "filesystem"
command = ["npx", "-y", "@modelcontextprotocol/server-filesystem", "/tmp"]

[[mcp_servers]]
name = "github"
command = ["npx", "-y", "@modelcontextprotocol/server-github"]
env = { GITHUB_PERSONAL_ACCESS_TOKEN = "your-token-here" }
```

### SSE Transport (Remote Servers)

For remote MCP servers accessible via HTTP/SSE:

```toml
[[mcp_servers]]
name = "remote-tools"
url = "http://example.com:8080"
```

## CLI Commands

### Server Management

```bash
# List connected MCP servers
/servers

# Example output:
# Name        Status      Port
# filesystem  connected   stdio
# remote-tools connected  http://example.com:8080
```

### Tool Operations

```bash
# List all available tools
/tools

# Execute a tool
/tool <server> <tool> [arguments]

# Examples:
/tool filesystem read_directory {"path": "/tmp"}
/tool filesystem read_file {"path": "/tmp/test.txt"}
/tool github search_repositories {"query": "language:elixir"}
```

Arguments can be:
- JSON object: `{"key": "value", "number": 123}`
- Plain text (wrapped as `{"input": "text"}`): `Hello world`

### Resource Operations

```bash
# List all available resources
/resources

# Read a resource
/resource <server> <uri>

# Example:
/resource filesystem file:///tmp/data.json
```

### Prompt Operations

```bash
# List all available prompts
/prompts

# Get a prompt template
/prompt <server> <name> [arguments]

# Examples:
/prompt writing essay {"topic": "AI Ethics"}
/prompt coding refactor {"language": "elixir"}
```

## Example Workflow

1. **Connect to an MCP server** (configured in config.toml)

2. **Discover available tools**:
   ```
   /tools
   
   Server      Tool            Description
   filesystem  read_directory  Read directory contents
   filesystem  read_file       Read file contents
   filesystem  write_file      Write content to file
   ```

3. **Execute a tool**:
   ```
   /tool filesystem read_directory {"path": "/home/user/documents"}
   
   Tool result:
   [
     {"name": "report.md", "type": "file", "size": 2048},
     {"name": "projects", "type": "directory"}
   ]
   ```

4. **Read a resource**:
   ```
   /resource filesystem file:///home/user/documents/report.md
   
   Resource contents:
   # Monthly Report
   ...
   ```

## Integration with Chat

MCP tools can enhance your chat experience:

1. **File Operations**: Read and write files during conversations
2. **Web Search**: Search the web for current information
3. **Code Analysis**: Analyze repositories and codebases
4. **Data Processing**: Transform and analyze data
5. **Custom Tools**: Any functionality exposed by MCP servers

## Error Handling

The client provides clear error messages:

- **Server not found**: Check server name in `/servers`
- **Tool execution failed**: Verify arguments format
- **Connection lost**: Server may have crashed or network issue
- **Invalid arguments**: Check tool's expected input schema

## Advanced Usage

### Tool Chaining

Execute multiple tools in sequence:
```
/tool filesystem read_file {"path": "config.json"}
# Analyze the output
/tool analyzer validate_json {"content": "..."}
```

### Batch Operations

Some servers support batch operations:
```
/tool filesystem read_directory {"path": "/data", "recursive": true}
```

### Streaming Results

Large results are automatically handled and displayed progressively.

## Troubleshooting

1. **No servers connected**: Check your config.toml
2. **Tool not found**: Ensure server is connected with `/servers`
3. **Execution timeout**: Some operations may take longer
4. **Permission denied**: Check server's access permissions

## Security Considerations

- Be cautious with file system operations
- Validate tool outputs before using in production
- Use environment variables for sensitive configuration
- Limit server permissions appropriately