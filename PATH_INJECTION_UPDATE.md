# Path Injection Implementation

## Summary

Successfully implemented path injection pattern to eliminate hardcoded file paths from core library components, making them more portable and testable.

## Changes Made

### 1. Created PathProvider Behaviour
- `MCPChat.PathProvider` - Defines the path provider interface
- `MCPChat.PathProvider.Default` - Uses standard application directories
- `MCPChat.PathProvider.Static` - Agent-based provider for testing/library usage

### 2. Updated Core Modules

#### Config Module ✅
- Accepts `:path_provider` option in `start_link/1`
- Uses PathProvider for config file location
- No longer hardcoded to `~/.config/mcp_chat/config.toml`

#### Alias Module ✅
- Accepts `:path_provider` option in `start_link/1`
- Uses PathProvider for aliases file location
- No longer hardcoded to `~/.config/mcp_chat/aliases.json`

#### Persistence Module ✅
- All functions accept optional `:path_provider` in `opts`
- Functions updated: `save_session/3`, `load_session/2`, `list_sessions/1`, `delete_session/2`
- Uses PathProvider for sessions directory
- No longer hardcoded to `~/.config/mcp_chat/sessions`

#### MCP Discovery Module ✅
- `discover_known_locations/1` accepts `:path_provider` option
- Uses configurable search directories
- No longer hardcoded to specific MCP server locations

### 3. PathProvider Configuration

The Default provider supports these file types:
- `:config_file` - Main configuration file
- `:aliases_file` - Command aliases storage
- `:sessions_dir` - Session persistence directory
- `:history_file` - CLI command history
- `:model_cache_dir` - LLM model cache
- `:server_connections_file` - MCP server connections
- `:mcp_discovery_dirs` - List of MCP server discovery directories

### 4. Usage Examples

```elixir
# Using default paths (standard application behavior)
MCPChat.Config.start_link()
MCPChat.Alias.start_link()
MCPChat.Persistence.save_session(session)

# Using custom paths for testing/library usage
{:ok, provider} = MCPChat.PathProvider.Static.start_link(%{
  config_dir: "/tmp/test_config",
  sessions_dir: "/tmp/test_sessions",
  aliases_file: "/tmp/test_aliases.json"
})

MCPChat.Config.start_link(path_provider: provider)
MCPChat.Alias.start_link(path_provider: provider)
MCPChat.Persistence.save_session(session, nil, path_provider: provider)
```

## Modules Still Using Hardcoded Paths

These can be updated in future iterations:
- `MCPChat.MCP.ServerPersistence` - `~/.mcp_chat/connected_servers.json`
- `MCPChat.LLM.ModelLoader` - `~/.mcp_chat/models`
- CLI history modules - `~/.config/mcp_chat/history`

## Benefits

1. **Library Portability**: Core modules no longer assume specific directory structures
2. **Testability**: Tests can use temporary directories without affecting user data
3. **Customization**: Applications using the libraries can specify their own paths
4. **Security**: Sensitive operations can be isolated to specific directories

## Next Steps

This completes the major hardcoded path removal for core library components. The next refactoring priorities are:
1. ✅ Break circular dependencies
2. ✅ Configuration injection pattern  
3. ✅ Fix hardcoded file paths (core modules)
4. Separate GenServer wrappers from functional cores
5. Standardize error handling
6. Make logger configurable
7. Update test infrastructure
8. Plan module namespaces for extraction