defmodule MCPChat.Security.KeyManager do
  @moduledoc """
  Manages cryptographic keys for JWT signing and verification.
  Handles key generation, rotation, and secure storage.
  """

  use GenServer
  require Logger

  @key_size 2048
  # 30 days
  @key_rotation_interval :timer.hours(24 * 30)
  # 1 day overlap
  @key_overlap_period :timer.hours(24)

  defstruct [
    :current_key,
    :current_kid,
    :previous_key,
    :previous_kid,
    :public_keys,
    :rotation_timer
  ]

  # Client API

  @doc """
  Starts the KeyManager GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current signing key.
  """
  def get_signing_key do
    GenServer.call(__MODULE__, :get_signing_key)
  end

  @doc """
  Gets all public keys for verification (current and previous).
  """
  def get_verification_keys do
    GenServer.call(__MODULE__, :get_verification_keys)
  end

  @doc """
  Gets a specific public key by key ID.
  """
  def get_public_key(kid) do
    GenServer.call(__MODULE__, {:get_public_key, kid})
  end

  @doc """
  Manually triggers key rotation.
  """
  def rotate_keys do
    GenServer.call(__MODULE__, :rotate_keys)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Generate initial key pair
    {private_key, public_key, kid} = generate_key_pair()

    state = %__MODULE__{
      current_key: private_key,
      current_kid: kid,
      previous_key: nil,
      previous_kid: nil,
      public_keys: %{kid => public_key}
    }

    # Schedule key rotation
    timer = Process.send_after(self(), :rotate_keys, @key_rotation_interval)

    Logger.info("KeyManager initialized with key ID: #{kid}")

    {:ok, %{state | rotation_timer: timer}}
  end

  @impl true
  def handle_call(:get_signing_key, _from, state) do
    {:reply, {:ok, state.current_key, state.current_kid}, state}
  end

  @impl true
  def handle_call(:get_verification_keys, _from, state) do
    {:reply, {:ok, state.public_keys}, state}
  end

  @impl true
  def handle_call({:get_public_key, kid}, _from, state) do
    case Map.get(state.public_keys, kid) do
      nil -> {:reply, {:error, :key_not_found}, state}
      key -> {:reply, {:ok, key}, state}
    end
  end

  @impl true
  def handle_call(:rotate_keys, _from, state) do
    new_state = perform_key_rotation(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:rotate_keys, state) do
    new_state = perform_key_rotation(state)

    # Schedule next rotation
    timer = Process.send_after(self(), :rotate_keys, @key_rotation_interval)

    {:noreply, %{new_state | rotation_timer: timer}}
  end

  @impl true
  def handle_info(:remove_old_key, state) do
    # Remove the previous key after overlap period
    new_public_keys = Map.delete(state.public_keys, state.previous_kid)

    Logger.info("Removed old key: #{state.previous_kid}")

    {:noreply, %{state | previous_key: nil, previous_kid: nil, public_keys: new_public_keys}}
  end

  # Private Functions

  defp generate_key_pair do
    # Generate RSA key pair
    private_key = :public_key.generate_key({:rsa, @key_size, 65537})
    public_key = extract_public_key(private_key)

    # Generate key ID (kid)
    kid = generate_kid()

    {private_key, public_key, kid}
  end

  defp extract_public_key({:RSAPrivateKey, _, modulus, public_exponent, _, _, _, _, _, _, _}) do
    {:RSAPublicKey, modulus, public_exponent}
  end

  defp generate_kid do
    # Generate a unique key ID
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end

  defp perform_key_rotation(state) do
    # Generate new key pair
    {new_private_key, new_public_key, new_kid} = generate_key_pair()

    # Update public keys map
    new_public_keys = Map.put(state.public_keys, new_kid, new_public_key)

    # Schedule removal of old key after overlap period
    if state.previous_kid do
      Process.send_after(self(), :remove_old_key, @key_overlap_period)
    end

    Logger.info("Rotated keys. New key ID: #{new_kid}, Previous: #{state.current_kid}")

    %{
      state
      | current_key: new_private_key,
        current_kid: new_kid,
        previous_key: state.current_key,
        previous_kid: state.current_kid,
        public_keys: new_public_keys
    }
  end

  @doc """
  Exports public keys in JWK format for external verification.
  """
  def export_jwks do
    {:ok, public_keys} = get_verification_keys()

    keys =
      Enum.map(public_keys, fn {kid, {:RSAPublicKey, n, e}} ->
        %{
          "kty" => "RSA",
          "kid" => kid,
          "use" => "sig",
          "alg" => "RS256",
          "n" => Base.url_encode64(:binary.encode_unsigned(n), padding: false),
          "e" => Base.url_encode64(:binary.encode_unsigned(e), padding: false)
        }
      end)

    %{"keys" => keys}
  end
end
