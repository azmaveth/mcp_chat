defmodule MCPChat.LLM.ExLLMAdapter do
  @moduledoc """
  Adapter that wraps ExLLM to work with MCPChat's LLM.Adapter interface.

  This adapter allows mcp_chat to use the ex_llm library while maintaining
  compatibility with the existing MCPChat.LLM.Adapter behavior.
  """

  @behaviour MCPChat.LLM.Adapter

  require Logger

  alias ExLLM.StreamRecovery
  alias ExLLM.ModelLoader
  alias ExLLM.Bumblebee.EXLAConfig

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

    # Add available MCP tools if enabled
    ex_llm_options = maybe_add_mcp_tools(ex_llm_options, options)

    # Add caching options if enabled
    ex_llm_options = maybe_add_caching_options(ex_llm_options, options)

    # Apply context truncation if enabled
    ex_llm_messages = maybe_truncate_messages(ex_llm_messages, provider, ex_llm_options, options)

    # Use ExLLM's new pipeline API (v0.8+)
    case ExLLM.chat(provider, ex_llm_messages, ex_llm_options) do
      {:ok, response} ->
        {:ok, convert_response(response)}

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

    # Add available MCP tools if enabled
    ex_llm_options = maybe_add_mcp_tools(ex_llm_options, options)

    # Apply context truncation if enabled
    ex_llm_messages = maybe_truncate_messages(ex_llm_messages, provider, ex_llm_options, options)

    # Add enhanced streaming options from ExLLM
    ex_llm_options = maybe_add_streaming_options(ex_llm_options, options)

    # Add recovery options if requested
    ex_llm_options = maybe_add_recovery_options(ex_llm_options, options)

    # Create a callback function to convert chunks to MCPChat format
    callback = fn chunk ->
      send(self(), {:stream_chunk, convert_stream_chunk(chunk)})
    end

    # Use ExLLM's new streaming API (v0.8+)
    case ExLLM.stream(provider, ex_llm_messages, callback, ex_llm_options) do
      :ok ->
        # Create stream from message receiving
        stream =
          Stream.resource(
            fn -> :start end,
            fn
              :start ->
                receive do
                  {:stream_chunk, chunk} -> {[chunk], :streaming}
                after
                  30_000 -> {:halt, :timeout}
                end

              :streaming ->
                receive do
                  {:stream_chunk, %{finish_reason: reason} = chunk} when reason != nil ->
                    {[chunk], :halt}

                  {:stream_chunk, chunk} ->
                    {[chunk], :streaming}
                after
                  30_000 -> {:halt, :timeout}
                end

              :halt ->
                {:halt, :completed}
            end,
            fn _ -> :ok end
          )

        # Store recovery ID if recovery is enabled
        if recovery_id = Keyword.get(ex_llm_options, :recovery_id) do
          {:ok, stream, recovery_id}
        else
          {:ok, stream}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl MCPChat.LLM.Adapter
  def configured? do
    # Check if at least one provider is configured using new API
    try do
      # Try to get providers that are configured
      configured_providers = [:anthropic, :openai, :ollama, :gemini, :groq]

      Enum.any?(configured_providers, fn provider ->
        case ExLLM.Providers.get_config(provider) do
          {:ok, _config} -> true
          {:error, _} -> false
        end
      end)
    rescue
      _ ->
        # Fallback: check environment variables directly
        System.get_env("ANTHROPIC_API_KEY") != nil or
          System.get_env("OPENAI_API_KEY") != nil or
          System.get_env("OLLAMA_API_BASE") != nil
    end
  end

  def configured?(provider_name) when is_binary(provider_name) do
    provider_atom = String.to_atom(provider_name)

    try do
      case ExLLM.Providers.get_config(provider_atom) do
        {:ok, _config} -> true
        {:error, _} -> false
      end
    rescue
      _ ->
        # Fallback: check common environment variables
        case provider_atom do
          :anthropic -> System.get_env("ANTHROPIC_API_KEY") != nil
          :openai -> System.get_env("OPENAI_API_KEY") != nil
          :ollama -> System.get_env("OLLAMA_API_BASE") != nil
          :gemini -> System.get_env("GEMINI_API_KEY") != nil
          :groq -> System.get_env("GROQ_API_KEY") != nil
          _ -> false
        end
    end
  end

  @impl MCPChat.LLM.Adapter
  def default_model do
    # Return a reasonable default
    "claude-sonnet-4-20250514"
  end

  @impl MCPChat.LLM.Adapter
  def list_models do
    # Try to list models from configured providers using new API
    providers = [:anthropic, :openai, :ollama, :bedrock, :gemini, :bumblebee]

    models =
      providers
      |> Enum.filter(&is_provider_configured?/1)
      |> Enum.flat_map(fn provider ->
        case ExLLM.list_models(provider) do
          {:ok, models} ->
            Enum.map(models, fn model ->
              case model do
                %{name: name} -> name
                %{id: id} -> id
                name when is_binary(name) -> name
                _ -> to_string(model)
              end
            end)

          {:error, _} ->
            []
        end
      end)

    {:ok, models}
  end

  def list_models(options) when is_list(options) do
    # Handle provider-specific listing
    provider = Keyword.get(options, :provider, :anthropic)

    case ExLLM.list_models(provider) do
      {:ok, models} ->
        # Convert ExLLM model format to MCPChat format
        converted_models =
          Enum.map(models, fn model ->
            case model do
              %{id: id, name: name} ->
                %{id: id, name: name}

              %{name: name} ->
                %{id: name, name: name}

              %{id: id} ->
                %{id: id, name: id}

              name when is_binary(name) ->
                %{id: name, name: name}

              _ ->
                model_str = to_string(model)
                %{id: model_str, name: model_str}
            end
          end)

        {:ok, converted_models}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp is_provider_configured?(provider_atom) when is_atom(provider_atom) do
    try do
      case ExLLM.Providers.get_config(provider_atom) do
        {:ok, _config} -> true
        {:error, _} -> false
      end
    rescue
      _ ->
        # Fallback: check common environment variables
        case provider_atom do
          :anthropic -> System.get_env("ANTHROPIC_API_KEY") != nil
          :openai -> System.get_env("OPENAI_API_KEY") != nil
          :ollama -> System.get_env("OLLAMA_API_BASE") != nil
          :gemini -> System.get_env("GEMINI_API_KEY") != nil
          :groq -> System.get_env("GROQ_API_KEY") != nil
          # Local provider doesn't need API key
          :bumblebee -> true
          :bedrock -> System.get_env("AWS_ACCESS_KEY_ID") != nil
          _ -> false
        end
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

    # Handle the ExLLM v0.4.2+ breaking change: :local → :bumblebee
    provider =
      case provider do
        :local -> :bumblebee
        other -> other
      end

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
    base_response = %{
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

    # Handle function calls if present
    case ex_llm_response do
      %{tool_calls: tool_calls} when is_list(tool_calls) and length(tool_calls) > 0 ->
        # Execute function calls and add results to response
        function_results = handle_function_calls(tool_calls)
        Map.put(base_response, :function_results, function_results)

      _ ->
        base_response
    end
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

  # ModelCapabilities functions - updated for new API
  def get_model_capabilities(provider, model_id) do
    try do
      ExLLM.Models.get_capabilities(provider, model_id)
    rescue
      _ ->
        # Fallback to old API if new one fails
        try do
          ExLLM.Config.ModelCapabilities.get_capabilities(provider, model_id)
        rescue
          _ -> %{}
        end
    end
  end

  def recommend_models(requirements) do
    try do
      ExLLM.Models.recommend(requirements)
    rescue
      _ ->
        # Fallback to old API
        try do
          ExLLM.Config.ModelCapabilities.recommend_models(requirements)
        rescue
          _ -> []
        end
    end
  end

  def list_model_features do
    try do
      ExLLM.Models.list_features()
    rescue
      _ ->
        # Fallback to old API
        try do
          ExLLM.Config.ModelCapabilities.list_features()
        rescue
          _ -> []
        end
    end
  end

  def compare_models(model_specs) do
    try do
      ExLLM.Models.compare(model_specs)
    rescue
      _ ->
        # Fallback to old API
        try do
          ExLLM.Config.ModelCapabilities.compare_models(model_specs)
        rescue
          _ -> %{}
        end
    end
  end

  def supports_feature?(provider, model_id, feature) do
    try do
      ExLLM.Models.supports_feature?(provider, model_id, feature)
    rescue
      _ ->
        # Fallback to old API
        try do
          ExLLM.Config.ModelCapabilities.supports?(provider, model_id, feature)
        rescue
          _ -> false
        end
    end
  end

  def find_models_with_features(features) do
    try do
      ExLLM.Models.find_with_features(features)
    rescue
      _ ->
        # Fallback to old API
        try do
          ExLLM.Config.ModelCapabilities.find_models_with_features(features)
        rescue
          _ -> []
        end
    end
  end

  def models_by_capability(feature) do
    try do
      ExLLM.Models.by_capability(feature)
    rescue
      _ ->
        # Fallback to old API
        try do
          ExLLM.Config.ModelCapabilities.models_by_capability(feature)
        rescue
          _ -> []
        end
    end
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

    # Configure flow control with ExLLM 0.8.0 StreamBuffer
    flow_control_opts = [
      buffer_capacity: get_streaming_config(:buffer_capacity, 100),
      backpressure_threshold: get_streaming_config(:backpressure_threshold, 0.8),
      rate_limit_ms: get_streaming_config(:rate_limit_ms, 1),
      overflow_strategy: get_streaming_config(:overflow_strategy, :drop)
    ]

    # Configure chunk batching with ExLLM 0.8.0 ChunkBatcher
    batch_opts = [
      batch_size: get_streaming_config(:batch_size, 5),
      batch_timeout_ms: get_streaming_config(:batch_timeout_ms, 25),
      adaptive: get_streaming_config(:adaptive_batching, true),
      min_batch_size: get_streaming_config(:min_batch_size, 1),
      max_batch_size: get_streaming_config(:max_batch_size, 10)
    ]

    # Enable ExLLM 0.8.0 advanced streaming infrastructure
    streaming_opts = [
      {:use_advanced_streaming, true},
      {:flow_control, flow_control_opts},
      {:batch_config, batch_opts},
      {:consumer_type, get_streaming_config(:consumer_type, :managed)} | streaming_opts
    ]

    ex_llm_options ++ streaming_opts
  end

  @doc """
  Create an enhanced stream using ExLLM's streaming infrastructure with MCP Chat compatibility.
  """
  defp create_enhanced_stream(stream, ex_llm_options, mcp_options) do
    # Check if advanced streaming is enabled
    if Keyword.get(ex_llm_options, :use_advanced_streaming, true) do
      # ExLLM 0.8.0 already provides enhanced streaming with FlowController, StreamBuffer, and ChunkBatcher
      # The stream is already optimized, just convert chunk format for MCP Chat compatibility
      stream
      |> Stream.map(&convert_stream_chunk/1)
      |> maybe_add_streaming_telemetry(ex_llm_options)
    else
      # Fallback to basic conversion for compatibility
      Stream.map(stream, &convert_stream_chunk/1)
    end
  end

  @doc """
  Add streaming telemetry if enabled in options.
  """
  defp maybe_add_streaming_telemetry(stream, ex_llm_options) do
    if Keyword.get(ex_llm_options, :track_metrics, false) do
      stream
      |> Stream.with_index()
      |> Stream.map(fn {chunk, index} ->
        # Emit telemetry for chunk processing
        :telemetry.execute(
          [:mcp_chat, :streaming, :chunk_processed],
          %{chunk_index: index, chunk_size: byte_size(chunk.delta || "")},
          %{provider: :ex_llm}
        )

        chunk
      end)
    else
      stream
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

    try do
      # Try new API
      case ExLLM.Core.Streaming.Recovery.resume_stream(recovery_id, strategy: strategy) do
        {:ok, stream} ->
          # Convert the resumed stream to MCPChat format
          converted_stream = Stream.map(stream, &convert_stream_chunk/1)
          {:ok, converted_stream}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      _ ->
        # Fallback to old API
        try do
          case StreamRecovery.resume_stream(recovery_id, strategy: strategy) do
            {:ok, stream} ->
              converted_stream = Stream.map(stream, &convert_stream_chunk/1)
              {:ok, converted_stream}

            {:error, reason} ->
              {:error, reason}
          end
        rescue
          _ -> {:error, "Stream recovery not available"}
        end
    end
  end

  @doc """
  List all recoverable streams.
  """
  def list_recoverable_streams do
    try do
      ExLLM.Core.Streaming.Recovery.list_recoverable_streams()
    rescue
      _ ->
        # Fallback to old API
        try do
          StreamRecovery.list_recoverable_streams()
        rescue
          _ -> []
        end
    end
  end

  @doc """
  Get partial response for a recovery ID.
  """
  def get_partial_response(recovery_id) do
    try do
      ExLLM.Core.Streaming.Recovery.get_partial_response(recovery_id)
    rescue
      _ ->
        # Fallback to old API
        try do
          StreamRecovery.get_partial_response(recovery_id)
        rescue
          _ -> {:error, "Stream recovery not available"}
        end
    end
  end

  @doc """
  Get cache statistics from ExLLM's cache system.
  """
  def get_cache_stats do
    try do
      ExLLM.Infrastructure.Cache.stats()
    rescue
      _ ->
        # Fallback to old API
        try do
          ExLLM.Cache.stats()
        rescue
          _ -> %{hits: 0, misses: 0, evictions: 0, errors: 0}
        end
    end
  end

  @doc """
  Clear the ExLLM response cache.
  """
  def clear_cache do
    try do
      ExLLM.Infrastructure.Cache.clear()
    rescue
      _ ->
        # Fallback to old API
        try do
          ExLLM.Cache.clear()
        rescue
          _ -> :ok
        end
    end
  end

  @doc """
  Configure disk persistence for ExLLM cache.
  """
  def configure_cache_persistence(enabled, cache_dir \\ nil) do
    # Get cache directory from MCP Chat config if not provided
    cache_dir = cache_dir || get_cache_directory()

    try do
      ExLLM.Infrastructure.Cache.configure_disk_persistence(enabled, cache_dir)
    rescue
      _ ->
        # Fallback to old API
        try do
          ExLLM.Cache.configure_disk_persistence(enabled, cache_dir)
        rescue
          _ -> :ok
        end
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

      # Use ExLLM's context truncation (try new API first)
      try do
        truncation_options = [
          strategy: truncation_strategy,
          max_tokens: Keyword.get(ex_llm_options, :max_tokens)
        ]

        ExLLM.Core.Context.truncate_messages(messages, provider, model, truncation_options)
      rescue
        _ ->
          # Fallback to old API
          try do
            ExLLM.Context.truncate_messages(messages, provider, model, truncation_strategy: truncation_strategy)
          rescue
            # If context truncation fails, return original messages
            _ -> messages
          end
      end
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
      # Try new API first
      context_window = ExLLM.Core.Context.get_context_window(provider, model)
      token_allocation = ExLLM.Core.Context.get_token_allocation(provider, model, options)
      estimated_tokens = ExLLM.Core.Cost.estimate_tokens(ex_llm_messages)

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
        # Fallback to old API
        try do
          context_window = ExLLM.Context.get_context_window(provider, model)
          estimated_tokens = ExLLM.Cost.estimate_tokens(ex_llm_messages)

          %{
            message_count: length(messages),
            estimated_tokens: estimated_tokens,
            context_window: context_window,
            token_allocation: %{},
            tokens_used_percentage: Float.round(estimated_tokens / context_window * 100, 1),
            tokens_remaining: max(0, context_window - estimated_tokens - 500)
          }
        rescue
          _ ->
            # Final fallback to basic stats
            fallback_ex_llm_messages = convert_messages(messages)

            %{
              message_count: length(messages),
              # rough estimate
              estimated_tokens: 100 * length(messages),
              context_window: 4_096,
              token_allocation: %{},
              tokens_used_percentage: 0.0,
              tokens_remaining: 3_596
            }
        end
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

  # MCP Tools Integration

  defp maybe_add_mcp_tools(ex_llm_options, mcp_options) do
    # Check if tools should be enabled
    tools_enabled = Keyword.get(mcp_options, :enable_tools, should_enable_tools_by_default?())

    if tools_enabled do
      case get_available_tools() do
        {:ok, tools} when length(tools) > 0 ->
          Logger.debug("Adding #{length(tools)} MCP tools to LLM options")
          # Add tools and tool_choice options
          tools_opts = [
            tools: tools,
            tool_choice: get_tool_choice_strategy(mcp_options)
          ]

          ex_llm_options ++ tools_opts

        {:ok, []} ->
          Logger.debug("No MCP tools available")
          ex_llm_options

        {:error, reason} ->
          Logger.warning("Failed to get MCP tools: #{inspect(reason)}")
          ex_llm_options
      end
    else
      ex_llm_options
    end
  end

  defp should_enable_tools_by_default? do
    # Enable tools by default unless explicitly disabled
    case System.get_env("MCP_ENABLE_TOOLS") do
      "false" -> false
      "0" -> false
      _ -> true
    end
  end

  defp get_available_tools do
    try do
      tools = MCPChat.LLM.ToolBridge.get_available_functions()
      {:ok, tools}
    rescue
      error ->
        Logger.error("Error getting available tools: #{inspect(error)}")
        {:error, error}
    end
  end

  defp get_tool_choice_strategy(mcp_options) do
    # Default to "auto" - let the LLM decide when to use tools
    Keyword.get(mcp_options, :tool_choice, "auto")
  end

  @doc """
  Handle function calls in LLM responses.

  This function should be called when the LLM response contains function calls
  that need to be executed.
  """
  def handle_function_calls(function_calls) when is_list(function_calls) do
    Enum.map(function_calls, &handle_single_function_call/1)
  end

  def handle_function_calls(function_call) do
    [handle_single_function_call(function_call)]
  end

  defp handle_single_function_call(%{"name" => function_name, "arguments" => arguments}) do
    Logger.debug("Executing function call: #{function_name}")

    case MCPChat.LLM.ToolBridge.execute_function(function_name, arguments) do
      {:ok, result} ->
        %{
          "name" => function_name,
          "result" => result,
          "status" => "success"
        }

      {:error, reason} ->
        %{
          "name" => function_name,
          "error" => reason,
          "status" => "error"
        }
    end
  end

  defp handle_single_function_call(invalid_call) do
    Logger.warning("Invalid function call format: #{inspect(invalid_call)}")

    %{
      "error" => "Invalid function call format",
      "status" => "error",
      "details" => inspect(invalid_call)
    }
  end
end
