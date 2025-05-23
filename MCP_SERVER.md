# MCP Server Mode

MCP Chat can function as an MCP server, allowing other MCP clients to interact with it. This enables you to expose the chat functionality as a tool that can be used by other applications.

Additionally, MCP Chat can connect to remote MCP servers via SSE (Server-Sent Events) transport, allowing it to use tools from servers running on different machines or in the cloud.

## Features

As an MCP server, MCP Chat provides:

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

## Configuration

Configure MCP server mode in your `config.toml`:

```toml
[mcp_server]
# Enable stdio server (for use with other MCP clients via stdio)
stdio_enabled = true

# Enable SSE server (for use with other MCP clients via HTTP/SSE)
sse_enabled = true
sse_port = 8080
```

## Usage

### Stdio Mode

To run as an stdio MCP server:

```bash
./mcp_server
```

Or configure it in another MCP client's configuration:

```json
{
  "mcpServers": {
    "mcp-chat": {
      "command": "/path/to/mcp_chat/mcp_server"
    }
  }
}
```

### SSE Mode

When SSE mode is enabled, the server listens on the configured port (default 8080).

Endpoints:
- `GET /sse` - Server-Sent Events stream
- `POST /message` - Send JSON-RPC messages
- `OPTIONS /*` - CORS preflight

Example usage with curl:

```bash
# Connect to SSE stream
curl -N http://localhost:8080/sse

# Send a message
curl -X POST http://localhost:8080/message \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "chat",
      "arguments": {
        "message": "Hello, how are you?"
      }
    },
    "id": 1
  }'
```

## Tool Examples

### Chat Tool

Send a message and get a response:

```json
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
```

### Get History Tool

Retrieve the last N messages:

```json
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

### New Session Tool

Start a fresh chat session:

```json
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "new_session",
    "arguments": {}
  },
  "id": 3
}
```