# MCP Chat Examples

This directory contains examples demonstrating various MCP Chat capabilities.

## Basic Examples

### 1. Getting Started (`getting_started.exs`)
A simple example showing basic chat interaction and commands.

### 2. MCP Server Connection (`mcp_server_example.exs`)
Demonstrates connecting to MCP servers and using their tools.

### 3. Multi-Model Chat (`multi_model.exs`)
Shows how to switch between different LLM providers and models.

### 4. Context Management (`context_management.exs`)
Demonstrates context window management and file inclusion.

## Advanced Examples

### 5. Multi-Agent System (`multi_agent/`)
A complete multi-agent setup using BEAM message passing.

### 6. Custom MCP Server (`custom_mcp_server/`)
Example of creating your own MCP server in Elixir.

### 7. Cost-Aware Processing (`cost_aware.exs`)
Demonstrates cost tracking and optimization strategies.

### 8. Session Persistence (`session_example.exs`)
Shows saving and loading chat sessions.

## BEAM Integration Examples

### 9. BEAM Message Passing (`beam_integration/`)
Advanced example showing direct BEAM message passing between MCP Chat instances.

### 10. Supervised Agents (`supervised_agents/`)
Demonstrates fault-tolerant multi-agent systems with OTP supervision.

## Running Examples

Most examples can be run directly:

```bash
elixir examples/getting_started.exs
```

For multi-file examples, see the README in each subdirectory.

## Prerequisites

- Elixir 1.15+ installed
- MCP Chat configured with at least one LLM provider
- For MCP server examples: Node.js and npx available

## Configuration

Examples use the default configuration from `~/.config/mcp_chat/config.toml`.
You can override settings with environment variables:

```bash
ANTHROPIC_API_KEY="your-key" elixir examples/getting_started.exs
```