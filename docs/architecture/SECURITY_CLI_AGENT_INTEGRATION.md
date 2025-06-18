# Security Model Integration with CLI Agent Architecture

This document describes how to integrate the MCP Chat security model (capability-based access control) with the CLI agent architecture for secure, real-time agent operations.

## Table of Contents

1. [Overview](#overview)
2. [Architecture Integration Points](#architecture-integration-points)
3. [Security-Aware Agent Bridge](#security-aware-agent-bridge)
4. [Secure Agent Command Execution](#secure-agent-command-execution)
5. [Agent Capability Management](#agent-capability-management)
6. [Real-time Security Events](#real-time-security-events)
7. [Implementation Guidelines](#implementation-guidelines)
8. [Migration Strategy](#migration-strategy)

## Overview

The integration combines:
- **Security Model**: Capability-based access control with JWT tokens
- **Agent Architecture**: Per-session agents with real-time progress updates
- **CLI Bridge**: Event-driven interface for asynchronous operations

Key benefits:
- Agents operate within security boundaries
- Real-time security monitoring via PubSub
- Token-based validation for distributed performance
- Capability delegation for sub-agents

## Architecture Integration Points

### High-Level Integration

```
┌─────────────────────────────────────────────────────────────────┐
│                        CLI Layer                                │
│  ┌─────────────────┐              ┌─────────────────────────┐   │
│  │   CLI Client    │              │    Event Subscriber     │   │
│  │                 │              │  (Security Events)      │   │
│  └─────────────────┘              └─────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
           │                                    │
           │ (Secure Commands)                  │ (Security Events)
           ▼                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Security-Aware Agent Bridge                     │
│  ┌─────────────────┐              ┌─────────────────────────┐   │
│  │ AgentBridge     │              │ AgentCommandBridge      │   │
│  │ + Capabilities  │              │ + Security Validation   │   │
│  └─────────────────┘              └─────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
           │                                    │
           │ (Capability Checks)                │ (Secure Routing)
           ▼                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Secure Agent Layer                           │
│  ┌─────────────────┐  ┌─────────────────┐  ┌───────────────────┐│
│  │ Security Kernel │  │ Secure Agents   │  │ Violation Monitor││
│  │                 │  │ (w/ Capabilities)│  │                  ││
│  └─────────────────┘  └─────────────────┘  └───────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

## Security-Aware Agent Bridge

### Enhanced Agent Bridge with Security

```elixir
defmodule MCPChat.CLI.SecureAgentBridge do
  @moduledoc """
  Enhanced agent bridge with integrated security capabilities.
  """
  
  alias MCPChat.CLI.AgentBridge
  alias MCPChat.Security
  alias MCPChat.Security.MCPSecurityAdapter
  
  # Session registry with security context
  @session_registry :secure_cli_agent_registry
  
  defstruct [
    :cli_session_id,
    :agent_session_id,
    :principal_id,
    :capabilities,
    :security_context
  ]
  
  @doc """
  Create a secure agent session with capability management.
  """
  def ensure_secure_session(opts \\ []) do
    cli_session_id = get_cli_session_id()
    principal_id = get_or_create_principal_id(cli_session_id)
    
    # Request base capabilities for CLI agent
    with {:ok, capabilities} <- request_cli_capabilities(principal_id, opts),
         {:ok, agent_session_id} <- AgentBridge.ensure_agent_session(opts) do
      
      # Store secure session mapping
      secure_session = %__MODULE__{
        cli_session_id: cli_session_id,
        agent_session_id: agent_session_id,
        principal_id: principal_id,
        capabilities: capabilities,
        security_context: build_security_context(capabilities)
      }
      
      :ets.insert(@session_registry, {cli_session_id, secure_session})
      
      # Subscribe to security events
      subscribe_to_security_events(agent_session_id)
      
      {:ok, agent_session_id, capabilities}
    end
  end
  
  @doc """
  Execute a tool with security validation.
  """
  def execute_tool_secure(tool_name, args, opts \\ []) do
    with {:ok, session} <- get_secure_session(),
         :ok <- validate_tool_permission(session, tool_name, args),
         {:ok, :async, result} <- AgentBridge.execute_tool_async(tool_name, args, opts) do
      
      # Log security-aware execution
      audit_tool_execution(session, tool_name, args, result)
      
      {:ok, :async, result}
    else
      {:error, :security_violation} = error ->
        record_violation(tool_name, args)
        error
        
      other ->
        other
    end
  end
  
  @doc """
  Send a message with content security checks.
  """
  def send_message_secure(content, opts \\ []) do
    with {:ok, session} <- get_secure_session(),
         :ok <- validate_message_content(session, content),
         result <- AgentBridge.send_message_async(content, opts) do
      result
    end
  end
  
  @doc """
  Delegate capabilities to a sub-agent.
  """
  def spawn_secure_subagent(task_spec, constraints \\ %{}) do
    with {:ok, session} <- get_secure_session(),
         {:ok, delegated_caps} <- delegate_capabilities(session, task_spec, constraints) do
      
      # Create sub-agent with delegated capabilities
      sub_agent_opts = [
        parent_session: session.agent_session_id,
        capabilities: delegated_caps,
        principal_id: "subagent_#{task_spec.id}"
      ]
      
      AgentBridge.spawn_subagent(task_spec, sub_agent_opts)
    end
  end
  
  # Private functions
  
  defp request_cli_capabilities(principal_id, opts) do
    # Request capabilities based on CLI mode and user permissions
    capabilities = []
    
    # Basic CLI operations
    {:ok, cli_cap} = Security.request_capability(
      :cli_operations,
      %{
        operations: [:read, :write, :execute],
        commands: ["*"],  # Will be filtered by command bridge
        rate_limit: 1000  # Operations per hour
      },
      principal_id
    )
    capabilities = [cli_cap | capabilities]
    
    # File system access (if needed)
    if Keyword.get(opts, :enable_filesystem, true) do
      {:ok, fs_cap} = Security.request_capability(
        :filesystem,
        %{
          operations: [:read, :write],
          paths: [System.user_home(), "/tmp"],
          allowed_extensions: [".txt", ".md", ".json", ".ex", ".exs"]
        },
        principal_id
      )
      capabilities = [fs_cap | capabilities]
    end
    
    # MCP tool access
    if Keyword.get(opts, :enable_mcp_tools, true) do
      {:ok, mcp_cap} = Security.request_capability(
        :mcp_tool,
        %{
          operations: [:execute],
          allowed_tools: get_allowed_mcp_tools(opts),
          rate_limit: 100
        },
        principal_id
      )
      capabilities = [mcp_cap | capabilities]
    end
    
    {:ok, capabilities}
  end
  
  defp validate_tool_permission(session, tool_name, args) do
    # Find the appropriate capability
    mcp_cap = Enum.find(session.capabilities, fn cap ->
      cap.resource_type == :mcp_tool
    end)
    
    if mcp_cap do
      MCPSecurityAdapter.validate_tool_permission(mcp_cap, tool_name, args)
    else
      {:error, :no_mcp_capability}
    end
  end
  
  defp validate_message_content(session, content) do
    # Implement content security policies
    cond do
      String.length(content) > 10_000 ->
        {:error, :message_too_large}
        
      contains_sensitive_data?(content) ->
        {:error, :sensitive_data_detected}
        
      true ->
        :ok
    end
  end
  
  defp delegate_capabilities(session, task_spec, constraints) do
    # Delegate each parent capability with additional constraints
    delegated = Enum.map(session.capabilities, fn cap ->
      task_constraints = Map.merge(
        %{
          max_delegation_depth: 1,
          expires_in: :timer.hours(1)
        },
        constraints
      )
      
      {:ok, delegated} = Security.delegate_capability(
        cap,
        "subagent_#{task_spec.id}",
        task_constraints
      )
      
      delegated
    end)
    
    {:ok, delegated}
  end
  
  defp subscribe_to_security_events(session_id) do
    # Subscribe to security-specific events
    Phoenix.PubSub.subscribe(MCPChat.PubSub, "security:violations")
    Phoenix.PubSub.subscribe(MCPChat.PubSub, "security:alerts")
    Phoenix.PubSub.subscribe(MCPChat.PubSub, "session:#{session_id}:security")
  end
  
  defp audit_tool_execution(session, tool_name, args, result) do
    Security.AuditLogger.log(:tool_execution, %{
      principal_id: session.principal_id,
      session_id: session.agent_session_id,
      tool_name: tool_name,
      args: sanitize_args(args),
      result_id: result[:execution_id],
      timestamp: DateTime.utc_now()
    })
  end
  
  defp record_violation(tool_name, args) do
    Security.ViolationMonitor.record_violation(:unauthorized_tool_execution, %{
      tool_name: tool_name,
      args: sanitize_args(args),
      principal_id: get_current_principal_id(),
      timestamp: DateTime.utc_now()
    })
  end
  
  defp sanitize_args(args) do
    # Remove sensitive information from args before logging
    args
    |> Enum.map(fn {k, v} ->
      if k in [:password, :token, :secret] do
        {k, "[REDACTED]"}
      else
        {k, v}
      end
    end)
    |> Enum.into(%{})
  end
end
```

## Secure Agent Command Execution

### Enhanced Command Bridge with Security

```elixir
defmodule MCPChat.CLI.SecureAgentCommandBridge do
  @moduledoc """
  Security-enhanced command routing for agent operations.
  """
  
  alias MCPChat.CLI.AgentCommandBridge
  alias MCPChat.Security
  alias MCPChat.CLI.SecureAgentBridge
  
  # Command security policies
  @command_policies %{
    # High-risk commands requiring additional validation
    "export" => %{risk_level: :high, requires_audit: true},
    "mcp" => %{risk_level: :medium, rate_limited: true},
    "backend" => %{risk_level: :medium, requires_confirmation: true},
    
    # Low-risk commands
    "help" => %{risk_level: :low},
    "context" => %{risk_level: :low},
    "history" => %{risk_level: :low}
  }
  
  @doc """
  Route command with security validation.
  """
  def route_secure_command(command, args, session_id \\ "default") do
    with {:ok, session} <- SecureAgentBridge.get_secure_session(),
         :ok <- validate_command_permission(session, command, args),
         {:ok, routing} <- AgentCommandBridge.route_command(command, args) do
      
      case routing do
        {:local, cmd, args} ->
          # Local commands still need security context
          execute_local_with_security(cmd, args, session)
          
        {:agent, agent_type, cmd, args} ->
          # Agent commands with capability validation
          execute_agent_with_security(agent_type, cmd, args, session)
          
        {:unknown, cmd, _args} ->
          # Log unknown command attempts
          Security.AuditLogger.log(:unknown_command, %{
            command: cmd,
            principal_id: session.principal_id
          })
          {:error, :unknown_command}
      end
    end
  end
  
  @doc """
  Execute agent command with security context.
  """
  def execute_secure_agent_command(agent_type, command, args, session) do
    # Prepare security context for agent
    task_spec = %{
      command: command,
      args: args,
      session_id: session.agent_session_id,
      agent_type: agent_type,
      security_context: %{
        principal_id: session.principal_id,
        capabilities: filter_capabilities_for_agent(session.capabilities, agent_type),
        audit_required: command_requires_audit?(command)
      }
    }
    
    # Execute through agent pool with security
    case AgentPool.request_tool_execution(session.agent_session_id, task_spec) do
      {:ok, agent_pid} ->
        # Monitor execution for security events
        monitor_agent_execution(agent_pid, task_spec)
        {:ok, agent_pid}
        
      {:error, reason} = error ->
        Security.AuditLogger.log(:agent_execution_failed, %{
          reason: reason,
          task_spec: sanitize_task_spec(task_spec)
        })
        error
    end
  end
  
  # Private functions
  
  defp validate_command_permission(session, command, args) do
    policy = Map.get(@command_policies, command, %{risk_level: :medium})
    
    # Check CLI operation capability
    cli_cap = Enum.find(session.capabilities, fn cap ->
      cap.resource_type == :cli_operations
    end)
    
    cond do
      # No CLI capability
      is_nil(cli_cap) ->
        {:error, :no_cli_capability}
        
      # High-risk command validation
      policy[:risk_level] == :high ->
        validate_high_risk_command(session, command, args)
        
      # Rate limiting check
      policy[:rate_limited] ->
        check_rate_limit(session.principal_id, command)
        
      # Default validation
      true ->
        Security.validate_capability(cli_cap, :execute, command)
    end
  end
  
  defp validate_high_risk_command(session, command, args) do
    # Additional validation for high-risk commands
    with :ok <- Security.validate_capability(
                  find_capability(session, :cli_operations),
                  :execute,
                  command
                ),
         :ok <- check_command_constraints(command, args),
         :ok <- maybe_require_confirmation(session, command, args) do
      :ok
    end
  end
  
  defp check_rate_limit(principal_id, command) do
    key = "#{principal_id}:#{command}"
    limit = get_rate_limit_for_command(command)
    
    case Hammer.check_rate(key, :timer.minutes(60), limit) do
      {:allow, _count} -> :ok
      {:deny, _limit} -> {:error, :rate_limit_exceeded}
    end
  end
  
  defp monitor_agent_execution(agent_pid, task_spec) do
    # Set up monitoring for security events during execution
    Task.start(fn ->
      ref = Process.monitor(agent_pid)
      
      receive do
        {:DOWN, ^ref, :process, ^agent_pid, reason} ->
          if reason != :normal do
            Security.ViolationMonitor.record_violation(:agent_crash, %{
              task_spec: sanitize_task_spec(task_spec),
              reason: inspect(reason)
            })
          end
      after
        :timer.minutes(5) ->
          # Timeout monitoring after 5 minutes
          Process.demonitor(ref, [:flush])
      end
    end)
  end
  
  defp filter_capabilities_for_agent(capabilities, agent_type) do
    # Filter capabilities relevant to specific agent type
    case agent_type do
      :llm_agent ->
        Enum.filter(capabilities, fn cap ->
          cap.resource_type in [:llm_operations, :model_management]
        end)
        
      :mcp_agent ->
        Enum.filter(capabilities, fn cap ->
          cap.resource_type in [:mcp_tool, :mcp_server]
        end)
        
      :export_agent ->
        Enum.filter(capabilities, fn cap ->
          cap.resource_type in [:filesystem, :export_operations]
        end)
        
      _ ->
        capabilities
    end
  end
  
  defp command_requires_audit?(command) do
    policy = Map.get(@command_policies, command, %{})
    Map.get(policy, :requires_audit, false)
  end
end
```

## Agent Capability Management

### Secure Agent Initialization

```elixir
defmodule MCPChat.Agents.SecureAgent do
  @moduledoc """
  Base behaviour for security-aware agents.
  """
  
  defmacro __using__(opts) do
    quote do
      use MCPChat.Agents.BaseAgent
      alias MCPChat.Security
      
      @agent_type unquote(opts[:type]) || :generic_agent
      
      def init(args) do
        # Set up security context
        principal_id = args[:principal_id] || generate_principal_id()
        Security.set_current_principal(principal_id)
        
        # Initialize with parent capabilities if provided
        capabilities = case args[:capabilities] do
          nil -> request_agent_capabilities(principal_id)
          caps -> validate_and_store_capabilities(caps)
        end
        
        # Subscribe to security events
        subscribe_to_security_events()
        
        # Initialize base agent
        {:ok, base_state} = super(args)
        
        # Merge security into state
        {:ok, Map.merge(base_state, %{
          principal_id: principal_id,
          capabilities: capabilities,
          security_context: build_security_context(capabilities)
        })}
      end
      
      # Override handle_task to add security validation
      def handle_task(task, state) do
        with :ok <- validate_task_security(task, state) do
          super(task, state)
        else
          {:error, :security_violation} = error ->
            report_security_violation(task, state)
            {:error, error}
        end
      end
      
      defp validate_task_security(task, state) do
        # Validate task against agent's capabilities
        required_capability = determine_required_capability(task)
        
        case find_matching_capability(state.capabilities, required_capability) do
          nil ->
            {:error, :no_matching_capability}
            
          capability ->
            Security.validate_capability(
              capability,
              task.operation || :execute,
              task.resource || task.command
            )
        end
      end
      
      defp request_agent_capabilities(principal_id) do
        # Override in specific agents
        []
      end
      
      defp subscribe_to_security_events do
        Phoenix.PubSub.subscribe(MCPChat.PubSub, "security:policy_updates")
        Phoenix.PubSub.subscribe(MCPChat.PubSub, "security:capability_revoked")
      end
      
      # Handle security events
      def handle_info({:capability_revoked, cap_id}, state) do
        # Remove revoked capability
        new_caps = Enum.reject(state.capabilities, fn cap ->
          cap.id == cap_id
        end)
        
        {:noreply, %{state | capabilities: new_caps}}
      end
      
      def handle_info({:security_policy_updated, policy}, state) do
        # Revalidate capabilities against new policy
        new_caps = revalidate_capabilities(state.capabilities, policy)
        {:noreply, %{state | capabilities: new_caps}}
      end
      
      # Allow agents to override these
      defoverridable [
        request_agent_capabilities: 1,
        validate_task_security: 2
      ]
    end
  end
end
```

### Example: Secure MCP Agent

```elixir
defmodule MCPChat.Agents.SecureMCPAgent do
  use MCPChat.Agents.SecureAgent, type: :mcp_agent
  
  @impl true
  def request_agent_capabilities(principal_id) do
    capabilities = []
    
    # MCP server management
    {:ok, server_cap} = Security.request_capability(
      :mcp_server,
      %{
        operations: [:connect, :disconnect, :list],
        allowed_servers: ["*"],  # Can be restricted
        max_connections: 10
      },
      principal_id
    )
    capabilities = [server_cap | capabilities]
    
    # MCP tool execution
    {:ok, tool_cap} = Security.request_capability(
      :mcp_tool,
      %{
        operations: [:execute, :list],
        allowed_tools: get_allowed_tools_from_config(),
        rate_limit: 100,
        timeout: :timer.minutes(5)
      },
      principal_id
    )
    capabilities = [tool_cap | capabilities]
    
    capabilities
  end
  
  @impl true
  def validate_task_security(%{command: "tool", args: args} = task, state) do
    tool_name = args[:tool]
    server = args[:server]
    
    # Find MCP tool capability
    tool_cap = Enum.find(state.capabilities, fn cap ->
      cap.resource_type == :mcp_tool
    end)
    
    with {:ok, _} <- Security.validate_capability(tool_cap, :execute, tool_name),
         :ok <- validate_server_permission(state, server),
         :ok <- check_tool_rate_limit(state.principal_id, tool_name) do
      :ok
    end
  end
  
  def validate_task_security(task, state) do
    # Delegate to parent for other tasks
    super(task, state)
  end
  
  defp validate_server_permission(state, server) do
    server_cap = Enum.find(state.capabilities, fn cap ->
      cap.resource_type == :mcp_server
    end)
    
    Security.validate_capability(server_cap, :connect, server)
  end
end
```

## Real-time Security Events

### Security Event Integration

```elixir
defmodule MCPChat.CLI.SecurityEventSubscriber do
  @moduledoc """
  Subscribes to security events and displays them in the CLI.
  """
  
  use GenServer
  require Logger
  alias MCPChat.CLI.Renderer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Subscribe to security events
    Phoenix.PubSub.subscribe(MCPChat.PubSub, "security:violations")
    Phoenix.PubSub.subscribe(MCPChat.PubSub, "security:alerts")
    Phoenix.PubSub.subscribe(MCPChat.PubSub, "security:audit")
    
    {:ok, %{ui_mode: :cli}}
  end
  
  # Handle security violations
  def handle_info({:security_violation, violation}, state) do
    case violation.severity do
      :critical ->
        Renderer.render_error("🚨 CRITICAL SECURITY VIOLATION: #{violation.message}")
        maybe_terminate_session(violation)
        
      :high ->
        Renderer.render_warning("⚠️  Security Warning: #{violation.message}")
        
      _ ->
        if Application.get_env(:mcp_chat, :debug_security, false) do
          Renderer.render_info("🔒 Security Notice: #{violation.message}")
        end
    end
    
    {:noreply, state}
  end
  
  # Handle security alerts
  def handle_info({:security_alert, alert}, state) do
    Renderer.render_warning("🔔 Security Alert: #{alert.type}")
    Renderer.render_info("   #{alert.message}")
    
    if alert[:action_required] do
      prompt_security_action(alert)
    end
    
    {:noreply, state}
  end
  
  # Handle audit events (debug mode only)
  def handle_info({:audit_event, event}, state) do
    if Application.get_env(:mcp_chat, :security_audit_display, false) do
      Renderer.render_debug("📝 Audit: #{event.action} by #{event.principal_id}")
    end
    
    {:noreply, state}
  end
  
  defp maybe_terminate_session(violation) do
    if violation[:terminate_session] do
      Renderer.render_error("Session terminated due to security violation.")
      # Signal CLI to exit
      Process.send(MCPChat.CLI, :security_termination, [])
    end
  end
  
  defp prompt_security_action(alert) do
    Task.start(fn ->
      response = Renderer.prompt_user(
        "Security action required: #{alert.prompt}",
        alert.options || ["allow", "deny"]
      )
      
      # Send response back to security system
      Security.respond_to_alert(alert.id, response)
    end)
  end
end
```

### Progress Updates with Security Context

```elixir
defmodule MCPChat.CLI.SecureProgressRenderer do
  @moduledoc """
  Renders progress with security status indicators.
  """
  
  alias MCPChat.CLI.Renderer
  
  def render_secure_progress(event, security_context) do
    base_progress = build_progress_bar(event)
    security_indicator = build_security_indicator(security_context)
    
    IO.write("\r#{security_indicator} #{base_progress}")
  end
  
  defp build_security_indicator(context) do
    cond do
      context[:elevated_privileges] -> "🔓"
      context[:restricted_mode] -> "🔒"
      context[:audit_mode] -> "📝"
      true -> "🔐"
    end
  end
  
  def render_secure_completion(event, security_stats) do
    if security_stats[:violations] > 0 do
      Renderer.render_warning(
        "⚠️  Operation completed with #{security_stats.violations} security warnings"
      )
    else
      Renderer.render_success(
        "✅ Operation completed securely"
      )
    end
    
    if security_stats[:audit_logged] do
      Renderer.render_info("📝 Operation has been logged for audit")
    end
  end
end
```

## Implementation Guidelines

### 1. Security-First Design

```elixir
# Always request capabilities before operations
def handle_command(command, args) do
  with {:ok, cap} <- request_command_capability(command),
       :ok <- validate_args_against_capability(cap, args) do
    execute_command(command, args)
  else
    {:error, :no_capability} ->
      render_error("Insufficient permissions for #{command}")
    {:error, :invalid_args} ->
      render_error("Invalid arguments for security policy")
  end
end
```

### 2. Capability Lifecycle

```elixir
# Request → Use → Revoke pattern
def perform_sensitive_operation(args) do
  {:ok, cap} = Security.request_capability(:sensitive_op, constraints, principal)
  
  try do
    result = do_operation(args, cap)
    audit_success(cap, result)
    result
  rescue
    error ->
      audit_failure(cap, error)
      reraise error
  after
    Security.revoke_capability(cap)
  end
end
```

### 3. Event-Driven Security

```elixir
# Subscribe to relevant security events
def init_secure_cli do
  Phoenix.PubSub.subscribe(MCPChat.PubSub, "security:#{session_id}")
  Phoenix.PubSub.subscribe(MCPChat.PubSub, "security:global")
  
  # Set up security event handlers
  :ok
end
```

### 4. Audit Trail

```elixir
# Log all security-relevant operations
def execute_with_audit(operation, args) do
  start_time = System.monotonic_time()
  
  result = try do
    operation.(args)
  catch
    kind, reason ->
      Security.AuditLogger.log(:operation_failed, %{
        operation: inspect(operation),
        error: {kind, reason},
        duration: System.monotonic_time() - start_time
      })
      :erlang.raise(kind, reason, __STACKTRACE__)
  end
  
  Security.AuditLogger.log(:operation_success, %{
    operation: inspect(operation),
    duration: System.monotonic_time() - start_time
  })
  
  result
end
```

## Migration Strategy

### Phase 1: Add Security Layer

1. **Implement SecureAgentBridge**
   - Wrap existing AgentBridge with security
   - Add capability management
   - Maintain backward compatibility

2. **Add Security Event Subscriber**
   - Display security events in CLI
   - Handle security prompts
   - Log violations

### Phase 2: Secure Command Routing

1. **Implement SecureAgentCommandBridge**
   - Add command validation
   - Implement rate limiting
   - Add audit logging

2. **Update Agents**
   - Migrate to SecureAgent base
   - Add capability requests
   - Implement security validation

### Phase 3: Full Integration

1. **Enable Token Mode**
   - Switch to JWT-based validation
   - Test performance improvements
   - Monitor security events

2. **Advanced Features**
   - Implement capability delegation UI
   - Add security dashboard
   - Enable real-time monitoring

### Rollback Plan

Each phase can be rolled back independently:

```elixir
# Feature flags for gradual rollout
config :mcp_chat,
  security_cli_integration: %{
    secure_bridge: true,      # Phase 1
    secure_commands: false,   # Phase 2  
    token_mode: false,       # Phase 3
    audit_display: true      # Always on
  }
```

## Testing Strategy

### Security Integration Tests

```elixir
defmodule MCPChat.CLI.SecurityIntegrationTest do
  use ExUnit.Case
  
  setup do
    # Start security system
    start_supervised!(MCPChat.Security.Supervisor)
    
    # Start CLI with security
    {:ok, session_id} = MCPChat.CLI.SecureAgentBridge.ensure_secure_session()
    
    %{session_id: session_id}
  end
  
  test "command execution requires valid capability", %{session_id: session_id} do
    # Attempt command without capability
    assert {:error, :security_violation} = 
      SecureAgentCommandBridge.route_secure_command("mcp", ["tool", "exec"], session_id)
  end
  
  test "rate limiting prevents abuse", %{session_id: session_id} do
    # Execute command up to limit
    for _ <- 1..100 do
      assert {:ok, _} = execute_rate_limited_command(session_id)
    end
    
    # Next attempt should fail
    assert {:error, :rate_limit_exceeded} = execute_rate_limited_command(session_id)
  end
  
  test "security events are displayed in CLI", %{session_id: session_id} do
    # Trigger security violation
    trigger_violation(session_id)
    
    # Verify CLI displays warning
    assert_receive {:cli_output, output}
    assert output =~ "Security Warning"
  end
end
```

## Conclusion

This integration provides a comprehensive security layer for the CLI agent architecture, ensuring:

1. **Secure Operations**: All agent operations validated against capabilities
2. **Real-time Monitoring**: Security events displayed in CLI
3. **Audit Trail**: Complete logging of security-relevant actions
4. **Performance**: Token-based validation for distributed operations
5. **Flexibility**: Gradual migration path with feature flags

The architecture maintains the responsive, event-driven nature of the CLI while adding robust security controls suitable for production AI agent systems.