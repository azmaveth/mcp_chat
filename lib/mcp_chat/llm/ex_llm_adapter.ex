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
      :ok -> :ok
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
    ExLLM.configured?(:anthropic) or ExLLM.configured?(:openai) or ExLLM.configured?(:ollama)
  end

  def configured?(provider_name) when is_binary(provider_name) do
    provider_atom = String.to_atom(provider_name)
    ExLLM.configured?(provider_atom)
  end

  @impl MCPChat.LLM.Adapter
  def default_model() do
    # Return a reasonable default
    "claude-sonnet-4-20250514"
  end

  @impl MCPChat.LLM.Adapter
  def list_models() do
    # Try to list models from configured providers
    providers = [:anthropic, :openai, :ollama]

    models =
      providers
      |> Enum.filter(&ExLLM.configured?/1)
      |> Enum.flat_map(fn provider ->
        case ExLLM.list_models(provider) do
          {:ok, models} -> Enum.map(models, & &1.name)
          {:error, _} -> []
        end
      end)

    {:ok, models}
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
    adapters = if Map.has_key?(llm_config, "anthropic") do
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
    adapters = if Map.has_key?(llm_config, "openai") do
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
    adapters = if Map.has_key?(llm_config, "ollama") do
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
    adapters = if Map.has_key?(llm_config, "local") do
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
      usage: if ex_llm_response.usage do
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
end
