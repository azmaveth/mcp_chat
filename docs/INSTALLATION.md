# MCP Chat Installation Guide

This guide will walk you through installing and setting up MCP Chat on your system.

## Prerequisites

### Required Software

1. **Elixir** (version 1.15 or higher)
   - macOS: `brew install elixir`
   - Ubuntu/Debian: `sudo apt-get install elixir`
   - Other systems: See [Elixir installation guide](https://elixir-lang.org/install.html)

2. **Erlang/OTP** (version 26 or higher)
   - Usually installed automatically with Elixir
   - Verify with: `erl -version`

3. **Git** (for cloning the repository)
   - Verify with: `git --version`

### Optional Software

1. **Node.js** (for MCP server integrations)
   - Required if you want to use npm-based MCP servers
   - Install from [nodejs.org](https://nodejs.org/)

## Installation Steps

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/mcp_chat.git
cd mcp_chat
```

### 2. Install Dependencies

```bash
mix deps.get
```

This will download and compile all required Elixir dependencies.

### 3. Compile the Application

```bash
mix compile
```

### 4. Initial Setup

Run the setup script to create necessary directories and configuration:

```bash
./setup.sh
```

Or manually create the config directory:

```bash
mkdir -p ~/.config/mcp_chat
```

## Configuration

### 1. API Keys

You'll need API keys for the LLM providers you want to use.

#### Anthropic (Claude)

1. Sign up at [console.anthropic.com](https://console.anthropic.com/)
2. Generate an API key
3. Set the environment variable:
   ```bash
   export ANTHROPIC_API_KEY="your-api-key-here"
   ```
   
   Or add to your shell profile (`~/.bashrc`, `~/.zshrc`, etc.):
   ```bash
   echo 'export ANTHROPIC_API_KEY="your-api-key-here"' >> ~/.bashrc
   source ~/.bashrc
   ```

#### OpenAI (GPT)

1. Sign up at [platform.openai.com](https://platform.openai.com/)
2. Generate an API key
3. Set the environment variable:
   ```bash
   export OPENAI_API_KEY="your-api-key-here"
   ```

### 2. Configuration File

Create or edit `~/.config/mcp_chat/config.toml`:

```toml
[llm]
default = "anthropic"  # or "openai"

[llm.anthropic]
# API key can be set here or via ANTHROPIC_API_KEY env var
# api_key = "sk-ant-..."
model = "claude-sonnet-4-20250514"
max_tokens = 4096

[llm.openai]
# API key can be set here or via OPENAI_API_KEY env var
# api_key = "sk-..."
model = "gpt-4"
max_tokens = 4096

[ui]
theme = "dark"
history_size = 1000
```

## Running MCP Chat

### Basic Usage

```bash
# Build the executable
mix escript.build

# Run with default settings
./mcp_chat

# Run with specific backend
./mcp_chat --backend openai

# Run with custom config file
./mcp_chat --config /path/to/config.toml
```

### Creating an Alias

Add to your shell profile for easier access:

```bash
alias mcp='cd /path/to/mcp_chat && ./mcp_chat'
```

Then you can simply run:
```bash
mcp
```

## Installing MCP Servers

MCP Chat can connect to various MCP (Model Context Protocol) servers for extended functionality.

### Automatic Installation

Use the discover command within MCP Chat:
```
/discover
/connect filesystem
```

### Manual Installation

Install MCP servers via npm:

```bash
# Filesystem server
npm install -g @modelcontextprotocol/server-filesystem

# GitHub server
npm install -g @modelcontextprotocol/server-github

# Other servers
npm install -g @modelcontextprotocol/server-gitlab
npm install -g @modelcontextprotocol/server-postgres
```

### Configuration

Add servers to your config.toml:

```toml
[mcp]
servers = [
  { 
    name = "filesystem", 
    command = ["npx", "-y", "@modelcontextprotocol/server-filesystem", "/home/user"],
    description = "Access local files"
  },
  { 
    name = "github",
    command = ["npx", "-y", "@modelcontextprotocol/server-github"],
    env = { GITHUB_TOKEN = "your-github-token" }
  }
]
```

## Platform-Specific Instructions

### macOS

1. Install Homebrew if not already installed:
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

2. Install Elixir:
   ```bash
   brew install elixir
   ```

3. Follow general installation steps above

### Linux (Ubuntu/Debian)

1. Update package list:
   ```bash
   sudo apt-get update
   ```

2. Install Elixir:
   ```bash
   sudo apt-get install elixir
   ```

3. Follow general installation steps above

### Windows

1. Install Elixir using the Windows installer from [elixir-lang.org](https://elixir-lang.org/install.html#windows)

2. Use PowerShell or WSL for running commands

3. Follow general installation steps above

## Development Setup

If you want to contribute or modify MCP Chat:

### 1. Fork and Clone

```bash
git clone https://github.com/yourusername/mcp_chat.git
cd mcp_chat
```

### 2. Install Development Dependencies

```bash
mix deps.get
mix deps.compile
```

### 3. Run Tests

```bash
mix test
```

### 4. Run with Interactive Shell

```bash
iex -S mix
```

## Troubleshooting

### Common Issues

1. **"Command not found: mix"**
   - Ensure Elixir is installed and in your PATH
   - Try: `which elixir` and `which mix`

2. **"Could not compile dependency"**
   - Clear build artifacts: `mix deps.clean --all`
   - Reinstall: `mix deps.get`
   - Recompile: `mix deps.compile`

3. **"API key not found"**
   - Check environment variable: `echo $ANTHROPIC_API_KEY`
   - Ensure it's exported in your current shell
   - Try setting it in the config file directly

4. **"Failed to start MCP server"**
   - Ensure Node.js is installed for npm-based servers
   - Check server command in config
   - Try running the server command manually to test

### Getting Help

1. Check the [User Guide](USER_GUIDE.md)
2. Run with debug logging:
   ```bash
   ELIXIR_LOG_LEVEL=debug ./mcp_chat
   ```
3. Check application logs in `~/.config/mcp_chat/logs/`

## Updating

To update MCP Chat to the latest version:

```bash
cd mcp_chat
git pull origin main
mix deps.get
mix compile
```

## Uninstalling

To remove MCP Chat:

1. Delete the application directory:
   ```bash
   rm -rf /path/to/mcp_chat
   ```

2. Remove configuration and data (optional):
   ```bash
   rm -rf ~/.config/mcp_chat
   ```

3. Remove shell aliases from your profile

## Next Steps

- Read the [User Guide](USER_GUIDE.md) for usage instructions
- Configure MCP servers for extended functionality
- Customize your configuration file
- Explore available LLM models and features