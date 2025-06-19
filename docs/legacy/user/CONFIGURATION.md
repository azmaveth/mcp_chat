# Configuration Guide

This guide covers all configuration options for MCP Chat.

## Configuration File Location

MCP Chat uses a TOML configuration file located at:
- `~/.config/mcp_chat/config.toml` (default)
- Custom location via `--config` flag

## Complete Configuration Reference

```toml
# LLM Backend Configuration
[llm]
default = "anthropic"  # Options: anthropic, openai, ollama, local

# Anthropic Claude Configuration
[llm.anthropic]
api_key = "YOUR_API_KEY"  # Or use ANTHROPIC_API_KEY env var
model = "claude-sonnet-4-20250514"  # Available models: claude-sonnet-4-*, claude-opus-4-*
max_tokens = 4096
temperature = 0.7
api_base = "https://api.anthropic.com"  # Or use ANTHROPIC_API_BASE env var

# OpenAI Configuration
[llm.openai]
api_key = "YOUR_API_KEY"  # Or use OPENAI_API_KEY env var
model = "gpt-4"  # Available models: gpt-4*, gpt-3.5-turbo*
max_tokens = 4096
temperature = 0.7
api_base = "https://api.openai.com"  # Or use OPENAI_API_BASE env var

# Ollama Configuration (Local server)
[llm.ollama]
model = "llama2"  # Available models: llama2, mistral, codellama, etc.
api_base = "http://localhost:11434"  # Or use OLLAMA_API_BASE env var
temperature = 0.7

# Local Model Configuration (Bumblebee/EMLX)
[llm.local]
model_path = "microsoft/phi-2"  # HuggingFace model ID or local path
device = "cpu"  # Options: cpu, cuda, metal (auto-detected)
max_tokens = 2048

# MCP Client Configuration
[[mcp.servers]]
name = "filesystem"
command = ["npx", "-y", "@modelcontextprotocol/server-filesystem", "/home/user"]
description = "Local file system access"
auto_connect = true  # Auto-connect on startup

[[mcp.servers]]
name = "github"
command = ["npx", "-y", "@modelcontextprotocol/server-github"]
env = { GITHUB_TOKEN = "ghp_xxxxxxxxxxxx" }
description = "GitHub integration"

[[mcp.servers]]
name = "remote-tools"
transport = "sse"
url = "http://example.com:8080"
description = "Remote MCP server via SSE"

# MCP Server Configuration (when running as server)
[mcp_server]
stdio_enabled = false  # Enable stdio server mode
sse_enabled = false    # Enable HTTP/SSE server mode
sse_port = 8080       # Port for SSE server
cors_origins = ["*"]  # CORS allowed origins

# UI Configuration
[ui]
theme = "dark"        # Options: dark, light
history_size = 1000   # Max messages to keep in memory
streaming = true      # Enable streaming responses
show_tokens = true    # Show token usage
show_cost = true      # Show cost estimates

# Context Management
[context]
max_tokens = 4096     # Maximum context window
strategy = "sliding_window"  # Options: sliding_window, smart
system_prompt = ""    # Global system prompt

# Session Management
[session]
auto_save = true      # Auto-save sessions
save_path = "~/.config/mcp_chat/sessions"
export_format = "markdown"  # Default export format

# Aliases Configuration
[aliases]
status = ["/context", "/cost"]
setup = ["/system You are a helpful assistant", "/tokens 8192"]
```

## Environment Variables

Environment variables take precedence over config file values:

### API Keys
- `ANTHROPIC_API_KEY` - Anthropic API key
- `OPENAI_API_KEY` - OpenAI API key
- `GITHUB_TOKEN` - GitHub personal access token

### API Endpoints
- `ANTHROPIC_API_BASE` - Custom Anthropic API endpoint
- `OPENAI_API_BASE` - Custom OpenAI API endpoint (e.g., for Azure)
- `OLLAMA_API_BASE` - Ollama server URL

### MCP Configuration
- `MCP_SERVERS` - JSON array of server configurations
- `MCP_SERVER_PORT` - Override SSE server port

### Other
- `NO_COLOR` - Disable colored output
- `DEBUG` - Enable debug logging

## Configuration Examples

### Basic Setup (Anthropic only)

```toml
[llm]
default = "anthropic"

[llm.anthropic]
api_key = "sk-ant-xxx"
model = "claude-sonnet-4-20250514"
```

### Multi-Backend Setup

```toml
[llm]
default = "anthropic"

[llm.anthropic]
api_key = "sk-ant-xxx"

[llm.openai]
api_key = "sk-xxx"

[llm.ollama]
model = "mixtral"
```

### Development Setup with Local Tools

```toml
[llm]
default = "ollama"

[llm.ollama]
model = "codellama"

[[mcp.servers]]
name = "filesystem"
command = ["npx", "-y", "@modelcontextprotocol/server-filesystem", ".", "/tmp"]
auto_connect = true

[[mcp.servers]]
name = "github"
command = ["npx", "-y", "@modelcontextprotocol/server-github"]
env = { GITHUB_TOKEN = "${GITHUB_TOKEN}" }  # Use env var
```

### Enterprise Setup with Custom Endpoints

```toml
[llm]
default = "openai"

[llm.openai]
api_key = "${AZURE_OPENAI_KEY}"
api_base = "https://company.openai.azure.com"
model = "gpt-4"

[mcp_server]
sse_enabled = true
sse_port = 8443
cors_origins = ["https://internal.company.com"]
```

## Command Line Options

Override configuration via command line:

```bash
# Use specific config file
./mcp_chat --config /path/to/config.toml

# Override backend
./mcp_chat --backend openai

# Override model
./mcp_chat --model gpt-4-turbo
```

## Validation

MCP Chat validates configuration on startup:
- Missing required fields (API keys)
- Invalid model names
- Unreachable MCP servers
- Permission issues

Run with `--validate` to check configuration without starting:

```bash
./mcp_chat --validate
```

## Security Best Practices

1. **Never commit API keys** - Use environment variables
2. **Restrict file access** - Limit MCP filesystem server paths
3. **Use HTTPS** - For remote MCP servers in production
4. **Rotate keys regularly** - Update API keys periodically
5. **Audit server access** - Review MCP server permissions

## Troubleshooting

### API Key Issues
```bash
# Check if key is set
echo $ANTHROPIC_API_KEY

# Test key directly
curl https://api.anthropic.com/v1/models \
  -H "x-api-key: $ANTHROPIC_API_KEY"
```

### Configuration Not Loading
1. Check file location: `~/.config/mcp_chat/config.toml`
2. Validate TOML syntax: `cat config.toml | toml-test`
3. Check permissions: `ls -la ~/.config/mcp_chat/`
4. Run with debug: `DEBUG=1 ./mcp_chat`

### MCP Server Issues
See [MCP Servers Guide](MCP_SERVERS.md#troubleshooting) for detailed troubleshooting.