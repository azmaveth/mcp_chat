defmodule MCPChat.Security.Capability do
  @moduledoc """
  Represents a security capability in the MCP Chat capability-based security system.

  A capability is a permission token that grants specific access rights to resources.
  Capabilities can be delegated to other principals with additional constraints.

  ## Fields

  - `id`: Unique identifier for the capability
  - `resource_type`: Type of resource this capability grants access to
  - `constraints`: Map of constraints limiting the capability's usage
  - `principal_id`: The principal that owns this capability
  - `parent_id`: ID of the parent capability if this was delegated
  - `issued_at`: When the capability was created
  - `expires_at`: When the capability expires (optional)
  - `delegation_depth`: How many times this capability has been delegated
  - `revoked`: Whether this capability has been revoked
  - `signature`: Cryptographic signature to prevent tampering
  """

  @type t :: %__MODULE__{
          id: String.t(),
          resource_type: atom(),
          constraints: map(),
          principal_id: String.t(),
          parent_id: String.t() | nil,
          issued_at: DateTime.t(),
          expires_at: DateTime.t() | nil,
          delegation_depth: non_neg_integer(),
          revoked: boolean(),
          signature: String.t()
        }

  @derive {Jason.Encoder, except: [:signature]}
  defstruct [
    :id,
    :resource_type,
    :constraints,
    :principal_id,
    :parent_id,
    :issued_at,
    :expires_at,
    :delegation_depth,
    :revoked,
    :signature
  ]

  @doc """
  Creates a new capability with the specified parameters.

  ## Parameters
  - `resource_type`: The type of resource this capability grants access to
  - `constraints`: Map of constraints for this capability
  - `principal_id`: The principal that will own this capability
  - `parent_id`: Optional parent capability ID if this is being delegated

  ## Returns
  - `{:ok, capability}` on success
  - `{:error, reason}` on failure
  """
  @spec create(atom(), map(), String.t(), String.t() | nil) :: {:ok, t()} | {:error, atom()}
  def create(resource_type, constraints, principal_id, parent_id \\ nil) do
    now = DateTime.utc_now()
    capability_id = generate_capability_id()

    # Will be adjusted by parent lookup
    delegation_depth = if parent_id, do: 1, else: 0

    capability = %__MODULE__{
      id: capability_id,
      resource_type: resource_type,
      constraints: constraints,
      principal_id: principal_id,
      parent_id: parent_id,
      issued_at: now,
      expires_at: Map.get(constraints, :expires_at),
      delegation_depth: delegation_depth,
      revoked: false,
      # Will be set after creation
      signature: nil
    }

    # Generate signature for integrity protection
    case sign_capability(capability) do
      {:ok, signature} ->
        {:ok, %{capability | signature: signature}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Validates that a capability is properly formed and has a valid signature.

  ## Parameters
  - `capability`: The capability to validate

  ## Returns
  - `:ok` if valid
  - `{:error, reason}` if invalid
  """
  @spec validate(t()) :: :ok | {:error, atom()}
  def validate(%__MODULE__{} = capability) do
    with :ok <- validate_structure(capability),
         :ok <- validate_signature(capability),
         :ok <- validate_expiration(capability),
         :ok <- validate_constraints(capability) do
      :ok
    end
  end

  @doc """
  Checks if a capability is currently valid for use.

  This includes checking expiration, revocation status, and basic validation.

  ## Parameters
  - `capability`: The capability to check

  ## Returns
  - `true` if the capability is valid
  - `false` if the capability is invalid
  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = capability) do
    case validate(capability) do
      :ok -> not capability.revoked
      {:error, _} -> false
    end
  end

  @doc """
  Checks if a capability has expired.

  ## Parameters
  - `capability`: The capability to check

  ## Returns
  - `true` if expired
  - `false` if not expired or no expiration set
  """
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{expires_at: nil}), do: false

  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Checks if a capability can be delegated based on its constraints.

  ## Parameters
  - `capability`: The capability to check

  ## Returns
  - `true` if delegation is allowed
  - `false` if delegation is not allowed
  """
  @spec delegatable?(t()) :: boolean()
  def delegatable?(%__MODULE__{} = capability) do
    max_delegations = Map.get(capability.constraints, :max_delegations, :unlimited)

    case max_delegations do
      :unlimited -> true
      0 -> false
      max when is_integer(max) -> capability.delegation_depth < max
      _ -> false
    end
  end

  @doc """
  Creates a delegated capability with additional constraints.

  The new capability inherits all constraints from the parent and applies
  additional constraints that are more restrictive.

  ## Parameters
  - `parent_capability`: The capability being delegated
  - `target_principal`: The principal receiving the delegated capability
  - `additional_constraints`: Additional constraints to apply

  ## Returns
  - `{:ok, delegated_capability}` on success
  - `{:error, reason}` on failure
  """
  @spec delegate(t(), String.t(), map()) :: {:ok, t()} | {:error, atom()}
  def delegate(%__MODULE__{} = parent_capability, target_principal, additional_constraints \\ %{}) do
    with :ok <- validate(parent_capability),
         true <- valid?(parent_capability),
         true <- delegatable?(parent_capability) do
      # Merge constraints, applying intersection where applicable
      merged_constraints = merge_constraints(parent_capability.constraints, additional_constraints)

      # Calculate correct delegation depth before creating capability
      correct_delegation_depth = parent_capability.delegation_depth + 1

      create(
        parent_capability.resource_type,
        merged_constraints,
        target_principal,
        parent_capability.id
      )
      |> case do
        {:ok, delegated_capability} ->
          # Update delegation depth with the correct value and re-sign
          updated_capability = %{delegated_capability | delegation_depth: correct_delegation_depth}

          case sign_capability(%{updated_capability | signature: nil}) do
            {:ok, new_signature} ->
              {:ok, %{updated_capability | signature: new_signature}}

            {:error, reason} ->
              {:error, reason}
          end

        error ->
          error
      end
    else
      false -> {:error, :delegation_not_allowed}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Marks a capability as revoked.

  ## Parameters
  - `capability`: The capability to revoke

  ## Returns
  - The revoked capability
  """
  @spec revoke(t()) :: t()
  def revoke(%__MODULE__{} = capability) do
    %{capability | revoked: true}
  end

  @doc """
  Converts a capability to a compact string representation for logging.

  ## Parameters
  - `capability`: The capability to summarize

  ## Returns
  - String summary of the capability
  """
  @spec to_summary(t()) :: String.t()
  def to_summary(%__MODULE__{} = capability) do
    "#{capability.resource_type}:#{String.slice(capability.id, 0, 8)}:#{capability.principal_id}"
  end

  @doc """
  Checks if a capability permits a specific operation on a resource.

  ## Parameters
  - `capability`: The capability to check
  - `operation`: The operation being attempted
  - `resource`: The specific resource being accessed

  ## Returns
  - `:ok` if the operation is permitted
  - `{:error, reason}` if the operation is not permitted
  """
  @spec permits?(t(), atom(), String.t()) :: :ok | {:error, atom()}
  def permits?(%__MODULE__{} = capability, operation, resource) do
    with :ok <- validate(capability),
         true <- valid?(capability),
         :ok <- check_operation_allowed(capability, operation),
         :ok <- check_resource_allowed(capability, resource) do
      :ok
    else
      false -> {:error, :capability_invalid}
      {:error, reason} -> {:error, reason}
    end
  end

  ## Private Functions

  defp generate_capability_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  defp sign_capability(%__MODULE__{} = capability) do
    # Create a signable representation of the capability
    signable_data = %{
      id: capability.id,
      resource_type: capability.resource_type,
      constraints: capability.constraints,
      principal_id: capability.principal_id,
      parent_id: capability.parent_id,
      issued_at: capability.issued_at,
      delegation_depth: capability.delegation_depth
    }

    # Convert to deterministic binary representation
    binary_data = :erlang.term_to_binary(signable_data, [:deterministic])

    # Generate HMAC signature using application secret
    secret = get_signing_secret()

    signature =
      :crypto.mac(:hmac, :sha256, secret, binary_data)
      |> Base.encode64()

    {:ok, signature}
  end

  defp validate_structure(%__MODULE__{
         id: id,
         resource_type: resource_type,
         constraints: constraints,
         principal_id: principal_id,
         issued_at: issued_at
       })
       when is_binary(id) and is_atom(resource_type) and is_map(constraints) and
              is_binary(principal_id) and is_struct(issued_at, DateTime) do
    :ok
  end

  defp validate_structure(_), do: {:error, :invalid_capability_structure}

  defp validate_signature(%__MODULE__{signature: nil}), do: {:error, :missing_signature}

  defp validate_signature(%__MODULE__{} = capability) do
    case sign_capability(%{capability | signature: nil}) do
      {:ok, expected_signature} ->
        if expected_signature == capability.signature do
          :ok
        else
          {:error, :invalid_signature}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_expiration(%__MODULE__{expires_at: nil}), do: :ok

  defp validate_expiration(%__MODULE__{expires_at: expires_at}) do
    # First validate that expires_at is a proper DateTime
    case expires_at do
      %DateTime{} ->
        if expired?(%__MODULE__{expires_at: expires_at}) do
          {:error, :capability_expired}
        else
          :ok
        end

      _ ->
        {:error, :invalid_expires_at_constraint}
    end
  end

  defp validate_constraints(%__MODULE__{constraints: constraints}) do
    # Basic constraint validation
    Enum.reduce_while(constraints, :ok, fn {key, value}, :ok ->
      case validate_constraint(key, value) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_constraint(:expires_at, %DateTime{}), do: :ok
  defp validate_constraint(:expires_at, _), do: {:error, :invalid_expires_at_constraint}
  defp validate_constraint(:operations, ops) when is_list(ops), do: :ok
  defp validate_constraint(:operations, _), do: {:error, :invalid_operations_constraint}
  defp validate_constraint(:paths, paths) when is_list(paths), do: :ok
  defp validate_constraint(:paths, _), do: {:error, :invalid_paths_constraint}
  defp validate_constraint(:allowed_tools, tools) when is_list(tools), do: :ok
  defp validate_constraint(:allowed_tools, _), do: {:error, :invalid_allowed_tools_constraint}
  defp validate_constraint(:max_delegations, n) when is_integer(n) and n >= 0, do: :ok
  defp validate_constraint(:max_delegations, :unlimited), do: :ok
  defp validate_constraint(:max_delegations, _), do: {:error, :invalid_max_delegations_constraint}
  # Allow unknown constraints for extensibility
  defp validate_constraint(_, _), do: :ok

  defp merge_constraints(parent_constraints, additional_constraints) do
    # Apply constraint intersection logic
    Enum.reduce(additional_constraints, parent_constraints, fn {key, value}, acc ->
      case key do
        :operations ->
          # Intersection of allowed operations
          parent_ops = Map.get(acc, :operations, [])
          intersected_ops = if parent_ops == [], do: value, else: parent_ops -- (parent_ops -- value)
          Map.put(acc, key, intersected_ops)

        :paths ->
          # Intersection of allowed paths (more complex logic needed for path hierarchies)
          parent_paths = Map.get(acc, :paths, [])
          intersected_paths = if parent_paths == [], do: value, else: intersect_paths(parent_paths, value)
          Map.put(acc, key, intersected_paths)

        :allowed_tools ->
          # Intersection of allowed tools
          parent_tools = Map.get(acc, :allowed_tools, [])
          intersected_tools = if parent_tools == [], do: value, else: parent_tools -- (parent_tools -- value)
          Map.put(acc, key, intersected_tools)

        :expires_at ->
          # Use the earlier expiration time
          parent_expires = Map.get(acc, :expires_at)
          earlier_expires = if parent_expires == nil, do: value, else: Enum.min([parent_expires, value], DateTime)
          Map.put(acc, key, earlier_expires)

        :max_delegations ->
          # Use the lower delegation limit
          parent_max = Map.get(acc, :max_delegations, :unlimited)
          lower_max = min_delegations(parent_max, value)
          Map.put(acc, key, lower_max)

        _ ->
          # For other constraints, the additional constraint overrides
          Map.put(acc, key, value)
      end
    end)
  end

  defp intersect_paths(parent_paths, additional_paths) do
    # Simplified path intersection - in practice, this would need more sophisticated logic
    # to handle path hierarchies and wildcards
    additional_paths
    |> Enum.filter(fn path ->
      Enum.any?(parent_paths, fn parent_path ->
        String.starts_with?(path, parent_path) or String.starts_with?(parent_path, path)
      end)
    end)
  end

  defp min_delegations(:unlimited, other), do: other
  defp min_delegations(other, :unlimited), do: other
  defp min_delegations(a, b) when is_integer(a) and is_integer(b), do: min(a, b)

  defp check_operation_allowed(%__MODULE__{constraints: constraints}, operation) do
    case Map.get(constraints, :operations) do
      # No operation constraints
      nil ->
        :ok

      allowed_operations when is_list(allowed_operations) ->
        if operation in allowed_operations do
          :ok
        else
          {:error, :operation_not_permitted}
        end

      _ ->
        {:error, :invalid_operation_constraint}
    end
  end

  defp check_resource_allowed(%__MODULE__{constraints: constraints, resource_type: resource_type}, resource) do
    case resource_type do
      :filesystem ->
        # Check path constraints for filesystem resources
        case Map.get(constraints, :paths) do
          # No path constraints
          nil ->
            :ok

          allowed_paths when is_list(allowed_paths) ->
            if Enum.any?(allowed_paths, &path_matches?(&1, resource)) do
              :ok
            else
              {:error, :resource_not_permitted}
            end

          _ ->
            {:error, :invalid_path_constraint}
        end

      :mcp_tool ->
        # Check tool constraints for MCP tool resources
        case Map.get(constraints, :allowed_tools) do
          # No tool constraints
          nil ->
            :ok

          allowed_tools when is_list(allowed_tools) ->
            if resource in allowed_tools do
              :ok
            else
              {:error, :resource_not_permitted}
            end

          _ ->
            {:error, :invalid_tool_constraint}
        end

      _ ->
        # For other resource types, check paths if available, otherwise allow
        case Map.get(constraints, :paths) do
          nil ->
            :ok

          allowed_paths when is_list(allowed_paths) ->
            if Enum.any?(allowed_paths, &path_matches?(&1, resource)) do
              :ok
            else
              {:error, :resource_not_permitted}
            end

          _ ->
            :ok
        end
    end
  end

  defp path_matches?(allowed_path, resource_path) do
    # Simplified path matching - in practice, this would handle wildcards, etc.
    String.starts_with?(resource_path, allowed_path)
  end

  defp get_signing_secret do
    Application.get_env(:mcp_chat, :security_signing_secret) ||
      System.get_env("MCP_CHAT_SECURITY_SECRET") ||
      "default_development_secret_change_in_production"
  end
end
