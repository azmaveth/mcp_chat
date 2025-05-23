# MCP Chat

An Elixir-based CLI chat client with support for the Model Context Protocol (MCP) and multiple LLM backends.

## Features

- 🤖 Multiple LLM backend support (Anthropic Claude 4, OpenAI GPT-4, Local models via Bumblebee)
- 🔌 MCP client functionality - connect to local (stdio) and remote (SSE) MCP servers
- 🛠️ MCP server functionality - expose chat as an MCP server (stdio and SSE transports)
- 💬 Interactive CLI chat interface with rich formatting
- 📝 Conversation history and session management
- 🎨 Beautiful terminal UI with Owl
- 📊 Export conversations to Markdown or JSON
- ⚡ Streaming response support
- 🔧 TOML-based configuration
- 🔑 Environment variable support for API keys

## Installation

### Prerequisites

- Elixir 1.18 or later
- Node.js (for MCP servers)

### Build from source

```bash
# Clone the repository
git clone https://github.com/yourusername/mcp_chat.git
cd mcp_chat

# Run the setup script (installs deps, builds, creates config)
./setup.sh

# Or manually:
mix deps.get
mix escript.build

# Run the chat client
./mcp_chat
```

## Configuration

The client can be configured via:
1. Configuration file at `~/.config/mcp_chat/config.toml`
2. Environment variables (e.g., `ANTHROPIC_API_KEY`)

### Configuration File

```toml
[llm]
default = "anthropic"

[llm.anthropic]
api_key = "YOUR_API_KEY"  # Or use ANTHROPIC_API_KEY env var
model = "claude-sonnet-4-20250514"
max_tokens = 4096

[[mcp.servers]]
name = "filesystem"
command = ["npx", "-y", "@modelcontextprotocol/server-filesystem", "/tmp"]

# MCP Server configuration (optional)
[mcp_server]
stdio_enabled = false
sse_enabled = false
sse_port = 8080
```

### Environment Variables

- `ANTHROPIC_API_KEY` - Your Anthropic API key (takes precedence if config file key is empty)
- `OPENAI_API_KEY` - Your OpenAI API key (takes precedence if config file key is empty)

See `config/example.toml` for a complete configuration example.

## Usage

```bash
# Start the chat client (uses default backend from config)
./mcp_chat

# Start with a specific backend
./mcp_chat --backend openai

# Switch backends during chat
/backend openai
/backend anthropic

# Switch models during chat
/model gpt-4-turbo-preview
/model claude-sonnet-4-20250514

# Use a custom config file
./mcp_chat --config /path/to/config.toml
```

### Available Commands

- `/help` - Show available commands
- `/clear` - Clear the screen
- `/history` - Show conversation history
- `/new` - Start a new conversation
- `/config` - Show current configuration
- `/servers` - List connected MCP servers
- `/tools` - List available MCP tools
- `/backend <name>` - Switch LLM backend
- `/model <name>` - Switch model
- `/export [format]` - Export conversation (markdown/json)
- `/exit` or `/quit` - Exit the application

## MCP Server Mode

MCP Chat can also function as an MCP server, allowing other MCP clients to interact with it. See [MCP_SERVER.md](MCP_SERVER.md) for detailed documentation.

### Quick Start

```bash
# Run as stdio MCP server
./mcp_server

# Or enable in config.toml and run normally
[mcp_server]
stdio_enabled = true  # For stdio transport
sse_enabled = true    # For HTTP/SSE transport
sse_port = 8080
```

## Troubleshooting

### No response from chat
- Ensure your API key is set either in `~/.config/mcp_chat/config.toml` or as the `ANTHROPIC_API_KEY` environment variable
- Check that you're using a valid model name (default: `claude-sonnet-4-20250514`)
- Verify your internet connection

### Build errors with EXLA
- The local model support via Bumblebee/Nx is optional and may have compilation issues on some systems
- The chat client works fine without it for cloud-based LLMs

## Development

See [TASKS.md](TASKS.md) for the development roadmap and task list.

## License

MIT

