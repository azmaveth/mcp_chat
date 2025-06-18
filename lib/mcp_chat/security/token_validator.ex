defmodule MCPChat.Security.TokenValidator do
  @moduledoc """
  Validates capability tokens locally without SecurityKernel round-trip.
  Checks signatures, expiration, revocation status, and permissions.
  """

  require Logger

  alias MCPChat.Security.{KeyManager, RevocationCache, ViolationMonitor}

  # 5 minutes in seconds
  @clock_skew_tolerance 300

  @doc """
  Validates a token for a specific operation and resource.
  Returns {:ok, claims} if valid, {:error, reason} otherwise.
  """
  def validate_token(token, operation, resource) do
    with {:ok, claims} <- verify_signature(token),
         :ok <- check_expiration(claims),
         :ok <- check_revocation(claims["jti"]),
         :ok <- check_permissions(claims, operation, resource) do
      {:ok, claims}
    else
      {:error, reason} = error ->
        Logger.debug("Token validation failed: #{inspect(reason)}")

        # Record violation
        case reason do
          :token_expired ->
            ViolationMonitor.record_violation(:expired_token, %{
              operation: operation,
              resource: resource
            })

          :token_revoked ->
            ViolationMonitor.record_violation(:revoked_token, %{
              operation: operation,
              resource: resource
            })

          {:operation_not_permitted, op} ->
            ViolationMonitor.record_violation(:unauthorized_operation, %{
              operation: op,
              resource: resource
            })

          {:resource_not_permitted, res} ->
            ViolationMonitor.record_violation(:unauthorized_resource, %{
              operation: operation,
              resource: res
            })

          _ ->
            ViolationMonitor.record_violation(:invalid_capability, %{
              reason: reason,
              operation: operation,
              resource: resource
            })
        end

        error
    end
  end

  @doc """
  Validates a token without checking specific permissions.
  Useful for token introspection.
  """
  def validate_token_structure(token) do
    with {:ok, claims} <- verify_signature(token),
         :ok <- check_expiration(claims),
         :ok <- check_revocation(claims["jti"]) do
      {:ok, claims}
    end
  end

  @doc """
  Extracts claims from a token without full validation.
  WARNING: Only use for non-security-critical operations.
  """
  def peek_claims(token) do
    case Joken.peek_claims(token) do
      {:ok, claims} -> {:ok, claims}
      _ -> {:error, :invalid_token_format}
    end
  end

  @doc """
  Checks if a token is expired without full validation.
  """
  def is_expired?(token) do
    case peek_claims(token) do
      {:ok, claims} ->
        check_expiration(claims) != :ok

      _ ->
        true
    end
  end

  # Private Functions

  defp verify_signature(token) do
    # Get verification keys from KeyManager
    case KeyManager.get_verification_keys() do
      {:ok, public_keys} ->
        # Try to verify with each key
        result =
          Enum.find_value(public_keys, {:error, :invalid_signature}, fn {_kid, public_key} ->
            signer = create_verifier(public_key)

            # Create token configuration with our custom claims
            token_config = Joken.Config.default_claims(skip: [:aud, :iat, :iss, :jti, :exp, :sub])

            case Joken.verify_and_validate(token_config, token, signer) do
              {:ok, claims} ->
                # Additional validation of required claims
                if validate_required_claims(claims) do
                  {:ok, claims}
                else
                  {:error, :missing_required_claims}
                end

              {:error, _} ->
                # Try next key
                nil
            end
          end)

        result

      {:error, reason} ->
        {:error, {:key_retrieval_failed, reason}}
    end
  end

  defp create_verifier(public_key) do
    # Convert public key to PEM
    pem_entry = :public_key.pem_entry_encode(:RSAPublicKey, public_key)
    pem = :public_key.pem_encode([pem_entry])

    Joken.Signer.create("RS256", %{"pem" => pem})
  end

  defp check_expiration(claims) do
    now = System.system_time(:second)
    exp = claims["exp"]
    iat = claims["iat"]

    cond do
      # Check if token is expired (exp is in the past)
      exp && exp < now ->
        {:error, :token_expired}

      # Check if token is used before issued (clock skew)
      iat && iat > now + @clock_skew_tolerance ->
        {:error, :token_used_before_issued}

      true ->
        :ok
    end
  end

  defp check_revocation(jti) do
    # Check with RevocationCache
    if RevocationCache.is_revoked?(jti) do
      {:error, :token_revoked}
    else
      :ok
    end
  end

  defp check_permissions(claims, operation, resource) do
    # Extract permission data from claims
    allowed_operations = claims["operations"] || []
    allowed_resource = claims["resource"]
    constraints = claims["constraints"] || %{}

    # Convert operation to string for comparison
    operation_str = to_string(operation)

    # Check operation permission
    unless operation_str in allowed_operations do
      {:error, {:operation_not_permitted, operation}}
    else
      # Check resource permission
      unless resource_matches?(allowed_resource, resource, constraints) do
        {:error, {:resource_not_permitted, resource}}
      else
        # Check additional constraints
        check_constraints(constraints, operation, resource)
      end
    end
  end

  defp resource_matches?(allowed_pattern, actual_resource, constraints) do
    cond do
      # Exact match
      allowed_pattern == actual_resource ->
        true

      # Wildcard pattern matching
      String.contains?(allowed_pattern, "*") ->
        if pattern_matches?(allowed_pattern, actual_resource) do
          # Also check paths constraint if present
          check_paths_constraint(actual_resource, constraints)
        else
          false
        end

      # Path prefix matching for filesystem resources
      Map.has_key?(constraints, "path_prefix") ->
        String.starts_with?(actual_resource, constraints["path_prefix"])

      # Default: check paths constraint
      true ->
        check_paths_constraint(actual_resource, constraints)
    end
  end

  defp check_paths_constraint(resource, constraints) do
    case Map.get(constraints, "paths") do
      # No paths constraint
      nil ->
        true

      paths when is_list(paths) ->
        # Check if resource starts with any allowed path
        Enum.any?(paths, fn path ->
          String.starts_with?(resource, path)
        end)

      _ ->
        true
    end
  end

  defp pattern_matches?(pattern, resource) do
    # Convert wildcard pattern to regex
    # Handle ** before * to avoid conflicts
    regex_pattern =
      pattern
      |> String.replace(".", "\\.")
      # Temporary placeholder
      |> String.replace("**", "@@DOUBLE_STAR@@")
      # Single star matches within path segment
      |> String.replace("*", "[^/]*")
      # Double star matches across path segments
      |> String.replace("@@DOUBLE_STAR@@", ".*")

    case Regex.compile("^#{regex_pattern}$") do
      {:ok, regex} -> Regex.match?(regex, resource)
      _ -> false
    end
  end

  defp check_constraints(constraints, operation, resource) do
    Enum.reduce_while(constraints, :ok, fn {key, value}, _acc ->
      case check_constraint(key, value, operation, resource) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp check_constraint("max_file_size", max_size, "write", _resource) when is_integer(max_size) do
    # This would be checked at execution time with actual file size
    :ok
  end

  defp check_constraint("allowed_extensions", extensions, _operation, resource) when is_list(extensions) do
    ext = Path.extname(resource)

    if ext in extensions do
      :ok
    else
      {:error, {:extension_not_allowed, ext}}
    end
  end

  defp check_constraint("rate_limit", _limit, _operation, _resource) do
    # Rate limiting would be enforced at execution time
    :ok
  end

  defp check_constraint("time_window", %{"start" => start_time, "end" => end_time}, _operation, _resource) do
    now = System.system_time(:second)

    if now >= start_time && now <= end_time do
      :ok
    else
      {:error, :outside_time_window}
    end
  end

  defp check_constraint(_key, _value, _operation, _resource) do
    # Unknown constraints are ignored for forward compatibility
    :ok
  end

  defp validate_required_claims(claims) do
    required_claims = ["iss", "sub", "aud", "exp", "iat", "jti", "resource", "operations"]
    Enum.all?(required_claims, &Map.has_key?(claims, &1))
  end

  @doc """
  Validates a token's delegation chain.
  """
  def validate_delegation_chain(token) do
    case validate_token_structure(token) do
      {:ok, claims} ->
        delegation = claims["delegation"] || %{}
        depth = delegation["depth"] || 0
        max_depth = delegation["max_depth"] || 3

        if depth <= max_depth do
          {:ok,
           %{
             depth: depth,
             max_depth: max_depth,
             parent_id: delegation["parent_id"]
           }}
        else
          {:error, :delegation_depth_exceeded}
        end

      error ->
        error
    end
  end

  # Cache for validated tokens to improve performance.
  # Tokens are cached for a short duration after validation.
  defmodule Cache do
    use GenServer

    # 30 seconds
    @cache_ttl :timer.seconds(30)

    def start_link(_opts) do
      GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
    end

    def get(token_hash) do
      GenServer.call(__MODULE__, {:get, token_hash})
    end

    def put(token_hash, result) do
      GenServer.cast(__MODULE__, {:put, token_hash, result})
    end

    @impl true
    def init(_) do
      {:ok, %{}}
    end

    @impl true
    def handle_call({:get, token_hash}, _from, cache) do
      now = System.monotonic_time(:millisecond)

      case Map.get(cache, token_hash) do
        {result, expiry} when expiry > now ->
          {:reply, {:ok, result}, cache}

        _ ->
          {:reply, :miss, cache}
      end
    end

    @impl true
    def handle_cast({:put, token_hash, result}, cache) do
      expiry = System.monotonic_time(:millisecond) + @cache_ttl
      {:noreply, Map.put(cache, token_hash, {result, expiry})}
    end

    @impl true
    def handle_info(:cleanup, cache) do
      now = System.monotonic_time(:millisecond)

      cleaned =
        Enum.filter(cache, fn {_hash, {_result, expiry}} ->
          expiry > now
        end)
        |> Enum.into(%{})

      Process.send_after(self(), :cleanup, @cache_ttl)
      {:noreply, cleaned}
    end
  end
end
