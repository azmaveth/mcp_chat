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
mcp_chat/                        # Main application (refactored to use extracted libraries)
├── lib/
│   ├── mcp_chat/
│   │   ├── application.ex      # OTP application supervisor
│   │   ├── cli/                # CLI interface modules
│   │   │   ├── chat.ex         # Main chat loop (uses ExLLMAdapter)
│   │   │   ├── commands/       # Refactored command modules
│   │   │   │   ├── alias.ex   # Alias management commands
│   │   │   │   ├── context.ex  # Context management commands
│   │   │   │   ├── llm.ex     # LLM backend commands
│   │   │   │   ├── mcp.ex     # MCP server commands
│   │   │   │   ├── session.ex # Session management commands
│   │   │   │   └── utility.ex # General utility commands
│   │   │   ├── renderer.ex     # Terminal UI rendering
│   │   │   └── ex_readline_adapter.ex # Adapter for ex_readline
│   │   ├── mcp/                # Legacy MCP modules (being phased out)
│   │   │   ├── ex_mcp_adapter.ex      # Adapter for ex_mcp
│   │   │   ├── server_manager/ # Uses ExMCPAdapter
│   │   │   └── ... (other legacy modules)
│   │   ├── llm/                # Legacy LLM modules (being phased out)
│   │   │   ├── ex_llm_adapter.ex      # Adapter for ex_llm
│   │   │   └── ... (other legacy modules)
│   │   ├── alias/              # Alias adapter
│   │   │   └── ex_alias_adapter.ex    # Adapter for ex_alias
│   │   ├── config.ex           # Configuration management
│   │   └── session.ex          # Chat session state
│   └── mcp_chat.ex             # Main module
├── config/                      # Configuration files
├── test/                        # Test files
└── priv/                        # Static assets

Extracted Libraries (COMPLETED):
├── ex_mcp/                     # Model Context Protocol library
│   ├── lib/
│   │   ├── ex_mcp.ex          # Main API module
│   │   ├── ex_mcp/
│   │   │   ├── client.ex      # MCP client functionality
│   │   │   ├── server.ex      # MCP server functionality  
│   │   │   ├── transports/    # Transport implementations
│   │   │   │   ├── stdio.ex   # Stdio transport
│   │   │   │   ├── websocket.ex # WebSocket transport
│   │   │   │   └── beam.ex    # BEAM transport (in progress)
│   │   │   ├── protocol/      # Protocol implementation
│   │   │   └── types.ex       # Shared types
│   └── test/                   # Comprehensive test suite
├── ex_llm/                     # All-in-one LLM library 
│   ├── lib/
│   │   ├── ex_llm.ex          # Main API module
│   │   ├── ex_llm/
│   │   │   ├── adapters/      # Provider adapters
│   │   │   │   ├── anthropic.ex # Anthropic Claude
│   │   │   │   ├── openai.ex    # OpenAI GPT
│   │   │   │   ├── ollama.ex    # Ollama local
│   │   │   │   ├── bedrock.ex   # AWS Bedrock
│   │   │   │   ├── gemini.ex    # Google Gemini
│   │   │   │   └── local.ex     # Bumblebee/Nx
│   │   │   ├── context.ex     # Context window management
│   │   │   ├── cost.ex        # Cost calculation
│   │   │   ├── session.ex     # Session management
│   │   │   └── types.ex       # Shared types
│   └── test/                   # Comprehensive test suite
├── ex_alias/                   # Command alias system
│   ├── lib/
│   │   ├── ex_alias.ex        # Main API module
│   │   ├── ex_alias/
│   │   │   ├── core.ex        # Pure functional core
│   │   │   └── persistence.ex # JSON persistence
│   └── test/                   # Test suite
└── ex_readline/                # Line editing library
    ├── lib/
    │   ├── ex_readline.ex     # Main API module
    │   ├── ex_readline/
    │   │   ├── simple_reader.ex  # Simple IO-based reader
    │   │   └── line_editor.ex    # Advanced readline features
    └── test/                   # Test suite

Architecture Benefits (ACHIEVED):
✅ Modular design - Each library handles one responsibility
✅ Reusable components - Libraries can be used in other projects  
✅ Adapter pattern - Maintains backward compatibility
✅ Reduced dependencies - Removed WebSockex, AWS, Req, Plug deps
✅ Clean separation - LLM, MCP, Alias, and Readline concerns separated
```

## Tasks

### Phase 1: Core Infrastructure
- [x] Create application supervisor structure
- [x] Implement configuration loader (TOML support)
- [x] Set up basic CLI interface with Owl
- [x] Create session state management

### Phase 2: MCP Protocol Implementation (COMPLETED - See ex_mcp)
- [x] Core MCP functionality extracted to ex_mcp library
- [x] All protocol implementation moved to [/Users/azmaveth/code/ex_mcp/TASKS.md]

### Phase 3: LLM Backend Integration (COMPLETED - See ex_llm)
- [x] LLM functionality extracted to ex_llm library
- [x] All provider adapters moved to [/Users/azmaveth/code/ex_llm/TASKS.md]
- [ ] TODO: Migrate mcp_chat to use ExLLMAdapter exclusively
  - [ ] Update CLI commands to use ExLLMAdapter with provider parameter
  - [ ] Update MCP server handler to use ExLLMAdapter
  - [ ] Remove redundant adapter files from mcp_chat/lib/mcp_chat/llm/
  - [ ] Update tests to use ExLLMAdapter

### Phase 4: CLI Chat Interface
- [x] Build interactive chat loop
- [x] Add command system (e.g., /help, /config, /servers)
- [x] Implement chat history
- [x] Add context management
- [x] Create rich terminal UI with Owl

### Phase 5: Local Model Support (COMPLETED - See ex_llm)
- [x] Local model support integrated into ex_llm library
- [x] See [/Users/azmaveth/code/ex_llm/TASKS.md] for local model features

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
- [x] Update /backend and /model commands to show current setting when no params
  - [x] /backend already showed current setting
  - [x] /model now shows current model and available models when no params
  - [ ] Add popup selection box for available backends/models (future enhancement)
- [x] Consolidate MCP commands under /mcp with subcommands
  - [x] Move /servers, /tools, /resources, /prompts, /connect, /disconnect, /discover, /saved
  - [ ] Add "/mcp connect <command> <args> --env KEY=VALUE" for arbitrary servers
  - [ ] Support multiple --env flags for environment variables
- [x] Add /context subcommands for manual file management
  - [x] /context add <file> - Add local file to context
  - [x] /context rm <file> - Remove file from context
  - [ ] Support persistent context files across conversations
- [ ] Fix arrow keys and Emacs keybindings (MOVED to ex_readline)
  - [ ] Currently showing escape sequences (^[[A, ^P, etc) instead of working
  - [ ] Need proper terminal input handling for SimpleLineReader
  - [ ] See [/Users/azmaveth/code/ex_readline/TASKS.md] for implementation

## Phase 9: BEAM-Native MCP Transport (MOVED to ex_mcp)
- [ ] BEAM transport implementation tracked in [/Users/azmaveth/code/ex_mcp/TASKS.md]
- [x] Initial BEAM transport completed in ex_mcp library

## Phase 10: Library Extraction and Refactoring (COMPLETED)
- [x] Extract reusable components into standalone libraries
- [x] Refactor mcp_chat to use extracted libraries
  - [x] Update dependencies in mix.exs to use path dependencies
  - [x] Remove external dependencies (websockex, aws, req, plug)
  - [x] Create adapter modules to bridge API differences
    - [x] MCPChat.LLM.ExLLMAdapter - Unified LLM interface
    - [x] MCPChat.Alias.ExAliasAdapter - Command alias management
    - [x] MCPChat.CLI.ExReadlineAdapter - Line reading with history
    - [x] MCPChat.MCP.ExMCPAdapter - MCP client functionality
  - [x] Update application supervision tree
  - [x] Fix API compatibility issues between old and new interfaces
  - [x] Update imports throughout codebase
  - [x] Successfully test refactored application startup

### Extracted Libraries:
- **ex_mcp** - Model Context Protocol implementation → See [/Users/azmaveth/code/ex_mcp/TASKS.md]
- **ex_llm** - All-in-one LLM library → See [/Users/azmaveth/code/ex_llm/TASKS.md]
- **ex_alias** - Command alias system → See [/Users/azmaveth/code/ex_alias/TASKS.md]
- **ex_readline** - Enhanced line editing → See [/Users/azmaveth/code/ex_readline/TASKS.md]

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
- [x] Add built-in MCP resources for better user experience
  - [x] Default resources to include:
    - [x] Project documentation links
      - GitHub repository URL
      - Online documentation site
      - API reference
      - Examples directory
    - [x] Quick reference cards
      - Command cheat sheet
      - MCP server setup guide
      - LLM backend comparison
    - [x] System information
      - Current version
      - Loaded configuration
      - Available features
  - [x] Implementation approach:
    - Create built-in MCP resource server
    - Auto-load on startup
    - Available via /resource command
- [x] Add default MCP prompts for common tasks
  - [x] Utility prompts:
    - [x] "getting_started" - Interactive tutorial
    - [x] "demo" - Showcase all capabilities
    - [x] "troubleshoot" - Diagnose common issues
    - [x] "optimize" - Suggest config improvements
  - [x] Workflow prompts:
    - [x] "code_review" - Template for code analysis
    - [x] "research_mode" - Structured research approach
    - [x] "debug_session" - Debugging methodology
    - [x] "explain_code" - Explain code with context
    - [x] "setup_mcp_server" - Guide for adding servers
  - [ ] Integration prompts:
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

## Phase 14: Additional LLM Backends (COMPLETED - See ex_llm)
- [x] AWS Bedrock and Google Gemini support added to ex_llm
- [x] See [/Users/azmaveth/code/ex_llm/TASKS.md] for provider details

## Development Notes

- Use supervisor trees for fault tolerance
- Implement backpressure for streaming responses
- Keep MCP protocol logic separate from UI
- Use behaviours for extensibility
- Follow Elixir naming conventions
- Add telemetry for monitoring