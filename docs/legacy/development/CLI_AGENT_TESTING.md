# CLI Agent Integration Testing

This document describes the end-to-end testing strategy for the CLI-to-agent integration.

## Test Coverage

### 1. Integration Tests (`test/cli/agent_integration_test.exs`)

Comprehensive tests covering:
- Session management flow
- Tool execution with async/sync modes
- Export operations with progress
- Event subscriber UI updates
- Agent pool integration
- Full CLI command flow

### 2. Full Flow Tests (`test/cli/full_flow_integration_test.exs`)

Real-world usage scenarios:
- Multiple MCP tool executions
- Concurrent operations
- Chat message flow
- Export with progress tracking
- Error handling and recovery
- System monitoring

### 3. PubSub Event Tests (`test/cli/pubsub_event_flow_test.exs`)

Event system verification:
- Event broadcasting and routing
- Multiple subscriber handling
- Event type flows (tools, exports, pool)
- Session isolation
- Event serialization
- Timing and ordering

### 4. Real Usage Simulation (`test/cli/real_usage_simulation_test.exs`)

Simulates actual user workflows:
- Typical command sequences
- Concurrent tool execution
- Progress monitoring
- Error scenarios
- Real-time updates

### 5. Mock Tests (`test/cli/mock_agent_integration_test.exs`)

Lightweight tests without full system:
- Event display verification
- Progress rendering
- Error message formatting
- Queue notifications

## Test Execution

### Running All CLI-Agent Tests

```bash
# Run all integration tests
mix test test/cli/

# Run specific test file
mix test test/cli/agent_integration_test.exs

# Run with trace for debugging
mix test test/cli/agent_integration_test.exs --trace

# Run only integration tagged tests
mix test --only integration
```

### Test Helpers

The `test/support/agent_test_helpers.ex` module provides:
- Event simulation functions
- Tool execution mocking
- Export flow simulation
- Timing utilities

## Key Test Scenarios

### 1. Tool Execution Flow

```elixir
# User executes a tool
Gateway.execute_tool(session_id, "analyze_code", args)
# ↓
# Routes to appropriate agent (fast/heavy)
# ↓
# Agent broadcasts progress events
# ↓
# EventSubscriber displays updates
# ↓
# Completion/failure event
```

### 2. Export Flow

```elixir
# User requests export
Gateway.request_export(session_id, "pdf", options)
# ↓
# ExportAgent started
# ↓
# Progress events (25%, 50%, 75%, 100%)
# ↓
# File saved, completion event
```

### 3. Concurrent Operations

```elixir
# Multiple tools started
# ↓
# Agent pool manages workers
# ↓
# Queue full events if needed
# ↓
# Progress updates interleaved
# ↓
# All complete independently
```

## Event Verification

Tests verify that events contain correct data:

```elixir
# Tool start event
assert event.tool_name == "expected_tool"
assert event.session_id == session_id
assert event.execution_id != nil

# Progress event
assert event.progress >= 0 and event.progress <= 100
assert event.message != nil

# Completion event
assert event.duration_ms > 0
assert event.result != nil
```

## UI Output Verification

Tests capture IO to verify display:

```elixir
output = capture_io(fn ->
  # Execute operation
  # Events trigger UI updates
end)

assert output =~ "Starting tool execution"
assert output =~ "Progress: [===="
assert output =~ "Tool completed"
```

## Performance Considerations

- Tests use short delays (10-50ms) for event propagation
- Async tests disabled to avoid race conditions
- Mock tests for fast feedback during development
- Integration tests for full system verification

## Debugging Tips

1. **Event Not Received**: Check subscription topic matches
2. **UI Not Updating**: Verify EventSubscriber is started
3. **Progress Not Shown**: Check UI mode setting
4. **Timeout Errors**: Increase receive timeout in tests

## Future Test Enhancements

1. **Load Testing**: Verify system under high concurrent load
2. **Failure Injection**: Test resilience to agent crashes
3. **Memory Leak Detection**: Long-running operation tests
4. **Benchmark Suite**: Performance regression tests
5. **Property-Based Tests**: Random operation sequences

## Running Tests in CI

```yaml
# Example GitHub Actions config
test:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v2
    - uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.14'
        otp-version: '25'
    - run: mix deps.get
    - run: mix test test/cli/ --cover
```

## Coverage Goals

- Unit tests: Internal module logic
- Integration tests: Component interaction
- End-to-end tests: Full user workflows
- Mock tests: Fast feedback cycle
- Performance tests: Scalability verification