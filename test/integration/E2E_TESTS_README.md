# End-to-End Tests for MCP Chat

This directory contains comprehensive end-to-end tests that verify the complete functionality of MCP Chat using real backends and servers without any mocking.

## Test Files

### 1. `comprehensive_e2e_test.exs`
Complete system tests covering:
- Ollama integration with real models
- Full chat conversations with context
- MCP server connections and tool execution
- Session persistence and exports
- Multi-backend switching
- Error scenarios and recovery
- Real CLI command execution

### 2. `realtime_features_e2e_test.exs`
Tests for real-time features:
- Streaming responses with timing verification
- Progress notifications for long operations
- Change notifications from MCP servers
- Concurrent operations and notification handling
- Circuit breaker behavior
- Performance under load

### 3. `advanced_scenarios_e2e_test.exs`
Complex scenarios and edge cases:
- Multi-agent coordination
- Complex workflow orchestration
- Resource contention handling
- Large context management
- Memory pressure testing
- Custom protocol extensions

## Prerequisites

1. **Ollama** must be running:
   ```bash
   # Check if running
   curl http://localhost:11434/api/tags
   
   # Start Ollama if needed
   ollama serve
   ```

2. **Required model** installed:
   ```bash
   # Install the test model
   ollama pull nomic-embed-text:latest
   
   # Or any other small, fast model
   ollama pull tinyllama
   ```

3. **Python 3** for demo MCP servers:
   ```bash
   # Check Python
   python3 --version
   
   # Install MCP server requirements
   pip3 install mcp pytz
   ```

## Running the Tests

### Using the Test Runner Script

The easiest way to run E2E tests:

```bash
# Run all E2E tests
./test/run_e2e_tests.exs --all

# Run specific test suites
./test/run_e2e_tests.exs --comprehensive
./test/run_e2e_tests.exs --realtime
./test/run_e2e_tests.exs --advanced

# Quick smoke test
./test/run_e2e_tests.exs --quick

# Set up environment (install deps, pull model)
./test/run_e2e_tests.exs --setup
```

### Using Mix Directly

```bash
# Run all E2E tests
mix test test/integration/comprehensive_e2e_test.exs test/integration/realtime_features_e2e_test.exs test/integration/advanced_scenarios_e2e_test.exs

# Run individual test files
mix test test/integration/comprehensive_e2e_test.exs

# Run specific tests
mix test test/integration/comprehensive_e2e_test.exs:45
```

### Running with Different Models

Set the test model via environment variable:

```bash
TEST_MODEL="llama2:latest" mix test test/integration/comprehensive_e2e_test.exs
```

## Test Coverage

The E2E tests verify:

### Core Functionality
- ✅ LLM integration (Ollama)
- ✅ Chat conversations with context
- ✅ Token tracking and cost calculation
- ✅ Session persistence and loading
- ✅ Export formats (JSON, Markdown)

### MCP Features
- ✅ Server connections (stdio transport)
- ✅ Tool discovery and execution
- ✅ Resource reading
- ✅ Multiple concurrent servers
- ✅ Server crash recovery
- ✅ Progress notifications
- ✅ Change notifications

### Advanced Features
- ✅ Streaming responses
- ✅ Multi-turn conversations
- ✅ Context window management
- ✅ Backend switching
- ✅ Error handling and recovery
- ✅ Concurrent operations
- ✅ Memory pressure handling

### Real-World Scenarios
- ✅ Multi-agent coordination
- ✅ Complex workflows
- ✅ Tool chaining
- ✅ Large context handling
- ✅ Performance under load

## Demo MCP Servers

The tests use Python-based demo servers located in `examples/demo_servers/`:

- **time_server.py** - Time and timezone operations
- **calculator_server.py** - Mathematical calculations
- **data_server.py** - Data generation and queries

These servers implement the full MCP protocol and provide realistic testing scenarios.

## Troubleshooting

### Ollama Not Running
```bash
# Start Ollama
ollama serve

# Verify it's running
curl http://localhost:11434/api/tags
```

### Model Not Found
```bash
# List available models
ollama list

# Pull required model
ollama pull nomic-embed-text:latest
```

### Python Issues
```bash
# Install Python 3
# macOS: brew install python3
# Ubuntu: sudo apt install python3 python3-pip

# Install dependencies
pip3 install mcp pytz
```

### Test Timeouts
Some tests may take longer with slower models. Adjust timeouts:
```elixir
@test_timeout 120_000  # 2 minutes
```

### Port Conflicts
If MCP servers fail to start, check for port conflicts:
```bash
# Check if ports are in use
lsof -i :8080-8090
```

## Adding New E2E Tests

1. Create a new test module in `test/integration/`
2. Use `async: false` for tests that modify global state
3. Include proper setup and teardown
4. Use real servers and backends (no mocks)
5. Add appropriate timeouts for long operations
6. Document prerequisites and assumptions

Example structure:
```elixir
defmodule MCPChat.NewFeatureE2ETest do
  use ExUnit.Case, async: false
  
  @moduledoc """
  E2E tests for new feature X
  """
  
  setup_all do
    # Global setup
    Application.ensure_all_started(:mcp_chat)
    :ok
  end
  
  setup do
    # Per-test setup
    MCPChat.Session.clear_session()
    :ok
  end
  
  describe "Feature X" do
    @tag timeout: 60_000
    test "does something real" do
      # Test with actual backends
    end
  end
end
```

## CI/CD Considerations

For CI environments:

1. Use Docker to run Ollama:
   ```yaml
   services:
     ollama:
       image: ollama/ollama
       ports:
         - "11434:11434"
   ```

2. Pre-pull models in CI:
   ```bash
   docker exec ollama ollama pull nomic-embed-text:latest
   ```

3. Set appropriate timeouts for CI runners

4. Consider using smaller models for faster CI runs

## Performance Tips

1. Use small, fast models for testing (nomic-embed-text, tinyllama)
2. Run tests in parallel where possible
3. Cache Ollama models between test runs
4. Use the `--quick` option for rapid feedback
5. Profile slow tests with `:timer.tc/3`

## Future Enhancements

- [ ] WebSocket MCP transport tests
- [ ] BEAM transport integration tests
- [ ] Distributed multi-node tests
- [ ] Load testing with many concurrent users
- [ ] Integration with external APIs
- [ ] Security and authentication tests