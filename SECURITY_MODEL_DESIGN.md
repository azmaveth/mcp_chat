# MCP Chat Security Model Design Document

## Overview

This document details the comprehensive security model design for MCP Chat, an Elixir/OTP application that orchestrates AI agents and MCP (Model Context Protocol) servers. The security model implements Capability-Based Security (CapSec) to provide fine-grained, delegatable permissions for AI agents executing code through external processes.

**Document Version:** 1.0  
**Last Updated:** 2025-06-18  
**Status:** Implementation Planning

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Security Requirements](#security-requirements)
3. [Core Components](#core-components)
4. [Implementation Phases](#implementation-phases)
5. [API Design](#api-design)
6. [Data Structures](#data-structures)
7. [Security Flows](#security-flows)
8. [Integration Points](#integration-points)
9. [Audit and Logging](#audit-and-logging)
10. [Edge Cases and Error Handling](#edge-cases-and-error-handling)
11. [Performance Considerations](#performance-considerations)
12. [Future Enhancements](#future-enhancements)

## Architecture Overview

### Security Paradigm: Capability-Based Security (CapSec)

We implement a **Capability-Based Security** model where:

- **Capabilities** are unforgeable tokens that grant specific rights to specific resources
- **Principals** (agent processes) can only access resources they have valid capabilities for
- **Delegation** allows agents to grant subsets of their capabilities to sub-agents
- **Revocation** provides immediate capability withdrawal with cascading effects

### Key Architectural Principles

1. **Principle of Least Privilege**: Agents start with no permissions; capabilities must be explicitly granted
2. **Explicit Authorization**: Every resource access requires presenting a valid capability
3. **Fail-Closed Security**: Default deny; operations fail securely when authorization is unclear
4. **OTP Integration**: Leverage Elixir/OTP process isolation and supervision for security boundaries
5. **Audit-First Design**: All security decisions are logged with structured metadata

### System Components

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   AI Agents     │    │  Security Kernel │    │  MCP Servers    │
│                 │    │                  │    │                 │
│ ┌─────────────┐ │    │ ┌──────────────┐ │    │ ┌─────────────┐ │
│ │ Coder Agent │ │◄──►│ │ Capability   │ │    │ │ FileSystem  │ │
│ └─────────────┘ │    │ │ Manager      │ │    │ └─────────────┘ │
│ ┌─────────────┐ │    │ └──────────────┘ │    │ ┌─────────────┐ │
│ │ Test Agent  │ │    │ ┌──────────────┐ │    │ │ Database    │ │
│ └─────────────┘ │    │ │ Audit Logger │ │    │ └─────────────┘ │
│ ┌─────────────┐ │    │ └──────────────┘ │    │ ┌─────────────┐ │
│ │ Sub-Agents  │ │    │ ┌──────────────┐ │    │ │ API Client  │ │
│ └─────────────┘ │    │ │ Policy Engine│ │    │ └─────────────┘ │
└─────────────────┘    │ └──────────────┘ │    └─────────────────┘
                       └──────────────────┘
```

## Security Requirements

### Functional Requirements

1. **FR-1: Fine-Grained Permissions**
   - Support resource-specific capabilities (e.g., read specific file, write to specific directory)
   - URI-based resource identification for extensibility
   - Operation-specific access control (read, write, execute, etc.)

2. **FR-2: Agent Delegation**
   - Parent agents can delegate subset of capabilities to sub-agents
   - Delegation constraints (time limits, resource restrictions, operation limits)
   - Cascading revocation when parent agents terminate

3. **FR-3: Dynamic Permission Management**
   - Runtime capability granting and revocation
   - Emergency revocation mechanisms
   - Capability introspection for debugging

4. **FR-4: Process Isolation**
   - Phase 1: OTP process isolation
   - Phase 2: OS-level sandboxing with MuonTrap + cgroups

5. **FR-5: Comprehensive Auditing**
   - All security decisions logged with structured metadata
   - Capability lifecycle tracking
   - Security event correlation and analysis

### Non-Functional Requirements

1. **NFR-1: Performance**
   - Phase 1: Accept central bottleneck for correctness
   - Phase 2: Distributed validation with signed tokens
   - Target: <10ms capability validation latency

2. **NFR-2: Availability**
   - Fail-closed security (deny on uncertainty)
   - SecurityKernel under supervision with state persistence
   - Graceful degradation when audit systems unavailable

3. **NFR-3: Usability**
   - Clean, ergonomic API for developers
   - Minimal security configuration overhead
   - Clear error messages for permission denials

4. **NFR-4: Maintainability**
   - Centralized security logic in SecurityKernel
   - Clear separation between policy and enforcement
   - Comprehensive test coverage for security paths

## Core Components

### 1. Security Module (Public API)

**Location:** `lib/mcp_chat/security.ex`

The primary interface for all security operations. Provides clean abstractions over the underlying SecurityKernel complexity.

**Key Functions:**
- `request/3` - Request capability for resource access
- `delegate/3` - Delegate capability to sub-agent with constraints
- `validate/2` - Validate capability for specific operation
- `revoke/1` - Revoke specific capability
- `list_my_capabilities/0` - Introspect agent's current capabilities

### 2. SecurityKernel GenServer

**Location:** `lib/mcp_chat/security/kernel.ex`

Central authority for capability management. Handles all capability lifecycle operations.

**Responsibilities:**
- Capability issuance and validation
- Delegation logic and constraint enforcement
- Revocation and cascading cleanup
- State persistence and recovery
- Audit event generation

**State Structure:**
```elixir
%SecurityKernel.State{
  capabilities: %{},        # capability_id => Capability struct
  agent_capabilities: %{},  # agent_pid => [capability_ids]
  delegation_tree: %{},     # parent_id => [child_ids]
  revoked_capabilities: %{}, # capability_id => revocation_timestamp
  audit_logger: pid,
  settings: %{}
}
```

### 3. Capability Struct

**Location:** `lib/mcp_chat/security/capability.ex`

Represents a specific permission grant with metadata.

**Structure:**
```elixir
%Security.Capability{
  id: "cap_123abc",                    # Unique identifier
  resource_uri: "mcp://fs/read/path",  # What resource/operation
  principal_pid: #PID<0.123.0>,       # Who owns this capability
  granted_at: ~U[2025-01-18 10:00:00Z], # When granted
  expires_at: ~U[2025-01-18 11:00:00Z], # When expires (optional)
  constraints: %{},                    # Delegation constraints
  parent_capability_id: nil,           # If delegated, parent ID
  delegation_depth: 3,                 # Max delegation levels remaining
  metadata: %{}                        # Additional context
}
```

### 4. Security Audit Logger

**Location:** `lib/mcp_chat/security/audit_logger.ex`

Structured logging for all security-relevant events.

**Event Types:**
- `capability_requested`
- `capability_granted`
- `capability_denied`
- `capability_delegated`
- `capability_revoked`
- `capability_validated`
- `security_violation`

### 5. Resource Validators

**Location:** `lib/mcp_chat/security/validators/`

Specific validation logic for different resource types.

**Validators:**
- `FilesystemValidator` - Path normalization and constraint checking
- `APIValidator` - URL validation and method restrictions
- `DatabaseValidator` - Query validation and table restrictions

## Implementation Phases

### Phase 1: Security MVP (Current Implementation)

**Goal:** Establish core capability model with correct security semantics

**Scope:**
- ✅ Security module API design
- ⏳ SecurityKernel GenServer implementation
- ⏳ Basic capability validation
- ⏳ OTP process isolation only
- ⏳ Comprehensive audit logging
- ⏳ Integration with MCP adapter layer

**Architecture Decisions:**
- All capability checks go through central SecurityKernel
- State persisted to DETS for simplicity
- No signed tokens yet (performance secondary to correctness)
- Focus on developer experience and usability

**Success Criteria:**
- Agents can request and use capabilities
- Delegation works with constraints
- Revocation cascades properly
- All security decisions are audited
- Clean integration with existing MCP tools

### Phase 2: Performance & Hardening (Future)

**Goal:** Scale the system and add stronger process isolation

**Scope:**
- Signed, short-lived capability tokens
- MuonTrap + cgroups integration (optional)
- Distributed capability validation
- Performance optimization
- Advanced constraint languages

**Architecture Decisions:**
- SecurityKernel issues signed tokens for distributed validation
- MuonTrap as optional high-security execution mode
- Rate limiting and DoS protection
- Move to Postgres for kernel state if needed

## API Design

### Security Module Public API

```elixir
# Basic capability request
{:ok, cap} = Security.request(:fs, :read, "/path/to/file")
{:ok, cap} = Security.request(:api, :post, "https://api.github.com/repos/org/repo")
{:ok, cap} = Security.request(:db, :query, "users_db", "SELECT * FROM orders")

# Using capabilities with resources
result = FileSystem.using(cap).read_file()
response = APIClient.using(cap).post(data)
rows = Database.using(cap).query(params)

# Delegation with constraints
{:ok, child_cap} = Security.delegate(cap, 
  to: child_pid,
  constraints: %{
    path_prefix: "/tmp",
    expires_in: 300,
    operations: [:read]
  }
)

# Bulk requests for plan mode
{:ok, plan_caps} = Security.request_for_plan([
  {:fs, :read, "/src/**"},
  {:fs, :write, "/dist/**"},
  {:api, :post, "https://github.com/api/**"}
])

# Capability management
:ok = Security.revoke(cap)
:ok = Security.revoke_all_for_agent(agent_pid)
{:ok, caps} = Security.list_my_capabilities()

# Validation (used by resources)
:ok = Security.validate(cap, for_resource: {:fs, :read, "/actual/path"})
{:error, :expired} = Security.validate(expired_cap, for_resource: {:fs, :read, "/path"})
```

### Resource Integration Pattern

```elixir
defmodule FileSystem do
  defstruct [:capability]
  
  def using(capability), do: %FileSystem{capability: capability}
  
  def read_file(%FileSystem{capability: cap}, path) do
    # Normalize path for security
    normalized_path = Path.expand(path) |> Path.absname()
    
    # Validate capability
    with :ok <- Security.validate(cap, for_resource: {:fs, :read, normalized_path}) do
      # Perform actual file operation
      File.read(normalized_path)
    else
      {:error, reason} -> {:error, {:security_violation, reason}}
    end
  end
end
```

## Data Structures

### URI Scheme for Resources

We use a consistent URI scheme for all resource identification:

```
mcp://<resource_type>/<operation>/<resource_path>

Examples:
mcp://fs/read/home/user/project/src/main.ex
mcp://fs/write/tmp/agent-123/
mcp://api/post/https/api.github.com/repos/org/repo/issues
mcp://db/query/users_db/orders
mcp://shell/execute/home/user/scripts/build.sh
```

**Benefits:**
- Consistent, extensible format
- Supports wildcard matching (`mcp://fs/read/project/*`)
- Clear separation of resource type, operation, and target
- Future-proof for new resource types

### Constraint Types

Delegation constraints are expressed as maps with predefined keys:

```elixir
%{
  # Time constraints
  expires_in: 300,  # seconds from now
  expires_at: ~U[2025-01-18 15:30:00Z],
  
  # Resource constraints
  path_prefix: "/tmp/agent-workspace/",
  allowed_paths: ["/src/**", "/tests/**"],
  denied_paths: ["/secrets/**"],
  
  # Operation constraints
  operations: [:read, :write],  # subset of parent's operations
  max_operations: 100,  # rate limiting
  
  # Network constraints
  allowed_hosts: ["api.github.com", "*.trusted-domain.com"],
  allowed_methods: [:get, :post],
  
  # Database constraints
  allowed_tables: ["orders", "products"],
  query_patterns: ["SELECT * FROM %table% WHERE user_id = ?"],
  
  # General constraints
  max_delegation_depth: 2,  # how many levels can this be delegated further
  delegation_constraints: %{},  # constraints to apply to any sub-delegations
}
```

## Security Flows

### 1. Capability Request Flow

```
Agent -> Security.request(:fs, :read, "/path") -> SecurityKernel
  1. Security normalizes path: "/path" -> "/absolute/path"
  2. SecurityKernel checks agent permissions and policies
  3. If approved, creates Capability struct with unique ID
  4. Stores capability in state, associates with agent PID
  5. Sets up process monitoring for agent
  6. Logs grant event
  7. Returns {:ok, capability} to agent
```

### 2. Capability Validation Flow

```
Resource <- Security.validate(cap, {:fs, :read, "/path"}) <- Agent
  1. Security extracts capability ID and checks with SecurityKernel
  2. SecurityKernel validates:
     - Capability exists and not revoked
     - Not expired
     - Principal PID matches caller
     - Requested operation matches granted operation
     - Resource path matches granted resource (with constraints)
  3. Returns :ok or {:error, reason}
  4. Logs validation event (success or failure)
```

### 3. Delegation Flow

```
Parent Agent -> Security.delegate(cap, to: child_pid, constraints: %{...})
  1. Security validates parent owns the capability
  2. SecurityKernel creates new delegated capability:
     - New unique ID
     - Principal = child_pid
     - Parent = original capability ID
     - Constraints = intersection of parent constraints + new constraints
     - Delegation depth = parent depth - 1
  3. Sets up monitoring for child process
  4. Records delegation relationship in delegation_tree
  5. Logs delegation event
  6. Returns {:ok, delegated_capability}
```

### 4. Revocation Flow

```
Agent -> Security.revoke(cap) -> SecurityKernel
  1. SecurityKernel validates agent owns capability
  2. Marks capability as revoked with timestamp
  3. Looks up all delegated capabilities in delegation_tree
  4. Recursively revokes all child capabilities
  5. Removes capabilities from agent_capabilities mapping
  6. Logs revocation events for all affected capabilities
  7. Sends revocation notifications to affected agents (optional)
```

### 5. Agent Termination Flow

```
Agent Process Dies -> SecurityKernel receives :DOWN message
  1. SecurityKernel looks up all capabilities owned by dead PID
  2. Automatically revokes all capabilities (with cascading)
  3. Cleans up process monitoring
  4. Logs agent termination and capability cleanup
  5. Removes agent from all internal mappings
```

## Integration Points

### 1. MCP Adapter Layer Integration

**Current MCP Flow:**
```
Agent -> MCPAgent.call_tool -> MCPAdapter -> ExMCP -> MCP Server
```

**Secured MCP Flow:**
```
Agent -> Security.request -> SecurityKernel (approve) -> Agent -> MCPAgent.call_tool -> MCPAdapter.with_capability -> ExMCP -> MCP Server
```

**Implementation:**
- Modify `MCPAdapter` to require capability for tool calls
- Add `MCPAdapter.with_capability/2` wrapper function
- Update all MCP tool calls to use secured pathway

### 2. Plan Mode Integration

**Plan Capability Bundling:**
```elixir
# In plan parser/executor
plan_capabilities = Security.request_for_plan([
  {:fs, :read, "/src/**"},
  {:fs, :write, "/dist/**"},
  {:api, :post, "https://github.com/**"}
])

# Execute plan steps with bundled capabilities
PlanExecutor.execute_with_capabilities(plan, plan_capabilities)
```

### 3. Agent Spawning Integration

**Secure Agent Delegation:**
```elixir
# When spawning sub-agent
def spawn_sub_agent(task_spec, parent_capabilities) do
  {:ok, sub_agent_pid} = Agent.start_link(task_spec)
  
  # Delegate only necessary capabilities
  required_caps = analyze_task_capabilities(task_spec)
  delegated_caps = for cap <- required_caps do
    Security.delegate(cap, to: sub_agent_pid, constraints: task_constraints(task_spec))
  end
  
  Agent.set_capabilities(sub_agent_pid, delegated_caps)
end
```

## Audit and Logging

### Structured Log Format

All security events use consistent structured logging:

```elixir
Logger.info("Security event",
  event_type: :capability_granted,
  trace_id: "trace_123abc",
  capability_id: "cap_456def",
  principal_pid: "#PID<0.123.0>",
  resource_uri: "mcp://fs/read/project/src/main.ex",
  granted_at: ~U[2025-01-18 10:00:00Z],
  expires_at: ~U[2025-01-18 11:00:00Z],
  delegation_depth: 3,
  parent_capability_id: nil,
  constraints: %{path_prefix: "/project/"},
  request_context: %{
    agent_type: :coder_agent,
    session_id: "session_789",
    plan_step: 3
  }
)
```

### Audit Event Types

1. **Capability Lifecycle Events:**
   - `capability_requested` - Agent requests new capability
   - `capability_granted` - SecurityKernel approves and issues capability
   - `capability_denied` - SecurityKernel denies capability request
   - `capability_delegated` - Parent delegates capability to child
   - `capability_revoked` - Capability explicitly revoked
   - `capability_expired` - Capability expired due to TTL

2. **Validation Events:**
   - `capability_validated` - Successful validation for resource access
   - `capability_validation_failed` - Failed validation attempt
   - `constraint_violation` - Constraint check failed during validation

3. **Security Violation Events:**
   - `unauthorized_access` - Attempt to access resource without capability
   - `capability_forgery` - Invalid or tampered capability presented
   - `privilege_escalation` - Attempt to exceed granted permissions

4. **System Events:**
   - `agent_terminated` - Agent process died, capabilities cleaned up
   - `security_kernel_started` - SecurityKernel initialization
   - `security_kernel_state_restored` - State recovered from persistence

### Audit Analysis and Alerting

**Trace Correlation:**
- Each security operation gets a unique trace_id
- Related operations (delegation chains) share trace correlation
- Enables end-to-end security flow analysis

**Security Metrics:**
- Capability grant/deny ratios
- Constraint violation frequency
- Agent termination cleanup statistics
- Performance metrics (validation latency)

**Alert Conditions:**
- High denial rates (potential attack)
- Unusual delegation patterns
- Capability validation failures
- Constraint violations from specific agents

## Edge Cases and Error Handling

### 1. Agent Process Crashes

**Scenario:** Agent dies while holding capabilities

**Handling:**
- SecurityKernel monitors all capability-holding processes
- Receives `:DOWN` message on process death
- Automatically revokes all capabilities owned by dead process
- Cascading revocation of all delegated capabilities
- Clean up all internal state mappings
- Log agent termination event

**Code:**
```elixir
def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
  caps_to_revoke = Map.get(state.agent_capabilities, pid, [])
  new_state = Enum.reduce(caps_to_revoke, state, &revoke_capability_internal/2)
  
  Logger.warn("Agent terminated, capabilities revoked",
    agent_pid: pid,
    revoked_capabilities: caps_to_revoke
  )
  
  {:noreply, new_state}
end
```

### 2. Capability Expiration During Operation

**Scenario:** Long-running operation where capability expires mid-execution

**Handling:**
- Resource validators check expiration at operation start
- For streaming/long operations, resource decides on re-validation frequency
- Graceful degradation: complete current operation, deny future operations
- Clear error messages to agent about expiration

### 3. Delegation Depth Exhaustion

**Scenario:** Agent tries to delegate but has reached max delegation depth

**Handling:**
- Check delegation_depth > 0 before allowing delegation
- Return clear error: `{:error, :delegation_depth_exhausted}`
- Log delegation attempt for security analysis
- Suggest alternative: agent requests new capability instead of delegating

### 4. Constraint Conflicts

**Scenario:** Delegated constraints conflict with parent constraints

**Handling:**
- Take intersection of parent and requested constraints
- If intersection is empty, deny delegation
- Example: parent allows `/project/*`, child requests `/home/*` → deny
- Log constraint conflict for debugging

### 5. SecurityKernel Crash

**Scenario:** SecurityKernel GenServer crashes and needs recovery

**Handling:**
- SecurityKernel under supervision with restart strategy
- State persisted to DETS after every state change
- On restart, reload state from DETS
- Re-establish process monitoring for all active capabilities
- Log recovery event with state restoration details

### 6. Resource Path Traversal Attempts

**Scenario:** Agent tries to use `../../../etc/passwd` in file path

**Handling:**
- Security.request normalizes ALL paths using `Path.expand` and `Path.absname`
- Validation always uses normalized paths
- Path traversal attempts are logged as security violations
- Clear error messages about invalid paths

### 7. Network Partitions (Future: Distributed Mode)

**Scenario:** Agent can't reach SecurityKernel for validation

**Handling:**
- Fail-closed: deny operation if can't validate
- Local caching with short TTLs for performance
- Graceful degradation with reduced functionality
- Clear error messages about network issues

## Performance Considerations

### Phase 1: Baseline Performance

**Current Bottlenecks:**
- All capability checks go through central SecurityKernel GenServer
- Synchronous validation calls add latency to every resource access
- State persistence to DETS on every state change

**Mitigation Strategies:**
- Efficient ETS-based lookups for capability validation
- Batch state persistence (every N operations or time interval)
- Capability caching at agent level (with TTL validation)

**Performance Targets:**
- Capability validation: <5ms (P95)
- Capability granting: <10ms (P95)
- System throughput: 1000+ operations/second

### Phase 2: Distributed Performance

**Optimizations:**
- Signed capability tokens for local validation
- Distributed SecurityKernel state with Mnesia
- Capability validation caching with invalidation
- Async audit logging to prevent bottlenecks

**Performance Targets:**
- Capability validation: <1ms (P95) with local tokens
- System throughput: 10,000+ operations/second
- Cross-node capability operations: <50ms (P95)

## Future Enhancements

### 1. Advanced Constraint Languages

**Current:** Simple map-based constraints
**Future:** DSL for complex policies

```elixir
constraints: """
  path must start with "/project/" and
  not contain "secrets" and
  file_size < 10MB and
  weekday in [monday, tuesday, wednesday, thursday, friday] and
  hour between 9 and 17
"""
```

### 2. Machine Learning Integration

**Anomaly Detection:**
- Learn normal capability usage patterns per agent type
- Detect unusual permission requests or access patterns
- Automatic threat scoring and response

**Adaptive Permissions:**
- Gradually expand permissions based on agent behavior
- Automatic constraint relaxation for trusted agents
- Dynamic risk assessment

### 3. Blockchain/Distributed Ledger

**Immutable Audit Trail:**
- Store security events in distributed ledger
- Cryptographic proof of security decisions
- Cross-organization capability verification

### 4. Integration with External Systems

**Identity Providers:**
- LDAP/Active Directory integration for user-based policies
- OAuth2/OIDC for external authorization
- SAML for enterprise SSO

**Security Information and Event Management (SIEM):**
- Real-time security event streaming
- Integration with Splunk, ELK, etc.
- Automated incident response

### 5. Advanced Sandboxing

**Container Integration:**
- Docker container per MCP server
- Kubernetes-based resource isolation
- Network policy enforcement

**WebAssembly (WASM):**
- WASM runtime for untrusted code execution
- Capability-based WASM module authorization
- Cross-platform sandboxing

## Implementation Checklist

### Phase 1 MVP Tasks

#### Foundation
- [ ] Create `Security` module with public API
- [ ] Implement `Security.Capability` struct
- [ ] Create `SecurityKernel` GenServer
- [ ] Set up capability state management (ETS + DETS)
- [ ] Implement process monitoring for capability cleanup

#### Core Operations
- [ ] Capability request and validation logic
- [ ] Delegation with constraint enforcement
- [ ] Revocation with cascading cleanup
- [ ] Path normalization and security validation
- [ ] Constraint intersection and validation

#### Audit System
- [ ] Structured audit logging implementation
- [ ] Security event definitions and schemas
- [ ] Log correlation and trace ID management
- [ ] Basic security metrics collection

#### Integration
- [ ] MCP adapter layer security integration
- [ ] Plan mode capability bundling
- [ ] Agent spawning with delegation
- [ ] Error handling and security violation responses

#### Testing
- [ ] Unit tests for all core security operations
- [ ] Integration tests with MCP tools
- [ ] Security violation scenario testing
- [ ] Performance benchmark baseline

#### Documentation
- [ ] API documentation and examples
- [ ] Security configuration guide
- [ ] Troubleshooting and debugging guide
- [ ] Security best practices for agent developers

### Phase 2 Performance Tasks

#### Distributed Validation
- [ ] Signed capability token implementation
- [ ] Local validation without kernel round-trip
- [ ] Token revocation list management
- [ ] Distributed state synchronization

#### Advanced Security
- [ ] MuonTrap + cgroups integration
- [ ] Container-based MCP server isolation
- [ ] Advanced constraint language parser
- [ ] Rate limiting and DoS protection

#### Operational
- [ ] Production deployment guides
- [ ] Monitoring and alerting setup
- [ ] Backup and disaster recovery procedures
- [ ] Performance tuning documentation

---

**End of Security Model Design Document**

This document serves as the authoritative guide for implementing the MCP Chat security model. It should be updated as implementation progresses and new requirements emerge.