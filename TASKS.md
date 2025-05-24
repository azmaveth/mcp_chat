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
- [x] Add tool discovery and execution with request/response correlation
- [x] Implement resource handling with CLI commands
- [x] Add prompt management with CLI commands
- [x] Implement stdio transport for MCP client
- [x] Implement SSE transport for MCP client

### Phase 3: LLM Backend Integration
- [x] Define LLM adapter behaviour
- [x] Implement OpenAI adapter (GPT-4 and GPT-3.5 support)
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
- [x] Integrate Bumblebee for model loading
- [x] Implement local model adapter
- [x] Add model download/management commands
- [x] Optimize for CPU/GPU inference with EXLA

### Phase 6: Advanced Features
- [x] Add conversation persistence (save/load sessions with metadata)
- [x] Implement multi-turn context handling (token counting, truncation strategies)
- [x] Add MCP server auto-discovery (quick setup, npm scan, env vars, local dirs)
- ~~[ ] Create plugin system for custom tools~~ *(MCP servers provide plugin functionality)*
- [x] Add export functionality (markdown, JSON)
- [x] Implement MCP server functionality (stdio and SSE transports)

### Phase 7: Testing & Documentation
- [ ] Write unit tests for all modules (in progress)
  - [x] Context module (token estimation, truncation strategies)
  - [x] Cost module (pricing calculations, usage tracking)
  - [x] Alias module (command aliases, circular reference detection)
  - [x] Persistence module (save/load sessions, exports)
  - [x] Session module (message management, context handling)
  - [x] Config module (TOML loading, environment variables)
  - [x] Anthropic LLM adapter (basic tests, needs mocking for full coverage)
  - [x] OpenAI LLM adapter (basic tests, needs mocking for full coverage)
  - [x] CLI Commands module (command handling, validation)
  - [x] CLI Chat module (basic tests with IO capture)
  - [x] CLI Renderer module
  - [x] MCP client modules (Protocol, Client, ServerManager tests)
  - [x] MCP server modules (Handler, SSEServer, StdioServer)
  - [x] Application supervisor
- [x] Add integration tests
  - [x] Basic integration tests (basic_integration_test.exs)
  - [x] MCP client integration tests (mcp_client_integration_test.exs)
  - [x] LLM backend integration tests (llm_backend_integration_test.exs)
  - [x] CLI chat integration tests (cli_chat_integration_test.exs)
  - [x] Session persistence integration tests (session_persistence_integration_test.exs)
- [x] Create user documentation
  - [x] Quick Start Guide
  - [x] Installation Guide (all platforms)
  - [x] User Guide (comprehensive)
  - [x] MCP Servers Guide
  - [x] Documentation README
- [x] Add example configurations (comprehensive config.example.toml)
- [x] Write MCP server integration guides (included in MCP_SERVERS.md)

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
- ✅ Implemented stdio transport for MCP client connections
- ✅ Added MCP server functionality with both stdio and SSE transports
- ✅ Created chat tools, resources, and prompts for MCP server mode
- ✅ Implemented SSE transport for MCP client to connect to remote servers
- ✅ Implemented OpenAI adapter with GPT-4 and GPT-3.5 support
- ✅ Completed MCP tool discovery and execution with synchronous request/response
- ✅ Added CLI commands for tool execution, resource reading, and prompt retrieval
- ✅ Implemented conversation persistence with save/load functionality
- ✅ Added session management with metadata (timestamps, message count, file size)
- ✅ Implemented multi-turn context handling with token counting and truncation
- ✅ Added context management commands (/context, /system, /tokens, /strategy)
- ✅ Implemented cost tracking with real-time token usage and pricing calculation
- ✅ Added /cost command to display session costs with model-specific pricing
- ✅ Implemented MCP server auto-discovery with multiple discovery methods
- ✅ Added /discover, /connect, /disconnect commands for dynamic server management
- ✅ Created quick setup configurations for popular MCP servers
- ✅ Implemented custom command aliases with parameter substitution
- ✅ Added /alias command for creating shortcuts and command sequences
- ✅ Added command history with arrow keys and Emacs keybindings (SimpleLineReader)

## Phase 8: UI/UX Improvements
- [ ] Update /backend and /model commands to show current setting when no params
  - [ ] Add popup selection box for available backends/models
  - [ ] Show "current: <value>" before selection
- [ ] Consolidate MCP commands under /mcp with subcommands
  - [ ] Move /servers, /tools, /resources, /prompts, /connect, /disconnect, /discover, /saved
  - [ ] Add "/mcp connect <command> <args> --env KEY=VALUE" for arbitrary servers
  - [ ] Support multiple --env flags for environment variables
- [ ] Add /context subcommands for manual file management
  - [ ] /context add <file> - Add local file to context
  - [ ] /context rm <file> - Remove file from context
  - [ ] Support persistent context files across conversations
- [ ] Fix arrow keys and Emacs keybindings in line editor
  - [ ] Currently showing escape sequences (^[[A, ^P, etc) instead of working
  - [ ] Need proper terminal input handling for SimpleLineReader

## Phase 9: BEAM-Native MCP Transport
- [ ] Create custom MCP transport using BEAM message passing
  - [ ] Implement transport that uses Erlang processes instead of stdio/SSE
  - [ ] Support connecting MCP servers as supervised GenServers
  - [ ] Enable direct message passing between Elixir MCP clients/servers
  - [ ] Benefits:
    - No serialization overhead for local connections
    - Built-in supervision and fault tolerance
    - Native distributed support (connect to remote BEAM nodes)
    - Better performance for Elixir-based MCP tools
  - [ ] Implementation:
    - Create MCPChat.MCP.BeamTransport behaviour
    - Implement client and server sides
    - Support both local and distributed (node-to-node) connections
    - Maintain compatibility with JSON-RPC protocol structure
  - [ ] Use cases:
    - Running MCP servers as part of the same BEAM VM
    - Distributed MCP servers across Erlang cluster
    - High-performance local tool execution

## Phase 10: Library Extraction
- [ ] Extract reusable components into standalone Hex packages
  - [ ] **ex_mcp** - Model Context Protocol client/server library
    - [ ] All MCP protocol implementation
    - [ ] Stdio, SSE, and BEAM transports
    - [ ] Server manager and discovery
    - [ ] Client connection handling
    - [ ] Would enable any Elixir app to add MCP support
  - [ ] **ex_llm** - Unified LLM adapter library
    - [ ] Adapter behaviour definition
    - [ ] Anthropic, OpenAI, Ollama adapters
    - [ ] Streaming support
    - [ ] Model listing and management
    - [ ] Standardized response format
  - [ ] **ex_llm_local** - Local model support via Bumblebee
    - [ ] Model loading/unloading
    - [ ] EXLA/EMLX configuration
    - [ ] Hardware acceleration detection
    - [ ] Optimized inference settings
  - [ ] **ex_context** - LLM context management library
    - [ ] Token counting for various models
    - [ ] Context truncation strategies (sliding window, smart)
    - [ ] Message prioritization
    - [ ] Token limit handling
  - [ ] **ex_llm_cost** - LLM cost tracking library
    - [ ] Pricing data for all major models
    - [ ] Token usage tracking
    - [ ] Cost calculation and reporting
    - [ ] Multiple currency support
  - [ ] **ex_cmd_alias** - Command alias system
    - [ ] Alias definition and storage
    - [ ] Parameter substitution
    - [ ] Command expansion
    - [ ] Circular reference detection
  - [ ] **ex_readline** - Better line editing for Elixir
    - [ ] Proper terminal handling
    - [ ] Command history
    - [ ] Keybinding support
    - [ ] Tab completion framework
  - [ ] Benefits of extraction:
    - Other Elixir apps can use MCP without the chat interface
    - LLM adapters become reusable across projects
    - Context management can be shared between different AI apps
    - Each library can evolve independently
    - Better testing and documentation per component

## Development Notes

- Use supervisor trees for fault tolerance
- Implement backpressure for streaming responses
- Keep MCP protocol logic separate from UI
- Use behaviours for extensibility
- Follow Elixir naming conventions
- Add telemetry for monitoring