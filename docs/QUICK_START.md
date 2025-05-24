# MCP Chat Quick Start Guide

Get up and running with MCP Chat in 5 minutes!

## 1. Install Prerequisites

```bash
# macOS
brew install elixir

# Ubuntu/Debian
sudo apt-get install elixir
```

## 2. Clone and Setup

```bash
git clone https://github.com/yourusername/mcp_chat.git
cd mcp_chat
mix deps.get
mix compile
```

## 3. Configure API Key

Choose one:

### Option A: Environment Variable (Recommended)
```bash
export ANTHROPIC_API_KEY="your-key-here"
# OR
export OPENAI_API_KEY="your-key-here"
```

### Option B: Config File
Create `~/.config/mcp_chat/config.toml`:
```toml
[llm.anthropic]
api_key = "your-key-here"
```

## 4. Start Chatting!

```bash
# Build the executable
mix escript.build

# Run the chat client
./mcp_chat
```

Or run directly in Elixir (with better terminal support):
```bash
iex -S mix
# Then in IEx:
iex> MCPChat.main()
```

## Essential Commands

Once running, try these commands:

- **Chat**: Just type your message and press Enter
- **Help**: `/help` - Show all commands
- **Save session**: `/save my-chat`
- **Switch model**: `/model claude-opus-4-20250514`
- **Show cost**: `/cost`
- **Exit**: `/exit`

## Quick MCP Server Setup

Connect to a filesystem server for file access:

```bash
# In MCP Chat:
/discover
/connect filesystem
/tool filesystem read_file path=/tmp/test.txt
```

## Pro Tips

1. **Save money**: Use `/cost` to track API usage
2. **Save time**: Create aliases for common commands
   ```
   /alias gpt /backend openai /model gpt-4
   ```
3. **Save work**: Export important conversations
   ```
   /export markdown project-notes.md
   ```

## Common Issues

- **No API key?** Get one from:
  - Anthropic: https://console.anthropic.com/
  - OpenAI: https://platform.openai.com/

- **Connection failed?** Check your internet and API key

- **Need help?** Type `/help` in the chat

## Next Steps

- Read the full [User Guide](USER_GUIDE.md)
- Learn about [MCP Servers](MCP_SERVERS.md)
- Customize your [configuration](USER_GUIDE.md#configuration)

Happy chatting! 🎉