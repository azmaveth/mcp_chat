# MCP Chat Security Integration Guide

This guide explains how to integrate with the MCP Chat security model for both Phase 1 (centralized) and Phase 2 (distributed) capabilities.

## Table of Contents

1. [Overview](#overview)
2. [Basic Usage](#basic-usage)
3. [Token Mode](#token-mode)
4. [MCP Tool Security](#mcp-tool-security)
5. [Agent Security](#agent-security)
6. [Security Monitoring](#security-monitoring)
7. [Best Practices](#best-practices)
8. [Troubleshooting](#troubleshooting)

## Overview

MCP Chat implements a capability-based security system that provides fine-grained access control for AI agents and MCP tools. The system supports two modes:

- **Phase 1 (Centralized)**: All capability checks go through the SecurityKernel GenServer
- **Phase 2 (Token-based)**: JWT tokens enable local validation for improved performance

## Basic Usage

### Requesting Capabilities

```elixir
# Request a capability for filesystem access
{:ok, capability} = MCPChat.Security.request_capability(
  :filesystem,                           # Resource type
  %{                                    # Constraints
    operations: [:read, :write],
    paths: ["/project", "/tmp"],
    max_file_size: 10_485_760,          # 10MB
    allowed_extensions: [".ex", ".exs", ".md"]
  },
  "my_agent_id"                         # Principal ID
)
```

### Validating Capabilities

```elixir
# Check if an operation is allowed
case MCPChat.Security.validate_capability(capability, :write, "/project/config.ex") do
  :ok ->
    # Proceed with the operation
    perform_file_write()
    
  {:error, reason} ->
    # Handle the security violation
    Logger.error("Security violation: #{inspect(reason)}")
end
```

### Delegating Capabilities

```elixir
# Delegate to a sub-agent with additional constraints
{:ok, delegated_cap} = MCPChat.Security.delegate_capability(
  parent_capability,
  "sub_agent_id",
  %{
    operations: [:read],  # More restrictive than parent
    paths: ["/project/src"]  # Subset of parent paths
  }
)
```

## Token Mode

### Enabling Token Mode

```elixir
# Enable globally
MCPChat.Security.set_token_mode(true)

# Or per-request
{:ok, cap} = MCPChat.Security.request_capability(
  :network,
  %{operations: [:read], resource: "https://api.example.com/**"},
  "agent_id",
  use_tokens: true  # Force token mode for this capability
)
```

### Token Structure

When in token mode, capabilities contain JWT tokens:

```elixir
%{
  id: "cap_abc123...",           # Capability ID (jti)
  token: "eyJhbGciOiJS...",      # JWT token
  is_token: true,                # Token mode indicator
  resource_type: :filesystem,
  principal_id: "agent_123",
  constraints: %{...}
}
```

### Token Validation

Token validation happens locally without SecurityKernel:

```elixir
# This validation is performed locally - no GenServer call
MCPChat.Security.validate_capability(token_cap, :read, "/tmp/file.txt")
```

## MCP Tool Security

### Secure Tool Execution

```elixir
defmodule MyMCPTool do
  alias MCPChat.Security.MCPSecurityAdapter
  
  def execute_tool(tool_name, args, capability) do
    # Validate permission before execution
    with :ok <- MCPSecurityAdapter.validate_tool_permission(
                  capability, 
                  tool_name, 
                  args
                ) do
      # Execute the tool
      perform_tool_operation(tool_name, args)
    else
      {:error, reason} ->
        {:error, {:security_violation, reason}}
    end
  end
end
```

### Tool-Specific Constraints

```elixir
# Request capability for specific MCP tools
{:ok, cap} = MCPChat.Security.request_capability(
  :mcp_tool,
  %{
    operations: [:execute],
    allowed_tools: ["list_repos", "get_repo", "create_issue"],
    resource: "github",
    rate_limit: 100  # Max 100 calls per hour
  },
  "github_agent"
)
```

## Agent Security

### Secure Agent Initialization

```elixir
defmodule MyAgent do
  use MCPChat.Agents.BaseAgent
  
  def init(args) do
    # Set agent's security principal
    MCPChat.Security.set_current_principal("agent_#{inspect(self())}")
    
    # Request required capabilities
    capabilities = request_agent_capabilities()
    
    {:ok, %{
      capabilities: capabilities,
      # ... other state
    }}
  end
  
  defp request_agent_capabilities do
    caps = []
    
    # Filesystem access
    {:ok, fs_cap} = MCPChat.Security.request_capability(
      :filesystem,
      %{operations: [:read], paths: ["/data"]},
      MCPChat.Security.get_current_principal()
    )
    caps = [fs_cap | caps]
    
    # Network access
    {:ok, net_cap} = MCPChat.Security.request_capability(
      :network,
      %{operations: [:read], resource: "https://api.example.com/**"},
      MCPChat.Security.get_current_principal()
    )
    caps = [net_cap | caps]
    
    caps
  end
end
```

### Spawning Secure Sub-Agents

```elixir
def spawn_sub_agent(parent_state, task) do
  # Delegate capabilities to sub-agent
  sub_caps = Enum.map(parent_state.capabilities, fn cap ->
    {:ok, delegated} = MCPChat.Security.delegate_capability(
      cap,
      "sub_agent_#{task.id}",
      %{max_delegation_depth: 1}  # Prevent further delegation
    )
    delegated
  end)
  
  # Spawn with delegated capabilities
  {:ok, pid} = MySubAgent.start_link(%{
    task: task,
    capabilities: sub_caps,
    parent: self()
  })
  
  pid
end
```

## Security Monitoring

### Subscribing to Alerts

```elixir
defmodule MySecurityMonitor do
  use GenServer
  alias MCPChat.Security.ViolationMonitor
  
  def init(_) do
    # Subscribe to security alerts
    ViolationMonitor.subscribe()
    {:ok, %{}}
  end
  
  def handle_info({:security_alert, alert}, state) do
    case alert.severity do
      :critical ->
        # Page on-call engineer
        notify_critical_alert(alert)
        
      :high ->
        # Send to security channel
        notify_security_team(alert)
        
      _ ->
        # Log for analysis
        Logger.warning("Security alert: #{alert.message}")
    end
    
    {:noreply, state}
  end
end
```

### Custom Violation Thresholds

```elixir
# Set custom thresholds for specific violation types
ViolationMonitor.set_threshold(
  :unauthorized_operation,
  3,                        # Count
  :timer.minutes(1)        # Time window
)

# Get violation statistics
{:ok, stats} = ViolationMonitor.get_stats()
IO.inspect(stats, label: "Security Stats")
```

### Manual Violation Recording

```elixir
# Record custom violations
ViolationMonitor.record_violation(:suspicious_pattern, %{
  pattern: "rapid_capability_requests",
  principal_id: "suspect_agent",
  request_count: 150,
  time_window: 60  # seconds
})
```

## Best Practices

### 1. Principle of Least Privilege

Always request the minimum capabilities required:

```elixir
# ❌ Bad: Overly broad permissions
{:ok, cap} = Security.request_capability(:filesystem, %{
  operations: [:read, :write, :delete],
  paths: ["/"]  # Root access!
})

# ✅ Good: Specific permissions
{:ok, cap} = Security.request_capability(:filesystem, %{
  operations: [:read],
  paths: ["/project/data", "/project/config"],
  allowed_extensions: [".json", ".toml"]
})
```

### 2. Capability Lifecycle Management

```elixir
defmodule MyWorker do
  def perform_task(task) do
    # Request capability
    {:ok, cap} = Security.request_capability(
      :network,
      %{operations: [:read], resource: task.api_url},
      "worker_#{task.id}"
    )
    
    try do
      # Use capability
      result = fetch_with_capability(cap, task.api_url)
      {:ok, result}
    after
      # Always revoke when done
      Security.revoke_capability(cap)
    end
  end
end
```

### 3. Delegation Patterns

```elixir
# Use delegation for hierarchical access control
def delegate_to_team(parent_cap, team_members) do
  Enum.map(team_members, fn member ->
    constraints = case member.role do
      :lead -> %{operations: [:read, :write]}
      :developer -> %{operations: [:read]}
      :intern -> %{operations: [:read], paths: ["/project/docs"]}
    end
    
    {:ok, cap} = Security.delegate_capability(
      parent_cap,
      member.id,
      constraints
    )
    
    {member.id, cap}
  end)
end
```

### 4. Security Context

```elixir
# Use security context for batch operations
def process_files(file_list, capability) do
  MCPChat.Security.with_capabilities([capability], fn ->
    Enum.map(file_list, fn file ->
      # Capability is available in context
      process_single_file(file)
    end)
  end)
end
```

## Troubleshooting

### Common Issues

#### 1. "Token validation failed: :invalid_signature"

**Cause**: Token was tampered with or signed with wrong key

**Solution**:
```elixir
# Ensure KeyManager is running
Process.whereis(MCPChat.Security.KeyManager)

# Check key rotation status
{:ok, keys} = MCPChat.Security.KeyManager.get_verification_keys()
IO.inspect(map_size(keys), label: "Active keys")
```

#### 2. "Security violation: :resource_not_permitted"

**Cause**: Resource doesn't match capability constraints

**Solution**:
```elixir
# Debug capability constraints
{:ok, claims} = MCPChat.Security.TokenValidator.peek_claims(cap.token)
IO.inspect(claims["constraints"], label: "Constraints")
IO.inspect(claims["resource"], label: "Allowed resource")
```

#### 3. High security violation rate

**Check violation patterns**:
```elixir
{:ok, violations} = ViolationMonitor.get_recent_violations(50)

# Group by type
violations
|> Enum.group_by(& &1.type)
|> Enum.map(fn {type, list} -> {type, length(list)} end)
|> IO.inspect(label: "Violations by type")
```

### Debug Mode

Enable detailed security logging:

```elixir
# In config/dev.exs
config :logger, :console,
  level: :debug,
  format: "$time $metadata[$level] $message\n",
  metadata: [:security_event, :capability_id, :principal_id]
```

### Performance Tuning

```elixir
# Run benchmarks
mix run test/benchmarks/security_benchmark.exs

# Check token validation cache hit rate
{:ok, cache_stats} = MCPChat.Security.TokenValidator.Cache.get_stats()
IO.inspect(cache_stats, label: "Cache performance")
```

## Migration Guide

### Phase 1 → Phase 2

1. **Test in dual mode**:
```elixir
# Test with both modes
test_capability_modes(fn mode ->
  Security.set_token_mode(mode)
  run_security_tests()
end, [false, true])
```

2. **Gradual rollout**:
```elixir
# Enable for specific agents
def init(args) do
  if args[:use_token_security] do
    Security.set_token_mode(true)
  end
  # ...
end
```

3. **Monitor performance**:
```elixir
# Compare validation times
{phase1_time, _} = :timer.tc(fn ->
  Security.set_token_mode(false)
  Security.validate_capability(cap, :read, "/tmp")
end)

{phase2_time, _} = :timer.tc(fn ->
  Security.set_token_mode(true)
  Security.validate_capability(cap, :read, "/tmp")
end)

IO.puts("Improvement: #{phase1_time / phase2_time}x")
```

---

For more information, see:
- [SECURITY_MODEL_DESIGN.md](./SECURITY_MODEL_DESIGN.md) - Detailed architecture
- [PHASE2_SECURITY_DESIGN.md](./PHASE2_SECURITY_DESIGN.md) - Token implementation
- [test/integration/security_integration_test.exs](./test/integration/security_integration_test.exs) - Working examples