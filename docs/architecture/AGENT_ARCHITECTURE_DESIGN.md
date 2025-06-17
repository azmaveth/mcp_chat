# MCP Chat Agent Architecture Design
## Decoupling UI from Core Agent with OTP and Pub/Sub

### Executive Summary

This document outlines the architectural refactor to decouple MCP Chat's UI layer from the core chat agent logic, enabling multiple concurrent UI interfaces (TUI, Web) while maintaining 100% uptime through OTP supervision patterns.

**Key Goals:**
- Background agent service with fault tolerance
- Multiple UI interfaces (TUI, Phoenix Web UI)
- Real-time updates via pub/sub messaging
- Clean separation of concerns
- Scalable multi-session support

---

## 1. Overall System Architecture

### Refined Three-Layer Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        UI Layer                                 │
│  ┌─────────────────┐              ┌─────────────────────────┐   │
│  │   TUI Client    │              │    Web UI (Phoenix)     │   │
│  │ (MCPChat.UI.TUI)│              │  (MCPChat.UI.Web)      │   │
│  └─────────────────┘              └─────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
           │                                    │
           │ (API Calls)                        │ (Phoenix Channels)
           │                                    │
           ▼                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Gateway API Layer                            │
│                   (MCPChat.Gateway)                             │
│               Stateless API Functions                           │
└─────────────────────────────────────────────────────────────────┘
           │
           │ (GenServer calls/casts via Registry)
           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Core Agent Layer                             │
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌───────────────────┐│
│  │ SessionManager  │  │ Phoenix.PubSub  │  │  Per-Session      ││
│  │  - Registry     │  │                 │  │   GenServers      ││
│  │  - DynamicSup   │  │                 │  │ (MCPChat.Session) ││
│  └─────────────────┘  └─────────────────┘  └───────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

**Critical Architectural Decision: Per-Session GenServer Model**

Instead of a single global agent, we implement a **per-session GenServer pattern**:
- Each chat session is its own supervised GenServer process
- Enables true concurrency and fault isolation
- Scales naturally with user growth
- Follows Elixir/OTP best practices

---

## 2. Core Components Design

### 2.1 MCPChat.SessionManager

**Purpose:** Central registry and lifecycle manager for all chat sessions.

```elixir
defmodule MCPChat.SessionManager do
  use GenServer
  
  # Public API
  def start_session(session_id, opts \\ [])
  def stop_session(session_id)
  def get_session_pid(session_id)
  def list_active_sessions()
  
  # Registry name for session lookup
  def registry_name, do: MCPChat.SessionRegistry
  
  # Via tuple for session addressing
  def via_tuple(session_id) do
    {:via, Registry, {registry_name(), session_id}}
  end
end
```

**Components:**
- **Registry:** Maps session_id → GenServer PID
- **DynamicSupervisor:** Supervises individual session processes
- **Session lifecycle management:** Start/stop/monitor sessions

**Pros:**
- Central point for session management
- OTP-supervised fault tolerance
- Easy session discovery and monitoring

**Cons:**
- Single point of coordination (mitigated by Registry's performance)
- Additional complexity over single-process model

### 2.2 MCPChat.Session (GenServer)

**Purpose:** Individual chat session state and logic.

```elixir
defmodule MCPChat.Session do
  use GenServer
  
  defstruct [
    :session_id,
    :messages,
    :user_context,
    :mcp_servers,
    :llm_adapter,
    :current_state,  # :idle, :thinking, :awaiting_permission, etc.
    :stats,
    :config
  ]
  
  # Commands (write operations)
  def handle_cast({:send_message, content}, state)
  def handle_cast({:connect_mcp_server, server_config}, state)
  def handle_call({:execute_command, command}, _from, state)
  
  # Queries (read operations)  
  def handle_call(:get_full_state, _from, state)
  def handle_call({:get_messages, opts}, _from, state)
end
```

**State Management:**
- **Messages:** Complete conversation history
- **MCP Servers:** Per-session MCP server connections
- **User Context:** Session-specific configuration and preferences
- **Current State:** Used for permission flows and UI state sync

**Pros:**
- True isolation between sessions
- Fault tolerance per session
- Clean state boundaries
- Natural concurrency model

**Cons:**
- Memory usage scales with active sessions
- State lost on process crash (addressed with persistence)

### 2.3 MCPChat.Gateway (Stateless API)

**Purpose:** Public API abstraction over OTP internals.

```elixir
defmodule MCPChat.Gateway do
  # Session management
  def create_session(user_id, opts \\ [])
  def destroy_session(session_id)
  
  # Message handling
  def send_message(session_id, content)
  def get_message_history(session_id, opts \\ [])
  
  # Commands
  def execute_command(session_id, command_string)
  def resolve_permission(session_id, request_id, decision)
  
  # State queries
  def get_session_state(session_id)
  def get_session_stats(session_id)
  
  # MCP operations
  def connect_mcp_server(session_id, server_config)
  def list_mcp_tools(session_id, server_name)
  def execute_mcp_tool(session_id, server_name, tool_name, args)
end
```

**Implementation Pattern:**
```elixir
def send_message(session_id, content) do
  case MCPChat.SessionManager.get_session_pid(session_id) do
    {:ok, pid} -> 
      GenServer.cast(pid, {:send_message, content})
      :ok
    {:error, :not_found} -> 
      {:error, :session_not_found}
  end
end
```

**Pros:**
- Clean abstraction for UI layers
- Hides OTP complexity from clients
- Consistent error handling
- Easy to test and mock

**Cons:**
- Additional indirection layer
- All operations require session lookup

---

## 3. Pub/Sub Event Architecture

### 3.1 Event Schema Design

```elixir
defmodule MCPChat.Events do
  # Session lifecycle
  defmodule SessionStarted do
    defstruct [:session_id, :user_id, :timestamp]
  end
  
  defmodule SessionEnded do
    defstruct [:session_id, :reason, :timestamp]
  end
  
  # Message events
  defmodule MessageAdded do
    defstruct [:session_id, :message_id, :message, :timestamp]
  end
  
  defmodule MessageUpdated do
    defstruct [:session_id, :message_id, :content, :timestamp]
  end
  
  # Streaming events
  defmodule StreamChunkReceived do
    defstruct [:session_id, :message_id, :chunk, :index, :timestamp]
  end
  
  defmodule StreamCompleted do
    defstruct [:session_id, :message_id, :final_content, :stats]
  end
  
  # State changes
  defmodule SessionStateChanged do
    defstruct [:session_id, :old_state, :new_state, :context]
  end
  
  # Permission handling
  defmodule PermissionRequired do
    defstruct [:session_id, :request_id, :prompt, :options, :timeout]
  end
  
  defmodule PermissionResolved do
    defstruct [:session_id, :request_id, :decision, :timestamp]
  end
  
  # MCP events
  defmodule MCPServerConnected do
    defstruct [:session_id, :server_name, :capabilities]
  end
  
  defmodule MCPToolExecuted do
    defstruct [:session_id, :server_name, :tool_name, :result, :duration]
  end
  
  # Error events
  defmodule ErrorOccurred do
    defstruct [:session_id, :error_type, :message, :context, :timestamp]
  end
end
```

### 3.2 Topic Naming Strategy

**Pattern:** `"session:{session_id}"`

**Examples:**
- `"session:user_123_20250616_001"` - User-specific session
- `"session:system"` - Global system events
- `"session:admin_dashboard"` - Admin monitoring

**Subscription Patterns:**
```elixir
# Subscribe to specific session
Phoenix.PubSub.subscribe(MCPChat.PubSub, "session:#{session_id}")

# Subscribe to all sessions (admin dashboard)
Phoenix.PubSub.subscribe(MCPChat.PubSub, "session:*")
```

### 3.3 Broadcasting Strategy

```elixir
# In MCPChat.Session GenServer
defp broadcast_event(session_id, event_struct) do
  topic = "session:#{session_id}"
  Phoenix.PubSub.broadcast(MCPChat.PubSub, topic, event_struct)
end

# Usage in session logic
def handle_cast({:send_message, content}, state) do
  message = create_message(content, state)
  new_state = add_message_to_history(state, message)
  
  # Broadcast the event
  broadcast_event(state.session_id, %MessageAdded{
    session_id: state.session_id,
    message_id: message.id,
    message: message,
    timestamp: DateTime.utc_now()
  })
  
  {:noreply, new_state}
end
```

---

## 4. OTP Supervision Tree

### 4.1 Application Structure

```elixir
# MCPChat.Application
def start(_type, _args) do
  children = [
    # Core infrastructure
    {Phoenix.PubSub, name: MCPChat.PubSub},
    
    # Session registry
    {Registry, keys: :unique, name: MCPChat.SessionRegistry},
    
    # Session management
    {DynamicSupervisor, name: MCPChat.SessionSupervisor, strategy: :one_for_one},
    MCPChat.SessionManager,
    
    # Telemetry and monitoring
    MCPChat.Telemetry,
    
    # Optional: Web interface
    # MCPChatWeb.Endpoint
  ]
  
  opts = [strategy: :one_for_one, name: MCPChat.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### 4.2 Session Supervision Strategy

```elixir
defmodule MCPChat.SessionSupervisor do
  use DynamicSupervisor
  
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  def start_session(session_id, opts) do
    child_spec = {MCPChat.Session, [session_id: session_id] ++ opts}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end
  
  def terminate_session(session_id) do
    case MCPChat.SessionManager.get_session_pid(session_id) do
      {:ok, pid} -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      error -> error
    end
  end
  
  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
```

**Fault Tolerance Strategy:**
- **Individual Session Crashes:** Session restarts, state recovered from persistence
- **SessionManager Crash:** Registry rebuilt from ETS tables
- **PubSub Crash:** Subscribers automatically reconnect
- **Application Crash:** All components restart, sessions reload from persistence

---

## 5. State Synchronization and Race Condition Handling

### 5.1 The Subscription-Before-Query Pattern

**Problem:** Race condition between initial state fetch and real-time updates.

**Solution:** Always subscribe before querying initial state.

```elixir
# In Phoenix Channel or TUI client initialization
defmodule MCPChatWeb.SessionChannel do
  use Phoenix.Channel
  
  def join("session:" <> session_id, _payload, socket) do
    # Step 1: Subscribe to session events FIRST
    Phoenix.PubSub.subscribe(MCPChat.PubSub, "session:#{session_id}")
    
    # Step 2: Get initial state synchronously
    case MCPChat.Gateway.get_session_state(session_id) do
      {:ok, state} ->
        # Step 3: Send initial state to client
        push(socket, "initial_state", state)
        {:ok, assign(socket, :session_id, session_id)}
      
      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end
  
  # Handle real-time updates
  def handle_info(event, socket) do
    push(socket, "event", event)
    {:noreply, socket}
  end
end
```

**Why This Works:**
1. Subscription ensures no events are missed after this point
2. Synchronous state fetch provides consistent baseline
3. Any events that occur between subscription and state fetch are queued in the process mailbox
4. Client receives initial state followed by any queued updates

### 5.2 State Reconciliation Strategy

For complex state synchronization, implement client-side state reconciliation:

```elixir
# Client-side pseudo-code
defmodule UIStateManager do
  def handle_initial_state(state) do
    # Replace entire local state
    set_state(state)
  end
  
  def handle_message_added(event) do
    # Apply delta update
    add_message_to_local_state(event.message)
  end
  
  def handle_state_inconsistency() do
    # Request fresh state from server
    MCPChat.Gateway.get_session_state(session_id)
  end
end
```

---

## 6. Streaming LLM Integration

### 6.1 Streaming Event Flow

```
Session GenServer → LLM Adapter → Stream Processing → PubSub Events → UI Updates
```

**Implementation:**

```elixir
# In MCPChat.Session
def handle_cast({:send_message, content}, state) do
  # Create user message
  message_id = generate_message_id()
  user_message = create_user_message(content, message_id)
  
  # Broadcast user message added
  broadcast_event(state.session_id, %MessageAdded{
    session_id: state.session_id,
    message_id: message_id,
    message: user_message
  })
  
  # Start LLM streaming
  assistant_message_id = generate_message_id()
  start_llm_stream(state, assistant_message_id)
  
  new_state = %{state | 
    current_state: :thinking,
    pending_message_id: assistant_message_id
  }
  
  {:noreply, new_state}
end

defp start_llm_stream(state, message_id) do
  # Use Task for concurrent execution
  task = Task.async(fn ->
    stream_opts = [
      session_id: state.session_id,
      message_id: message_id,
      callback: &handle_stream_chunk/2
    ]
    
    MCPChat.LLM.ExLLMAdapter.stream_chat(
      state.messages, 
      stream_opts
    )
  end)
  
  # Store task reference for monitoring
  Process.monitor(task.pid)
end

def handle_stream_chunk(chunk, %{session_id: session_id, message_id: message_id}) do
  # Broadcast each chunk in real-time
  broadcast_event(session_id, %StreamChunkReceived{
    session_id: session_id,
    message_id: message_id,
    chunk: chunk.delta,
    index: chunk.index
  })
end
```

### 6.2 Stream Failure Recovery

```elixir
def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
  case reason do
    :normal -> 
      # Stream completed successfully
      finalize_stream(state)
      
    error ->
      # Stream failed, broadcast error and reset state
      broadcast_event(state.session_id, %ErrorOccurred{
        session_id: state.session_id,
        error_type: :stream_failure,
        message: inspect(error),
        context: %{message_id: state.pending_message_id}
      })
      
      {:noreply, %{state | 
        current_state: :idle,
        pending_message_id: nil
      }}
  end
end
```

---

## 7. Permission Handling for Multi-UI

### 7.1 Asynchronous Permission Flow

**Traditional CLI Pattern (Blocking):**
```elixir
# OLD - blocking, CLI-only
permission = IO.gets("Allow connection to server X? (y/n): ")
```

**New Multi-UI Pattern (Async):**
```elixir
# NEW - async, multi-UI compatible
def request_permission(session_id, prompt, options \\ ["allow", "deny"]) do
  request_id = generate_request_id()
  
  # Broadcast permission request to all connected UIs
  broadcast_event(session_id, %PermissionRequired{
    session_id: session_id,
    request_id: request_id,
    prompt: prompt,
    options: options,
    timeout: 30_000
  })
  
  # Store pending request in session state
  # Session will wait for response via Gateway.resolve_permission/3
  {:pending, request_id}
end
```

### 7.2 Permission Resolution

```elixir
# In MCPChat.Gateway
def resolve_permission(session_id, request_id, decision) do
  case MCPChat.SessionManager.get_session_pid(session_id) do
    {:ok, pid} ->
      GenServer.cast(pid, {:resolve_permission, request_id, decision})
    error -> 
      error
  end
end

# In MCPChat.Session
def handle_cast({:resolve_permission, request_id, decision}, state) do
  case Map.get(state.pending_permissions, request_id) do
    nil -> 
      {:noreply, state}  # Stale or invalid request
      
    permission_context ->
      # Process the permission decision
      new_state = process_permission_decision(state, permission_context, decision)
      
      # Broadcast resolution
      broadcast_event(state.session_id, %PermissionResolved{
        session_id: state.session_id,
        request_id: request_id,
        decision: decision
      })
      
      {:noreply, new_state}
  end
end
```

---

## 8. UI Implementation Patterns

### 8.1 TUI Client (Refactored CLI)

```elixir
defmodule MCPChat.UI.TUI do
  use GenServer
  
  def start_link(session_id) do
    GenServer.start_link(__MODULE__, session_id, name: __MODULE__)
  end
  
  def init(session_id) do
    # Subscribe to session events
    Phoenix.PubSub.subscribe(MCPChat.PubSub, "session:#{session_id}")
    
    # Get initial state
    {:ok, initial_state} = MCPChat.Gateway.get_session_state(session_id)
    
    # Initialize UI
    render_initial_state(initial_state)
    start_input_loop()
    
    {:ok, %{session_id: session_id, ui_state: initial_state}}
  end
  
  # Handle real-time updates
  def handle_info(%MessageAdded{} = event, state) do
    render_new_message(event.message)
    {:noreply, state}
  end
  
  def handle_info(%StreamChunkReceived{} = event, state) do
    append_chunk_to_display(event.chunk)
    {:noreply, state}
  end
  
  def handle_info(%PermissionRequired{} = event, state) do
    decision = prompt_user_for_permission(event.prompt, event.options)
    MCPChat.Gateway.resolve_permission(state.session_id, event.request_id, decision)
    {:noreply, state}
  end
end
```

### 8.2 Web UI (Phoenix LiveView)

```elixir
defmodule MCPChatWeb.SessionLive do
  use MCPChatWeb, :live_view
  
  def mount(%{"session_id" => session_id}, _session, socket) do
    if connected?(socket) do
      # Subscribe to session events
      Phoenix.PubSub.subscribe(MCPChat.PubSub, "session:#{session_id}")
      
      # Get initial state
      {:ok, initial_state} = MCPChat.Gateway.get_session_state(session_id)
      
      {:ok, assign(socket, 
        session_id: session_id,
        messages: initial_state.messages,
        session_state: initial_state.current_state,
        pending_permission: nil
      )}
    else
      {:ok, assign(socket, session_id: session_id, messages: [], session_state: :loading)}
    end
  end
  
  # Handle form submissions
  def handle_event("send_message", %{"message" => content}, socket) do
    MCPChat.Gateway.send_message(socket.assigns.session_id, content)
    {:noreply, socket}
  end
  
  def handle_event("resolve_permission", %{"decision" => decision}, socket) do
    if socket.assigns.pending_permission do
      MCPChat.Gateway.resolve_permission(
        socket.assigns.session_id,
        socket.assigns.pending_permission.request_id,
        decision
      )
      {:noreply, assign(socket, pending_permission: nil)}
    else
      {:noreply, socket}
    end
  end
  
  # Handle real-time updates
  def handle_info(%MessageAdded{} = event, socket) do
    messages = socket.assigns.messages ++ [event.message]
    {:noreply, assign(socket, messages: messages)}
  end
  
  def handle_info(%PermissionRequired{} = event, socket) do
    {:noreply, assign(socket, pending_permission: event)}
  end
end
```

---

## 9. Migration Strategy

### 9.1 Phase 1: Backend Refactor

**Goal:** Implement new architecture while maintaining existing CLI functionality.

**Steps:**
1. **Implement Core Components:**
   - Create `MCPChat.SessionManager`
   - Create `MCPChat.Session` GenServer
   - Create `MCPChat.Gateway` API
   - Add Phoenix.PubSub to supervision tree

2. **Migrate Session Logic:**
   - Move state from `MCPChat.Session` module to `MCPChat.Session` GenServer
   - Refactor existing session functions to work with new state structure
   - Ensure backward compatibility with existing tests

3. **Update CLI to Use Gateway:**
   - Modify `MCPChat.CLI.Chat` to use `MCPChat.Gateway` instead of direct calls
   - Add PubSub subscription for real-time updates
   - Test CLI functionality with new backend

**Success Criteria:**
- Existing CLI works identically to before
- All tests pass
- Session state is properly managed in GenServer

### 9.2 Phase 2: TUI Client

**Goal:** Decouple CLI from direct session management.

**Steps:**
1. **Create TUI Client:**
   - Implement `MCPChat.UI.TUI` as separate GenServer
   - Handle PubSub events for real-time updates
   - Implement permission handling UI

2. **Update Main Entry Point:**
   - Modify `MCPChat.main/0` to start TUI client
   - Ensure session lifecycle is managed properly

**Success Criteria:**
- TUI provides same user experience as old CLI
- Real-time updates work correctly
- Permission prompts work in TUI mode

### 9.3 Phase 3: Web UI

**Goal:** Add Phoenix web interface using same backend.

**Steps:**
1. **Add Phoenix to Application:**
   - Add Phoenix endpoint to supervision tree
   - Create basic web interface structure

2. **Implement LiveView Interface:**
   - Create session management pages
   - Implement real-time chat interface
   - Add permission handling modals

3. **Multi-User Considerations:**
   - Add user authentication if needed
   - Implement session sharing/permissions
   - Add administrative interface

**Success Criteria:**
- Web UI provides equivalent functionality to TUI
- Multiple UIs can connect to same session
- Permission flows work across different UI types

---

## 10. Performance and Scalability Considerations

### 10.1 Memory Management

**Per-Session Memory Usage:**
- **Message History:** ~1KB per message (estimate)
- **MCP Connections:** ~10KB per connection
- **Session State:** ~5KB base overhead
- **Total per Session:** ~50-100KB for active session

**Scaling Estimates:**
- 1,000 concurrent sessions: ~100MB
- 10,000 concurrent sessions: ~1GB
- Performance bottleneck likely in MCP I/O before memory

**Memory Optimization Strategies:**
- **Message Pagination:** Store only recent messages in memory
- **State Compression:** Use binary term storage for large message histories
- **Session Hibernation:** Hibernate inactive sessions to reduce memory usage

### 10.2 Pub/Sub Performance

**Phoenix.PubSub Characteristics:**
- **Local Node:** ~1M messages/second
- **Distributed:** ~100K messages/second across nodes
- **Memory:** Minimal overhead per subscription

**Optimization Strategies:**
- **Event Batching:** Batch rapid-fire events (e.g., typing indicators)
- **Topic Granularity:** Use specific topics to avoid unnecessary broadcasts
- **Event Filtering:** Let clients filter events they don't need

### 10.3 Fault Tolerance

**Failure Scenarios and Recovery:**

| Component | Failure Impact | Recovery Strategy | RTO |
|-----------|---------------|-------------------|-----|
| Session GenServer | Single session down | Supervisor restart + state reload | <1s |
| SessionManager | Session discovery fails | Registry rebuild from ETS | <5s |
| PubSub | Real-time updates lost | Auto-reconnect + state refresh | <10s |
| Gateway | API calls fail | Stateless, no recovery needed | 0s |
| Entire Application | Full system down | Application restart + session reload | <30s |

---

## 11. Pros and Cons Analysis

### 11.1 Per-Session GenServer Architecture

**Pros:**
✅ **True Concurrency:** Each session runs independently
✅ **Fault Isolation:** Session crashes don't affect others  
✅ **Scalability:** Scales with Erlang VM capabilities
✅ **OTP Patterns:** Follows established Elixir/OTP practices
✅ **Memory Efficiency:** Hibernate unused sessions

**Cons:**
❌ **Process Overhead:** ~2KB per GenServer process
❌ **Coordination Complexity:** Registry and supervision management
❌ **State Persistence:** Need explicit persistence strategy

### 11.2 Gateway API Pattern

**Pros:**
✅ **Clean Abstraction:** Hides OTP complexity from UIs
✅ **Testing:** Easy to mock and test
✅ **Consistency:** Uniform API across all UI types
✅ **Future-Proof:** Easy to add new operations

**Cons:**
❌ **Indirection:** Additional layer of abstraction
❌ **Session Lookup:** Registry lookup on every call

### 11.3 Pub/Sub Event Architecture

**Pros:**
✅ **Real-Time:** Immediate updates to all connected UIs
✅ **Decoupling:** UIs don't need to poll for updates
✅ **Multi-UI:** Natural support for multiple interfaces
✅ **Event History:** Can record and replay events

**Cons:**
❌ **Complexity:** More complex than synchronous APIs
❌ **Race Conditions:** Requires careful subscription ordering
❌ **Event Schema:** Need to maintain backward compatibility

---

## 12. Implementation Checklist

### 12.1 Core Infrastructure
- [ ] Add Phoenix.PubSub to supervision tree
- [ ] Create Registry for session management
- [ ] Implement DynamicSupervisor for sessions
- [ ] Define event schema modules
- [ ] Create telemetry integration

### 12.2 Session Management
- [ ] Implement MCPChat.SessionManager
- [ ] Create MCPChat.Session GenServer
- [ ] Add session lifecycle management
- [ ] Implement state persistence strategy
- [ ] Add session monitoring and cleanup

### 12.3 Gateway API
- [ ] Implement MCPChat.Gateway module
- [ ] Add message handling functions
- [ ] Add command execution functions
- [ ] Add state query functions
- [ ] Add MCP operation functions

### 12.4 UI Refactoring
- [ ] Refactor CLI to use Gateway API
- [ ] Add PubSub subscription to CLI
- [ ] Implement permission handling
- [ ] Test CLI with new architecture

### 12.5 Web UI Implementation
- [ ] Add Phoenix endpoint to application
- [ ] Create session LiveView components
- [ ] Implement real-time chat interface
- [ ] Add permission handling modals
- [ ] Add administrative interface

### 12.6 Testing and Documentation
- [ ] Update unit tests for new architecture
- [ ] Add integration tests for pub/sub flows
- [ ] Test multi-UI scenarios
- [ ] Update documentation and README
- [ ] Performance testing with multiple sessions

---

## 13. Future Enhancements

### 13.1 Multi-User Support
- User authentication and sessions
- Shared session permissions
- Admin dashboard for session management

### 13.2 Persistence and Recovery
- Database integration for message history
- Session state snapshots
- Cross-restart session recovery

### 13.3 Advanced Features
- Session sharing between users
- Real-time collaboration
- Message search and indexing
- Analytics and usage tracking

### 13.4 Scaling and Distribution
- Multi-node clustering
- Database-backed session storage
- Load balancing strategies
- Horizontal scaling patterns

---

## Conclusion

This architecture provides a robust foundation for decoupling MCP Chat's UI from its core logic while maintaining the reliability and performance characteristics expected of an Elixir/OTP application. The per-session GenServer pattern, combined with Phoenix.PubSub for real-time updates and a clean Gateway API, creates a scalable system that can support multiple UI interfaces and future enhancements.

The migration strategy allows for incremental implementation with minimal risk, and the event-driven architecture provides excellent observability and debugging capabilities through the comprehensive telemetry integration already in place.
