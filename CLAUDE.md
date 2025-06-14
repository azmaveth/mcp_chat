# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 🚀 Essential Commands

```bash
# Initial setup and build
./setup.sh                        # One-time setup: installs deps, builds, creates config

# Development workflow
mix deps.get                      # Get dependencies
mix compile                       # Compile the project
mix escript.build                 # Build the executable
./mcp_chat                        # Run the chat client

# Testing
mix test                          # Run all tests
mix test test/specific_test.exs  # Run specific test file
mix test --only integration:true  # Run only integration tests

# Code quality
mix credo                         # Run code analysis
mix dialyzer                      # Run static type checking (slow first run)

# Running MCP Chat

# Method 1: Interactive mode with full terminal support (RECOMMENDED)
iex -S mix                        # Start in IEx shell
iex> MCPChat.main()              # Run with full readline support

# Method 2: Direct launcher (uses elixir --no-halt)
./mcp_chat                        # Direct execution with terminal support

# Method 3: IEx launcher scripts
./mcp_chat_iex                    # Attempts to auto-start (may have issues)
./mcp_chat_manual                 # Starts IEx, type MCPChat.main() to begin

# Method 4: Escript mode (limited terminal features)
mix escript.build
./mcp_chat                        # Basic functionality, no arrow keys

# Method 5: Mix task (not recommended for interactive use)
mix mcp_chat.run                  # May exit immediately due to TTY issues
```

## 🏗️ Architecture Overview

MCP Chat is an Elixir OTP application using extracted libraries for modularity:

### Core Architecture
- **OTP Supervision**: Application supervisor manages all stateful processes
- **Library Extraction**: Core functionality split into reusable libraries (ex_mcp, ex_llm, ex_alias, ex_readline)
- **Adapter Pattern**: Maintains backward compatibility while using new libraries
- **Configuration**: TOML-based with environment variable overrides

### Key Modules
- `MCPChat` - Main entry point (escript module)
- `MCPChat.Application` - OTP supervisor defining the supervision tree
- `MCPChat.Config` - TOML configuration loader with env var support
- `MCPChat.Session` - Chat session state management (GenServer)
- `MCPChat.CLI.Chat` - Main interactive chat loop
- `MCPChat.CLI.Commands.*` - Refactored command modules (session, utility, llm, mcp, context, alias)

### Extracted Libraries (Path Dependencies)
- `ex_mcp` - Model Context Protocol implementation (stdio, SSE transports)
- `ex_llm` - Unified LLM interface (Anthropic, OpenAI, Ollama, Bedrock, Gemini, Local)
- `ex_alias` - Command alias system with circular reference detection
- `ex_readline` - Enhanced line editing with history

### Adapter Modules
Bridge the old interfaces with new libraries:
- `MCPChat.LLM.ExLLMAdapter` - Wraps ex_llm for backward compatibility
- `MCPChat.MCP.ExMCPAdapter` - Wraps ex_mcp client functionality
- `MCPChat.Alias.ExAliasAdapter` - Wraps ex_alias
- `MCPChat.CLI.ExReadlineAdapter` - Wraps ex_readline

## 📝 Important Notes

### Numeric Formatting in Tests
The Elixir formatter automatically adds underscores to numeric literals (e.g., `100000` → `100_000`), which breaks cost tests expecting specific formats. We've disabled the Credo `LargeNumbers` check and use arithmetic expressions instead of literals in tests. See `NUMERIC_FORMATTING_NOTES.md` for details.

### Hardware Acceleration
- Apple Silicon: Uses EMLX (preferred) or EXLA with Metal
- NVIDIA: Uses EXLA with CUDA
- AMD: Uses EXLA with ROCm
- Fallback: Binary backend (no acceleration)

The system auto-detects available backends. Debug messages about acceleration are normal and logged at debug level.

### MCP Server Management
- Servers defined in `config.toml` under `[mcp.servers]`
- Auto-discovery via `/discover` command
- Supports stdio (local) and SSE (remote) transports
- Server state managed by `MCPChat.MCP.ServerManager` GenServer

### Interrupted Response Recovery
- Automatic saving of partial responses during streaming interruptions
- Use `/resume` command to continue from where the response was interrupted
- Three recovery strategies: `exact` (continue from cutoff), `paragraph` (from last complete paragraph), `summarize` (summarize and continue)
- Configurable via `[streaming]` section in config.toml
- Built on ExLLM.StreamRecovery module for robust recovery handling

### Testing Strategy
- Unit tests for all core modules
- Integration tests for LLM backends and MCP functionality
- CLI command tests using meck for mocking
- Use `capture_io` for testing CLI output
- Tests should handle multiple response formats for backward compatibility

## 🔧 Configuration

Configuration file: `~/.config/mcp_chat/config.toml`

Key sections:
- `[llm]` - Default backend and provider-specific settings
- `[mcp]` - MCP server definitions
- `[ui]` - Interface preferences
- `[session]` - Session management settings
- `[context]` - Token limits and truncation strategies
- `[streaming]` - Streaming behavior and recovery settings

Environment variables override config values:
- `ANTHROPIC_API_KEY`
- `OPENAI_API_KEY`
- `OLLAMA_API_BASE`
- `GITHUB_TOKEN`
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` (for Bedrock)
- `GEMINI_API_KEY`