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
│   │   │   ├── commands/       # Refactored command modules
│   │   │   │   ├── alias.ex   # Alias management commands
│   │   │   │   ├── context.ex  # Context management commands
│   │   │   │   ├── llm.ex     # LLM backend commands
│   │   │   │   ├── mcp.ex     # MCP server commands
│   │   │   │   ├── session.ex # Session management commands
│   │   │   │   └── utility.ex # General utility commands
│   │   │   └── renderer.ex     # Terminal UI rendering
│   │   ├── mcp/                # MCP protocol implementation
│   │   │   ├── client.ex       # MCP client connection
│   │   │   ├── protocol.ex     # Protocol messages
│   │   │   └── server.ex       # Server connection manager
│   │   ├── llm/                # LLM backend adapters
│   │   │   ├── adapter.ex      # Common adapter behaviour
│   │   │   ├── openai.ex       # OpenAI API adapter
│   │   │   ├── anthropic.ex    # Anthropic API adapter
│   │   │   ├── bedrock.ex      # AWS Bedrock adapter
│   │   │   ├── gemini.ex       # Google Gemini adapter
│   │   │   ├── ollama.ex       # Ollama adapter
│   │   │   └── local.ex        # Bumblebee/Nx local models
│   │   ├── config.ex           # Configuration management
│   │   └── session.ex          # Chat session state
│   └── mcp_chat.ex             # Main module
├── config/                      # Configuration files
├── test/                        # Test files
└── priv/                        # Static assets

Extracted Libraries:
├── ex_llm/                     # All-in-one LLM library (COMPLETED)
│   ├── lib/
│   │   ├── ex_llm.ex          # Main API module
│   │   ├── ex_llm/
│   │   │   ├── adapters/      # Provider adapters
│   │   │   ├── context.ex     # Context window management
│   │   │   ├── cost.ex        # Cost calculation
│   │   │   ├── session.ex     # Session management (integrated)
│   │   │   └── types.ex       # Shared types
│   └── test/                   # Comprehensive test suite

Note: ex_session was integrated into ex_llm for a complete all-in-one solution
Note: ex_alias has not been extracted yet - still exists as MCPChat.Alias
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
- [x] Write unit tests for all modules (completed - all major modules have test coverage)
  - [x] Context module (token estimation, truncation strategies)
  - [x] Cost module (pricing calculations, usage tracking)
  - [x] Alias module (command aliases, circular reference detection)
  - [x] Persistence module (save/load sessions, exports)
  - [x] Session module (message management, context handling)
  - [x] Config module (TOML loading, environment variables)
  - [x] Anthropic LLM adapter (basic tests, needs mocking for full coverage)
  - [x] OpenAI LLM adapter (basic tests, needs mocking for full coverage)
  - [x] Ollama LLM adapter (basic tests)
  - [x] AWS Bedrock LLM adapter (basic tests)
  - [x] Google Gemini LLM adapter (basic tests)
  - [x] Local LLM adapter (needs Bumblebee mock tests)
  - [x] Model Loader module (GenServer for model management)
  - [x] EXLA/EMLX configuration module
  - [x] CLI Commands module (command handling, validation)
  - [x] CLI Chat module (basic tests with IO capture)
  - [x] CLI Renderer module
  - [x] CLI SimpleLineReader module (line editing, history)
  - [ ] CLI LineEditor module (complex line editing - deprecated)
  - [x] MCP client modules (Protocol, Client, ServerManager tests)
  - [x] MCP server modules (Handler, SSEServer, StdioServer)
  - [x] MCP SSE client module
  - [x] MCP Discovery module (server auto-discovery)
  - [x] MCP ServerPersistence module (saved servers)
  - [x] MCP BuiltinResources module
  - [ ] MCP DemoServer module (example server)
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

## Phase 10: Library Extraction (COMPLETED)
- [x] Extract reusable components into standalone Hex packages
  - [ ] **ex_mcp** - Model Context Protocol client/server library
    - [ ] All MCP protocol implementation
    - [ ] Stdio, SSE, and BEAM transports
    - [ ] Server manager and discovery
    - [ ] Client connection handling
    - [ ] Would enable any Elixir app to add MCP support
  - [x] **ex_llm** - All-in-one Elixir LLM library (COMPLETED)
    - [x] Unified adapter interface for multiple providers
    - [x] Anthropic, OpenAI (planned), Ollama (planned) adapters
    - [x] Streaming support with SSE parsing
    - [x] Model listing and management
    - [x] Standardized response format
    - [x] Integrated cost tracking and calculation
    - [x] Token estimation functionality
    - [x] Context window management
      - [x] Automatic message truncation
      - [x] Multiple truncation strategies (sliding_window, smart)
      - [x] Model-specific context window sizes
      - [x] Context validation and statistics
    - [x] Configuration injection pattern
    - [x] Comprehensive error handling
    - [x] Full test coverage
    - [x] Published to local directory: `/Users/azmaveth/code/ex_llm/ex_llm`
  - [ ] **ex_llm_local** - Local model support via Bumblebee
    - [ ] Model loading/unloading
    - [ ] EXLA/EMLX configuration
    - [ ] Hardware acceleration detection
    - [ ] Optimized inference settings
    - Note: May be integrated into ex_llm in the future
  - [x] **ex_session** - Pure functional session management (INTEGRATED INTO ex_llm)
    - [x] Message history management
    - [x] Token usage tracking
    - [x] JSON persistence
    - [x] Metadata handling (timestamps, etc.)
    - [x] Integrated into ex_llm as ExLLM.Session module
  - [ ] **ex_alias** - Command alias system (NOT YET EXTRACTED)
    - [x] Alias definition and storage (exists in mcp_chat)
    - [x] Parameter substitution (exists in mcp_chat)
    - [x] Command expansion (exists in mcp_chat)
    - [x] Circular reference detection (exists in mcp_chat)
    - [x] JSON persistence (exists in mcp_chat)
    - [ ] Extract to standalone library
    - Note: Currently exists as MCPChat.Alias in the main project
  - [ ] **ex_readline** - Better line editing for Elixir
    - [ ] Proper terminal handling
    - [ ] Command history
    - [ ] Keybinding support
    - [ ] Tab completion framework
  - [x] Design decisions made:
    - Combined ex_llm, ex_context, and ex_llm_cost into single ex_llm library
    - Created ex_llm as comprehensive all-in-one solution for Elixir LLM needs
    - Kept modular internal architecture while presenting unified API
    - Prioritized developer experience with automatic features (cost tracking, context management)
    - Maintained flexibility through configuration injection pattern
  - [x] Benefits achieved:
    - Single dependency for all LLM functionality
    - Automatic cost tracking and context management
    - Consistent API across all providers
    - Easy to integrate into any Elixir project
    - Well-tested and documented

## Phase 11: Supervision Improvements
- [ ] Enhance supervision tree for better fault tolerance
  - [ ] Add supervision for Port processes (stdio connections)
  - [ ] Create supervised wrapper for main chat loop
  - [ ] Implement circuit breakers for LLM API calls
  - [ ] Add connection pooling with supervision for HTTP clients
  - [ ] Create health checks for supervised processes
  - [ ] Add telemetry and monitoring hooks
- [ ] See [SUPERVISION.md](SUPERVISION.md) for current supervision structure

## Phase 12: Interrupted Response Recovery
- [ ] Implement resumable LLM streaming responses
  - [ ] Save partial responses during streaming
    - [ ] Store response chunks with timestamps
    - [ ] Track token count of partial response
    - [ ] Save request context (messages, model, parameters)
  - [ ] Detect interruptions (network, user-initiated, errors)
    - [ ] Distinguish between recoverable and non-recoverable errors
    - [ ] Implement timeout detection for stalled streams
    - [ ] Handle Ctrl-C gracefully during streaming
  - [ ] Resume mechanisms
    - [ ] `/resume` command to continue last interrupted response
    - [ ] Show partial response and continuation point
    - [ ] Adjust token count to account for already-received content
    - [ ] Support different resumption strategies:
      - Continue from exact cutoff
      - Regenerate last paragraph for coherence
      - Summarize and continue
  - [ ] Storage considerations
    - [ ] Save interrupted streams to session
    - [ ] Persist across application restarts
    - [ ] Clean up old interrupted responses
    - [ ] Handle multiple interrupted responses per session
  - [ ] UI/UX improvements
    - [ ] Show indicator when response is resumable
    - [ ] Display partial response differently (e.g., dimmed or italic)
    - [ ] Prompt user to resume on reconnection
    - [ ] Show estimated tokens/cost saved by resuming

## Phase 13: CLI Commands Refactoring
- [ ] Refactor monolithic CLI commands module (in progress)
  - [x] Create base behavior for command modules
  - [x] Split commands into logical modules:
    - [x] Session commands (new, save, load, sessions, history)
    - [x] Utility commands (help, clear, config, cost, export)
    - [x] LLM commands (backend, model, models, loadmodel, unloadmodel, acceleration)
    - [x] MCP commands (servers, discover, connect, disconnect, tools, resources, prompts)
    - [x] Context commands (context, system, tokens, strategy)
    - [x] Alias commands (alias add/remove/list)
  - [ ] Fix compilation issues with refactored modules
    - [x] Update function references to use correct module names
    - [x] Fix renderer function calls (render_* -> show_*)
    - [x] Fix config get calls
    - [x] Fix cost/context data structure references
    - [x] Fix remaining compilation error in utility module
  - [x] Update tests for refactored command structure
  - [ ] Benefits:
    - Reduced cyclomatic complexity (from 37 to <10 per module)
    - Better code organization and maintainability
    - Easier to add new commands
    - Follows single responsibility principle

## Phase 14: Default Resources and Prompts
- [ ] Add built-in MCP resources for better user experience
  - [ ] Default resources to include:
    - [ ] Project documentation links
      - GitHub repository URL
      - Online documentation site
      - API reference
      - Examples directory
    - [ ] Quick reference cards
      - Command cheat sheet
      - MCP server setup guide
      - LLM backend comparison
    - [ ] System information
      - Current version
      - Loaded configuration
      - Available features
  - [ ] Implementation approach:
    - Create built-in MCP resource server
    - Auto-load on startup
    - Available via /resource command
- [ ] Add default MCP prompts for common tasks
  - [ ] Utility prompts:
    - [ ] "getting_started" - Interactive tutorial
    - [ ] "demo" - Showcase all capabilities
    - [ ] "troubleshoot" - Diagnose common issues
    - [ ] "optimize" - Suggest config improvements
  - [ ] Workflow prompts:
    - [ ] "code_review" - Template for code analysis
    - [ ] "writing_assistant" - Content creation workflow
    - [ ] "research_mode" - Structured research approach
    - [ ] "debug_session" - Debugging methodology
  - [ ] Integration prompts:
    - [ ] "setup_mcp_server" - Guide for adding new servers
    - [ ] "create_agent" - Multi-agent setup wizard
    - [ ] "api_integration" - Connect external services
- [ ] Include default MCP servers for demos
  - [ ] Essential servers to bundle:
    - [ ] Filesystem (already common)
    - [ ] Time/date server (for scheduling demos)
    - [ ] Calculator (for computation demos)
    - [ ] Demo data server (sample datasets)
  - [ ] Optional but useful:
    - [ ] SQLite server (local data management)
    - [ ] Git server (code repository interaction)
    - [ ] Markdown server (documentation access)
  - [ ] Demo scenarios:
    - [ ] "Analyze this file and suggest improvements"
    - [ ] "Schedule a task for next week"
    - [ ] "Calculate the cost of running this prompt 1000 times"
    - [ ] "Search my documents for information about X"
- [ ] Create interactive demo system
  - [ ] `/demo` command that:
    - [ ] Checks available MCP servers
    - [ ] Runs through capability showcase
    - [ ] Demonstrates each major feature
    - [ ] Shows cost tracking
    - [ ] Displays context management
    - [ ] Performs actual useful tasks
  - [ ] Demo flow:
    1. Connect to filesystem server
    2. Create a sample file
    3. Analyze the file
    4. Generate improvements
    5. Save results
    6. Show cost and token usage
    7. Demonstrate context truncation
    8. Show session save/load

## Phase 14: Additional LLM Backends
- [x] Add AWS Bedrock support
  - [x] Implement Bedrock adapter (MCPChat.LLM.Bedrock)
  - [x] Support multiple model providers through Bedrock:
    - [x] Anthropic Claude (via Bedrock)
    - [x] AI21 Labs Jurassic
    - [x] Amazon Titan
    - [x] Cohere Command
    - [x] Meta Llama 2/3
    - [x] Mistral/Mixtral
  - [x] Authentication via AWS credentials:
    - [x] AWS access key/secret key
    - [x] IAM role support
    - [x] AWS profile support
    - [x] STS temporary credentials
  - [x] Region configuration
  - [x] Streaming support with Bedrock runtime
  - [x] Model-specific parameter handling
  - [x] Cost tracking for Bedrock pricing
- [x] Add Google Gemini support
  - [x] Implement Gemini adapter (MCPChat.LLM.Gemini)
  - [x] Support Gemini model variants:
    - [x] Gemini Pro
    - [x] Gemini Pro Vision (multimodal)
    - [x] Gemini Ultra (when available)
    - [x] Gemini Nano (for local/edge)
  - [x] Authentication:
    - [x] API key support
    - [ ] OAuth2 for user auth (not implemented - API key sufficient)
    - [ ] Service account credentials (not implemented - API key sufficient) 
    - [ ] ADC (Application Default Credentials) (not implemented - API key sufficient)
  - [x] Features:
    - [x] Text generation
    - [x] Multimodal support (images)
    - [ ] Function calling (not implemented in initial version)
    - [x] Streaming responses
    - [x] Safety settings configuration
  - [ ] Region/location configuration (uses default)
  - [ ] Rate limiting and quota management (handled by API)
- [x] Update configuration examples:
  - [x] Add Bedrock config section
  - [x] Add Gemini config section
  - [x] Document authentication methods
  - [x] Show region/endpoint configuration
- [x] Update model listing:
  - [x] Dynamically fetch available Bedrock models
  - [x] List Gemini model variants
  - [x] Show model capabilities (text, vision, etc.)
- [x] Integration testing:
  - [x] Test each Bedrock model provider (basic tests)
  - [x] Test Gemini multimodal features (basic tests)
  - [ ] Verify streaming works correctly (requires API keys)
  - [x] Ensure cost tracking is accurate

## Development Notes

- Use supervisor trees for fault tolerance
- Implement backpressure for streaming responses
- Keep MCP protocol logic separate from UI
- Use behaviours for extensibility
- Follow Elixir naming conventions
- Add telemetry for monitoring