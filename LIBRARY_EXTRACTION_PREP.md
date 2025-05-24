# Library Extraction Preparation - Refactoring Needs

## Current State Analysis

After analyzing the codebase, here are the refactoring tasks that should be completed before extracting libraries:

## 1. Configuration Injection Pattern

**Issue**: Many modules directly access `MCPChat.Config.get()`, creating tight coupling.

**Affected modules**:
- All LLM adapters (Anthropic, OpenAI, Ollama, Bedrock, Gemini, Local)
- MCP modules (BuiltinResources, Discovery)
- Cost module

**Refactoring needed**:
- Change from direct Config access to configuration injection
- Pass config as parameter or in init/start_link
- This allows libraries to be used without MCPChat.Config

**Example**:
```elixir
# Current (coupled)
def get_config do
  MCPChat.Config.get([:llm, :anthropic]) || %{}
end

# Refactored (decoupled)
def new(config \\ %{}) do
  %__MODULE__{config: config}
end
```

## 2. Logger Standardization

**Issue**: Direct use of Logger throughout, should be configurable.

**Refactoring needed**:
- Add logger option to library initialization
- Allow nil logger for library usage
- Wrap logger calls in conditional checks

## 3. Extract Shared Types Module

**Issue**: Message and response types are duplicated across modules.

**Refactoring needed**:
- Create `MCPChat.Types` module with shared type definitions
- Define message format, responses, errors
- This becomes part of ex_llm library

## 4. Session Dependency in Context Module

**Issue**: Some modules assume Session exists, but libraries shouldn't depend on stateful processes.

**Affected**:
- Context module (clean)
- Cost module (clean) 
- But their tests might assume Session

**Refactoring needed**:
- Ensure all modules work with plain data structures
- Move any Session-specific logic to application layer

## 5. File System Dependencies

**Issue**: Several modules directly access file system:
- Alias module uses hardcoded path `~/.mcp_chat/aliases.json`
- Persistence module uses hardcoded paths
- ServerPersistence uses hardcoded path `~/.mcp_chat/connected_servers.json`
- ModelLoader uses hardcoded path `~/.mcp_chat/models`

**Refactoring needed**:
- Make all paths configurable
- Add path injection to init functions
- Libraries should not assume specific directory structures

## 6. Process Dependencies

**Issue**: Some modules assume they're running in a supervised application.

**Affected**:
- ServerManager (GenServer)
- Session (GenServer)
- Alias (GenServer)

**Refactoring needed**:
- Separate functional core from GenServer wrapper
- Allow libraries to work without process state
- Create both stateless and stateful APIs

## 7. Error Handling Standardization

**Issue**: Inconsistent error handling patterns across modules.

**Refactoring needed**:
- Standardize on {:ok, result} | {:error, reason} pattern
- Create common error types
- Remove raises in library code (return errors instead)

## 8. Test Infrastructure Separation

**Issue**: Tests use application-specific helpers and fixtures.

**Refactoring needed**:
- Create test helpers that can move with libraries
- Remove dependencies on application-level test setup
- Make fixtures portable

## 9. Module Naming Preparation

**Issue**: All modules use MCPChat namespace.

**Refactoring needed**:
- Plan namespace migration (MCPChat.LLM -> ExLLM)
- Consider compatibility aliases during transition
- Update all internal references

## 10. Break Circular Dependencies

**Issue**: Circular dependency between Session and Persistence modules.
- Session calls Persistence for save/load/export
- Persistence calls Session.get_current_session()

**Refactoring needed**:
- Remove Session.get_current_session() call from Persistence
- Pass session as parameter to Persistence functions
- Make Persistence purely functional

## 11. Documentation Updates

**Issue**: Documentation assumes application context.

**Refactoring needed**:
- Rewrite docs from library perspective
- Add library-specific examples
- Include standalone usage instructions

## Priority Order

1. **Break Circular Dependencies** (Blocker - prevents clean separation)
2. **Configuration Injection** (Critical - blocks all extractions)
3. **File System Dependencies** (Critical - blocks Alias extraction)
4. **Process Dependencies** (High - affects API design)
5. **Extract Shared Types** (High - needed by multiple libraries)
6. **Error Handling** (Medium - can be done during extraction)
7. **Logger Standardization** (Medium)
8. **Test Infrastructure** (Medium)
9. **Module Naming** (Low - can use aliases)
10. **Documentation** (Low - can be done during extraction)

## Estimated Effort

- Configuration Injection: 2-3 hours
- File System Dependencies: 1-2 hours
- Process Dependencies: 3-4 hours
- Shared Types: 1 hour
- Total prep work: ~1-2 days

## Recommendation

Complete at least items 1-4 before starting library extraction. This will make the extraction process much smoother and result in cleaner, more reusable libraries.