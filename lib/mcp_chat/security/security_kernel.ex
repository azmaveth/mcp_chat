defmodule MCPChat.Security.SecurityKernel do
  @moduledoc """
  The SecurityKernel is the central authority for capability-based security in MCP Chat.

  It manages the lifecycle of capabilities, validates permissions, handles delegation,
  and maintains the security state for the entire system. This GenServer provides
  thread-safe operations and centralized security policy enforcement.

  ## Responsibilities

  - Capability creation and validation
  - Permission checking and enforcement
  - Capability delegation with constraint inheritance
  - Capability revocation with cascading effects
  - Security event logging and audit trails
  - Integration with resource validators

  ## State

  The SecurityKernel maintains:
  - Active capabilities indexed by ID and principal
  - Delegation relationships for cascading revocation
  - Security policies and configuration
  - Audit event buffer for performance
  """

  use GenServer
  require Logger

  alias MCPChat.Security.{Capability, AuditLogger}

  @type capability_id :: String.t()
  @type principal_id :: String.t()
  @type resource_type :: atom()
  @type operation :: atom()

  defstruct [
    # %{capability_id => Capability.t()}
    :capabilities,
    # %{principal_id => [capability_id]}
    :principal_capabilities,
    # %{parent_id => [child_id]}
    :delegation_tree,
    # Map of security policies
    :security_policies,
    # Buffer for audit events
    :audit_buffer,
    # Last cleanup timestamp
    :last_cleanup,
    # Performance statistics
    :stats
  ]

  ## Public API

  @doc """
  Starts the SecurityKernel GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Requests a new capability for the specified resource type.
  """
  @spec request_capability(resource_type(), map(), principal_id()) ::
          {:ok, Capability.t()} | {:error, atom()}
  def request_capability(resource_type, constraints, principal_id) do
    GenServer.call(__MODULE__, {:request_capability, resource_type, constraints, principal_id})
  end

  @doc """
  Validates a capability for a specific operation on a resource.
  """
  @spec validate_capability(Capability.t(), operation(), String.t()) ::
          :ok | {:error, atom()}
  def validate_capability(capability, operation, resource) do
    GenServer.call(__MODULE__, {:validate_capability, capability, operation, resource})
  end

  @doc """
  Delegates a capability to another principal with additional constraints.
  """
  @spec delegate_capability(Capability.t(), principal_id(), map()) ::
          {:ok, Capability.t()} | {:error, atom()}
  def delegate_capability(capability, target_principal, additional_constraints) do
    GenServer.call(__MODULE__, {:delegate_capability, capability, target_principal, additional_constraints})
  end

  @doc """
  Revokes a capability and all its delegated children.
  """
  @spec revoke_capability(Capability.t(), String.t()) :: :ok | {:error, atom()}
  def revoke_capability(capability, reason \\ "manual_revocation") do
    GenServer.call(__MODULE__, {:revoke_capability, capability, reason})
  end

  @doc """
  Lists all active capabilities for a principal.
  """
  @spec list_capabilities(principal_id()) :: {:ok, [Capability.t()]} | {:error, atom()}
  def list_capabilities(principal_id) do
    GenServer.call(__MODULE__, {:list_capabilities, principal_id})
  end

  @doc """
  Checks if a principal has permission for a specific operation.
  """
  @spec check_permission(principal_id(), resource_type(), operation(), String.t()) ::
          :ok | {:error, atom()}
  def check_permission(principal_id, resource_type, operation, resource) do
    GenServer.call(__MODULE__, {:check_permission, principal_id, resource_type, operation, resource})
  end

  @doc """
  Gets security statistics and system status.
  """
  @spec get_security_stats() :: map()
  def get_security_stats do
    GenServer.call(__MODULE__, :get_security_stats)
  end

  @doc """
  Forces cleanup of expired capabilities.
  """
  @spec cleanup_expired_capabilities() :: :ok
  def cleanup_expired_capabilities do
    GenServer.cast(__MODULE__, :cleanup_expired_capabilities)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    # Schedule periodic cleanup
    schedule_cleanup()

    state = %__MODULE__{
      capabilities: %{},
      principal_capabilities: %{},
      delegation_tree: %{},
      security_policies: load_security_policies(opts),
      audit_buffer: [],
      last_cleanup: DateTime.utc_now(),
      stats: %{
        capabilities_created: 0,
        capabilities_validated: 0,
        capabilities_delegated: 0,
        capabilities_revoked: 0,
        validation_failures: 0
      }
    }

    Logger.info("SecurityKernel started", security_policies: map_size(state.security_policies))

    {:ok, state}
  end

  @impl true
  def handle_call({:request_capability, resource_type, constraints, principal_id}, _from, state) do
    case create_capability(resource_type, constraints, principal_id, state) do
      {:ok, capability, new_state} ->
        audit_event = %{
          event: :capability_created,
          capability_id: capability.id,
          resource_type: resource_type,
          principal_id: principal_id,
          constraints: constraints
        }

        final_state = log_audit_event(audit_event, new_state)
        {:reply, {:ok, capability}, final_state}

      {:error, reason} = error ->
        audit_event = %{
          event: :capability_creation_failed,
          resource_type: resource_type,
          principal_id: principal_id,
          reason: reason
        }

        final_state = log_audit_event(audit_event, state)
        {:reply, error, final_state}
    end
  end

  @impl true
  def handle_call({:validate_capability, capability, operation, resource}, _from, state) do
    case validate_capability_internal(capability, operation, resource, state) do
      :ok ->
        new_stats = Map.update!(state.stats, :capabilities_validated, &(&1 + 1))
        new_state = %{state | stats: new_stats}
        {:reply, :ok, new_state}

      {:error, reason} = error ->
        audit_event = %{
          event: :capability_validation_failed,
          capability_id: capability.id,
          operation: operation,
          resource: resource,
          reason: reason
        }

        new_stats = Map.update!(state.stats, :validation_failures, &(&1 + 1))
        new_state = %{state | stats: new_stats}
        final_state = log_audit_event(audit_event, new_state)

        {:reply, error, final_state}
    end
  end

  @impl true
  def handle_call({:delegate_capability, capability, target_principal, additional_constraints}, _from, state) do
    case delegate_capability_internal(capability, target_principal, additional_constraints, state) do
      {:ok, delegated_capability, new_state} ->
        audit_event = %{
          event: :capability_delegated,
          parent_capability_id: capability.id,
          delegated_capability_id: delegated_capability.id,
          target_principal: target_principal,
          additional_constraints: additional_constraints
        }

        final_state = log_audit_event(audit_event, new_state)
        {:reply, {:ok, delegated_capability}, final_state}

      {:error, reason} = error ->
        audit_event = %{
          event: :capability_delegation_failed,
          capability_id: capability.id,
          target_principal: target_principal,
          reason: reason
        }

        final_state = log_audit_event(audit_event, state)
        {:reply, error, final_state}
    end
  end

  @impl true
  def handle_call({:revoke_capability, capability, reason}, _from, state) do
    case revoke_capability_internal(capability, reason, state) do
      {:ok, revoked_count, new_state} ->
        audit_event = %{
          event: :capability_revoked,
          capability_id: capability.id,
          reason: reason,
          cascaded_revocations: revoked_count - 1
        }

        final_state = log_audit_event(audit_event, new_state)
        {:reply, :ok, final_state}

      {:error, reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:list_capabilities, principal_id}, _from, state) do
    capability_ids = Map.get(state.principal_capabilities, principal_id, [])

    capabilities =
      Enum.map(capability_ids, &Map.get(state.capabilities, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(& &1.revoked)

    {:reply, {:ok, capabilities}, state}
  end

  @impl true
  def handle_call({:check_permission, principal_id, resource_type, operation, resource}, _from, state) do
    case check_permission_internal(principal_id, resource_type, operation, resource, state) do
      :ok -> {:reply, :ok, state}
      {:error, reason} = error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_security_stats, _from, state) do
    stats = %{
      total_capabilities: map_size(state.capabilities),
      active_capabilities: count_active_capabilities(state),
      total_principals: map_size(state.principal_capabilities),
      delegation_relationships: count_delegation_relationships(state),
      audit_buffer_size: length(state.audit_buffer),
      last_cleanup: state.last_cleanup,
      performance_stats: state.stats
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_cast(:cleanup_expired_capabilities, state) do
    new_state = cleanup_expired_capabilities_internal(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:periodic_cleanup, state) do
    new_state = cleanup_expired_capabilities_internal(state)
    schedule_cleanup()
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:flush_audit_buffer, state) do
    new_state = flush_audit_buffer(state)
    {:noreply, new_state}
  end

  ## Private Functions

  defp create_capability(resource_type, constraints, principal_id, state) do
    # Validate the capability request against security policies
    case validate_capability_request(resource_type, constraints, principal_id, state) do
      :ok ->
        case Capability.create(resource_type, constraints, principal_id) do
          {:ok, capability} ->
            new_state = store_capability(capability, state)
            {:ok, capability, new_state}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_capability_internal(capability, operation, resource, state) do
    with :ok <- validate_capability_exists(capability, state),
         :ok <- Capability.validate(capability),
         true <- Capability.valid?(capability),
         :ok <- Capability.permits?(capability, operation, resource) do
      :ok
    else
      false -> {:error, :capability_invalid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp delegate_capability_internal(capability, target_principal, additional_constraints, state) do
    with :ok <- validate_capability_exists(capability, state),
         :ok <- Capability.validate(capability),
         true <- Capability.valid?(capability),
         true <- Capability.delegatable?(capability),
         {:ok, delegated_capability} <- Capability.delegate(capability, target_principal, additional_constraints) do
      new_state =
        store_capability(delegated_capability, state)
        |> add_delegation_relationship(capability.id, delegated_capability.id)

      {:ok, delegated_capability, new_state}
    else
      false -> {:error, :delegation_not_allowed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp revoke_capability_internal(capability, reason, state) do
    case validate_capability_exists(capability, state) do
      :ok ->
        # Get all capabilities that need to be revoked (including delegated ones)
        capabilities_to_revoke = get_capability_tree(capability.id, state)

        # Revoke all capabilities in the tree
        {revoked_count, new_state} =
          Enum.reduce(capabilities_to_revoke, {0, state}, fn cap_id, {count, acc_state} ->
            case Map.get(acc_state.capabilities, cap_id) do
              nil ->
                {count, acc_state}

              cap ->
                revoked_cap = Capability.revoke(cap)
                updated_capabilities = Map.put(acc_state.capabilities, cap_id, revoked_cap)
                updated_state = %{acc_state | capabilities: updated_capabilities}
                {count + 1, updated_state}
            end
          end)

        # Update stats
        new_stats = Map.update!(new_state.stats, :capabilities_revoked, &(&1 + revoked_count))
        final_state = %{new_state | stats: new_stats}

        {:ok, revoked_count, final_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_permission_internal(principal_id, resource_type, operation, resource, state) do
    capability_ids = Map.get(state.principal_capabilities, principal_id, [])

    # Check if any capability grants the requested permission
    Enum.reduce_while(capability_ids, {:error, :permission_denied}, fn cap_id, _acc ->
      case Map.get(state.capabilities, cap_id) do
        nil ->
          {:cont, {:error, :permission_denied}}

        capability ->
          case validate_capability_internal(capability, operation, resource, state) do
            :ok -> {:halt, :ok}
            {:error, _} -> {:cont, {:error, :permission_denied}}
          end
      end
    end)
  end

  defp validate_capability_request(resource_type, constraints, principal_id, state) do
    # Apply security policies to validate the request
    policies = Map.get(state.security_policies, resource_type, [])

    Enum.reduce_while(policies, :ok, fn policy, :ok ->
      case apply_security_policy(policy, resource_type, constraints, principal_id) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_capability_exists(capability, state) do
    case Map.get(state.capabilities, capability.id) do
      nil ->
        {:error, :capability_not_found}

      stored_capability ->
        # Verify the capability hasn't been tampered with
        if stored_capability.signature == capability.signature do
          :ok
        else
          {:error, :capability_signature_mismatch}
        end
    end
  end

  defp store_capability(capability, state) do
    # Store the capability
    updated_capabilities = Map.put(state.capabilities, capability.id, capability)

    # Update principal index
    principal_caps = Map.get(state.principal_capabilities, capability.principal_id, [])

    updated_principal_caps =
      Map.put(
        state.principal_capabilities,
        capability.principal_id,
        [capability.id | principal_caps]
      )

    # Update stats
    new_stats = Map.update!(state.stats, :capabilities_created, &(&1 + 1))

    %{state | capabilities: updated_capabilities, principal_capabilities: updated_principal_caps, stats: new_stats}
  end

  defp add_delegation_relationship(state, parent_id, child_id) do
    children = Map.get(state.delegation_tree, parent_id, [])
    updated_tree = Map.put(state.delegation_tree, parent_id, [child_id | children])

    new_stats = Map.update!(state.stats, :capabilities_delegated, &(&1 + 1))

    %{state | delegation_tree: updated_tree, stats: new_stats}
  end

  defp get_capability_tree(capability_id, state) do
    # Get all descendants of a capability for cascading operations
    get_capability_descendants(capability_id, state.delegation_tree, [capability_id])
  end

  defp get_capability_descendants(capability_id, delegation_tree, acc) do
    children = Map.get(delegation_tree, capability_id, [])

    Enum.reduce(children, acc, fn child_id, acc ->
      get_capability_descendants(child_id, delegation_tree, [child_id | acc])
    end)
  end

  defp cleanup_expired_capabilities_internal(state) do
    now = DateTime.utc_now()

    # Find expired capabilities
    {expired_capabilities, active_capabilities} =
      Enum.split_with(state.capabilities, fn {_id, capability} ->
        Capability.expired?(capability)
      end)

    expired_count = length(expired_capabilities)

    if expired_count > 0 do
      Logger.info("Cleaning up expired capabilities", count: expired_count)

      # Remove expired capabilities from all indexes
      expired_ids = Enum.map(expired_capabilities, fn {id, _cap} -> id end)

      updated_principal_capabilities =
        Enum.reduce(state.principal_capabilities, %{}, fn {principal_id, cap_ids}, acc ->
          filtered_caps = cap_ids -- expired_ids

          if filtered_caps == [] do
            acc
          else
            Map.put(acc, principal_id, filtered_caps)
          end
        end)

      updated_delegation_tree =
        Enum.reduce(expired_ids, state.delegation_tree, fn expired_id, acc ->
          Map.delete(acc, expired_id)
        end)

      %{
        state
        | capabilities: Map.new(active_capabilities),
          principal_capabilities: updated_principal_capabilities,
          delegation_tree: updated_delegation_tree,
          last_cleanup: now
      }
    else
      %{state | last_cleanup: now}
    end
  end

  defp count_active_capabilities(state) do
    Enum.count(state.capabilities, fn {_id, capability} ->
      not capability.revoked and Capability.valid?(capability)
    end)
  end

  defp count_delegation_relationships(state) do
    Enum.reduce(state.delegation_tree, 0, fn {_parent, children}, acc ->
      acc + length(children)
    end)
  end

  defp log_audit_event(event, state) do
    event_with_timestamp = Map.put(event, :timestamp, DateTime.utc_now())
    new_buffer = [event_with_timestamp | state.audit_buffer]

    # If buffer is getting large, schedule a flush
    if length(new_buffer) >= 100 do
      Process.send_after(self(), :flush_audit_buffer, 0)
    end

    %{state | audit_buffer: new_buffer}
  end

  defp flush_audit_buffer(state) do
    # Send audit events to the audit logger
    Enum.each(state.audit_buffer, &AuditLogger.log_event(&1.event, Map.delete(&1, :event), "SecurityKernel"))

    %{state | audit_buffer: []}
  end

  defp load_security_policies(_opts) do
    # Load security policies from configuration
    # This would be expanded to load from files, database, etc.
    %{
      filesystem: [
        %{type: :path_restriction, allowed_paths: ["/tmp", "/var/tmp"]},
        %{type: :operation_restriction, allowed_operations: [:read, :write]}
      ],
      mcp_tool: [
        %{type: :tool_whitelist, allowed_tools: ["calculator", "time", "filesystem"]},
        %{type: :rate_limit, max_calls_per_minute: 100}
      ]
    }
  end

  defp apply_security_policy(policy, resource_type, constraints, principal_id) do
    # Simplified policy enforcement - would be expanded based on policy type
    case policy.type do
      :path_restriction ->
        requested_paths = Map.get(constraints, :paths, [])
        allowed_paths = policy.allowed_paths

        if Enum.all?(requested_paths, &path_allowed?(&1, allowed_paths)) do
          :ok
        else
          {:error, :path_not_allowed}
        end

      :operation_restriction ->
        requested_ops = Map.get(constraints, :operations, [])
        allowed_ops = policy.allowed_operations

        if Enum.all?(requested_ops, &(&1 in allowed_ops)) do
          :ok
        else
          {:error, :operation_not_allowed}
        end

      _ ->
        # Unknown policy types are ignored for now
        :ok
    end
  end

  defp path_allowed?(requested_path, allowed_paths) do
    Enum.any?(allowed_paths, &String.starts_with?(requested_path, &1))
  end

  defp schedule_cleanup do
    # Schedule cleanup every 5 minutes
    Process.send_after(self(), :periodic_cleanup, 5 * 60 * 1000)
  end
end
