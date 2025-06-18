# Starting MCP Chat with Web Dashboard

## Quick Start

Due to the warnings and configuration complexities, here's the recommended way to start MCP Chat with the web dashboard:

### Method 1: Using the Start Script

```bash
# Run the provided start script
elixir start_with_web.exs
```

This script handles the configuration and starts both the application and web server.

### Method 2: Manual Configuration in IEx

```elixir
# Start IEx
iex -S mix

# Configure Phoenix endpoint
Application.put_env(:mcp_chat, MCPChatWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  server: true,
  url: [host: "localhost"],
  secret_key_base: String.duplicate("a", 64),
  render_errors: [
    formats: [html: MCPChatWeb.ErrorHTML, json: MCPChatWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MCPChat.PubSub,
  live_view: [signing_salt: "mcp_chat_lv_salt"]
)

# Restart the endpoint to pick up config
Supervisor.terminate_child(MCPChat.Supervisor, MCPChatWeb.Endpoint)
Supervisor.restart_child(MCPChat.Supervisor, MCPChatWeb.Endpoint)

# Check if it's running
MCPChatWeb.Endpoint.url()
```

### Method 3: Test Without Full Phoenix

For testing without dealing with all the Phoenix warnings, you can use the mock web UI:

```bash
# Start a simple HTTP server to test the interface
cd priv/static
python3 -m http.server 4000
```

Then open http://localhost:4000/test.html in your browser.

## Addressing the Warnings

The warnings you're seeing are mostly due to:

1. **Missing Functions**: Many functions referenced by the web UI are stubs or not yet implemented
2. **Configuration**: Phoenix needs proper configuration which wasn't included in the main app config
3. **Dependencies**: Some Phoenix features expect additional dependencies

These have been addressed with stub implementations, but for production use, you would need to:

1. Properly implement all Gateway API functions
2. Add complete Phoenix configuration
3. Implement actual agent management functions
4. Add authentication/authorization

## Web Dashboard URLs

Once running, the web dashboard provides:

- **Dashboard**: http://localhost:4000/ - System overview
- **Sessions**: http://localhost:4000/sessions - Session management  
- **Agents**: http://localhost:4000/agents - Agent monitoring
- **Chat**: http://localhost:4000/sessions/:id/chat - Web chat interface
- **Health**: http://localhost:4000/health - JSON health endpoint

## Testing the Integration

1. Start the web server using one of the methods above
2. Open http://localhost:4000 in your browser
3. Create a new session via the web UI
4. In IEx, run `MCPChat.main()` to start the CLI
5. Use `/connect <session_id>` to connect CLI to the web session
6. Send messages from both interfaces - they should sync in real-time

## Troubleshooting

If the web server doesn't start:

1. Check if port 4000 is already in use: `lsof -i :4000`
2. Ensure all dependencies are installed: `mix deps.get`
3. Check the logs for specific errors
4. Try the simpler start script first

The warnings about undefined functions are expected - they're stubs for features that would be implemented in a production system.