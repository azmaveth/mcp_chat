defmodule MCPChat.CLI.SecureAgentCommandBridge do
  @moduledoc """
  Security-enhanced command routing for agent operations.

  This module provides command-level security validation, rate limiting,
  and audit logging for CLI agent commands, ensuring all operations comply
  with capability-based access control policies.
  """

  require Logger

  alias MCPChat.CLI.AgentCommandBridge
  alias MCPChat.Security
  alias MCPChat.CLI.SecureAgentBridge
  alias MCPChat.Agents.AgentPool

  # Command security policies
  @command_policies %{
    # High-risk commands requiring additional validation
    "export" => %{risk_level: :high, requires_audit: true, rate_limit: 10},
    "mcp" => %{risk_level: :medium, rate_limited: true, rate_limit: 50},
    "backend" => %{risk_level: :medium, requires_confirmation: false, rate_limit: 20},
    "model" => %{risk_level: :medium, rate_limit: 30},
    "cost" => %{risk_level: :medium, rate_limit: 25},

    # Low-risk commands
    "help" => %{risk_level: :low},
    "context" => %{risk_level: :low, rate_limit: 100},
    "history" => %{risk_level: :low, rate_limit: 50},
    "config" => %{risk_level: :low, rate_limit: 20},
    "stats" => %{risk_level: :low, rate_limit: 40}
  }

  @doc """
  Route command with security validation.
  Returns {:ok, result} on success or {:error, reason} on failure.
  """
  def route_secure_command(command, args, _session_id \\ "default") do
    with {:ok, session} <- SecureAgentBridge.get_security_context(),
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
          audit_unknown_command(cmd, session)
          {:error, :unknown_command}
      end
    else
      {:error, :security_violation} = error ->
        record_command_violation(command, args, :security_violation)
        error

      {:error, :rate_limit_exceeded} = error ->
        record_command_violation(command, args, :rate_limit_exceeded)
        error

      other ->
        other
    end
  end

  @doc """
  Execute agent command with security context and validation.
  """
  def execute_secure_agent_command(agent_type, command, args, session) do
    # Prepare security context for agent
    task_spec = %{
      command: command,
      args: args,
      session_id: session[:session_id] || "default",
      agent_type: agent_type,
      security_context: %{
        principal_id: session[:principal_id],
        capabilities: filter_capabilities_for_agent(session[:capabilities] || [], agent_type),
        audit_required: command_requires_audit?(command),
        risk_level: get_command_risk_level(command)
      }
    }

    # Log command execution attempt
    audit_command_execution_start(task_spec)

    # Execute through agent pool with security
    case AgentPool.request_tool_execution(task_spec.session_id, task_spec) do
      {:ok, agent_pid} ->
        # Monitor execution for security events
        monitor_agent_execution(agent_pid, task_spec)
        {:ok, agent_pid}

      {:error, reason} = error ->
        audit_command_execution_failed(task_spec, reason)
        error
    end
  end

  @doc """
  Validate command permissions against session capabilities.
  """
  def validate_command_permissions(session, command, args) do
    validate_command_permission(session, command, args)
  end

  @doc """
  Get enhanced help with security information.
  """
  def generate_secure_help(session_id \\ "default") do
    with {:ok, session} <- SecureAgentBridge.get_security_context() do
      base_help = AgentCommandBridge.generate_enhanced_help(session_id)

      security_info = %{
        security_level: session[:security_level] || :unknown,
        capabilities_count: length(session[:capabilities] || []),
        token_mode: Security.use_token_mode?(),
        audit_enabled: true,
        rate_limits: get_applicable_rate_limits(session)
      }

      Map.put(base_help, :security_info, security_info)
    else
      _ ->
        # Fallback to basic help without security info
        AgentCommandBridge.generate_enhanced_help(session_id)
    end
  end

  # Private functions

  defp execute_local_with_security(command, args, session) do
    # Local commands execute in current process but with security validation
    audit_local_command(command, args, session)

    # For now, delegate to the underlying command bridge
    # In the future, this could route to secure local command handlers
    {:local, command, args}
  end

  defp execute_agent_with_security(agent_type, command, args, session) do
    execute_secure_agent_command(agent_type, command, args, session)
  end

  defp validate_command_permission(session, command, args) do
    policy = Map.get(@command_policies, command, %{risk_level: :medium})

    # Check if user has CLI operation capabilities
    cli_capabilities = get_cli_capabilities(session)

    cond do
      # No CLI capability at all
      Enum.empty?(cli_capabilities) ->
        {:error, :no_cli_capability}

      # High-risk command validation
      policy[:risk_level] == :high ->
        validate_high_risk_command(session, command, args)

      # Rate limiting check
      policy[:rate_limited] || policy[:rate_limit] ->
        with :ok <- check_rate_limit(session[:principal_id], command) do
          validate_basic_command_permission(cli_capabilities, command)
        end

      # Default validation
      true ->
        validate_basic_command_permission(cli_capabilities, command)
    end
  end

  defp get_cli_capabilities(session) do
    (session[:capabilities] || [])
    |> Enum.filter(fn cap ->
      Map.get(cap, :resource_type) == :cli_operations
    end)
  end

  defp validate_basic_command_permission(cli_capabilities, command) do
    # Find a capability that allows this command
    case Enum.find(cli_capabilities, fn cap ->
           constraints = Map.get(cap, :constraints, %{})
           commands = Map.get(constraints, :commands, ["*"])
           command in commands || "*" in commands
         end) do
      nil ->
        {:error, :command_not_permitted}

      capability ->
        # Validate the capability itself
        Security.validate_capability(capability, :execute, command)
    end
  end

  defp validate_high_risk_command(session, command, args) do
    cli_caps = get_cli_capabilities(session)

    with :ok <- validate_basic_command_permission(cli_caps, command),
         :ok <- check_command_constraints(command, args),
         :ok <- maybe_require_confirmation(session, command, args) do
      :ok
    end
  end

  defp check_command_constraints(command, args) do
    case command do
      "export" ->
        # Validate export parameters
        validate_export_constraints(args)

      "mcp" ->
        # Validate MCP operation constraints
        validate_mcp_constraints(args)

      _ ->
        :ok
    end
  end

  defp validate_export_constraints(args) do
    # Check export format and destination
    cond do
      length(args) < 2 ->
        {:error, :insufficient_export_args}

      true ->
        :ok
    end
  end

  defp validate_mcp_constraints(args) do
    # Validate MCP command structure
    case args do
      ["tool" | _] -> :ok
      ["server" | _] -> :ok
      ["list" | _] -> :ok
      _ -> {:error, :invalid_mcp_command}
    end
  end

  defp maybe_require_confirmation(_session, _command, _args) do
    # For now, skip confirmation prompts in CLI
    # Future: implement interactive confirmation for high-risk operations
    :ok
  end

  defp check_rate_limit(principal_id, command) do
    policy = Map.get(@command_policies, command, %{})
    limit = Map.get(policy, :rate_limit, 100)

    key = "command_rate:#{principal_id}:#{command}"
    # 1 hour window
    window_seconds = 3600

    case check_rate_limit_internal(key, limit, window_seconds) do
      :ok -> :ok
      :exceeded -> {:error, :rate_limit_exceeded}
    end
  end

  defp check_rate_limit_internal(key, limit, window_seconds) do
    # Simple rate limiting using ETS
    table = ensure_rate_limit_table()
    now = System.system_time(:second)

    case :ets.lookup(table, key) do
      [{^key, count, last_reset}] ->
        if now - last_reset > window_seconds do
          # Reset window
          :ets.insert(table, {key, 1, now})
          :ok
        else
          if count >= limit do
            :exceeded
          else
            :ets.insert(table, {key, count + 1, last_reset})
            :ok
          end
        end

      [] ->
        # First request
        :ets.insert(table, {key, 1, now})
        :ok
    end
  end

  defp ensure_rate_limit_table do
    table_name = :secure_command_rate_limits

    case :ets.info(table_name) do
      :undefined ->
        :ets.new(table_name, [:set, :public, :named_table])

      _ ->
        table_name
    end
  end

  defp monitor_agent_execution(agent_pid, task_spec) do
    # Set up monitoring for security events during execution
    Task.start(fn ->
      ref = Process.monitor(agent_pid)

      receive do
        {:DOWN, ^ref, :process, ^agent_pid, reason} ->
          if reason != :normal do
            record_agent_failure(task_spec, reason)
          else
            audit_command_execution_completed(task_spec)
          end
      after
        :timer.minutes(10) ->
          # Timeout monitoring after 10 minutes
          Process.demonitor(ref, [:flush])
          record_agent_timeout(task_spec)
      end
    end)
  end

  defp filter_capabilities_for_agent(capabilities, agent_type) do
    # Filter capabilities relevant to specific agent type
    case agent_type do
      :llm_agent ->
        Enum.filter(capabilities, fn cap ->
          Map.get(cap, :resource_type) in [:llm_operations, :model_management, :network]
        end)

      :mcp_agent ->
        Enum.filter(capabilities, fn cap ->
          Map.get(cap, :resource_type) in [:mcp_tool, :mcp_server]
        end)

      :export_agent ->
        Enum.filter(capabilities, fn cap ->
          Map.get(cap, :resource_type) in [:filesystem, :export_operations]
        end)

      :analysis_agent ->
        Enum.filter(capabilities, fn cap ->
          Map.get(cap, :resource_type) in [:filesystem, :cli_operations]
        end)

      _ ->
        capabilities
    end
  end

  defp command_requires_audit?(command) do
    policy = Map.get(@command_policies, command, %{})
    Map.get(policy, :requires_audit, false)
  end

  defp get_command_risk_level(command) do
    policy = Map.get(@command_policies, command, %{})
    Map.get(policy, :risk_level, :medium)
  end

  defp get_applicable_rate_limits(session) do
    principal_id = session[:principal_id]

    if principal_id do
      @command_policies
      |> Enum.filter(fn {_cmd, policy} -> Map.has_key?(policy, :rate_limit) end)
      |> Enum.map(fn {cmd, policy} ->
        key = "command_rate:#{principal_id}:#{cmd}"
        current_count = get_current_rate_count(key)
        limit = policy[:rate_limit]

        %{
          command: cmd,
          current: current_count,
          limit: limit,
          remaining: max(0, limit - current_count)
        }
      end)
    else
      []
    end
  end

  defp get_current_rate_count(key) do
    table = ensure_rate_limit_table()

    case :ets.lookup(table, key) do
      [{^key, count, _last_reset}] -> count
      [] -> 0
    end
  end

  # Audit and logging functions

  defp audit_command_execution_start(task_spec) do
    Security.log_security_event(:command_execution_started, %{
      command: task_spec.command,
      agent_type: task_spec.agent_type,
      principal_id: task_spec.security_context.principal_id,
      session_id: task_spec.session_id,
      risk_level: task_spec.security_context.risk_level,
      timestamp: DateTime.utc_now()
    })
  end

  defp audit_command_execution_completed(task_spec) do
    Security.log_security_event(:command_execution_completed, %{
      command: task_spec.command,
      agent_type: task_spec.agent_type,
      principal_id: task_spec.security_context.principal_id,
      session_id: task_spec.session_id,
      timestamp: DateTime.utc_now()
    })
  end

  defp audit_command_execution_failed(task_spec, reason) do
    Security.log_security_event(:command_execution_failed, %{
      command: task_spec.command,
      agent_type: task_spec.agent_type,
      principal_id: task_spec.security_context.principal_id,
      session_id: task_spec.session_id,
      reason: inspect(reason),
      timestamp: DateTime.utc_now()
    })
  end

  defp audit_local_command(command, args, session) do
    Security.log_security_event(:local_command_executed, %{
      command: command,
      args: sanitize_args(args),
      principal_id: session[:principal_id],
      timestamp: DateTime.utc_now()
    })
  end

  defp audit_unknown_command(command, session) do
    Security.log_security_event(:unknown_command_attempted, %{
      command: command,
      principal_id: session[:principal_id],
      timestamp: DateTime.utc_now()
    })
  end

  defp record_command_violation(command, args, violation_type) do
    MCPChat.Security.ViolationMonitor.record_violation(violation_type, %{
      command: command,
      args: sanitize_args(args),
      principal_id: get_current_principal_id(),
      timestamp: DateTime.utc_now()
    })
  end

  defp record_agent_failure(task_spec, reason) do
    MCPChat.Security.ViolationMonitor.record_violation(:agent_execution_failure, %{
      task_spec: sanitize_task_spec(task_spec),
      reason: inspect(reason),
      timestamp: DateTime.utc_now()
    })
  end

  defp record_agent_timeout(task_spec) do
    MCPChat.Security.ViolationMonitor.record_violation(:agent_execution_timeout, %{
      task_spec: sanitize_task_spec(task_spec),
      timestamp: DateTime.utc_now()
    })
  end

  defp get_current_principal_id do
    case SecureAgentBridge.get_security_context() do
      {:ok, context} -> context[:principal_id]
      _ -> "unknown"
    end
  end

  defp sanitize_args(args) when is_list(args) do
    Enum.map(args, fn arg ->
      if is_binary(arg) && String.contains?(arg, "password") do
        "[REDACTED]"
      else
        arg
      end
    end)
  end

  defp sanitize_args(args), do: args

  defp sanitize_task_spec(task_spec) do
    %{
      command: task_spec.command,
      agent_type: task_spec.agent_type,
      session_id: task_spec.session_id,
      args: sanitize_args(task_spec.args || [])
    }
  end
end
