# MCP Chat Refactoring Plan

## Overview
The codebase has grown organically and needs refactoring to improve maintainability, reduce complexity, and make future feature development easier.

## Key Issues Identified

### 1. CLI Commands Module (Critical)
- **Problem**: `lib/mcp_chat/cli/commands.ex` is 1,191 lines with cyclomatic complexity up to 37
- **Impact**: Hard to maintain, test, and extend

### 2. Code Quality Issues (from Credo)
- 50 refactoring opportunities
- 147 code readability issues  
- 47 software design suggestions
- Functions with excessive nesting (max depth 2, some at 3-4)
- Functions with high cyclomatic complexity (max 9, some at 37)

### 3. Common Patterns
- Nested module aliases that should be at the top
- Missing @moduledoc tags
- Functions with parentheses but no arguments
- Large numbers without underscores

## Refactoring Strategy

### Phase 1: Break Up CLI Commands Module

Create focused command modules:

```
lib/mcp_chat/cli/commands/
├── base.ex          # Common command functionality
├── session.ex       # /save, /load, /sessions, /new, /history
├── mcp.ex          # /servers, /connect, /disconnect, /discover, /tools, /resources, /prompts
├── llm.ex          # /backend, /model, /models, /loadmodel, /unloadmodel
├── context.ex      # /context, /system, /tokens, /strategy
├── utility.ex      # /help, /clear, /export, /config, /cost
└── alias.ex        # /alias commands
```

Each module will:
- Have a clear, focused responsibility
- Implement a common behavior for commands
- Have its own tests
- Keep functions under 50 lines
- Maintain cyclomatic complexity under 9

### Phase 2: Extract Common LLM Adapter Patterns

Create shared modules:
```
lib/mcp_chat/llm/
├── adapter_base.ex     # Common adapter behavior
├── http_client.ex      # Shared HTTP client logic
├── stream_handler.ex   # SSE/streaming response handling
├── error_handler.ex    # Common error formatting
└── token_counter.ex    # Token counting utilities
```

### Phase 3: Simplify Complex Functions

Target functions with complexity > 9:
1. Break down into smaller, focused functions
2. Use pattern matching more effectively
3. Extract validation logic
4. Reduce nesting levels

### Phase 4: Fix Code Readability Issues

1. Add missing @moduledoc tags
2. Fix function naming (remove `is_` prefix, add `?` suffix)
3. Remove parentheses from zero-argument functions
4. Add underscores to large numbers
5. Move nested module aliases to module top

## Implementation Order

1. **Start with CLI Commands** (highest impact)
   - Create new directory structure
   - Define command behavior
   - Extract commands by category
   - Update router in main commands module
   - Ensure all tests pass

2. **Fix Simple Issues** (quick wins)
   - Run `mix format`
   - Fix number formatting
   - Remove unnecessary parentheses
   - Add missing @moduledoc tags

3. **Extract LLM Common Code** (reduce duplication)
   - Identify common patterns
   - Create base modules
   - Update adapters to use shared code
   - Ensure backward compatibility

4. **Refactor Complex Functions** (improve maintainability)
   - Start with highest complexity
   - Break down systematically
   - Add tests for new functions
   - Verify behavior unchanged

## Success Criteria

- [ ] No function with cyclomatic complexity > 9
- [ ] No function with nesting depth > 2
- [ ] All modules have @moduledoc
- [ ] No module larger than 300 lines
- [ ] Credo strict mode passes with < 50 issues
- [ ] All existing tests still pass
- [ ] Test coverage remains > 80%

## Risks and Mitigation

1. **Breaking Changes**
   - Mitigation: Keep public APIs identical
   - Use deprecation warnings if needed
   - Comprehensive testing

2. **Lost Functionality**
   - Mitigation: Run full test suite after each change
   - Manual testing of all commands
   - Keep old code until new code verified

3. **Merge Conflicts**
   - Mitigation: Work in small, focused PRs
   - Refactor one module at a time
   - Communicate changes clearly

## Timeline Estimate

- Phase 1 (CLI Commands): 2-3 hours
- Phase 2 (LLM Adapters): 1-2 hours  
- Phase 3 (Complex Functions): 2-3 hours
- Phase 4 (Readability): 1 hour

Total: ~8 hours of focused work