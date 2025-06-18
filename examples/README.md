# MCP Chat Examples

This directory contains streamlined example scripts and demos for MCP Chat functionality.

## Running Examples

### Interactive Examples

To run examples interactively:

```bash
# Basic getting started examples
elixir examples/getting_started.exs

# Interactive notifications demo with menu
elixir examples/notifications_demo.exs

# Multi-model comparison demo
elixir examples/multi_model.exs
```

### Non-Interactive Test Runners

For automated testing and CI/CD:

```bash
# Run all examples non-interactively
make examples

# Or directly:
elixir examples/run_examples_simple.exs

# Run comprehensive user acceptance tests
make acceptance

# Or directly:
elixir examples/user_acceptance_tests.exs
```

## Example Descriptions

### `getting_started.exs`
Essential introduction to MCP Chat features:
- Simple chat interactions
- Command usage (/model, /cost, /context)
- Context management with files
- Command aliases
- Built-in MCP resources
- Health monitoring

### `notifications_demo.exs`
Interactive demo showcasing MCP v0.2.0 features:
- Progress tracking with visual bars
- Change notifications (tools/resources/prompts)
- Server-side LLM sampling
- Custom notification handlers

### `multi_model.exs`
Demonstrates switching between LLM providers:
- Listing available models
- Provider comparison
- Response time measurement
- Cost comparison
- Streaming responses

### `run_examples_simple.exs`
Streamlined non-interactive test runner:
- Executes core example scenarios automatically
- Uses mock providers for predictable output
- Captures and validates results
- Provides pass/fail summary for CI/CD

### `user_acceptance_tests.exs`
Comprehensive acceptance test suite:
- Tests all major features
- Validates expected behavior
- Uses assertions for verification
- Returns appropriate exit codes for CI/CD

### CLI/Agent Detach Examples
**Core Files:**
- `cli_agent_detach_demo.exs` - Basic agent persistence concepts
- `cli_agent_detach_with_web_demo.exs` - Enhanced demo with web dashboard
- `detach_reattach_workflow.sh` - CLI-only workflow simulation
- `detach_reattach_with_web_workflow.sh` - Web-integrated workflow
- `CLI_AGENT_DETACH_README.md` - Comprehensive documentation

**Features Demonstrated:**
- Agent persistence independent of interfaces
- Web dashboard real-time monitoring
- Background task execution with progress tracking
- Multi-interface collaboration (CLI + Web)
- Session management and state synchronization

## Demo Servers

The `demo_servers/` directory contains Python-based MCP servers for testing:

- `calculator_server.py` - Basic arithmetic operations
- `time_server.py` - Time and date utilities  
- `data_server.py` - Sample data generation and manipulation
- `dynamic_server.py` - Dynamic server capabilities

To use these servers, ensure Python is installed and run:

```bash
python examples/demo_servers/calculator_server.py
```

## CLI/Agent Examples with Web Dashboard

### Complete Multi-Interface Workflow

MCP Chat supports multiple interfaces connecting to the same agent sessions:

```bash
# Method 1: Full system with web dashboard (recommended)
iex -S mix
# Open http://localhost:4000 in browser
# In IEx: MCPChat.main()

# Method 2: Run demos
elixir examples/cli_agent_detach_demo.exs              # Basic demo
elixir examples/cli_agent_detach_with_web_demo.exs     # Web-enhanced demo

# Method 3: Interactive workflows
./examples/detach_reattach_workflow.sh                  # CLI-only
./examples/detach_reattach_with_web_workflow.sh         # With web UI

# Method 4: Manual testing
./mcp_chat                    # Start CLI session
# Open http://localhost:4000   # Monitor via web
# Press Ctrl+C to disconnect CLI
# Agents keep working (visible in web)
./mcp_chat -c                 # Reconnect to see results
```

**Key Features:**
- **Multi-Interface Support**: CLI, Web, and API access to same sessions
- **Real-time Monitoring**: Phoenix LiveView dashboard at http://localhost:4000
- **Agent Persistence**: Agents continue working when interfaces disconnect
- **State Synchronization**: Full state sync across all connected interfaces
- **Team Collaboration**: Multiple users can join the same session
- **Background Tasks**: Long-running operations with progress tracking
- **Rich Web UI**: Better visualization than CLI for complex outputs

**Web Dashboard URLs:**
- http://localhost:4000 - System overview dashboard
- http://localhost:4000/agents - Agent monitoring and control
- http://localhost:4000/sessions - Session management
- http://localhost:4000/sessions/:id/chat - Web chat interface

See `CLI_AGENT_DETACH_README.md` for detailed documentation.

## Writing New Examples

When adding new examples:

1. **Interactive Examples**: Include user prompts and clear instructions
2. **Non-Interactive Examples**: Use mock providers and predictable data
3. **Always Include**: Setup code, error handling, and cleanup
4. **Document**: Add description to this README

Example template:

```elixir
#!/usr/bin/env elixir

# Add dependencies to path
Code.prepend_path("_build/dev/lib/mcp_chat/ebin")
# ... other deps

# Ensure application is started
{:ok, _} = Application.ensure_all_started(:mcp_chat)
Process.sleep(500)

# Your example code here
defmodule ExampleDemo do
  def run do
    # Demo implementation
  end
end

ExampleDemo.run()
```

## Integration with CI/CD

The non-interactive runners are designed for CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Run Examples
  run: make examples
  
- name: Run Acceptance Tests
  run: make acceptance
```

Both runners exit with appropriate codes:
- `0` - All tests passed
- `1` - One or more tests failed