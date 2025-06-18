defmodule MCPChat.Security.TokenIssuer do
  @moduledoc """
  Issues signed capability tokens for distributed validation.
  Manages token lifecycle and integrates with KeyManager for signing.
  """

  use GenServer
  require Logger

  alias MCPChat.Security.{KeyManager, Capability}

  # Default 1 hour
  @token_lifetime :timer.hours(1)
  @issuer "mcp_chat_security"

  defstruct [
    :signer,
    :default_lifetime,
    :issued_tokens
  ]

  # Client API

  @doc """
  Starts the TokenIssuer GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Issues a new capability token.
  """
  def issue_token(resource_type, operations, resource, principal_id, constraints \\ %{}) do
    GenServer.call(__MODULE__, {
      :issue_token,
      resource_type,
      operations,
      resource,
      principal_id,
      constraints
    })
  end

  @doc """
  Issues a token with a custom TTL.
  """
  def issue_token_with_ttl(resource_type, operations, resource, principal_id, constraints, ttl_seconds) do
    GenServer.call(__MODULE__, {
      :issue_token_with_ttl,
      resource_type,
      operations,
      resource,
      principal_id,
      constraints,
      ttl_seconds
    })
  end

  @doc """
  Issues a delegated token from a parent capability.
  """
  def issue_delegated_token(parent_token, target_principal, additional_constraints \\ %{}) do
    GenServer.call(__MODULE__, {
      :issue_delegated_token,
      parent_token,
      target_principal,
      additional_constraints
    })
  end

  @doc """
  Revokes a token by adding it to the revocation list.
  """
  def revoke_token(jti) do
    GenServer.call(__MODULE__, {:revoke_token, jti})
  end

  @doc """
  Gets statistics about issued tokens.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    lifetime = Keyword.get(opts, :default_lifetime, @token_lifetime)

    # Create Joken signer configuration
    signer = create_signer()

    state = %__MODULE__{
      signer: signer,
      default_lifetime: lifetime,
      issued_tokens: %{}
    }

    Logger.info("TokenIssuer initialized with #{div(lifetime, 1000)}s token lifetime")

    {:ok, state}
  end

  @impl true
  def handle_call({:issue_token, resource_type, operations, resource, principal_id, constraints}, _from, state) do
    # Generate token ID
    jti = generate_jti()

    # Calculate expiration
    now = System.system_time(:second)
    exp = now + div(state.default_lifetime, 1000)
    iat = now

    # Build token claims
    claims = %{
      # Standard JWT claims
      "iss" => @issuer,
      "sub" => to_string(principal_id),
      "aud" => to_string(resource_type),
      "exp" => exp,
      "iat" => iat,
      "jti" => jti,

      # Custom capability claims
      "resource" => resource,
      "operations" => Enum.map(operations, &to_string/1),
      "constraints" => stringify_constraints(constraints),
      "delegation" => %{
        "parent_id" => nil,
        "depth" => 0,
        "max_depth" => constraints[:max_delegation_depth] || 3
      }
    }

    # Sign the token
    case sign_token(claims, state.signer) do
      {:ok, token} when is_binary(token) ->
        # Track issued token
        new_state = track_token(state, jti, claims)

        Logger.debug("Issued token #{jti} for #{principal_id} to access #{resource}")

        {:reply, {:ok, token, jti}, new_state}

      {:ok, token, _claims} ->
        # Handle three-tuple format from Joken
        new_state = track_token(state, jti, claims)

        Logger.debug("Issued token #{jti} for #{principal_id} to access #{resource}")

        {:reply, {:ok, token, jti}, new_state}

      {:error, reason} ->
        Logger.error("Failed to issue token: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(
        {:issue_token_with_ttl, resource_type, operations, resource, principal_id, constraints, ttl_seconds},
        _from,
        state
      ) do
    # Generate token ID
    jti = generate_jti()

    # Calculate expiration based on provided TTL
    now = System.system_time(:second)
    # Use provided TTL instead of default
    exp = now + ttl_seconds
    iat = now

    # Build token claims
    claims = %{
      # Standard JWT claims
      "iss" => @issuer,
      "sub" => to_string(principal_id),
      "aud" => to_string(resource_type),
      "exp" => exp,
      "iat" => iat,
      "jti" => jti,

      # Custom capability claims
      "resource" => resource,
      "operations" => Enum.map(operations, &to_string/1),
      "constraints" => stringify_constraints(constraints),
      "delegation" => %{
        "parent_id" => nil,
        "depth" => 0,
        "max_depth" => constraints[:max_delegation_depth] || 3
      }
    }

    # Sign the token
    case sign_token(claims, state.signer) do
      {:ok, token} when is_binary(token) ->
        # Track issued token
        new_state = track_token(state, jti, claims)

        Logger.debug("Issued token #{jti} for #{principal_id} to access #{resource} (TTL: #{ttl_seconds}s)")

        {:reply, {:ok, token, jti}, new_state}

      {:ok, token, _claims} ->
        # Handle three-tuple format from Joken
        new_state = track_token(state, jti, claims)

        Logger.debug("Issued token #{jti} for #{principal_id} to access #{resource} (TTL: #{ttl_seconds}s)")

        {:reply, {:ok, token, jti}, new_state}

      {:error, reason} ->
        Logger.error("Failed to issue token: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:issue_delegated_token, parent_token, target_principal, additional_constraints}, _from, state) do
    # Decode parent token
    case verify_and_decode_token(parent_token) do
      {:ok, parent_payload} ->
        # Check delegation depth
        parent_depth = get_in(parent_payload, ["delegation", "depth"]) || 0
        max_depth = get_in(parent_payload, ["delegation", "max_depth"]) || 3

        if parent_depth >= max_depth do
          {:reply, {:error, :delegation_depth_exceeded}, state}
        else
          # Generate new token ID
          jti = generate_jti()

          # Calculate expiration (min of parent exp and new lifetime)
          now = System.system_time(:second)
          parent_exp = parent_payload["exp"]
          new_exp = now + div(state.default_lifetime, 1000)
          exp = min(parent_exp, new_exp)

          # Merge constraints (intersection)
          # First normalize the additional_constraints keys to strings to match parent format
          normalized_child_constraints = stringify_constraints(additional_constraints)

          merged_constraints =
            merge_constraints(
              parent_payload["constraints"] || %{},
              normalized_child_constraints
            )

          # Get operations from additional_constraints or inherit from parent
          # Operations should be intersection when specified in child constraints
          parent_operations = parent_payload["operations"] || []

          child_operations =
            case Map.get(normalized_child_constraints, "operations") do
              # No restriction, inherit all
              nil ->
                parent_operations

              ops when is_list(ops) ->
                # Take intersection of parent and child operations
                Enum.filter(ops, &(&1 in parent_operations))

              _ ->
                parent_operations
            end

          # Build delegated token payload
          payload = %{
            # Standard JWT claims
            "iss" => @issuer,
            "sub" => to_string(target_principal),
            "aud" => parent_payload["aud"],
            "exp" => exp,
            "iat" => now,
            "jti" => jti,

            # Inherit from parent
            "resource" => parent_payload["resource"],
            # Use merged operations
            "operations" => child_operations,
            "constraints" => stringify_constraints(merged_constraints),
            "delegation" => %{
              "parent_id" => parent_payload["jti"],
              "depth" => parent_depth + 1,
              "max_depth" => max_depth
            }
          }

          # Sign the token
          case sign_token(payload, state.signer) do
            {:ok, token} when is_binary(token) ->
              # Track issued token
              new_state = track_token(state, jti, payload)

              Logger.debug("Issued delegated token #{jti} from parent #{parent_payload["jti"]}")

              {:reply, {:ok, token, jti}, new_state}

            {:ok, token, _claims} ->
              # Handle three-tuple format from Joken
              new_state = track_token(state, jti, payload)

              Logger.debug("Issued delegated token #{jti} from parent #{parent_payload["jti"]}")

              {:reply, {:ok, token, jti}, new_state}

            {:error, reason} ->
              Logger.error("Failed to issue delegated token: #{inspect(reason)}")
              {:reply, {:error, reason}, state}
          end
        end

      {:error, reason} ->
        {:reply, {:error, {:invalid_parent_token, reason}}, state}
    end
  end

  @impl true
  def handle_call({:revoke_token, jti}, _from, state) do
    # Update the distributed revocation cache
    case MCPChat.Security.RevocationCache.revoke(jti) do
      :ok ->
        Logger.info("Token revoked: #{jti}")

        # Remove from tracked tokens
        new_issued_tokens = Map.delete(state.issued_tokens, jti)

        {:reply, :ok, %{state | issued_tokens: new_issued_tokens}}

      {:error, reason} ->
        Logger.error("Failed to revoke token #{jti}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      tokens_issued: map_size(state.issued_tokens),
      active_tokens: count_active_tokens(state.issued_tokens),
      expired_tokens: count_expired_tokens(state.issued_tokens)
    }

    {:reply, {:ok, stats}, state}
  end

  @impl true
  def handle_info({:cleanup_expired, jti}, state) do
    # Remove expired token from tracking
    new_issued_tokens = Map.delete(state.issued_tokens, jti)
    {:noreply, %{state | issued_tokens: new_issued_tokens}}
  end

  # Private Functions

  defp create_signer do
    # This will be updated dynamically with KeyManager
    # For now, create a static signer
    Joken.Signer.create("RS256", %{"pem" => get_signing_key_pem()})
  end

  defp get_signing_key_pem do
    # Get from KeyManager
    case KeyManager.get_signing_key() do
      {:ok, private_key, _kid} ->
        # Convert to PEM format
        pem_entry = :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
        :public_key.pem_encode([pem_entry])

      _ ->
        # Fallback for testing
        generate_test_key()
    end
  end

  defp generate_test_key do
    # Generate a test key for development
    private_key = :public_key.generate_key({:rsa, 2048, 65537})
    pem_entry = :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
    :public_key.pem_encode([pem_entry])
  end

  defp sign_token(payload, _signer) do
    # Get fresh signer with current key
    signer = create_fresh_signer()

    # Create token configuration
    token_config = Joken.Config.default_claims(skip: [:aud, :iat, :iss, :jti, :exp, :sub, :nbf])

    # Generate and sign token
    Joken.generate_and_sign(token_config, payload, signer)
  end

  defp create_fresh_signer do
    # Always get the current signing key
    case KeyManager.get_signing_key() do
      {:ok, private_key, _kid} ->
        pem_entry = :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
        pem = :public_key.pem_encode([pem_entry])
        Joken.Signer.create("RS256", %{"pem" => pem})

      _ ->
        # Fallback
        private_key = :public_key.generate_key({:rsa, 2048, 65537})
        pem_entry = :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
        pem = :public_key.pem_encode([pem_entry])
        Joken.Signer.create("RS256", %{"pem" => pem})
    end
  end

  defp verify_and_decode_token(token) do
    # Get verification keys from KeyManager
    case KeyManager.get_verification_keys() do
      {:ok, public_keys} ->
        # Try to verify with each key
        Enum.find_value(public_keys, {:error, :invalid_signature}, fn {_kid, public_key} ->
          signer = create_verifier(public_key)

          # Create token configuration
          token_config = Joken.Config.default_claims(skip: [:aud, :iat, :iss, :jti, :exp, :sub, :nbf])

          case Joken.verify_and_validate(token_config, token, signer) do
            {:ok, claims} -> {:ok, claims}
            _ -> nil
          end
        end)

      _ ->
        {:error, :no_verification_keys}
    end
  end

  defp create_verifier(public_key) do
    # Convert public key to PEM
    pem_entry = :public_key.pem_entry_encode(:RSAPublicKey, public_key)
    pem = :public_key.pem_encode([pem_entry])

    Joken.Signer.create("RS256", %{"pem" => pem})
  end

  defp generate_jti do
    # Generate unique token ID
    "cap_" <> generate_uuid4()
  end

  defp generate_uuid4 do
    # Simple UUID v4 generation
    <<a1::48, _::4, a2::12, _::2, a3::62>> = :crypto.strong_rand_bytes(16)

    hex =
      <<a1::48, 4::4, a2::12, 2::2, a3::62>>
      |> Base.encode16(case: :lower)

    String.slice(hex, 0..7) <>
      "-" <>
      String.slice(hex, 8..11) <>
      "-" <>
      String.slice(hex, 12..15) <>
      "-" <>
      String.slice(hex, 16..19) <>
      "-" <>
      String.slice(hex, 20..31)
  end

  defp track_token(state, jti, payload) do
    # Schedule cleanup after expiration
    exp = payload["exp"]
    now = System.system_time(:second)
    cleanup_after = max(0, (exp - now) * 1000)

    Process.send_after(self(), {:cleanup_expired, jti}, cleanup_after)

    # Track token
    new_issued_tokens = Map.put(state.issued_tokens, jti, payload)

    %{state | issued_tokens: new_issued_tokens}
  end

  defp merge_constraints(parent_constraints, child_constraints) do
    # Take the intersection of constraints (most restrictive)
    Map.merge(parent_constraints, child_constraints, fn key, parent_val, child_val ->
      case key do
        # Special handling for paths - child paths must be subpaths of parent paths
        "paths" when is_list(parent_val) and is_list(child_val) ->
          # Child paths should be kept if they are subpaths of any parent path
          Enum.filter(child_val, fn child_path ->
            Enum.any?(parent_val, fn parent_path ->
              String.starts_with?(child_path, parent_path)
            end)
          end)

        # For other lists, take intersection
        _ when is_list(parent_val) and is_list(child_val) ->
          Enum.filter(child_val, &(&1 in parent_val))

        _ when is_integer(parent_val) and is_integer(child_val) ->
          # For numbers, take the minimum (most restrictive)
          min(parent_val, child_val)

        _ ->
          # Default to child value
          child_val
      end
    end)
  end

  defp count_active_tokens(tokens) do
    now = System.system_time(:second)

    Enum.count(tokens, fn {_jti, payload} ->
      payload["exp"] > now
    end)
  end

  defp count_expired_tokens(tokens) do
    now = System.system_time(:second)

    Enum.count(tokens, fn {_jti, payload} ->
      payload["exp"] <= now
    end)
  end

  defp stringify_constraints(constraints) do
    # Convert atom keys and values to strings for JWT serialization
    Enum.into(constraints, %{}, fn {k, v} ->
      key = to_string(k)

      value =
        case v do
          atom when is_atom(atom) ->
            to_string(atom)

          list when is_list(list) ->
            Enum.map(list, fn
              item when is_atom(item) -> to_string(item)
              item -> item
            end)

          other ->
            other
        end

      {key, value}
    end)
  end
end
