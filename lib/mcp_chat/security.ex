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
  alias MCPChat.Security.SecurityKernel
  alias MCPChat.Security.AuditLogger

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
  @spec request_capability(resource_type(), constraints(), principal_id()) ::
          {:ok, struct()} | {:error, atom()}
  def request_capability(resource_type, constraints, principal_id \\ nil) do
    principal_id = principal_id || get_current_principal()
    SecurityKernel.request_capability(resource_type, constraints, principal_id)
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
    SecurityKernel.validate_capability(capability, operation, resource)
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
    SecurityKernel.delegate_capability(capability, target_principal, additional_constraints)
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
    SecurityKernel.revoke_capability(capability, reason)
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
  def request_temporary_capability(resource_type, constraints, duration_seconds, principal_id \\ nil) do
    principal_id = principal_id || get_current_principal()

    expires_at = DateTime.add(DateTime.utc_now(), duration_seconds, :second)
    constraints_with_expiry = Map.put(constraints, :expires_at, expires_at)

    request_capability(resource_type, constraints_with_expiry, principal_id)
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
end
