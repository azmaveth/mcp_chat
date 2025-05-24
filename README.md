# MCP Chat

An Elixir-based CLI chat client with support for the Model Context Protocol (MCP) and multiple LLM backends.

## 📚 Documentation

- **[Quick Start Guide](docs/QUICK_START.md)** - Get running in 5 minutes
- **[Installation Guide](docs/INSTALLATION.md)** - Detailed setup instructions
- **[User Guide](docs/USER_GUIDE.md)** - Complete feature documentation
- **[MCP Servers Guide](docs/MCP_SERVERS.md)** - Extend functionality with MCP

## Features

- 🤖 Multiple LLM backend support (Anthropic Claude 4, OpenAI GPT-4, Ollama, Local models via Bumblebee)
- 🚀 GPU acceleration support with EXLA (CUDA, ROCm, Metal)
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
- `/discover` - Discover available MCP servers
- `/connect <name>` - Connect to a discovered server
- `/disconnect <name>` - Disconnect from a server
- `/tools` - List available MCP tools
- `/tool <server> <tool> [args]` - Execute an MCP tool
- `/resources` - List available MCP resources  
- `/resource <server> <uri>` - Read an MCP resource
- `/prompts` - List available MCP prompts
- `/prompt <server> <name> [args]` - Get an MCP prompt
- `/backend <name>` - Switch LLM backend
- `/model <name>` - Switch model
- `/models` - List available models for current backend
- `/loadmodel <id>` - Load a local model (local backend only)
- `/unloadmodel <id>` - Unload a local model (local backend only)
- `/acceleration` - Show hardware acceleration info
- `/save [name]` - Save the current session
- `/load <name or index>` - Load a saved session
- `/sessions` - List all saved sessions
- `/export [format]` - Export conversation (markdown/json)
- `/context` - Show context statistics and estimated cost for next message
- `/system <prompt>` - Set/clear system prompt
- `/tokens <number>` - Set max context tokens
- `/strategy <type>` - Set context strategy (sliding_window/smart)
- `/cost` - Show session cost based on token usage
- `/alias` - Manage custom command shortcuts
- `/exit` or `/quit` - Exit the application

## Context Management

MCP Chat includes intelligent context management to handle long conversations:

### Features

- **Token Counting**: Estimates token usage to stay within model limits
- **Automatic Truncation**: Manages context window with configurable strategies
- **System Prompts**: Persistent system prompts across conversations
- **Context Statistics**: Real-time visibility into token usage
- **Cost Estimation**: Shows estimated cost for the next message

### Context Strategies

1. **Sliding Window** (default): Keeps the most recent messages that fit within token limit
2. **Smart**: Preserves system prompt, initial context, and recent messages with truncation notices

### Usage Examples

```bash
# Set a system prompt
/system You are an expert Elixir developer

# Set max tokens (default: 4096)
/tokens 8192

# Change context strategy
/strategy smart

# Check context usage
/context
```

## Cost Tracking

MCP Chat automatically tracks token usage and calculates costs based on current provider pricing:

### Features

- **Automatic Token Tracking**: Counts input and output tokens for each message
- **Real-time Cost Calculation**: Uses up-to-date pricing for each model
- **Multiple Model Support**: Pricing for all major Anthropic and OpenAI models
- **Smart Formatting**: Shows costs in appropriate units (cents for small amounts)

### Usage

```bash
# Check current session cost
/cost
```

The cost display includes:
- Token counts (input/output/total)
- Cost breakdown by input and output
- Total session cost in USD
- Current model pricing information

## MCP Server Discovery

MCP Chat can automatically discover available MCP servers:

### Auto-Discovery Methods

1. **Quick Setup**: Pre-configured popular MCP servers
2. **NPM Packages**: Scans globally installed npm packages
3. **Environment Variables**: Detects MCP-related environment variables
4. **Local Directories**: Searches known locations for MCP servers

### Usage

```bash
# Discover available servers
/discover

# Connect to a discovered server
/connect filesystem

# Disconnect from a server
/disconnect filesystem
```

### Quick Setup Servers

- `filesystem` - Local file access
- `github` - GitHub integration (requires GITHUB_TOKEN)
- `postgres` - PostgreSQL access (requires DATABASE_URL)
- `sqlite` - SQLite database access
- `memory` - Persistent memory storage
- `puppeteer` - Browser automation
- And more...

## Command Aliases

Create custom shortcuts for frequently used command sequences:

### Creating Aliases

```bash
# Simple alias for multiple commands
/alias add status=/context;/cost

# Alias with parameters ($1, $2, etc.)
/alias add check=/tool $1 $2;/resource $1 $3

# Complex setup alias
/alias add setup=/system You are a helpful assistant;/tokens 8192;/strategy smart

# Alias that includes a message
/alias add greet=/clear;Hello! How can I help you today?
```

### Using Aliases

```bash
# Execute an alias
/status

# Pass arguments to parameterized aliases
/check filesystem read_file /etc/hosts

# Use $* for all arguments
/alias add say=I want to say: $*
/say hello world
```

### Managing Aliases

```bash
# List all aliases
/alias list
/alias

# Remove an alias
/alias remove status
```

Aliases are saved to `~/.config/mcp_chat/aliases.json` and persist between sessions.

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

## Local Model Support & GPU Acceleration

MCP Chat supports running models locally using Bumblebee with optional GPU acceleration via EXLA.

### Features

- **Automatic Hardware Detection**: Detects available acceleration (CUDA, ROCm, Metal, CPU)
- **Optimized Inference**: Uses mixed precision and memory optimization
- **Dynamic Model Loading**: Load and unload models on demand
- **Multi-Backend Support**: Automatically selects the best available backend

### Installation with GPU Support

```bash
# For NVIDIA GPUs (CUDA)
XLA_TARGET=cuda12 mix deps.get
mix compile

# For AMD GPUs (ROCm)
XLA_TARGET=rocm mix deps.get
mix compile

# For Apple Silicon (Metal)
mix deps.get
mix compile

# For CPU optimization only
XLA_TARGET=cpu mix deps.get
mix compile
```

### Usage

```bash
# Switch to local backend
/backend local

# Check acceleration status
/acceleration

# List available models
/models

# Load a model
/loadmodel microsoft/phi-2

# Unload a model
/unloadmodel microsoft/phi-2
```

### Supported Models

- Microsoft Phi-2 (2.7B parameters)
- Llama 2 7B
- Mistral 7B
- GPT-Neo 1.3B
- Flan-T5 Base

### Performance Tips

1. **GPU Memory**: Larger models require more VRAM
   - 8GB: Can run models up to 7B parameters
   - 16GB: Better performance for 7B models
   - 24GB+: Can run multiple models or larger batch sizes

2. **Mixed Precision**: Automatically enabled for better performance

3. **Model Caching**: Models are cached locally after first download

## Development

See [TASKS.md](TASKS.md) for the development roadmap and task list.

## License

MIT

