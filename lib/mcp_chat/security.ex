defmodule MCPChat.Security do
  @moduledoc """
  Security module for MCP Chat providing capability-based security (CapSec) 
  for AI agent orchestration and MCP server interactions.

  This module implements a comprehensive security model that:
  - Uses capabilities for fine-grained permission control
  - Supports delegation with constraint inheritance
  - Provides audit logging for all security events
  - Integrates with MCP adapter layer for secure tool execution

  ## Core Concepts

  - **Capability**: A permission token that grants specific access rights
  - **Principal**: An entity (agent, user, process) that can hold capabilities
  - **Resource**: A protected entity (file, tool, MCP server) that requires capabilities
  - **Constraint**: Limitations on capability usage (time, scope, delegation depth)

  ## Usage Examples

      # Request filesystem access capability
      {:ok, capability} = Security.request_capability(:filesystem, %{
        paths: ["/tmp"],
        operations: [:read, :write]
      })
      
      # Validate capability before tool execution
      case Security.validate_capability(capability, :write, "/tmp/test.txt") do
        :ok -> execute_write_operation()
        {:error, reason} -> handle_security_violation(reason)
      end
      
      # Delegate capability with additional constraints
      {:ok, delegated} = Security.delegate_capability(capability, agent_id, %{
        operations: [:read],  # More restrictive
        expires_at: DateTime.add(DateTime.utc_now(), 3600)
      })
  """

  # Forward declaration to avoid circular dependency
  alias MCPChat.Security.{SecurityKernel, AuditLogger, TokenIssuer, TokenValidator}

  @type principal_id :: String.t()
  @type resource_type :: :filesystem | :mcp_tool | :network | :process | :database
  @type operation :: :read | :write | :execute | :delete | :create | :list
  @type constraint_key :: :paths | :operations | :expires_at | :max_delegations | :scope
  @type constraints :: %{constraint_key() => any()}
  @type security_result :: :ok | {:error, atom()}

  ## Public API

  @doc """
  Requests a new capability for the specified resource type.

  ## Parameters
  - `resource_type`: The type of resource to access
  - `constraints`: Initial constraints for the capability
  - `principal_id`: The requesting principal (defaults to current process)

  ## Returns
  - `{:ok, capability}` on success
  - `{:error, reason}` on failure
  """
  @spec request_capability(resource_type(), constraints(), principal_id(), Keyword.t()) ::
          {:ok, struct()} | {:error, atom()}
  def request_capability(resource_type, constraints, principal_id \\ nil, opts \\ []) do
    principal_id = principal_id || get_current_principal()

    # Check if token mode is enabled
    if Keyword.get(opts, :use_tokens, use_token_mode?()) do
      # Phase 2: Issue JWT token
      operations = Map.get(constraints, :operations, [:read, :write, :execute])
      resource = Map.get(constraints, :resource, "*")

      case TokenIssuer.issue_token(resource_type, operations, resource, principal_id, constraints) do
        {:ok, token, jti} ->
          # Return a token-based capability struct
          {:ok,
           %{
             __struct__: MCPChat.Security.Capability,
             id: jti,
             token: token,
             resource_type: resource_type,
             principal_id: principal_id,
             constraints: constraints,
             is_token: true
           }}

        error ->
          error
      end
    else
      # Phase 1: Use SecurityKernel
      SecurityKernel.request_capability(resource_type, constraints, principal_id)
    end
  end

  @doc """
  Validates a capability for a specific operation on a resource.

  ## Parameters
  - `capability`: The capability to validate
  - `operation`: The operation being attempted
  - `resource`: The specific resource being accessed

  ## Returns
  - `:ok` if the capability is valid
  - `{:error, reason}` if validation fails
  """
  @spec validate_capability(struct(), operation(), String.t()) :: security_result()
  def validate_capability(capability, operation, resource) do
    # Check if this is a token-based capability
    if Map.get(capability, :is_token, false) && Map.get(capability, :token) do
      # Phase 2: Validate JWT token locally
      TokenValidator.validate_token(capability.token, operation, resource)
      |> case do
        {:ok, _claims} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      # Phase 1: Use SecurityKernel
      SecurityKernel.validate_capability(capability, operation, resource)
    end
  end

  @doc """
  Delegates a capability to another principal with additional constraints.

  The new capability will inherit all constraints from the parent capability
  and apply any additional constraints specified.

  ## Parameters
  - `capability`: The capability to delegate
  - `target_principal`: The principal receiving the delegated capability
  - `additional_constraints`: Additional constraints to apply

  ## Returns
  - `{:ok, delegated_capability}` on success
  - `{:error, reason}` on failure
  """
  @spec delegate_capability(struct(), principal_id(), constraints()) ::
          {:ok, struct()} | {:error, atom()}
  def delegate_capability(capability, target_principal, additional_constraints \\ %{}) do
    # Check if this is a token-based capability
    if Map.get(capability, :is_token, false) && Map.get(capability, :token) do
      # Phase 2: Issue delegated token
      case TokenIssuer.issue_delegated_token(capability.token, target_principal, additional_constraints) do
        {:ok, token, jti} ->
          # Return a new token-based capability struct
          {:ok,
           %{
             __struct__: MCPChat.Security.Capability,
             id: jti,
             token: token,
             resource_type: capability.resource_type,
             principal_id: target_principal,
             constraints: merge_constraints(capability.constraints, additional_constraints),
             is_token: true,
             parent_id: capability.id
           }}

        error ->
          error
      end
    else
      # Phase 1: Use SecurityKernel
      SecurityKernel.delegate_capability(capability, target_principal, additional_constraints)
    end
  end

  defp merge_constraints(parent_constraints, child_constraints) do
    Map.merge(parent_constraints, child_constraints, fn key, parent_val, child_val ->
      case key do
        # Special handling for paths - child paths must be subpaths of parent paths
        :paths when is_list(parent_val) and is_list(child_val) ->
          # Child paths should be kept if they are subpaths of any parent path
          Enum.filter(child_val, fn child_path ->
            Enum.any?(parent_val, fn parent_path ->
              String.starts_with?(to_string(child_path), to_string(parent_path))
            end)
          end)

        # For other lists, take intersection
        _ when is_list(parent_val) and is_list(child_val) ->
          Enum.filter(child_val, &(&1 in parent_val))

        # For other values, take the more restrictive (child)
        _ ->
          child_val
      end
    end)
  end

  @doc """
  Revokes a capability, making it invalid for future operations.

  If the capability has been delegated, all delegated capabilities will also be revoked.

  ## Parameters
  - `capability`: The capability to revoke
  - `reason`: Optional reason for revocation (for audit logging)

  ## Returns
  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @spec revoke_capability(struct(), String.t()) :: security_result()
  def revoke_capability(capability, reason \\ "manual_revocation") do
    # Check if this is a token-based capability
    if Map.get(capability, :is_token, false) do
      # Phase 2: Revoke token via RevocationCache
      TokenIssuer.revoke_token(capability.id)
    else
      # Phase 1: Use SecurityKernel
      SecurityKernel.revoke_capability(capability, reason)
    end
  end

  @doc """
  Lists all active capabilities for a principal.

  ## Parameters
  - `principal_id`: The principal to query (defaults to current process)

  ## Returns
  - `{:ok, [capability]}` list of active capabilities
  - `{:error, reason}` on failure
  """
  @spec list_capabilities(principal_id()) :: {:ok, [struct()]} | {:error, atom()}
  def list_capabilities(principal_id \\ nil) do
    principal_id = principal_id || get_current_principal()
    SecurityKernel.list_capabilities(principal_id)
  end

  @doc """
  Checks if a principal has permission for a specific operation.

  This is a convenience function that checks all capabilities of a principal
  to see if any grants the requested permission.

  ## Parameters
  - `principal_id`: The principal to check
  - `resource_type`: The type of resource
  - `operation`: The operation being attempted
  - `resource`: The specific resource

  ## Returns
  - `:ok` if permission is granted
  - `{:error, reason}` if permission is denied
  """
  @spec check_permission(principal_id(), resource_type(), operation(), String.t()) :: security_result()
  def check_permission(principal_id, resource_type, operation, resource) do
    SecurityKernel.check_permission(principal_id, resource_type, operation, resource)
  end

  @doc """
  Creates a temporary capability that expires after a specified duration.

  ## Parameters
  - `resource_type`: The type of resource to access
  - `constraints`: Initial constraints for the capability
  - `duration_seconds`: How long the capability should be valid
  - `principal_id`: The requesting principal (defaults to current process)

  ## Returns
  - `{:ok, capability}` on success
  - `{:error, reason}` on failure
  """
  @spec request_temporary_capability(resource_type(), constraints(), non_neg_integer(), principal_id()) ::
          {:ok, struct()} | {:error, atom()}
  def request_temporary_capability(resource_type, constraints, duration_seconds, principal_id \\ nil, opts \\ []) do
    principal_id = principal_id || get_current_principal()

    expires_at = DateTime.add(DateTime.utc_now(), duration_seconds, :second)
    constraints_with_expiry = Map.put(constraints, :expires_at, expires_at)

    # For token mode, we need to pass a custom TTL to the token issuer
    if Keyword.get(opts, :use_tokens, use_token_mode?()) do
      operations = Map.get(constraints, :operations, [:read, :write, :execute])
      resource = Map.get(constraints, :resource, "*")

      # Issue token with custom expiration
      case TokenIssuer.issue_token_with_ttl(
             resource_type,
             operations,
             resource,
             principal_id,
             constraints,
             duration_seconds
           ) do
        {:ok, token, jti} ->
          # Return a token-based capability struct
          {:ok,
           %{
             __struct__: MCPChat.Security.Capability,
             id: jti,
             token: token,
             resource_type: resource_type,
             principal_id: principal_id,
             constraints: constraints_with_expiry,
             is_token: true,
             expires_at: expires_at
           }}

        error ->
          error
      end
    else
      # Phase 1: Use SecurityKernel with expires_at constraint
      request_capability(resource_type, constraints_with_expiry, principal_id)
    end
  end

  ## Security Event Logging

  @doc """
  Logs a security event for audit purposes.

  ## Parameters
  - `event_type`: The type of security event
  - `details`: Additional details about the event
  - `principal_id`: The principal involved (defaults to current process)
  """
  @spec log_security_event(atom(), map(), principal_id()) :: :ok
  def log_security_event(event_type, details, principal_id \\ nil) do
    principal_id = principal_id || get_current_principal()
    AuditLogger.log_event(event_type, details, principal_id)
  end

  ## Utility Functions

  @doc """
  Gets the current principal ID based on the calling process.

  Returns a unique identifier for the current process/agent.
  """
  @spec get_current_principal() :: principal_id()
  def get_current_principal do
    case Process.get(:security_principal_id) do
      nil ->
        # Generate a unique principal ID for this process
        principal_id = "proc_#{:erlang.pid_to_list(self()) |> to_string()}_#{System.system_time(:microsecond)}"
        Process.put(:security_principal_id, principal_id)
        principal_id

      principal_id ->
        principal_id
    end
  end

  @doc """
  Sets the principal ID for the current process.

  This is typically used by agents to establish their identity.
  """
  @spec set_current_principal(principal_id()) :: :ok
  def set_current_principal(principal_id) do
    Process.put(:security_principal_id, principal_id)
    :ok
  end

  @doc """
  Checks if the security system is enabled.

  Returns false in test environments or when explicitly disabled.
  """
  @spec security_enabled?() :: boolean()
  def security_enabled? do
    Application.get_env(:mcp_chat, :security_enabled, true) and
      not Application.get_env(:mcp_chat, :disable_security_for_tests, false)
  end

  @doc """
  Creates a security context for executing a function with specific capabilities.

  ## Parameters
  - `capabilities`: List of capabilities to use for the execution
  - `fun`: Function to execute in the security context

  ## Returns
  - The result of the function execution
  - `{:error, :security_violation}` if any capability validation fails
  """
  @spec with_capabilities([struct()], (-> any())) :: any() | {:error, :security_violation}
  def with_capabilities(capabilities, fun) when is_list(capabilities) and is_function(fun, 0) do
    # Store capabilities in process dictionary for this execution context
    old_capabilities = Process.get(:security_capabilities, [])
    Process.put(:security_capabilities, capabilities)

    try do
      fun.()
    after
      Process.put(:security_capabilities, old_capabilities)
    end
  end

  @doc """
  Gets the currently active capabilities for this process.
  """
  @spec get_current_capabilities() :: [struct()]
  def get_current_capabilities do
    Process.get(:security_capabilities, [])
  end

  ## Phase 2 Token Support

  @doc """
  Checks if token mode is enabled for the security system.

  Token mode uses JWT tokens for distributed validation instead of 
  centralized SecurityKernel checks.
  """
  @spec use_token_mode?() :: boolean()
  def use_token_mode? do
    Application.get_env(:mcp_chat, :security_token_mode, false)
  end

  @doc """
  Enables or disables token mode at runtime.

  ## Parameters
  - `enabled`: Whether to enable token mode

  ## Returns
  - `:ok`
  """
  @spec set_token_mode(boolean()) :: :ok
  def set_token_mode(enabled) when is_boolean(enabled) do
    Application.put_env(:mcp_chat, :security_token_mode, enabled)
    :ok
  end

  @doc """
  Revokes all capabilities for a principal.

  ## Parameters
  - `principal_id`: The principal whose capabilities to revoke
  - `reason`: Optional reason for revocation

  ## Returns
  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @spec revoke_all_for_principal(principal_id(), String.t()) :: security_result()
  def revoke_all_for_principal(principal_id, reason \\ "principal_cleanup") do
    SecurityKernel.revoke_all_for_principal(principal_id, reason)
  end

  @doc """
  Gets audit statistics for the security system.

  ## Returns
  - `{:ok, stats}` with audit statistics
  - `{:error, reason}` on failure
  """
  @spec get_audit_stats() :: {:ok, map()} | {:error, atom()}
  def get_audit_stats do
    AuditLogger.get_stats()
  end
end
