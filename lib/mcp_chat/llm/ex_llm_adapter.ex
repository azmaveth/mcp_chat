defmodule MCPChat.LLM.ExLLMAdapter do
  @moduledoc """
  Adapter that wraps ExLLM to work with MCPChat's LLM.Adapter interface.

  This adapter allows mcp_chat to use the ex_llm library while maintaining
  compatibility with the existing MCPChat.LLM.Adapter behavior.
  """

  @behaviour MCPChat.LLM.Adapter

  require Logger

  alias ExLLM.{ConfigProvider, StreamRecovery}
  alias ExLLM.Local.{EXLAConfig, ModelLoader}

  @doc """
  Initialize the adapter with configuration from mcp_chat's config system.
  """
  def configure(config) do
    # For ExLLM, configuration is handled through environment variables
    # or config providers, so we just validate that the config is reasonable
    case validate_config(config) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Invalid configuration: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl MCPChat.LLM.Adapter
  def chat(messages, options \\ []) do
    # Convert MCPChat message format to ExLLM format
    ex_llm_messages = convert_messages(messages)

    # Extract provider and options
    {provider, ex_llm_options} = extract_options(options)

    # Add config provider to options
    ex_llm_options = [{:config_provider, ConfigProvider.Env} | ex_llm_options]

    # Add caching options if enabled
    ex_llm_options = maybe_add_caching_options(ex_llm_options, options)

    # Apply context truncation if enabled
    ex_llm_messages = maybe_truncate_messages(ex_llm_messages, provider, ex_llm_options, options)

    # Call ExLLM through ExLLM's circuit breaker
    circuit_name = "llm_#{provider}"

    circuit_opts = [
      failure_threshold: 3,
      reset_timeout: 60_000,
      timeout: 30_000
    ]

    case ExLLM.CircuitBreaker.call(
           circuit_name,
           fn ->
             ExLLM.chat(provider, ex_llm_messages, ex_llm_options)
           end,
           circuit_opts
         ) do
      {:ok, response} ->
        {:ok, convert_response(response)}

      {:error, :circuit_open} ->
        {:error, "LLM service temporarily unavailable (circuit breaker open)"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl MCPChat.LLM.Adapter
  def stream_chat(messages, options \\ []) do
    # Convert MCPChat message format to ExLLM format
    ex_llm_messages = convert_messages(messages)

    # Extract provider and options
    {provider, ex_llm_options} = extract_options(options)

    # Add config provider to options
    ex_llm_options = [{:config_provider, ConfigProvider.Env} | ex_llm_options]

    # Apply context truncation if enabled
    ex_llm_messages = maybe_truncate_messages(ex_llm_messages, provider, ex_llm_options, options)

    # Add enhanced streaming options from ExLLM
    ex_llm_options = maybe_add_streaming_options(ex_llm_options, options)

    # Add recovery options if requested
    ex_llm_options = maybe_add_recovery_options(ex_llm_options, options)

    # Call ExLLM streaming through ExLLM's circuit breaker
    circuit_name = "llm_#{provider}"

    circuit_opts = [
      failure_threshold: 3,
      reset_timeout: 60_000,
      timeout: 30_000
    ]

    case ExLLM.CircuitBreaker.call(
           circuit_name,
           fn ->
             ExLLM.stream_chat(provider, ex_llm_messages, ex_llm_options)
           end,
           circuit_opts
         ) do
      {:ok, {:ok, stream}} ->
        # Use ExLLM's enhanced streaming infrastructure
        enhanced_stream = create_enhanced_stream(stream, ex_llm_options, options)

        # Store recovery ID if recovery is enabled
        if recovery_id = Keyword.get(ex_llm_options, :recovery_id) do
          {:ok, enhanced_stream, recovery_id}
        else
          {:ok, enhanced_stream}
        end

      {:ok, {:error, reason}} ->
        {:error, reason}

      {:error, :circuit_open} ->
        {:error, "LLM service temporarily unavailable (circuit breaker open)"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl MCPChat.LLM.Adapter
  def configured? do
    # Check if at least one provider is configured
    options = [{:config_provider, ExLLM.ConfigProvider.Env}]
    ExLLM.configured?(:anthropic, options) or ExLLM.configured?(:openai, options) or ExLLM.configured?(:ollama, options)
  end

  def configured?(provider_name) when is_binary(provider_name) do
    provider_atom = String.to_atom(provider_name)
    options = [{:config_provider, ExLLM.ConfigProvider.Env}]
    ExLLM.configured?(provider_atom, options)
  end

  @impl MCPChat.LLM.Adapter
  def default_model do
    # Return a reasonable default
    "claude-sonnet-4-20250514"
  end

  @impl MCPChat.LLM.Adapter
  def list_models do
    # Try to list models from configured providers
    providers = [:anthropic, :openai, :ollama, :bedrock, :gemini, :bumblebee]
    options = [{:config_provider, ExLLM.ConfigProvider.Env}]

    models =
      providers
      |> Enum.filter(&ExLLM.configured?(&1, options))
      |> Enum.flat_map(fn provider ->
        case ExLLM.list_models(provider, options) do
          {:ok, models} -> Enum.map(models, & &1.name)
          {:error, _} -> []
        end
      end)

    {:ok, models}
  end

  def list_models(options) when is_list(options) do
    # Handle provider-specific listing
    provider = Keyword.get(options, :provider, :anthropic)

    # Add config provider
    ex_llm_options = [{:config_provider, ExLLM.ConfigProvider.Env}]

    case ExLLM.list_models(provider, ex_llm_options) do
      {:ok, models} ->
        # Convert ExLLM model format to MCPChat format
        converted_models =
          Enum.map(models, fn model ->
            %{
              id: model.id,
              name: model.name
            }
          end)

        {:ok, converted_models}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper functions

  defp validate_config(mcp_chat_config) do
    # Basic validation - ensure we have some LLM configuration
    case Map.get(mcp_chat_config, "llm") do
      nil -> {:error, :no_llm_config}
      llm_config when is_map(llm_config) -> :ok
      _ -> {:error, :invalid_llm_config}
    end
  end

  defp convert_messages(messages) do
    # Convert MCPChat message format to ExLLM format
    Enum.map(messages, fn message ->
      %{
        role: Map.get(message, :role) || Map.get(message, "role"),
        content: Map.get(message, :content) || Map.get(message, "content")
      }
    end)
  end

  defp extract_options(options) do
    # Extract provider (defaulting to anthropic) and model
    provider = Keyword.get(options, :provider, :anthropic)
    model = Keyword.get(options, :model)

    # Convert mcp_chat options to ex_llm options
    ex_llm_options = []

    ex_llm_options = if model, do: [{:model, model} | ex_llm_options], else: ex_llm_options

    ex_llm_options =
      if max_tokens = Keyword.get(options, :max_tokens) do
        [{:max_tokens, max_tokens} | ex_llm_options]
      else
        ex_llm_options
      end

    ex_llm_options =
      if temperature = Keyword.get(options, :temperature) do
        [{:temperature, temperature} | ex_llm_options]
      else
        ex_llm_options
      end

    {provider, ex_llm_options}
  end

  defp convert_response(ex_llm_response) do
    # Convert ExLLM response to MCPChat format
    %{
      content: ex_llm_response.content,
      finish_reason: ex_llm_response.finish_reason,
      usage:
        if ex_llm_response.usage do
          %{
            input_tokens: ex_llm_response.usage.input_tokens,
            output_tokens: ex_llm_response.usage.output_tokens
          }
        else
          nil
        end,
      # Preserve ExLLM's cost data
      cost: ex_llm_response.cost
    }
  end

  defp convert_stream_chunk(ex_llm_chunk) do
    # Convert ExLLM stream chunk to MCPChat format
    %{
      delta: ex_llm_chunk.content || "",
      finish_reason: ex_llm_chunk.finish_reason
    }
  end

  # Model loader functions for local model support

  @doc """
  Load a model for local inference.
  Delegates to ExLLM.Local.ModelLoader if available.
  """
  def load_model(model_id) do
    if model_loader_available?() do
      ModelLoader.load_model(model_id)
    else
      {:error, "Model loader not available. Ensure ex_llm is properly configured."}
    end
  end

  @doc """
  Unload a model from memory.
  Delegates to ExLLM.Local.ModelLoader if available.
  """
  def unload_model(model_id) do
    if model_loader_available?() do
      ModelLoader.unload_model(model_id)
    else
      {:error, "Model loader not available. Ensure ex_llm is properly configured."}
    end
  end

  @doc """
  List loaded models.
  Delegates to ExLLM.Local.ModelLoader if available.
  """
  def list_loaded_models do
    if model_loader_available?() do
      ModelLoader.list_loaded_models()
    else
      []
    end
  end

  @doc """
  Get hardware acceleration info.
  Delegates to ExLLM.Local.EXLAConfig if available.
  """
  def acceleration_info do
    if Code.ensure_loaded?(EXLAConfig) do
      EXLAConfig.acceleration_info()
    else
      %{
        type: :cpu,
        name: "CPU",
        backend: "Not available"
      }
    end
  end

  # ModelCapabilities functions
  def get_model_capabilities(provider, model_id) do
    ExLLM.ModelCapabilities.get_capabilities(provider, model_id)
  end

  def recommend_models(requirements) do
    ExLLM.ModelCapabilities.recommend_models(requirements)
  end

  def list_model_features do
    ExLLM.ModelCapabilities.list_features()
  end

  def compare_models(model_specs) do
    ExLLM.ModelCapabilities.compare_models(model_specs)
  end

  def supports_feature?(provider, model_id, feature) do
    ExLLM.ModelCapabilities.supports?(provider, model_id, feature)
  end

  def find_models_with_features(features) do
    ExLLM.ModelCapabilities.find_models_with_features(features)
  end

  def models_by_capability(feature) do
    ExLLM.ModelCapabilities.models_by_capability(feature)
  end

  defp model_loader_available? do
    case Process.whereis(ModelLoader) do
      nil -> false
      _pid -> true
    end
  end

  defp maybe_add_recovery_options(ex_llm_options, mcp_options) do
    if Keyword.get(mcp_options, :enable_recovery, false) do
      recovery_opts = [
        recovery: [
          enabled: true,
          strategy: Keyword.get(mcp_options, :recovery_strategy, :paragraph),
          storage: :memory
        ]
      ]

      ex_llm_options ++ recovery_opts
    else
      ex_llm_options
    end
  end

  @doc """
  Add ExLLM's enhanced streaming options based on MCP Chat configuration.
  """
  defp maybe_add_streaming_options(ex_llm_options, mcp_options) do
    streaming_opts = []

    # Enable metrics tracking
    streaming_opts =
      if Keyword.get(mcp_options, :track_metrics, true) do
        [{:track_metrics, true} | streaming_opts]
      else
        streaming_opts
      end

    # Add metrics callback if requested
    streaming_opts =
      if Keyword.get(mcp_options, :on_metrics) do
        [{:on_metrics, Keyword.get(mcp_options, :on_metrics)} | streaming_opts]
      else
        streaming_opts
      end

    # Configure flow control
    flow_control_opts = [
      buffer_capacity: get_streaming_config(:buffer_capacity, 100),
      backpressure_threshold: get_streaming_config(:backpressure_threshold, 0.8),
      rate_limit_ms: get_streaming_config(:rate_limit_ms, 0)
    ]

    # Configure chunk batching
    batch_opts = [
      batch_size: get_streaming_config(:batch_size, 5),
      batch_timeout_ms: get_streaming_config(:batch_timeout_ms, 25),
      adaptive: get_streaming_config(:adaptive_batching, true),
      min_batch_size: get_streaming_config(:min_batch_size, 1),
      max_batch_size: get_streaming_config(:max_batch_size, 10)
    ]

    # Add streaming configuration
    streaming_opts = [
      {:flow_control, flow_control_opts},
      {:batch_config, batch_opts},
      {:consumer_type, :managed} | streaming_opts
    ]

    ex_llm_options ++ streaming_opts
  end

  @doc """
  Create an enhanced stream using ExLLM's streaming infrastructure with MCP Chat compatibility.
  """
  defp create_enhanced_stream(stream, ex_llm_options, mcp_options) do
    # Check if we should use ExLLM's enhanced streaming
    if get_streaming_config(:use_ex_llm_streaming, true) do
      # Use ExLLM's stream directly with conversion wrapper
      Stream.map(stream, &convert_stream_chunk/1)
    else
      # Fallback to basic conversion for compatibility
      Stream.map(stream, &convert_stream_chunk/1)
    end
  end

  @doc """
  Get streaming configuration value with fallback to MCP Chat config.
  """
  defp get_streaming_config(key, default) do
    case MCPChat.Config.get([:streaming, key]) do
      nil -> default
      value -> value
    end
  end

  @doc """
  Add ExLLM caching options based on MCP Chat configuration.
  """
  defp maybe_add_caching_options(ex_llm_options, mcp_options) do
    caching_enabled = should_enable_caching?(mcp_options)

    if caching_enabled do
      cache_opts = [
        cache: true,
        cache_ttl: get_cache_ttl()
      ]

      # Add provider for disk persistence context
      cache_opts =
        if provider = Keyword.get(ex_llm_options, :provider) do
          [{:provider, provider} | cache_opts]
        else
          cache_opts
        end

      ex_llm_options ++ cache_opts
    else
      ex_llm_options
    end
  end

  @doc """
  Determine if caching should be enabled for this request.
  """
  defp should_enable_caching?(mcp_options) do
    cond do
      # Explicitly disabled by request
      Keyword.get(mcp_options, :cache) == false -> false
      # Explicitly enabled by request
      Keyword.get(mcp_options, :cache) == true -> true
      # Check global configuration
      true -> caching_enabled_globally?()
    end
  end

  @doc """
  Check if caching is enabled globally via configuration.
  """
  defp caching_enabled_globally? do
    caching_config = MCPChat.Config.get([:caching], %{})

    cond do
      # Explicitly enabled in config
      Map.get(caching_config, :enabled) == true -> true
      # Auto-enable in development if configured
      Map.get(caching_config, :auto_enable_dev) == true and development_mode?() -> true
      # Default to disabled
      true -> false
    end
  end

  @doc """
  Check if we're running in development mode.
  """
  defp development_mode? do
    # Check various indicators of development mode
    cond do
      # Mix environment
      Mix.env() == :dev -> true
      # Environment variable
      System.get_env("MIX_ENV") == "dev" -> true
      # Default to false
      true -> false
    end
  rescue
    # If Mix isn't available (e.g., in production), assume not dev
    _ -> false
  end

  @doc """
  Get cache TTL from configuration.
  """
  defp get_cache_ttl do
    caching_config = MCPChat.Config.get([:caching], %{})
    ttl_minutes = Map.get(caching_config, :ttl_minutes, 15)
    # Convert minutes to milliseconds
    ttl_minutes * 60 * 1_000
  end

  @doc """
  Resume an interrupted stream using the recovery ID.
  """
  def resume_stream(recovery_id, options \\ []) do
    strategy = Keyword.get(options, :strategy, :paragraph)

    case StreamRecovery.resume_stream(recovery_id, strategy: strategy) do
      {:ok, stream} ->
        # Convert the resumed stream to MCPChat format
        converted_stream = Stream.map(stream, &convert_stream_chunk/1)
        {:ok, converted_stream}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  List all recoverable streams.
  """
  def list_recoverable_streams do
    StreamRecovery.list_recoverable_streams()
  end

  @doc """
  Get partial response for a recovery ID.
  """
  def get_partial_response(recovery_id) do
    StreamRecovery.get_partial_response(recovery_id)
  end

  @doc """
  Get cache statistics from ExLLM's cache system.
  """
  def get_cache_stats do
    try do
      ExLLM.Cache.stats()
    rescue
      _ -> %{hits: 0, misses: 0, evictions: 0, errors: 0}
    end
  end

  @doc """
  Clear the ExLLM response cache.
  """
  def clear_cache do
    try do
      ExLLM.Cache.clear()
    rescue
      _ -> :ok
    end
  end

  @doc """
  Configure disk persistence for ExLLM cache.
  """
  def configure_cache_persistence(enabled, cache_dir \\ nil) do
    # Get cache directory from MCP Chat config if not provided
    cache_dir = cache_dir || get_cache_directory()

    try do
      ExLLM.Cache.configure_disk_persistence(enabled, cache_dir)
    rescue
      _ -> :ok
    end
  end

  @doc """
  Get configured cache directory from MCP Chat configuration.
  """
  defp get_cache_directory do
    caching_config = MCPChat.Config.get([:caching], %{})

    case Map.get(caching_config, :cache_dir) do
      nil ->
        # Default to MCP Chat cache directory
        config_dir = MCPChat.Config.config_dir()
        Path.join(config_dir, "cache")

      path ->
        Path.expand(path)
    end
  end

  defp maybe_truncate_messages(messages, provider, ex_llm_options, mcp_options) do
    # Check if context management is enabled
    if Keyword.get(mcp_options, :truncate_context, true) do
      model = Keyword.get(ex_llm_options, :model, default_model_for_provider(provider))
      truncation_strategy = Keyword.get(mcp_options, :truncation_strategy, :smart)

      # Use ExLLM's context truncation
      truncation_options = [
        strategy: truncation_strategy,
        max_tokens: Keyword.get(ex_llm_options, :max_tokens)
      ]

      ExLLM.Context.truncate_messages(messages, provider, model, truncation_options)
    else
      messages
    end
  end

  defp default_model_for_provider(:anthropic), do: "claude-sonnet-4-20250514"
  defp default_model_for_provider(:openai), do: "gpt-4-turbo"
  defp default_model_for_provider(:groq), do: "llama3-70b"
  defp default_model_for_provider(:gemini), do: "gemini-1.5-pro"
  defp default_model_for_provider(_), do: "default"

  @doc """
  Get context statistics for the current conversation.
  Uses ExLLM's context window information.
  """
  def get_context_stats(messages, provider, model, options \\ []) do
    ex_llm_messages = convert_messages(messages)

    try do
      context_window = ExLLM.Context.get_context_window(provider, model)
      token_allocation = ExLLM.Context.get_token_allocation(provider, model, options)
      estimated_tokens = ExLLM.Cost.estimate_tokens(ex_llm_messages)

      %{
        message_count: length(messages),
        estimated_tokens: estimated_tokens,
        context_window: context_window,
        token_allocation: token_allocation,
        tokens_used_percentage: Float.round(estimated_tokens / context_window * 100, 1),
        tokens_remaining: max(0, context_window - estimated_tokens - 500)
      }
    rescue
      _ ->
        # Fallback to basic stats if model info not available
        %{
          message_count: length(messages),
          estimated_tokens: ExLLM.Cost.estimate_tokens(ex_llm_messages),
          context_window: 4_096,
          tokens_used_percentage: 0.0,
          tokens_remaining: 3_596
        }
    end
  end

  # Helper functions for capabilities
  defp get_current_backend_and_model do
    backend = MCPChat.Session.get_session_state().llm_backend || "anthropic"
    model = MCPChat.Session.get_session_state().model || get_default_model_for_backend(backend)
    {String.to_atom(backend), model}
  end

  defp get_default_model_for_backend("anthropic"), do: "claude-sonnet-4-20250514"
  defp get_default_model_for_backend("openai"), do: "gpt-4"
  defp get_default_model_for_backend("gemini"), do: "gemini-pro"
  defp get_default_model_for_backend(_), do: "default"
end
