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