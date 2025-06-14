# MCP Chat User Guide

Welcome to MCP Chat, an Elixir-based chat client that supports multiple Large Language Model (LLM) backends and the Model Context Protocol (MCP) for extensible functionality.

## Table of Contents

1. [Getting Started](#getting-started)
2. [Configuration](#configuration)
3. [Using MCP Chat](#using-mcp-chat)
4. [CLI Commands](#cli-commands)
5. [MCP Server Integration](#mcp-server-integration)
6. [Session Management](#session-management)
7. [Advanced Features](#advanced-features)
8. [Troubleshooting](#troubleshooting)

## Getting Started

### Installation

1. Ensure you have Elixir 1.15+ installed
2. Clone the repository
3. Install dependencies:
   ```bash
   mix deps.get
   ```
4. Build the application:
   ```bash
   mix compile
   ```

### First Run

Build and run MCP Chat:
```bash
# Build the executable
mix escript.build

# Run the chat client
./mcp_chat
```

Or with options:
```bash
./mcp_chat --config path/to/config.toml --backend anthropic
```

### Command Line Options

- `-c, --config PATH` - Path to configuration file (default: `~/.config/mcp_chat/config.toml`)
- `-b, --backend NAME` - LLM backend to use (anthropic, openai, local)
- `-h, --help` - Show help message

## Configuration

MCP Chat uses TOML format for configuration. The default config file is created at `~/.config/mcp_chat/config.toml` on first run.

### Basic Configuration

```toml
[llm]
default = "anthropic"  # Default LLM backend

[llm.anthropic]
api_key = "YOUR_API_KEY"  # Or use ANTHROPIC_API_KEY env var
model = "claude-sonnet-4-20250514"
max_tokens = 4096

[llm.openai]
api_key = "YOUR_API_KEY"  # Or use OPENAI_API_KEY env var
model = "gpt-4"
max_tokens = 4096

[ui]
theme = "dark"
history_size = 1000

[context]
strategy = "smart"    # Context truncation strategy: "smart" or "sliding_window"
max_tokens = 2048     # Tokens to reserve for model response
```

### Environment Variables

API keys can be set via environment variables:
- `ANTHROPIC_API_KEY` - Anthropic API key
- `OPENAI_API_KEY` - OpenAI API key

Environment variables take precedence over config file values.

### MCP Server Configuration

Configure MCP servers in your config file:

```toml
[mcp]
servers = [
  { name = "filesystem", command = ["npx", "-y", "@modelcontextprotocol/server-filesystem", "/tmp"] },
  { name = "github", command = ["npx", "-y", "@modelcontextprotocol/server-github"] }
]
```

## Using MCP Chat

### Basic Chat

Simply type your message and press Enter to send it to the configured LLM:

```
You: Hello, how can you help me today?
Assistant: I'm Claude, an AI assistant. I can help you with a wide variety of tasks...
```

### Multi-line Input

For multi-line messages, use Shift+Enter or paste multi-line text.

### Streaming Responses

Responses are streamed in real-time, showing text as it's generated by the LLM.

## CLI Commands

MCP Chat supports various slash commands for control and configuration:

### General Commands

- `/help` - Show all available commands
- `/exit` or `/quit` - Exit the application
- `/clear` - Clear the chat display
- `/new` - Start a new chat session
- `/history [n]` - Show last n messages (default: 10)
- `/resume` - Resume the last interrupted streaming response
- `/recovery` - Manage recoverable streams (list, info, resume, clean)

### Session Management

- `/save [name]` - Save current session
- `/load <name|number>` - Load a saved session
- `/sessions` - List all saved sessions
- `/export [format] [path]` - Export session (format: json|markdown)

### Configuration Commands

- `/config` - Show current configuration
- `/backend <name>` - Switch LLM backend (anthropic, openai)
- `/model <subcommand>` - Model management (see Model Management section)
- `/models` - List available models for current backend
- `/loadmodel <model-id>` - Load a local model for inference
- `/unloadmodel <model-id>` - Unload a local model
- `/acceleration` - Show hardware acceleration information

### Context Management

MCP Chat now includes automatic context window management powered by ExLLM:

- `/context` - Show context statistics and settings
- `/system <prompt>` - Set or update system prompt
- `/tokens [max]` - Set maximum token limit
- `/strategy <name>` - Set truncation strategy (sliding_window, smart)
- `/cost` - Display current session cost
- `/stats` - Show detailed session statistics including:
  - Token usage and context window utilization
  - Model-specific context window size
  - Token allocation (system/conversation/response)
  - Remaining tokens available

#### Automatic Context Truncation

MCP Chat automatically manages conversation context to prevent overflow:

- **Smart Strategy** (default): Preserves system messages and recent context while intelligently removing middle messages
- **Sliding Window Strategy**: Keeps only the most recent messages that fit in the context window

Configure in `config.toml`:
```toml
[context]
strategy = "smart"  # or "sliding_window"
max_tokens = 2048   # Reserve tokens for response
```

The system automatically:
- Detects the context window size for your chosen model
- Tracks token usage across the conversation
- Truncates messages intelligently when approaching limits
- Ensures responses always have sufficient token space

### MCP Server Commands

- `/mcp servers` - List connected MCP servers with health status
- `/mcp discover` - Discover available MCP servers
- `/mcp connect <name>` - Connect to an MCP server
- `/mcp disconnect <name>` - Disconnect from an MCP server

The `/mcp servers` command shows comprehensive server status including:
- Connection status (✓ CONNECTED, ⟳ CONNECTING, ✗ FAILED, ⚠ DISCONNECTED)
- Health indicators (✓ HEALTHY, ⚠ UNHEALTHY)
- Server uptime and tool counts
- Success rate percentage and average response time
- Auto-disable feature for unhealthy servers after consecutive failures

### MCP Tool Commands

- `/tools [server]` - List available tools
- `/tool <server> <tool> [args]` - Execute a tool

### MCP Resource Commands

- `/resources [server]` - List available resources
- `/resource <server> <uri>` - Read a resource

### MCP Prompt Commands

- `/prompts [server]` - List available prompts
- `/prompt <server> <name> [args]` - Get a prompt

### Custom Aliases

- `/alias <name> <command1> [command2...]` - Create command alias
- `/alias <name>` - Show alias definition
- `/alias` - List all aliases
- `/alias remove <name>` - Remove an alias

Example:
```
/alias morning /new /system "You are a helpful morning assistant" Hello! What's on the agenda today?
```

### Notification Management

- `/notification on` - Enable all notifications
- `/notification off` - Disable all notifications  
- `/notification status` - Show notification settings
- `/notification history [n]` - Show last n notification events
- `/notification clear` - Clear notification history
- `/notification test` - Send test notifications

Configure notification settings per category:
```
/notification config connection on    # Connection events
/notification config resource off     # Resource changes
/notification config progress on      # Progress updates
```

## MCP Server Integration

### Quick Setup

Use the discover command to find and connect to popular MCP servers:

```
/discover
/connect filesystem
```

### Manual Connection

1. List available servers: `/servers`
2. Connect to a server: `/connect github`
3. Use server tools: `/tool github list_repos owner=anthropics`

### Using MCP Tools

After connecting to an MCP server, you can:

1. List available tools:
   ```
   /tools filesystem
   ```

2. Execute a tool:
   ```
   /tool filesystem read_file path=/tmp/test.txt
   ```

3. Tools can also be invoked automatically during conversation when relevant.

## Session Management

### Saving Sessions

Save your conversation for later:
```
/save project-discussion
```

### Loading Sessions

Load by name:
```
/load project-discussion
```

Load by number from session list:
```
/sessions
/load 3
```

### Exporting Sessions

Export to JSON:
```
/export json chat-backup.json
```

Export to Markdown:
```
/export markdown conversation.md
```

## Advanced Features

### Context Window Management

MCP Chat automatically manages context to fit within token limits:

- View current context usage: `/context`
- Set custom token limit: `/tokens 8192`
- Choose truncation strategy:
  - `/strategy sliding_window` - Keep most recent messages
  - `/strategy smart` - Keep system prompt, initial context, and recent messages

### Cost Tracking

Track API usage costs:
- View current session cost: `/cost`
- Costs are calculated based on model pricing
- Token usage is tracked automatically

### Command Aliases

Create shortcuts for common command sequences:

```
/alias gpt /backend openai /model gpt-4-turbo
/alias claude4 /backend anthropic /model claude-sonnet-4-20250514
```

Use aliases:
```
/gpt  # Switches to GPT-4 Turbo
/claude4  # Switches to Claude 4
```

### TUI (Text User Interface) Components

MCP Chat includes beautiful text-based UI components for monitoring operations:

#### Progress Display
Track long-running MCP operations with real-time progress bars:
```
/tui show progress  # Show progress display
/tui hide          # Hide all displays
```

Features:
- Multiple concurrent progress bars
- Color-coded status indicators
- Automatic updates for MCP operations

#### Resource Cache Display
Monitor the local resource cache:
```
/tui show cache      # Summary view
/tui show cache full # Detailed view with resource list
/tui show both       # Show both progress and cache
```

Cache statistics shown:
- Total resources and cache size
- Hit rate percentage
- Average response time
- Memory usage
- Last cleanup time

#### TUI Controls
```
/tui toggle   # Cycle through display modes
/tui status   # Show current display status
```

Keyboard shortcuts (when TUI is active):
- `p` - Show progress
- `c` - Show cache
- `b` - Show both
- `h` - Hide all
- `d` - Detailed cache view
- `s` - Summary cache view

### Performance Optimization

MCP Chat includes several performance features:

#### Startup Modes
Configure how MCP servers connect at startup:
```toml
[startup]
mcp_connection_mode = "lazy"  # Options: lazy, eager, background
profiling_enabled = false     # Enable startup time profiling
```

- **lazy**: Connect when first used (fastest startup)
- **eager**: Connect all at startup (slower startup, no delays)  
- **background**: Connect after UI loads (balanced)

Enable startup profiling:
```bash
MCP_CHAT_STARTUP_PROFILING=true ./mcp_chat
```

Or in config:
```toml
[startup]
profiling_enabled = true
```

When enabled, shows detailed timing for each startup phase.

#### Memory Management
Configure message storage limits:
```toml
[memory]
memory_limit = 100          # Messages kept in memory
session_cache_size = 5      # Number of sessions to cache
page_size = 20              # Messages per page for pagination
max_disk_size = 10485760    # Max disk storage per session (10MB)
disk_cache_enabled = true   # Enable disk storage for old messages
cache_dir = "~/.config/mcp_chat/cache"  # Cache directory
```

Features:
- Hybrid memory/disk storage prevents memory bloat
- Automatic pagination for large conversations
- Smart context retrieval for token management
- Per-session storage limits

#### Resource Caching
Enable local caching for MCP resources:
```toml
[resource_cache]
enabled = true
max_size = 104857600    # 100MB
ttl = 3600              # 1 hour
cleanup_interval = 300  # 5 minutes
```

Benefits:
- Faster resource access
- Reduced server load
- Automatic cache invalidation
- LRU eviction policy

### @ Symbol Context Inclusion

MCP Chat supports including external content directly in your messages using @ symbol references. This feature allows you to seamlessly integrate files, URLs, MCP resources, and more into your conversations.

#### Supported @ Symbol Types

1. **Files**: `@file:path` or `@f:path`
   ```
   Please analyze @file:README.md and suggest improvements
   ```

2. **URLs**: `@url:https://...` or `@u:https://...`
   ```
   Summarize @url:https://example.com/article.html
   ```

3. **MCP Resources**: `@resource:name` or `@r:name`
   ```
   Check the database schema in @resource:db/schema
   ```

4. **MCP Prompts**: `@prompt:name` or `@p:name`
   ```
   Use @prompt:code-review to analyze this code
   ```

5. **MCP Tools**: `@tool:name:args` or `@t:name:args`
   ```
   Calculate @tool:calculator:expression=2+2
   ```

#### Usage Examples

**Including multiple files:**
```
Compare @file:src/main.ex with @file:test/main_test.exs
```

**Combining different types:**
```
Based on @url:https://docs.example.com/api and @file:config.toml, 
please implement the missing features
```

**Using MCP resources:**
```
Update the code based on @resource:project/requirements
```

**Tool execution with arguments:**
```
Check if @tool:github:list_repos:owner=elixir-lang has any new releases
```

#### Features

- **Automatic Resolution**: Content is fetched and included before sending to the LLM
- **Error Handling**: Failed references show clear error messages
- **Token Counting**: Included content is counted in context tokens
- **Concurrent Fetching**: Multiple references are resolved in parallel
- **Smart Formatting**: Content is formatted appropriately based on type

#### Configuration

Configure @ symbol behavior in your config.toml:
```toml
[context]
max_file_size = 1048576        # 1MB max file size
http_timeout = 10000           # 10s timeout for URLs
mcp_timeout = 30000            # 30s timeout for MCP operations
validate_content = true        # Validate content before inclusion
```

#### Tips

1. **Use shortcuts**: `@f:` instead of `@file:`, `@r:` instead of `@resource:`
2. **Check available resources**: Use `/resources` to see what's available
3. **Monitor token usage**: Large files can consume many tokens
4. **Combine with commands**: `/context` shows total tokens including @ symbol content

### Conversation Templates

Use system prompts to set conversation context:
```
/system You are an expert Elixir developer. Provide concise, idiomatic code examples.
```

## Troubleshooting

### Common Issues

1. **"API key not configured"**
   - Set your API key in the config file or environment variable
   - Check with `/config` command

2. **"Failed to connect to MCP server"**
   - Ensure the server command is correct
   - Check if required npm packages are installed
   - Try `/discover` for auto-configuration

3. **"Context window exceeded"**
   - Use `/context` to check usage
   - Adjust with `/tokens` or `/strategy`
   - Start a new session with `/new`

### Debug Mode

Set log level in config for debugging:
```toml
[debug]
log_level = "debug"
```

### Getting Help

- Use `/help` for command reference
- Check configuration with `/config`
- View server logs for MCP connection issues

### Streaming Recovery

MCP Chat includes comprehensive streaming recovery powered by ExLLM's StreamRecovery module:

#### Automatic Recovery
- Streams are automatically saved with recovery checkpoints during generation
- Recovery IDs are preserved when interruptions occur (Ctrl+C, network issues, etc.)
- Smart error detection determines if streams are recoverable
- Automatic resume hints guide users to continue interrupted responses

#### Recovery Commands
- `/resume` - Resume the last interrupted response in current session
- `/recovery list` - Show all recoverable streams with detailed metadata
- `/recovery info <id>` - View detailed information about a specific recovery
- `/recovery resume <id>` - Resume any recoverable stream by its ID
- `/recovery clean` - Clean up expired recovery data

#### Recovery Strategies
Configure how resumed content is reconstructed in `config.toml`:

- **`exact`** - Continue from the exact interruption point
- **`paragraph`** - Find the last complete paragraph and continue from there
- **`summarize`** - Add a resumption marker and continue

#### Configuration
```toml
[streaming]
# Enable automatic recovery (default: true)
enable_recovery = true

# Recovery strategy (exact, paragraph, summarize)
recovery_strategy = "paragraph"

# Storage backend for recovery data
recovery_storage = "memory"  # or "disk"

# How long to keep recovery data (seconds)
recovery_ttl = 3600  # 1 hour

# Save recovery checkpoints every N chunks
recovery_checkpoint_interval = 10
```

#### Features
- Works with both enhanced and simple streaming modes
- Persistent recovery across application restarts (with disk storage)
- Detailed recovery metadata (provider, model, chunks, tokens, age)
- Content preview for recovery decisions
- Automatic cleanup of expired recovery data

### Response Caching

MCP Chat includes intelligent response caching powered by ExLLM's Cache system to speed up development and testing:

#### Overview
- Runtime response caching with configurable TTL (default: 15 minutes)
- Optional disk persistence for testing and debugging scenarios
- Auto-enable in development mode for faster iteration cycles
- Smart cache key generation based on provider, model, messages, and options

#### Commands
- `/cache stats` - Show cache statistics and configuration
- `/cache clear` - Clear all cached responses
- `/cache enable` - Enable caching for current session
- `/cache disable` - Disable caching for current session
- `/cache persist enable` - Enable disk persistence
- `/cache persist disable` - Disable disk persistence

#### Configuration

```toml
[caching]
# Enable response caching (default: false)
enabled = false

# Cache TTL in minutes (default: 15)
ttl_minutes = 15

# Enable disk persistence for testing/debugging (default: false)
persist_disk = false

# Directory for cache storage (optional)
# cache_dir = "~/.config/mcp_chat/cache"

# Automatically enable caching in development mode (default: true)
auto_enable_dev = true
```

#### Features
- **ETS Backend**: High-performance in-memory caching with TTL support
- **Development Mode**: Automatically enables in development for faster iteration
- **Cache Statistics**: Hit rate, miss rate, and performance metrics tracking
- **Disk Persistence**: Optional disk storage for testing scenarios and debugging
- **Smart Exclusions**: Streaming requests and function calls are not cached
- **Zero Configuration**: Works out of the box with sensible defaults

### Model Management

MCP Chat provides comprehensive model management through the `/model` command with various subcommands:

#### Basic Model Operations
- `/model <name>` - Switch to a specific model (backward compatible)
- `/model switch <name>` - Switch to a specific model
- `/model list` - List available models for current backend
- `/model info` - Show current model information
- `/model help` - Show all model subcommands

#### Model Capabilities and Discovery
MCP Chat integrates ExLLM's ModelCapabilities system for intelligent model discovery and selection:

- `/model capabilities [model]` - Show model capabilities and features
- `/model features` - List all available model features
- `/model recommend [features]` - Get model recommendations based on requirements
- `/model compare <model1> <model2> [...]` - Compare multiple models side by side

#### Features Tracked
- **Core Features**: Streaming, function calling, vision, audio
- **Input/Output**: System messages, multi-turn, structured output, JSON mode
- **Advanced**: Context caching, embeddings, token counting, reasoning
- **Controls**: Temperature, top-p, presence/frequency penalties, stop sequences

#### Model Comparison
- Feature support matrix with visual indicators (✓/✗)
- Context window and output token comparisons
- Release date and capability details

#### Smart Recommendations
- `/model recommend` - Get general model recommendations
- `/model recommend streaming vision` - Find models with specific features
- Scored recommendations based on:
  - Required feature support
  - Context window size
  - Model recency and deprecation status
  - Performance characteristics

#### Example Usage
```
# Switch to a model (backward compatible)
/model gpt-4

# Show current model information
/model info

# Show capabilities for current model
/model capabilities

# Show capabilities for specific model
/model capabilities claude-3-opus-20240229

# Compare OpenAI models
/model compare gpt-4 gpt-4-turbo gpt-3.5-turbo

# Find models with vision and function calling
/model recommend streaming vision function_calling

# List all available features
/model features

# Get help
/model help
```

The system uses ExLLM's comprehensive model database with up-to-date capability information from multiple providers (Anthropic, OpenAI, Gemini, Groq, and more).

## Tips and Best Practices

1. **Organize Sessions**: Use meaningful names when saving sessions
2. **Manage Context**: Monitor token usage with `/context` for long conversations
3. **Use Aliases**: Create aliases for frequently used command combinations
4. **Export Important Chats**: Regularly export important conversations
5. **Optimize Costs**: Use `/cost` to monitor API usage
6. **Leverage MCP**: Connect relevant MCP servers for enhanced functionality
7. **Use Recovery**: If responses get interrupted, use `/resume` or `/recovery list` to continue
8. **Choose the Right Model**: Use `/model capabilities` and `/model compare` to select models with the features you need
9. **Explore Features**: Use `/model features` to discover new model capabilities
10. **Get Recommendations**: Use `/model recommend` with specific features to find optimal models for your task

## Keyboard Shortcuts

- `Ctrl+C` - Cancel current input or stop streaming response
- `Ctrl+D` - Exit application (same as `/exit`)
- `Ctrl+L` - Clear screen (same as `/clear`)
- `Tab` - Autocomplete commands and server names
- `↑/↓` - Navigate command history