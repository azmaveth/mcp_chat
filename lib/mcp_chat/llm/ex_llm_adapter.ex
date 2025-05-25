defmodule MCPChat.LLM.ExLLMAdapter do
  @moduledoc """
  Adapter that wraps ExLLM to work with MCPChat's LLM.Adapter interface.

  This adapter allows mcp_chat to use the ex_llm library while maintaining
  compatibility with the existing MCPChat.LLM.Adapter behavior.
  """

  @behaviour MCPChat.LLM.Adapter

  require Logger

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
    ex_llm_options = [{:config_provider, ExLLM.ConfigProvider.Env} | ex_llm_options]

    # Call ExLLM
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

    # Add config provider to options
    ex_llm_options = [{:config_provider, ExLLM.ConfigProvider.Env} | ex_llm_options]

    # Call ExLLM streaming
    case ExLLM.stream_chat(provider, ex_llm_messages, ex_llm_options) do
      {:ok, stream} ->
        # Convert the stream to MCPChat format
        converted_stream = Stream.map(stream, &convert_stream_chunk/1)
        {:ok, converted_stream}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl MCPChat.LLM.Adapter
  def configured?() do
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
  def default_model() do
    # Return a reasonable default
    "claude-sonnet-4-20250514"
  end

  @impl MCPChat.LLM.Adapter
  def list_models() do
    # Try to list models from configured providers
    providers = [:anthropic, :openai, :ollama, :bedrock, :gemini, :local]
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

  defp convert_config(mcp_chat_config) do
    # Convert mcp_chat configuration format to ex_llm format
    # This maps the TOML config structure to ExLLM's expected format

    llm_config = Map.get(mcp_chat_config, "llm", %{})
    default_backend = Map.get(llm_config, "default", "anthropic")

    adapters = []

    # Add Anthropic adapter if configured
    adapters =
      if Map.has_key?(llm_config, "anthropic") do
        anthropic_config = Map.get(llm_config, "anthropic", %{})

        anthropic_adapter = %{
          adapter: ExLLM.Adapters.Anthropic,
          config: %{
            api_key: Map.get(anthropic_config, "api_key") || System.get_env("ANTHROPIC_API_KEY"),
            model: Map.get(anthropic_config, "model", "claude-sonnet-4-20250514"),
            max_tokens: Map.get(anthropic_config, "max_tokens", 4_096)
          }
        }

        [anthropic_adapter | adapters]
      else
        adapters
      end

    # Add OpenAI adapter if configured
    adapters =
      if Map.has_key?(llm_config, "openai") do
        openai_config = Map.get(llm_config, "openai", %{})

        openai_adapter = %{
          adapter: ExLLM.Adapters.OpenAI,
          config: %{
            api_key: Map.get(openai_config, "api_key") || System.get_env("OPENAI_API_KEY"),
            model: Map.get(openai_config, "model", "gpt-4"),
            max_tokens: Map.get(openai_config, "max_tokens", 4_096)
          }
        }

        [openai_adapter | adapters]
      else
        adapters
      end

    # Add Ollama adapter if configured
    adapters =
      if Map.has_key?(llm_config, "ollama") do
        ollama_config = Map.get(llm_config, "ollama", %{})

        ollama_adapter = %{
          adapter: ExLLM.Adapters.Ollama,
          config: %{
            base_url: Map.get(ollama_config, "base_url", "http://localhost:11_434"),
            model: Map.get(ollama_config, "model", "llama3"),
            timeout: Map.get(ollama_config, "timeout", 60_000)
          }
        }

        [ollama_adapter | adapters]
      else
        adapters
      end

    # Add Local adapter if configured
    adapters =
      if Map.has_key?(llm_config, "local") do
        local_config = Map.get(llm_config, "local", %{})

        local_adapter = %{
          adapter: ExLLM.Adapters.Local,
          config: %{
            model_path: Map.get(local_config, "model_path"),
            device: Map.get(local_config, "device", "cpu"),
            max_tokens: Map.get(local_config, "max_tokens", 2048)
          }
        }

        [local_adapter | adapters]
      else
        adapters
      end

    # Add Bedrock adapter if configured
    adapters =
      if Map.has_key?(llm_config, "bedrock") do
        bedrock_config = Map.get(llm_config, "bedrock", %{})

        bedrock_adapter = %{
          adapter: ExLLM.Adapters.Bedrock,
          config: %{
            access_key_id: Map.get(bedrock_config, "access_key_id") || System.get_env("AWS_ACCESS_KEY_ID"),
            secret_access_key: Map.get(bedrock_config, "secret_access_key") || System.get_env("AWS_SECRET_ACCESS_KEY"),
            region: Map.get(bedrock_config, "region", "us-east-1"),
            model: Map.get(bedrock_config, "model", "claude-3-sonnet")
          }
        }

        [bedrock_adapter | adapters]
      else
        adapters
      end

    # Add Gemini adapter if configured
    adapters =
      if Map.has_key?(llm_config, "gemini") do
        gemini_config = Map.get(llm_config, "gemini", %{})

        gemini_adapter = %{
          adapter: ExLLM.Adapters.Gemini,
          config: %{
            api_key: Map.get(gemini_config, "api_key") || System.get_env("GOOGLE_API_KEY"),
            model: Map.get(gemini_config, "model", "gemini-pro")
          }
        }

        [gemini_adapter | adapters]
      else
        adapters
      end

    %{
      adapters: adapters,
      default_adapter: default_backend,
      cost_tracking: %{
        enabled: true
      },
      context: %{
        max_tokens: 8_000,
        strategy: :sliding_window
      }
    }
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

    if max_tokens = Keyword.get(options, :max_tokens) do
      ex_llm_options = [{:max_tokens, max_tokens} | ex_llm_options]
    end

    if temperature = Keyword.get(options, :temperature) do
      ex_llm_options = [{:temperature, temperature} | ex_llm_options]
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
        end
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
      ExLLM.Local.ModelLoader.load_model(model_id)
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
      ExLLM.Local.ModelLoader.unload_model(model_id)
    else
      {:error, "Model loader not available. Ensure ex_llm is properly configured."}
    end
  end

  @doc """
  List loaded models.
  Delegates to ExLLM.Local.ModelLoader if available.
  """
  def list_loaded_models() do
    if model_loader_available?() do
      ExLLM.Local.ModelLoader.list_loaded_models()
    else
      []
    end
  end

  @doc """
  Get hardware acceleration info.
  Delegates to ExLLM.Local.EXLAConfig if available.
  """
  def acceleration_info() do
    if Code.ensure_loaded?(ExLLM.Local.EXLAConfig) do
      ExLLM.Local.EXLAConfig.acceleration_info()
    else
      %{
        type: :cpu,
        name: "CPU",
        backend: "Not available"
      }
    end
  end

  defp model_loader_available?() do
    case Process.whereis(ExLLM.Local.ModelLoader) do
      nil -> false
      _pid -> true
    end
  end
end
