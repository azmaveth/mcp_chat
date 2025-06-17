# Agent Command Architecture

This document describes the enhanced command system that integrates CLI commands with the agent architecture, providing dynamic command discovery, real-time progress updates, and intelligent AI-powered operations.

## Architecture Overview

The enhanced command system provides a hybrid approach:

1. **Local Commands** - Handled directly by the CLI for immediate operations
2. **Agent Commands** - Routed to specialized agents for AI-powered processing
3. **Dynamic Discovery** - Commands are discovered from connected agents at runtime
4. **Real-time Updates** - Progress and results stream back via Phoenix.PubSub

## Command Classification

### Local Commands (CLI-handled)

These remain in the CLI for immediate local operations:

```bash
# System/UI Management
/help                    # Enhanced help with agent discovery
/clear                   # Clear screen
/config                  # Show configuration
/tui                     # Switch to TUI mode
/notification            # Notification preferences
/alias                   # Command aliases

# Session Management
/new                     # Start new conversation
/save [name]             # Save session locally
/load <name>             # Load session
/sessions                # List sessions
/history                 # Show history

# Context Management
/context stats           # Context statistics
/context add <file>      # Add files to context
/context rm <file>       # Remove files
/context list            # List context files
/context clear           # Clear context
/tokens <number>         # Set token limits
/strategy <type>         # Set truncation strategy
/system <prompt>         # Set system prompt

# Stream Recovery
/resume                  # Resume interrupted response
/recovery list           # List recoverable streams
/recovery clean          # Clean old streams
```

### Agent Commands (AI-powered)

These are routed to specialized agents for intelligent processing:

```bash
# LLM Management (LLMAgent)
/backend [name]          # Smart backend switching with validation
/model [subcommand]      # Intelligent model management
  /model recommend [features]    # AI-powered recommendations
  /model compare <models>        # Multi-dimensional comparison
  /model capabilities [model]    # Capability analysis
  /model switch <name>           # Compatible switching
/models [--filters]      # Smart model listing with filters
/acceleration [mode]     # Hardware optimization analysis

# MCP Operations (MCPAgent)
/mcp discover            # Intelligent server discovery
/mcp connect <server>    # Validated connections
/mcp tools               # Capability-aware tool listing
/mcp tool <server> <tool> # Monitored tool execution
/mcp resources           # Resource discovery with metadata
/mcp resource <server> <uri> # Enhanced resource reading
/mcp prompts             # Prompt discovery and analysis
/mcp prompt <server> <name>  # Intelligent prompt retrieval
/mcp sample <server> <prompt> # Server-side AI generation

# Analysis & Export (AnalysisAgent, ExportAgent)
/cost [detailed]         # AI-powered cost analysis
/stats                   # Intelligent session analytics
/export [format]         # Smart export with formatting
/concurrent <operations> # Parallel operation management
```

## Enhanced Features

### 1. Dynamic Command Discovery

Commands are discovered at runtime from connected agents:

```bash
# Basic help shows all available commands
/help

# Context-aware help with agent status
/help model              # Shows model-specific help
/help mcp               # Shows MCP capabilities
```

### 2. Real-time Progress Updates

Agent commands provide live progress feedback:

```
🤖 Executing with llm_agent...
🚀 Started: model_recommendation
⏱ Estimated duration: 8s
🔄 [██████████░░░░░░░░░░] 50% - Analyzing capabilities
🔄 [████████████████████] 100% - Completed
✅ Completed: model_recommendation
```

### 3. Intelligent Error Handling

Unknown commands get smart suggestions:

```
Unknown command: /modle
Did you mean:
  /model
  /models
Type /help for available commands
```

### 4. Context-Aware Completions

Tab completion includes agent capabilities:

```bash
/model <TAB>
  recommend (AI-powered selection)
  compare (multi-model analysis)
  capabilities (detailed analysis)
  switch (compatible switching)
```

## Agent Specialization

### LLMAgent Capabilities

```bash
/backend                 # Performance analysis and switching
/model recommend vision streaming  # Feature-based recommendations
/model compare gpt-4 claude-3-opus # Detailed comparisons
/model capabilities claude-3-sonnet # Capability analysis
/acceleration analyze    # Hardware optimization analysis
```

### MCPAgent Capabilities

```bash
/mcp discover           # Intelligent server discovery
/mcp connect filesystem --auto-config  # Automated setup
/mcp tool filesystem read_file --with-progress  # Monitored execution
/mcp sample server "analyze this code" # Server-side AI
```

### AnalysisAgent Capabilities

```bash
/cost detailed          # Cost optimization analysis
/stats --insights       # AI-powered session insights
/export markdown --enhanced  # Smart formatting
```

## Configuration

### Environment Variables

```bash
# Enable/disable enhanced commands
export MCP_ENHANCED_COMMANDS=true   # Force enable
export MCP_ENHANCED_COMMANDS=false  # Force disable
# (auto-detects if not set)

# Debug mode for command routing
export MCP_DEBUG=1
```

### Agent Pool Configuration

```elixir
config :mcp_chat, :agent_pool,
  max_concurrent: 5,
  queue_timeout: 30_000,
  default_timeout: 120_000
```

## Migration Strategy

The system supports gradual migration:

1. **Phase 1** - Enhanced commands auto-detect agent availability
2. **Phase 2** - Graceful fallback to legacy commands if agents unavailable
3. **Phase 3** - Progressive enhancement as agents come online

### Backward Compatibility

- All existing commands continue to work
- Legacy command handlers remain functional
- Enhanced features activate automatically when agents are available
- No breaking changes to existing workflows

## Usage Examples

### Model Management Workflow

```bash
# Get AI recommendations
/model recommend vision function_calling

# Compare recommended models
/model compare gpt-4-vision-preview claude-3-opus

# Switch with compatibility checking
/model switch claude-3-opus

# Verify capabilities
/model capabilities
```

### MCP Server Management

```bash
# Discover available servers
/mcp discover

# Connect with auto-configuration
/mcp connect filesystem

# List available tools with metadata
/mcp tools

# Execute tool with progress monitoring
/mcp tool filesystem analyze_directory ~/code/myproject
```

### Cost Optimization

```bash
# Analyze current session costs
/cost detailed

# Get optimization recommendations
/stats --cost-analysis

# Compare provider costs for task
/model recommend --budget 0.10 --task "document analysis"
```

## Implementation Status

- ✅ Command bridge architecture
- ✅ Agent routing system
- ✅ Real-time progress updates
- ✅ Enhanced help system
- ✅ LLMAgent implementation
- ✅ MCPAgent implementation
- ✅ AnalysisAgent implementation
- ✅ ExportAgent implementation
- ✅ Basic testing framework
- 📋 Comprehensive integration testing (planned)

## Next Steps

1. Add comprehensive integration test coverage for all agent command routing
2. Implement agent command caching for performance optimization
3. Add command usage analytics and optimization suggestions
4. Create interactive agent command documentation system
5. Implement command macro/scripting system for complex workflows
6. Add agent command validation and error recovery systems