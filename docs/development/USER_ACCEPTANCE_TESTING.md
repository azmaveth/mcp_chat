# User Acceptance Testing for MCP Chat

This document describes the user acceptance testing approach for MCP Chat, including automated test runners and example demonstrations.

## Overview

MCP Chat includes several approaches to user acceptance testing:

1. **Example Demonstrations** - Interactive and non-interactive examples showing features
2. **Integration Tests** - Shell scripts testing the compiled escript
3. **Automated Test Runners** - Elixir scripts that run examples programmatically
4. **Makefile Targets** - Easy commands for running different test suites

## Test Structure

### 1. Example Files (`examples/`)

#### Interactive Examples
- `getting_started.exs` - Basic introduction to features
- `notifications_demo.exs` - Menu-driven notification demos
- `multi_model.exs` - Provider comparison demo
- `stdio_server_example.exs` - Direct server integration

#### Non-Interactive Test Runners
- `run_examples_simple.exs` - Lightweight example runner
- `run_all_examples.exs` - Comprehensive example suite
- `user_acceptance_tests.exs` - Full acceptance test suite

### 2. Shell Script Tests

- `test_examples.sh` - Tests the compiled escript with commands
- `test_integration.sh` - Tests core functionality with proper environment

### 3. Demo Servers (`examples/demo_servers/`)

Python-based MCP servers for testing:
- `calculator_server.py` - Arithmetic operations
- `time_server.py` - Time utilities
- `data_generator_server.py` - Sample data generation
- `slow_server.py` - Timeout testing
- `notification_server.py` - Notification testing

## Running Tests

### Quick Test
```bash
# Simple example runner (no dependencies)
make examples

# Or directly:
elixir examples/run_examples_simple.exs
```

### Integration Test
```bash
# Test the compiled escript
make acceptance

# Or directly:
./test_examples.sh
```

### Full Test Suite
```bash
# Comprehensive example suite
make examples-full

# Full acceptance tests
make acceptance-full
```

### Manual Testing
```bash
# Build and test manually
mix escript.build
./mcp_chat

# In the chat interface:
/help
/version
/model
/context stats
/stats
/cost
```

## Test Coverage

The acceptance tests cover:

1. **Core Commands**
   - Help system (`/help`)
   - Version info (`/version`)
   - Model management (`/model`)
   - Context operations (`/context`)
   - Session commands (`/stats`, `/cost`)

2. **Chat Features**
   - Basic message exchange
   - Multi-provider support
   - Streaming responses
   - Cost tracking

3. **MCP Features**
   - Server connections
   - Tool execution
   - Progress tracking
   - Notifications

4. **Advanced Features**
   - Alias system
   - Session persistence
   - Context management
   - Concurrent operations

## CI/CD Integration

### GitHub Actions Example
```yaml
name: User Acceptance Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.14'
          otp-version: '25'
      
      - name: Install dependencies
        run: |
          mix deps.get
          mix compile
      
      - name: Build escript
        run: mix escript.build
      
      - name: Run examples
        run: make examples
      
      - name: Run acceptance tests
        run: make acceptance
```

### GitLab CI Example
```yaml
stages:
  - build
  - test

build:
  stage: build
  script:
    - mix deps.get
    - mix compile
    - mix escript.build
  artifacts:
    paths:
      - mcp_chat

acceptance:
  stage: test
  dependencies:
    - build
  script:
    - make examples
    - make acceptance
```

## Writing New Tests

### Example Test Template
```elixir
defp test_new_feature do
  IO.puts "│ Testing new feature..."
  
  # Setup
  setup_data = prepare_test_data()
  
  # Execute
  result = execute_feature(setup_data)
  
  # Verify
  case result do
    {:ok, output} ->
      IO.puts "│ ✓ Feature works: #{output}"
      true
    {:error, reason} ->
      IO.puts "│ ✗ Feature failed: #{reason}"
      false
  end
end
```

### Assertion Helpers
```elixir
# Basic assertions
assert(condition, "Error message")
assert_equal(actual, expected, "Values don't match")
assert_contains(string, substring, "Missing substring")

# Pattern matching
assert match?({:ok, _}, result), "Expected ok tuple"
assert match?(%{key: _}, map), "Expected key in map"
```

## Troubleshooting

### Common Issues

1. **Application start failures**
   - Ensure all dependencies are compiled: `mix deps.compile`
   - Check environment variables are set
   - Verify no port conflicts for servers

2. **Missing modules**
   - Run `mix compile` before tests
   - Ensure correct paths in test scripts
   - Check dependency resolution

3. **Timeout errors**
   - Increase timeouts in shell scripts
   - Check for blocking operations
   - Ensure mock providers are used

### Debug Mode

Set environment variables for debugging:
```bash
export MCP_CHAT_DEBUG=true
export EX_LLM_DEBUG=true
```

## Best Practices

1. **Use Mock Providers** - For predictable, fast tests
2. **Isolate Tests** - Each test should be independent
3. **Clear Output** - Use structured output with clear pass/fail
4. **Exit Codes** - Return proper exit codes for CI/CD
5. **Timeouts** - Set reasonable timeouts to prevent hanging
6. **Documentation** - Document what each test validates

## Future Improvements

1. **Property-Based Testing** - Add StreamData tests
2. **Performance Testing** - Measure response times
3. **Load Testing** - Test with many concurrent operations
4. **Visual Testing** - Capture and compare UI output
5. **Coverage Reporting** - Integration with ExCoveralls