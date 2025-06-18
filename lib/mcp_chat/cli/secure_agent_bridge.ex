defmodule MCPChat.CLI.SecureAgentBridge do
  @moduledoc """
  Enhanced agent bridge with integrated security capabilities.

  This module provides a security-aware wrapper around the existing AgentBridge,
  adding capability-based access control, audit logging, and real-time security
  monitoring for CLI agent operations.
  """

  require Logger

  alias MCPChat.CLI.AgentBridge
  alias MCPChat.Security
  alias MCPChat.CLI.SecurityEventSubscriber

  # Session registry with security context
  @secure_session_registry :secure_cli_agent_registry

  defstruct [
    :cli_session_id,
    :agent_session_id,
    :principal_id,
    :capabilities,
    :security_context,
    :created_at,
    :last_activity
  ]

  @doc """
  Initialize the secure agent bridge.
  """
  def init do
    # Initialize the underlying AgentBridge
    AgentBridge.init()

    # Create ETS table for secure session mapping if it doesn't exist
    if :ets.info(@secure_session_registry) == :undefined do
      :ets.new(@secure_session_registry, [:set, :public, :named_table])
    end

    # Start security event subscriber
    SecurityEventSubscriber.start_link([])

    :ok
  end

  @doc """
  Create a secure agent session with capability management.
  """
  def ensure_secure_session(opts \\ []) do
    cli_session_id = get_cli_session_id()

    case lookup_secure_session(cli_session_id) do
      {:ok, secure_session} ->
        # Verify session is still active and update activity
        if session_active?(secure_session.agent_session_id) do
          updated_session = %{secure_session | last_activity: DateTime.utc_now()}
          store_secure_session(updated_session)
          {:ok, secure_session.agent_session_id, secure_session.capabilities}
        else
          # Session expired, create a new one
          create_secure_session(cli_session_id, opts)
        end

      :error ->
        # No mapping exists, create new session
        create_secure_session(cli_session_id, opts)
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
        record_violation(:unauthorized_tool_execution, %{
          tool_name: tool_name,
          args: sanitize_args(args)
        })

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
      # Log message sending
      audit_message(session, content)

      result
    else
      {:error, :security_violation} = error ->
        record_violation(:unauthorized_message, %{
          content_length: String.length(content)
        })

        error

      other ->
        other
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
        principal_id: "subagent_#{task_spec.id || generate_subagent_id()}"
      ]

      # Log subagent creation
      audit_subagent_creation(session, task_spec, delegated_caps)

      AgentBridge.send_message_async(
        "Creating subagent with delegated capabilities for: #{task_spec.description || "task"}",
        sub_agent_opts
      )
    else
      error ->
        Logger.error("Failed to spawn secure subagent: #{inspect(error)}")
        error
    end
  end

  @doc """
  Get current security context for the session.
  """
  def get_security_context do
    case get_secure_session() do
      {:ok, session} ->
        {:ok,
         %{
           principal_id: session.principal_id,
           capabilities: length(session.capabilities),
           security_level: determine_security_level(session),
           token_mode: Security.use_token_mode?(),
           last_activity: session.last_activity
         }}

      error ->
        error
    end
  end

  @doc """
  Revoke all capabilities for the current session.
  """
  def revoke_session_capabilities(reason \\ "manual_revocation") do
    with {:ok, session} <- get_secure_session() do
      # Revoke all capabilities
      results =
        Enum.map(session.capabilities, fn cap ->
          Security.revoke_capability(cap, reason)
        end)

      # Update session to remove capabilities
      updated_session = %{session | capabilities: []}
      store_secure_session(updated_session)

      # Log revocation
      audit_capability_revocation(session, reason)

      {:ok, results}
    end
  end

  @doc """
  Clean up secure session when CLI session ends.
  """
  def cleanup_secure_session do
    cli_session_id = get_cli_session_id()

    case lookup_secure_session(cli_session_id) do
      {:ok, secure_session} ->
        # Revoke all capabilities
        Enum.each(secure_session.capabilities, fn cap ->
          Security.revoke_capability(cap, "session_cleanup")
        end)

        # Cleanup underlying agent session
        AgentBridge.cleanup_session()

        # Remove secure mapping
        :ets.delete(@secure_session_registry, cli_session_id)

        # Log cleanup
        audit_session_cleanup(secure_session)

        :ok

      :error ->
        # No secure session, just cleanup underlying
        AgentBridge.cleanup_session()
        :ok
    end
  end

  # Private functions

  defp get_cli_session_id do
    case Process.get(:cli_session_id) do
      nil ->
        session_id = generate_cli_session_id()
        Process.put(:cli_session_id, session_id)
        session_id

      session_id ->
        session_id
    end
  end

  defp generate_cli_session_id do
    timestamp = System.system_time(:millisecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "secure_cli_#{timestamp}_#{random}"
  end

  defp lookup_secure_session(cli_session_id) do
    case :ets.lookup(@secure_session_registry, cli_session_id) do
      [{^cli_session_id, secure_session}] -> {:ok, secure_session}
      [] -> :error
    end
  end

  defp store_secure_session(secure_session) do
    :ets.insert(@secure_session_registry, {secure_session.cli_session_id, secure_session})
  end

  defp create_secure_session(cli_session_id, opts) do
    principal_id = get_or_create_principal_id(cli_session_id)

    # Request base capabilities for CLI agent
    with {:ok, capabilities} <- request_cli_capabilities(principal_id, opts),
         {:ok, agent_session_id} <- AgentBridge.ensure_agent_session(opts) do
      # Create secure session mapping
      secure_session = %__MODULE__{
        cli_session_id: cli_session_id,
        agent_session_id: agent_session_id,
        principal_id: principal_id,
        capabilities: capabilities,
        security_context: build_security_context(capabilities),
        created_at: DateTime.utc_now(),
        last_activity: DateTime.utc_now()
      }

      store_secure_session(secure_session)

      # Subscribe to security events
      subscribe_to_security_events(agent_session_id)

      # Log session creation
      audit_session_creation(secure_session)

      {:ok, agent_session_id, capabilities}
    else
      error ->
        Logger.error("Failed to create secure session: #{inspect(error)}")
        error
    end
  end

  defp get_or_create_principal_id(cli_session_id) do
    # Use CLI session ID as base for principal ID
    "cli_principal_#{cli_session_id}"
  end

  defp request_cli_capabilities(principal_id, opts) do
    capabilities = []

    # Basic CLI operations
    {:ok, cli_cap} =
      Security.request_capability(
        :cli_operations,
        %{
          operations: [:read, :write, :execute],
          # Will be filtered by command bridge
          commands: ["*"],
          # Operations per hour
          rate_limit: 1000
        },
        principal_id
      )

    capabilities = [cli_cap | capabilities]

    # File system access (if needed)
    capabilities =
      if Keyword.get(opts, :enable_filesystem, true) do
        {:ok, fs_cap} =
          Security.request_capability(
            :filesystem,
            %{
              operations: [:read, :write],
              paths: ["/tmp"],
              allowed_extensions: [".txt", ".md", ".json", ".ex", ".exs", ".toml"]
            },
            principal_id
          )

        [fs_cap | capabilities]
      end

    # MCP tool access
    capabilities =
      if Keyword.get(opts, :enable_mcp_tools, true) do
        {:ok, mcp_cap} =
          Security.request_capability(
            :mcp_tool,
            %{
              operations: [:execute],
              resource: "*",
              allowed_tools: get_allowed_mcp_tools(opts),
              rate_limit: 100
            },
            principal_id
          )

        [mcp_cap | capabilities]
      end

    # Network access for LLM backends
    capabilities =
      if Keyword.get(opts, :enable_network, true) do
        {:ok, network_cap} =
          Security.request_capability(
            :network,
            %{
              operations: [:read, :write],
              resource: "https://*",
              allowed_domains: ["api.anthropic.com", "api.openai.com", "api.google.com"],
              rate_limit: 1000
            },
            principal_id
          )

        [network_cap | capabilities]
      end

    {:ok, capabilities}
  end

  defp get_allowed_mcp_tools(opts) do
    # Get from config or use defaults
    Keyword.get(opts, :allowed_tools, ["*"])
  end

  defp build_security_context(capabilities) do
    %{
      capability_count: length(capabilities),
      resource_types: Enum.map(capabilities, & &1.resource_type) |> Enum.uniq(),
      elevated_privileges: has_elevated_privileges?(capabilities),
      audit_mode: true,
      created_at: DateTime.utc_now()
    }
  end

  defp has_elevated_privileges?(capabilities) do
    # Check if any capabilities have broad access
    Enum.any?(capabilities, fn cap ->
      case cap.constraints do
        %{resource: "*"} ->
          true

        %{paths: paths} when is_list(paths) ->
          Enum.any?(paths, &String.starts_with?(&1, "/"))

        _ ->
          false
      end
    end)
  end

  defp get_secure_session do
    cli_session_id = get_cli_session_id()
    lookup_secure_session(cli_session_id)
  end

  defp session_active?(_session_id) do
    case AgentBridge.get_system_health() do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp validate_tool_permission(session, tool_name, _args) do
    # Find the appropriate capability
    mcp_cap =
      Enum.find(session.capabilities, fn cap ->
        cap.resource_type == :mcp_tool
      end)

    if mcp_cap do
      Security.validate_capability(mcp_cap, :execute, tool_name)
    else
      {:error, :no_mcp_capability}
    end
  end

  defp validate_message_content(session, content) do
    # Implement content security policies
    cond do
      String.length(content) > 50_000 ->
        {:error, :message_too_large}

      contains_sensitive_data?(content) ->
        {:error, :sensitive_data_detected}

      exceeds_rate_limit?(session.principal_id) ->
        {:error, :rate_limit_exceeded}

      true ->
        :ok
    end
  end

  defp contains_sensitive_data?(content) do
    # Simple patterns for sensitive data detection
    sensitive_patterns = [
      # Email
      ~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/,
      # Credit card
      ~r/\b(?:\d{4}[-\s]?){3}\d{4}\b/,
      # SSN
      ~r/\b\d{3}-\d{2}-\d{4}\b/,
      # Password
      ~r/(?i)password\s*[:=]\s*\S+/,
      # API key
      ~r/(?i)api[_-]?key\s*[:=]\s*\S+/
    ]

    Enum.any?(sensitive_patterns, &Regex.match?(&1, content))
  end

  defp exceeds_rate_limit?(principal_id) do
    # Simple rate limiting - 100 messages per minute
    key = "message_rate:#{principal_id}"

    case :ets.lookup(:rate_limits, key) do
      [{^key, count, last_reset}] ->
        now = System.system_time(:second)

        if now - last_reset > 60 do
          # Reset counter
          :ets.insert(:rate_limits, {key, 1, now})
          false
        else
          if count >= 100 do
            true
          else
            :ets.insert(:rate_limits, {key, count + 1, last_reset})
            false
          end
        end

      [] ->
        # First message
        now = System.system_time(:second)
        :ets.insert(:rate_limits, {key, 1, now})
        false
    end
  end

  defp delegate_capabilities(session, task_spec, constraints) do
    # Delegate each parent capability with additional constraints
    delegated =
      Enum.map(session.capabilities, fn cap ->
        task_constraints =
          Map.merge(
            %{
              max_delegation_depth: 1,
              expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
            },
            constraints
          )

        case Security.delegate_capability(
               cap,
               "subagent_#{task_spec.id || generate_subagent_id()}",
               task_constraints
             ) do
          {:ok, delegated} ->
            delegated

          {:error, reason} ->
            Logger.warning("Failed to delegate capability: #{inspect(reason)}")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, delegated}
  end

  defp generate_subagent_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp subscribe_to_security_events(session_id) do
    # Subscribe to security-specific events
    Phoenix.PubSub.subscribe(MCPChat.PubSub, "security:violations")
    Phoenix.PubSub.subscribe(MCPChat.PubSub, "security:alerts")
    Phoenix.PubSub.subscribe(MCPChat.PubSub, "session:#{session_id}:security")
  end

  defp determine_security_level(session) do
    cond do
      session.security_context.elevated_privileges -> :high
      length(session.capabilities) > 3 -> :medium
      true -> :low
    end
  end

  # Audit logging functions

  defp audit_session_creation(session) do
    Security.log_security_event(:session_created, %{
      principal_id: session.principal_id,
      session_id: session.agent_session_id,
      capability_count: length(session.capabilities),
      security_level: determine_security_level(session)
    })
  end

  defp audit_session_cleanup(session) do
    Security.log_security_event(:session_cleanup, %{
      principal_id: session.principal_id,
      session_id: session.agent_session_id,
      duration: DateTime.diff(DateTime.utc_now(), session.created_at, :second)
    })
  end

  defp audit_tool_execution(session, tool_name, args, result) do
    Security.log_security_event(:tool_execution, %{
      principal_id: session.principal_id,
      session_id: session.agent_session_id,
      tool_name: tool_name,
      args: sanitize_args(args),
      result_id: result[:execution_id],
      timestamp: DateTime.utc_now()
    })
  end

  defp audit_message(session, content) do
    Security.log_security_event(:message_sent, %{
      principal_id: session.principal_id,
      session_id: session.agent_session_id,
      content_length: String.length(content),
      timestamp: DateTime.utc_now()
    })
  end

  defp audit_subagent_creation(session, task_spec, capabilities) do
    Security.log_security_event(:subagent_created, %{
      principal_id: session.principal_id,
      parent_session: session.agent_session_id,
      task_description: task_spec.description || "unknown",
      delegated_capabilities: length(capabilities)
    })
  end

  defp audit_capability_revocation(session, reason) do
    Security.log_security_event(:capabilities_revoked, %{
      principal_id: session.principal_id,
      session_id: session.agent_session_id,
      reason: reason,
      capability_count: length(session.capabilities)
    })
  end

  defp record_violation(type, details) do
    MCPChat.Security.ViolationMonitor.record_violation(
      type,
      Map.merge(details, %{
        principal_id: get_current_principal_id(),
        timestamp: DateTime.utc_now()
      })
    )
  end

  defp get_current_principal_id do
    case get_secure_session() do
      {:ok, session} -> session.principal_id
      _ -> "unknown"
    end
  end

  defp sanitize_args(args) do
    # Remove sensitive information from args before logging
    args
    |> Enum.map(fn {k, v} ->
      key_str = to_string(k)

      if key_str in ["password", "token", "secret", "key", "auth"] do
        {k, "[REDACTED]"}
      else
        {k, v}
      end
    end)
    |> Enum.into(%{})
  end
end
