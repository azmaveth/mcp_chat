# MCP Chat

An Elixir-based CLI chat client with support for the Model Context Protocol (MCP) and multiple LLM backends.

## 📚 Documentation

- **[Quick Start Guide](docs/QUICK_START.md)** - Get running in 5 minutes
- **[Installation Guide](docs/INSTALLATION.md)** - Detailed setup instructions
- **[User Guide](docs/USER_GUIDE.md)** - Complete feature documentation
- **[MCP Servers Guide](docs/MCP_SERVERS.md)** - Extend functionality with MCP

## Features

- 🤖 Multiple LLM backend support (Anthropic Claude 4, OpenAI GPT-4, Ollama, Local models via Bumblebee)
- 🚀 GPU acceleration support with EXLA (CUDA, ROCm) and EMLX (Apple Silicon/Metal)
- 🔌 MCP client functionality - connect to local (stdio) and remote (SSE) MCP servers
- 🛠️ MCP server functionality - expose chat as an MCP server (stdio and SSE transports)
- 💬 Interactive CLI chat interface with rich formatting
- 📝 Conversation history and session management
- 🎨 Beautiful terminal UI with Owl (progress bars, cache displays)
- 📊 Export conversations to Markdown or JSON
- ⚡ Streaming response support
- 🔧 TOML-based configuration
- 🔑 Environment variable support for API keys
- 🚀 Performance optimizations (startup profiling, lazy loading, resource caching)
- 💾 Smart memory management with hybrid disk/memory storage
- 📈 Real-time progress tracking for MCP operations
- 🗂️ Local resource caching with automatic invalidation

## Architecture

MCP Chat is built on a modular architecture using extracted Elixir libraries:

### 📦 Extracted Libraries

- **[ex_llm](../ex_llm/)** - All-in-one LLM library with support for multiple providers
  - Unified API for Anthropic, OpenAI, Ollama, Bedrock, Gemini, and local models
  - Automatic cost tracking and context window management
  - Streaming support with configurable options
  
- **[ex_mcp](../ex_mcp/)** - Model Context Protocol implementation
  - Full MCP client and server functionality
  - Multiple transports: stdio, WebSocket, and BEAM
  - Server discovery and connection management
  
- **[ex_alias](../ex_alias/)** - Command alias system
  - Define custom command shortcuts
  - Parameter substitution and command chaining
  - Circular reference detection
  
- **[ex_readline](../ex_readline/)** - Enhanced line editing
  - Command history with persistence
  - Tab completion framework
  - Emacs-style keybindings and arrow key support

### 🔄 Adapter Pattern

MCP Chat uses adapter modules to maintain backward compatibility while leveraging the extracted libraries:

- `MCPChat.LLM.ExLLMAdapter` - Bridges mcp_chat's LLM interface with ex_llm
- `MCPChat.MCP.ExMCPAdapter` - Bridges mcp_chat's MCP client with ex_mcp  
- `MCPChat.Alias.ExAliasAdapter` - Bridges mcp_chat's alias system with ex_alias
- `MCPChat.CLI.ExReadlineAdapter` - Bridges mcp_chat's line reading with ex_readline

This architecture provides:
- ✅ **Modularity** - Each library handles one responsibility
- ✅ **Reusability** - Libraries can be used in other projects
- ✅ **Maintainability** - Clean separation of concerns
- ✅ **Backward Compatibility** - Existing functionality preserved

## Installation

### Prerequisites

- Elixir 1.18 or later
- Node.js (for MCP servers)

### Build from source

```bash
# Clone the repository
git clone https://github.com/azmaveth/mcp_chat.git
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

MCP Chat is configured via TOML files and environment variables. See the [Configuration Guide](docs/CONFIGURATION.md) for complete details.

**Quick setup:**
1. Configuration file: `~/.config/mcp_chat/config.toml`
2. API keys via environment: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`
3. See `config.example.toml` for a complete example

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

### Running in Elixir Shell (with full readline support)

For full command history with arrow keys and readline support, run the app in the Elixir shell:

```bash
# Start IEx with the project loaded
iex -S mix

# In the IEx shell, start the chat interface
iex> MCPChat.main()
```

This provides:
- Full arrow key support (↑/↓ for history, ←/→ for cursor movement)
- Emacs keybindings (Ctrl-A/E, Ctrl-K/U, etc.)
- Tab completion
- All standard readline features

To exit: type `/exit` in the chat, then `Ctrl-C` twice to exit IEx.

### Key Commands

- `/help` - Show all available commands
- `/backend <name>` - Switch LLM backend (anthropic, openai, ollama, local)
- `/models` - List available models
- `/servers` - List connected MCP servers
- `/discover` - Auto-discover MCP servers
- `/save` - Save current session
- `/notification` - Manage MCP event notifications
- `/tui` - Control text UI displays (progress, cache)

### New MCP Features (v0.2.0)

- **Progress Tracking**: See real-time progress bars for long operations
  - `/mcp tool server tool_name --progress` - Execute with progress tracking
  - `/mcp progress` - View active operations
  
- **Notifications**: Get alerts when server capabilities change
  - `/mcp notify on/off/status` - Control notifications
  - Automatic alerts for tool/resource/prompt changes
  
- **Server-side LLM**: Use MCP servers' own language models
  - `/mcp sample server "prompt"` - Generate text via server
  - `/mcp capabilities` - Check which servers support sampling
- `/cost` - Show session cost
- `/acceleration` - Show GPU/acceleration info
- `/exit` - Exit the application

See the [User Guide](docs/USER_GUIDE.md) for the complete command reference.

## Key Features Explained

### Context Management
- Intelligent handling of long conversations with token counting
- Multiple truncation strategies (sliding window, smart)
- Real-time token usage and cost estimation

### Cost Tracking
- Automatic tracking of input/output tokens
- Real-time cost calculation with current pricing
- Session cost summaries with `/cost`

### MCP Integration
- Auto-discover and connect to MCP servers with `/discover`
- Use filesystem, GitHub, database, and other tools
- Run MCP Chat as a server for other clients

### Command Aliases
- Create custom command shortcuts
- Support for parameters and command sequences
- Persistent aliases across sessions

See the [MCP Servers Guide](docs/MCP_SERVERS.md) for detailed MCP functionality.

## Troubleshooting

### No response from chat
- Ensure your API key is set either in `~/.config/mcp_chat/config.toml` or as the `ANTHROPIC_API_KEY` environment variable
- Check that you're using a valid model name (default: `claude-sonnet-4-20250514`)
- Verify your internet connection

### Build errors with EXLA

#### macOS Compilation Error
If you encounter C++ template errors when compiling EXLA on macOS:
```
error: a template argument list is expected after a name prefixed by the template keyword
```

**Solutions:**
1. **Recommended for Apple Silicon**: Skip EXLA and use EMLX instead:
   ```bash
   mix deps.clean exla
   mix deps.get  # EMLX will be used automatically
   ```

2. **Use the provided installation script**:
   ```bash
   ./install_exla_macos.sh
   ```

3. **Manual workaround**:
   ```bash
   export CXXFLAGS="-Wno-error=missing-template-arg-list-after-template-kw"
   mix deps.compile exla --force
   ```

#### General Notes
- The local model support via Bumblebee/Nx is optional and may have compilation issues on some systems
- The chat client works fine without it for cloud-based LLMs
- On Apple Silicon, EMLX is preferred over EXLA for better performance

## Local Model Support & GPU Acceleration

MCP Chat supports running models locally using Bumblebee with optional GPU acceleration via EXLA and EMLX.

### Features

- **Automatic Hardware Detection**: Detects available acceleration (CUDA, ROCm, Metal, CPU)
- **Apple Silicon Optimization**: Native Metal acceleration via EMLX
- **Optimized Inference**: Uses mixed precision and memory optimization
- **Dynamic Model Loading**: Load and unload models on demand
- **Multi-Backend Support**: Automatically selects the best available backend

### Installation with GPU Support

```bash
# For Apple Silicon (M1/M2/M3) - Recommended
mix deps.get  # EMLX will be installed automatically
mix compile

# For NVIDIA GPUs (CUDA)
XLA_TARGET=cuda12 mix deps.get
mix compile

# For AMD GPUs (ROCm)
XLA_TARGET=rocm mix deps.get
mix compile

# For CPU optimization only (non-Apple Silicon)
XLA_TARGET=cpu mix deps.get
mix compile
```

#### Backend Selection

The system automatically selects the best backend:
1. **Apple Silicon**: EMLX (preferred) or EXLA with Metal
2. **NVIDIA GPUs**: EXLA with CUDA
3. **AMD GPUs**: EXLA with ROCm
4. **CPU**: EXLA with optimized CPU settings or binary backend

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

2. **Apple Silicon**: Unified memory architecture allows efficient model loading
   - M1/M2 (8-16GB): Good for smaller models (up to 7B)
   - M1/M2 Pro/Max (16-64GB): Can handle larger models efficiently
   - M3 series: Enhanced performance with EMLX optimization

3. **Mixed Precision**: Automatically enabled for better performance
   - EMLX: Automatic mixed precision on Apple Silicon
   - EXLA: Configurable FP16/FP32 mixed precision

4. **Model Caching**: Models are cached locally after first download

## Known Limitations

- **Arrow Keys**: In escript mode, arrow keys for command history show escape sequences (^[[A, ^[[B) instead of navigating history. This is a limitation of running as an escript rather than in an Erlang shell.
- **Emacs Keybindings**: Similar to arrow keys, Ctrl-P/N and other readline keybindings show as literal characters.
- **Workaround**: Run the app in the Elixir shell for full readline support (see "Running in Elixir Shell" section above).

## Development

### Testing

Run the test suite:

```bash
mix test
```

Run specific test files:

```bash
mix test test/mcp_chat/cli/commands/mcp_basic_test.exs
```

The test suite includes:
- Unit tests for all major modules
- Integration tests for LLM backends and MCP functionality
- CLI command tests ensuring commands continue to work as expected

See [NUMERIC_FORMATTING_NOTES.md](NUMERIC_FORMATTING_NOTES.md) for information about handling numeric formatting in tests.

### Roadmap

See [TASKS.md](TASKS.md) for the development roadmap and task list.

## License

MIT

