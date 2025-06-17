# Multi-Agent Architecture for MCP Chat

## Executive Summary

This document outlines a comprehensive multi-agent architecture for MCP Chat that leverages BEAM/OTP strengths while integrating seamlessly with the existing `ex_llm` and `ex_mcp` libraries. The design emphasizes security through capability delegation, fault tolerance through supervision, and scalability through distributed computing.

## Design Principles

### 1. **Security by Design**
- Hierarchical capability delegation (agents can only delegate to agents they spawn)
- Capability subset validation prevents privilege escalation
- Secure handshake protocol for manual agent control
- Process isolation provides security boundaries

### 2. **BEAM/OTP Integration**
- Native supervision trees for fault tolerance
- Actor model maps perfectly to agent concepts
- Hot code reloading preserves agent state
- Message passing for secure inter-agent communication

### 3. **Library Ecosystem Compatibility**
- Seamless integration with `ex_llm` (stateless with optional Session state)
- Integration with `ex_mcp` (GenServer-based client/server)
- Preserves existing MCP Chat adapter patterns
- Maintains backward compatibility

## Core Architecture

### Supervision Tree Structure

```elixir
MCPChat.Application
├── AgentSupervisor (supervisor)
│   ├── AgentRegistry (GenServer + ETS)
│   ├── CapabilityManager (GenServer) 
│   └── AgentPoolSupervisor (DynamicSupervisor)
│       ├── Agent_CLI_001 (GenServer) - Root agent
│       ├── Agent_002 (GenServer) - Spawned agent
│       │   └── Agent_003 (GenServer) - Child of 002
│       └── Agent_N (GenServer)
├── MCPServerManager (existing)
├── SessionManager (existing)  
└── ... (other existing components)
```

### Agent State Model

```elixir
defmodule MCPChat.Agent do
  use GenServer

  defstruct [
    # Identity
    id: nil,                    # "agent-007" (human-readable)
    parent_id: nil,             # "agent-001" or "cli-session-xyz"
    children: MapSet.new(),     # Set of child agent IDs
    
    # Configuration
    persona: "Default assistant",
    system_prompt: "",
    model_config: %{},          # Provider/model configuration
    
    # Capabilities & Security
    owned_capabilities: %{},     # Map of %{cap_name => cap_struct}
    delegated_capabilities: %{}, # Map of %{child_id => %{cap_name => cap_struct}}
    
    # State
    session_pid: nil,           # ExLLM.Session for conversation state
    mcp_clients: %{},           # Map of server_name => client_pid
    status: :idle,              # :idle | :busy | :controlled
    controller: nil,            # {cli_pid, nonce} for manual control
    
    # Metrics
    created_at: nil,
    last_active: nil,
    message_count: 0,
    total_cost: 0.0
  ]
end
```

## Capability System Design

### Capability Structure

```elixir
defmodule MCPChat.Capability do
  @enforce_keys [:name, :type, :params]
  defstruct [:name, :type, :params, :metadata]

  # Capability types
  def file_read(path_pattern), do: %__MODULE__{
    name: :file_read,
    type: :filesystem,
    params: %{path_pattern: path_pattern}
  }

  def agent_spawn(max_children), do: %__MODULE__{
    name: :agent_spawn, 
    type: :system,
    params: %{max_children: max_children}
  }

  def mcp_tool(server, tool_name), do: %__MODULE__{
    name: :mcp_tool,
    type: :mcp,
    params: %{server: server, tool: tool_name}
  }

  def llm_provider(provider, model), do: %__MODULE__{
    name: :llm_provider,
    type: :llm,
    params: %{provider: provider, model: model}
  }
end
```

### Capability Delegation Logic

```elixir
defmodule MCPChat.CapabilityManager do
  use GenServer

  def is_subset_capability?(child_cap, parent_cap) do
    case {child_cap.type, parent_cap.type} do
      {:filesystem, :filesystem} ->
        is_path_subset?(child_cap.params.path_pattern, parent_cap.params.path_pattern)
      
      {:system, :system} ->
        child_cap.params.max_children <= parent_cap.params.max_children
      
      {:mcp, :mcp} ->
        child_cap.params.server == parent_cap.params.server and
        child_cap.params.tool == parent_cap.params.tool
      
      {:llm, :llm} ->
        child_cap.params.provider == parent_cap.params.provider and
        is_model_subset?(child_cap.params.model, parent_cap.params.model)
      
      _ -> false
    end
  end

  defp is_path_subset?(child_pattern, parent_pattern) do
    # Implementation for path subset validation
    # e.g., "/home/user/data/*" is subset of "/home/user/*"
    String.starts_with?(child_pattern, String.trim_trailing(parent_pattern, "*"))
  end
end
```

## Agent Communication Protocol

### Message Format

```elixir
defmodule MCPChat.Agent.Message do
  defstruct [
    :type,      # :chat | :tool_request | :delegation | :control
    :from,      # agent_id
    :to,        # agent_id or :broadcast
    :payload,   # Message content
    :reply_to,  # Optional correlation ID
    :timestamp
  ]
end

# Example messages
%Message{
  type: :chat,
  from: "agent-001", 
  to: "agent-002",
  payload: %{content: "Please analyze this code", context: %{file: "main.ex"}},
  timestamp: DateTime.utc_now()
}

%Message{
  type: :tool_request,
  from: "agent-002",
  to: "agent-001", 
  payload: %{tool: "file_read", params: %{path: "/code/main.ex"}},
  reply_to: "req-123"
}
```

### Inter-Agent Communication

```elixir
defmodule MCPChat.Agent do
  # Send message to another agent
  def send_message(agent_id, message) do
    case AgentRegistry.lookup(agent_id) do
      {:ok, pid} -> GenServer.cast(pid, {:message, message})
      {:error, :not_found} -> {:error, :agent_not_found}
    end
  end

  # Handle incoming messages
  def handle_cast({:message, %Message{type: :chat} = msg}, state) do
    # Process chat message with LLM
    response = process_with_llm(msg.payload.content, state)
    reply = %Message{
      type: :chat,
      from: state.id,
      to: msg.from,
      payload: %{content: response},
      reply_to: msg.reply_to
    }
    send_message(msg.from, reply)
    {:noreply, update_activity(state)}
  end

  def handle_cast({:message, %Message{type: :tool_request} = msg}, state) do
    # Validate and execute tool request
    case validate_capability(msg.payload.tool, state) do
      :ok -> 
        result = execute_tool(msg.payload.tool, msg.payload.params, state)
        reply = %Message{type: :tool_response, payload: result, reply_to: msg.reply_to}
        send_message(msg.from, reply)
      {:error, reason} ->
        error_reply = %Message{type: :error, payload: reason, reply_to: msg.reply_to}
        send_message(msg.from, error_reply)
    end
    {:noreply, state}
  end
end
```

## Integration with Existing Libraries

### ExLLM Integration

```elixir
defmodule MCPChat.Agent.LLMIntegration do
  def process_with_llm(content, agent_state) do
    # Use agent's model configuration
    provider = agent_state.model_config.provider
    model = agent_state.model_config.model
    
    # Build messages with persona/system prompt
    messages = [
      %{role: "system", content: agent_state.system_prompt},
      %{role: "user", content: content}
    ]
    
    # Add conversation history from session
    full_messages = if agent_state.session_pid do
      ExLLM.Session.get_messages(agent_state.session_pid) ++ messages
    else
      messages
    end
    
    # Make LLM call
    case ExLLM.chat(provider, full_messages, model: model) do
      {:ok, response} ->
        # Update session if exists
        if agent_state.session_pid do
          ExLLM.Session.add_message(agent_state.session_pid, 
            %{role: "assistant", content: response.content})
        end
        response.content
      
      {:error, reason} ->
        "I encountered an error: #{inspect(reason)}"
    end
  end
end
```

### ExMCP Integration

```elixir
defmodule MCPChat.Agent.MCPIntegration do
  def execute_mcp_tool(server_name, tool_name, params, agent_state) do
    case Map.get(agent_state.mcp_clients, server_name) do
      nil ->
        # Try to connect to server if not already connected
        case connect_to_server(server_name) do
          {:ok, client_pid} ->
            execute_tool_with_client(client_pid, tool_name, params)
          error -> error
        end
      
      client_pid ->
        execute_tool_with_client(client_pid, tool_name, params)
    end
  end

  defp execute_tool_with_client(client_pid, tool_name, params) do
    case ExMCP.Client.call_tool(client_pid, tool_name, params) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

## Security Model

### Hierarchical Capability Delegation

```elixir
defmodule MCPChat.Agent.Security do
  # Validate that agent can spawn child with given capabilities
  def validate_spawn_request(parent_agent, requested_capabilities) do
    # Check if parent has spawn capability
    spawn_cap = Map.get(parent_agent.owned_capabilities, :agent_spawn)
    
    case spawn_cap do
      nil -> {:error, :no_spawn_capability}
      cap ->
        current_children = MapSet.size(parent_agent.children)
        if current_children >= cap.params.max_children do
          {:error, :spawn_limit_exceeded}
        else
          validate_capability_delegation(parent_agent, requested_capabilities)
        end
    end
  end

  defp validate_capability_delegation(parent_agent, requested_capabilities) do
    # Ensure each requested capability is a subset of parent's capabilities
    Enum.reduce_while(requested_capabilities, :ok, fn req_cap, acc ->
      case Map.get(parent_agent.owned_capabilities, req_cap.name) do
        nil -> {:halt, {:error, {:capability_not_owned, req_cap.name}}}
        parent_cap ->
          if MCPChat.CapabilityManager.is_subset_capability?(req_cap, parent_cap) do
            {:cont, acc}
          else
            {:halt, {:error, {:capability_not_subset, req_cap.name}}}
          end
      end
    end)
  end
end
```

### Secure Manual Control

```elixir
defmodule MCPChat.Agent.Control do
  # Request control of an agent (called by CLI)
  def request_control(agent_id, cli_pid) do
    case AgentRegistry.lookup(agent_id) do
      {:ok, agent_pid} ->
        nonce = :crypto.strong_rand_bytes(32)
        GenServer.call(agent_pid, {:grant_control, cli_pid, nonce})
        {:ok, nonce}
      error -> error
    end
  end

  # Agent grants control with time-limited nonce
  def handle_call({:grant_control, cli_pid, nonce}, _from, state) do
    # Store control session with TTL
    control_session = {cli_pid, nonce, System.monotonic_time() + 30_000} # 30 second TTL
    new_state = %{state | status: :controlled, controller: control_session}
    {:reply, :ok, new_state}
  end

  # Validate control message from CLI
  def handle_call({:control_message, content, nonce}, {from_pid, _}, state) do
    case state.controller do
      {^from_pid, ^nonce, expires_at} when expires_at > System.monotonic_time() ->
        # Valid control session - process message
        response = process_controlled_message(content, state)
        {:reply, {:ok, response}, state}
      
      _ ->
        {:reply, {:error, :unauthorized}, state}
    end
  end
end
```

## Distributed Architecture with Horde

### Horde Integration

```elixir
defmodule MCPChat.DistributedAgentRegistry do
  use Horde.Registry

  def start_link(_) do
    Horde.Registry.start_link(__MODULE__, [keys: :unique], name: __MODULE__)
  end

  def init(init_arg) do
    [members: members()]
    |> Keyword.merge(init_arg)
    |> Horde.Registry.init()
  end

  def lookup(agent_id) do
    case Horde.Registry.lookup(__MODULE__, agent_id) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  def register(agent_id, pid) do
    Horde.Registry.register(__MODULE__, agent_id, nil)
  end

  defp members() do
    # Get cluster members dynamically
    [Node.self() | Node.list()]
  end
end

defmodule MCPChat.DistributedAgentSupervisor do
  use Horde.DynamicSupervisor

  def start_link(_) do
    Horde.DynamicSupervisor.start_link(__MODULE__, [strategy: :one_for_one], 
                                      name: __MODULE__)
  end

  def init(init_arg) do
    [members: members()]
    |> Keyword.merge(init_arg)
    |> Horde.DynamicSupervisor.init()
  end

  def spawn_agent(parent_id, persona, capabilities) do
    agent_id = generate_agent_id()
    child_spec = {MCPChat.Agent, [
      id: agent_id,
      parent_id: parent_id,
      persona: persona,
      capabilities: capabilities
    ]}
    
    case Horde.DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        MCPChat.DistributedAgentRegistry.register(agent_id, pid)
        {:ok, agent_id, pid}
      error -> error
    end
  end

  defp members() do
    [Node.self() | Node.list()]
  end
end
```

## CLI Integration

### Agent Management Commands

```elixir
defmodule MCPChat.CLI.Commands.Agent do
  def handle_command(["spawn", persona | capabilities_args], _session) do
    capabilities = parse_capabilities(capabilities_args)
    
    case MCPChat.AgentManager.spawn_agent("cli-session", persona, capabilities) do
      {:ok, agent_id} ->
        "✅ Spawned agent #{agent_id} with persona: #{persona}"
      {:error, reason} ->
        "❌ Failed to spawn agent: #{inspect(reason)}"
    end
  end

  def handle_command(["list"], _session) do
    agents = MCPChat.AgentManager.list_agents()
    render_agent_list(agents)
  end

  def handle_command(["connect", agent_id], session) do
    case MCPChat.Agent.Control.request_control(agent_id, self()) do
      {:ok, nonce} ->
        # Switch CLI to agent control mode
        new_session = %{session | 
          mode: :agent_control, 
          controlled_agent: agent_id,
          control_nonce: nonce
        }
        {"🔄 Connected to #{agent_id}. Type /disconnect to return to main CLI.", new_session}
      
      {:error, reason} ->
        {"❌ Failed to connect: #{inspect(reason)}", session}
    end
  end

  def handle_command(["delegate", agent_id | capability_args], _session) do
    capabilities = parse_capabilities(capability_args)
    
    case MCPChat.AgentManager.delegate_capabilities(agent_id, capabilities) do
      {:ok, _} -> "✅ Delegated capabilities to #{agent_id}"
      {:error, reason} -> "❌ Failed to delegate: #{inspect(reason)}"
    end
  end

  defp parse_capabilities(args) do
    # Parse capability strings like "file_read:/tmp/*" or "mcp_tool:filesystem:read_file"
    Enum.map(args, &parse_single_capability/1)
  end
end
```

## Threat Mitigation

### 1. Privilege Escalation Prevention

```elixir
defmodule MCPChat.Security.PrivilegeEscalation do
  # Prevent capability chain attacks
  def validate_delegation_chain(agent_id, target_capability) do
    case build_capability_chain(agent_id) do
      {:ok, chain} ->
        validate_chain_integrity(chain, target_capability)
      error -> error
    end
  end

  defp build_capability_chain(agent_id, chain \\ []) do
    case MCPChat.AgentRegistry.get_agent_info(agent_id) do
      {:ok, agent} ->
        new_chain = [agent | chain]
        if agent.parent_id do
          build_capability_chain(agent.parent_id, new_chain)
        else
          {:ok, new_chain}
        end
      error -> error
    end
  end
end
```

### 2. Resource Exhaustion Protection

```elixir
defmodule MCPChat.Security.ResourceLimits do
  @max_total_agents 100
  @max_depth 10
  @max_message_rate 10 # messages per second

  def enforce_global_limits() do
    total_agents = MCPChat.AgentRegistry.count_agents()
    if total_agents >= @max_total_agents do
      {:error, :global_agent_limit_exceeded}
    else
      :ok
    end
  end

  def validate_agent_depth(parent_id) do
    case calculate_depth(parent_id) do
      depth when depth >= @max_depth -> {:error, :max_depth_exceeded}
      _ -> :ok
    end
  end

  def check_message_rate(agent_id) do
    # Rate limiting implementation
    case :ets.lookup(:agent_rate_limits, agent_id) do
      [{^agent_id, count, window_start}] ->
        now = System.monotonic_time(:second)
        if now - window_start < 1 and count >= @max_message_rate do
          {:error, :rate_limit_exceeded}
        else
          update_rate_limit(agent_id, now)
          :ok
        end
      [] ->
        :ets.insert(:agent_rate_limits, {agent_id, 1, System.monotonic_time(:second)})
        :ok
    end
  end
end
```

## Performance Considerations

### 1. Message Routing Optimization

```elixir
defmodule MCPChat.Performance.MessageRouting do
  # Use ETS for fast agent lookups
  def setup_fast_routing() do
    :ets.new(:agent_pids, [:public, :named_table, {:read_concurrency, true}])
  end

  def fast_lookup(agent_id) do
    case :ets.lookup(:agent_pids, agent_id) do
      [{^agent_id, pid}] when is_pid(pid) -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end
end
```

### 2. Batched Operations

```elixir
defmodule MCPChat.Performance.BatchOperations do
  # Batch capability validations
  def validate_capabilities_batch(capabilities) do
    # Process validations in parallel using Task.async_stream
    capabilities
    |> Task.async_stream(&validate_single_capability/1, max_concurrency: 4)
    |> Enum.to_list()
  end
end
```

## Monitoring and Observability

### Telemetry Integration

```elixir
defmodule MCPChat.Telemetry.AgentMetrics do
  def setup_telemetry() do
    :telemetry.attach_many(
      "mcp-chat-agent-metrics",
      [
        [:mcp_chat, :agent, :spawn],
        [:mcp_chat, :agent, :message],
        [:mcp_chat, :agent, :capability_check],
        [:mcp_chat, :agent, :tool_execution]
      ],
      &handle_telemetry_event/4,
      nil
    )
  end

  def handle_telemetry_event([:mcp_chat, :agent, :spawn], measurements, metadata, _config) do
    # Track agent creation metrics
    :telemetry.execute([:system, :agent_count], %{count: 1})
  end
end
```

## Migration Strategy

### Phase 1: Core Infrastructure (1-2 months)
1. Implement basic Agent GenServer with capabilities
2. Create AgentRegistry and CapabilityManager
3. Basic spawn/delegate functionality
4. Integration with existing ex_llm sessions

### Phase 2: Communication & Control (1 month)
1. Inter-agent message protocol
2. Secure manual control system
3. CLI agent management commands
4. Basic capability validation

### Phase 3: Advanced Features (2-3 months)
1. Horde integration for distributed agents
2. Advanced security policies
3. Performance optimizations
4. Comprehensive telemetry

### Phase 4: Production Hardening (1 month)
1. Extensive testing and security audits
2. Documentation and examples
3. Migration tools and guides
4. Performance benchmarking

## Conclusion

This multi-agent architecture leverages BEAM/OTP's unique strengths while maintaining compatibility with MCP Chat's existing libraries and patterns. The hierarchical capability model provides strong security guarantees, while the supervision tree ensures fault tolerance. The design scales from single-node deployments to distributed clusters using Horde.

Key advantages:
- **Security**: Hierarchical capability delegation prevents privilege escalation
- **Reliability**: OTP supervision provides fault isolation and recovery
- **Performance**: ETS-based lookups and parallel processing optimize throughput
- **Scalability**: Horde enables transparent distributed operation
- **Maintainability**: Clean separation of concerns and modular design

The architecture positions MCP Chat as a platform for sophisticated multi-agent workflows while maintaining the simplicity and reliability that make it unique in the AI coding assistant landscape.