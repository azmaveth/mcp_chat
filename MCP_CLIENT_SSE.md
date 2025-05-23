# MCP Client - SSE Transport

MCP Chat supports connecting to remote MCP servers via SSE (Server-Sent Events) transport. This allows you to use tools from servers running on different machines, in containers, or in the cloud.

## Configuration

To connect to a remote MCP server via SSE, add it to your `config.toml`:

```toml
[[mcp_servers]]
name = "remote-tools"
url = "http://example.com:8080"  # Base URL of the SSE server

[[mcp_servers]]
name = "local-sse-server"
url = "http://localhost:3000"
```

## How It Works

When connecting to an SSE server, MCP Chat:

1. Establishes an SSE connection to `{url}/sse` for receiving events
2. Sends JSON-RPC messages to `{url}/message` via HTTP POST
3. Maintains the connection with automatic reconnection on failure

## Example: Connecting MCP Chat Instances

You can connect two MCP Chat instances together, where one acts as a server and the other as a client:

### Server Instance (config.toml)

```toml
[mcp_server]
sse_enabled = true
sse_port = 8080
```

### Client Instance (config.toml)

```toml
[[mcp_servers]]
name = "chat-server"
url = "http://localhost:8080"
```

Now the client instance can use the chat tools from the server instance!

## Testing SSE Connections

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

## Benefits of SSE Transport

1. **Remote Access**: Connect to MCP servers running anywhere with HTTP access
2. **Firewall Friendly**: Uses standard HTTP/HTTPS protocols
3. **Browser Compatible**: Can be used from web applications
4. **Scalable**: Supports multiple concurrent connections
5. **Real-time**: Server can push notifications and updates

## Security Considerations

When using SSE transport:

1. Use HTTPS in production to encrypt communications
2. Implement authentication if exposing servers publicly
3. Configure CORS appropriately for browser-based clients
4. Use firewall rules to restrict access to trusted clients

## Troubleshooting

### Connection Refused
- Ensure the server is running and listening on the correct port
- Check firewall rules allow the connection
- Verify the URL is correct (no trailing slashes)

### No Response
- Check the server logs for errors
- Ensure the server implements the SSE protocol correctly
- Try connecting with curl to debug

### Frequent Disconnections
- Check network stability
- Increase timeouts if needed
- Ensure the server sends periodic keepalive pings