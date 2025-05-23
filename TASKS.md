# MCP Chat Client - Tasks

## Project Overview

An Elixir-based MCP (Model Context Protocol) client that provides a CLI chat interface with support for:
- Multiple LLM backends (Anthropic Claude 4, OpenAI, local models via Bumblebee/Nx)
- MCP server connections for extensible functionality
- Configuration via TOML files and environment variables
- Interactive chat interface with history and context management
- Real-time streaming responses

## Architecture

```
mcp_chat/
├── lib/
│   ├── mcp_chat/
│   │   ├── application.ex      # OTP application supervisor
│   │   ├── cli/                # CLI interface modules
│   │   │   ├── chat.ex         # Main chat loop
│   │   │   ├── commands.ex     # CLI commands handler
│   │   │   └── renderer.ex     # Terminal UI rendering
│   │   ├── mcp/                # MCP protocol implementation
│   │   │   ├── client.ex       # MCP client connection
│   │   │   ├── protocol.ex     # Protocol messages
│   │   │   └── server.ex       # Server connection manager
│   │   ├── llm/                # LLM backend adapters
│   │   │   ├── adapter.ex      # Common adapter behaviour
│   │   │   ├── openai.ex       # OpenAI API adapter
│   │   │   ├── anthropic.ex    # Anthropic API adapter
│   │   │   └── local.ex        # Bumblebee/Nx local models
│   │   ├── config.ex           # Configuration management
│   │   └── session.ex          # Chat session state
│   └── mcp_chat.ex             # Main module
├── config/                      # Configuration files
├── test/                        # Test files
└── priv/                        # Static assets
```

## Tasks

### Phase 1: Core Infrastructure
- [x] Create application supervisor structure
- [x] Implement configuration loader (TOML support)
- [x] Set up basic CLI interface with Owl
- [x] Create session state management

### Phase 2: MCP Protocol Implementation
- [x] Implement MCP client WebSocket connection
- [x] Create protocol message encoding/decoding
- [x] Build server connection manager
- [ ] Add tool discovery and execution (partial - UI complete)
- [ ] Implement resource handling (partial - UI complete)
- [ ] Add prompt management (partial - UI complete)
- [ ] Implement stdio transport for MCP servers

### Phase 3: LLM Backend Integration
- [x] Define LLM adapter behaviour
- [ ] Implement OpenAI adapter
- [x] Implement Anthropic adapter (with Claude 4 support)
- [x] Add streaming response support
- [x] Create backend configuration system
- [x] Add environment variable support for API keys

### Phase 4: CLI Chat Interface
- [x] Build interactive chat loop
- [x] Add command system (e.g., /help, /config, /servers)
- [x] Implement chat history
- [x] Add context management
- [x] Create rich terminal UI with Owl

### Phase 5: Local Model Support
- [ ] Integrate Bumblebee for model loading
- [ ] Implement local model adapter
- [ ] Add model download/management commands
- [ ] Optimize for CPU/GPU inference with EXLA

### Phase 6: Advanced Features
- [ ] Add conversation persistence
- [ ] Implement multi-turn context handling
- [ ] Add MCP server auto-discovery
- [ ] Create plugin system for custom tools
- [x] Add export functionality (markdown, JSON)

### Phase 7: Testing & Documentation
- [ ] Write unit tests for all modules
- [ ] Add integration tests
- [ ] Create user documentation
- [ ] Add example configurations
- [ ] Write MCP server integration guides

## Configuration Format

Example `config.toml`:
```toml
[llm]
default = "anthropic"

[llm.anthropic]
api_key = "YOUR_API_KEY"  # Or use ANTHROPIC_API_KEY env var
model = "claude-sonnet-4-20250514"
max_tokens = 4096

[llm.openai]
api_key = "YOUR_API_KEY"
model = "gpt-4"

[llm.local]
model_path = "models/llama-2-7b"
device = "cpu"

[mcp]
servers = [
  { name = "filesystem", command = ["npx", "-y", "@modelcontextprotocol/server-filesystem", "/tmp"] },
  { name = "github", command = ["npx", "-y", "@modelcontextprotocol/server-github"] }
]

[ui]
theme = "dark"
history_size = 1000
```

## Recent Updates (May 2025)

- ✅ Updated to Claude 4 models (claude-sonnet-4-20250514)
- ✅ Fixed SSE streaming implementation for real-time responses
- ✅ Added environment variable support for API keys
- ✅ Fixed Owl.Table rendering issues
- ✅ Improved error handling and user feedback

## Development Notes

- Use supervisor trees for fault tolerance
- Implement backpressure for streaming responses
- Keep MCP protocol logic separate from UI
- Use behaviours for extensibility
- Follow Elixir naming conventions
- Add telemetry for monitoring