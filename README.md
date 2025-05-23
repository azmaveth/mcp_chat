# MCP Chat

An Elixir-based CLI chat client with support for the Model Context Protocol (MCP) and multiple LLM backends.

## Features

- 🤖 Multiple LLM backend support (Anthropic Claude, OpenAI, Local models via Bumblebee)
- 🔌 MCP server integration for extensible functionality
- 💬 Interactive CLI chat interface with rich formatting
- 📝 Conversation history and session management
- 🎨 Beautiful terminal UI with Owl
- 📊 Export conversations to Markdown or JSON
- ⚡ Streaming response support
- 🔧 TOML-based configuration

## Installation

### Prerequisites

- Elixir 1.18 or later
- Node.js (for MCP servers)

### Build from source

```bash
# Clone the repository
git clone https://github.com/yourusername/mcp_chat.git
cd mcp_chat

# Install dependencies
mix deps.get

# Build the escript
mix escript.build

# Run the chat client
./mcp_chat
```

## Configuration

Create a configuration file at `~/.config/mcp_chat/config.toml`:

```toml
[llm]
default = "anthropic"

[llm.anthropic]
api_key = "YOUR_API_KEY"
model = "claude-3-sonnet-20240229"
max_tokens = 4096

[[mcp.servers]]
name = "filesystem"
command = ["npx", "-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
```

See `config/example.toml` for a complete configuration example.

## Usage

```bash
# Start the chat client
./mcp_chat

# Start with a specific backend
./mcp_chat --backend openai

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

## Development

See [TASKS.md](TASKS.md) for the development roadmap and task list.

## License

MIT

