defmodule MCPChat.LLM.ModelLoader do
  @moduledoc """
  Handles loading and caching of Bumblebee models for local inference.
  """

  use GenServer
  require Logger

  @model_cache_dir Path.expand("~/.mcp_chat/models")

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Load a model by name or path. Returns {:ok, model_info} or {:error, reason}.
  """
  def load_model(model_identifier) do
    GenServer.call(__MODULE__, {:load_model, model_identifier}, :infinity)
  end

  @doc """
  Get information about a loaded model.
  """
  def get_model_info(model_identifier) do
    GenServer.call(__MODULE__, {:get_model_info, model_identifier})
  end

  @doc """
  List all loaded models.
  """
  def list_loaded_models() do
    GenServer.call(__MODULE__, :list_loaded_models)
  end

  @doc """
  Unload a model from memory.
  """
  def unload_model(model_identifier) do
    GenServer.call(__MODULE__, {:unload_model, model_identifier})
  end

  # Server callbacks

  def init(_opts) do
    # Ensure model cache directory exists
    File.mkdir_p!(@model_cache_dir)

    state = %{
      models: %{},
      loading: MapSet.new()
    }

    {:ok, state}
  end

  def handle_call({:load_model, model_identifier}, _from, state) do
    cond do
      Map.has_key?(state.models, model_identifier) ->
        {:reply, {:ok, state.models[model_identifier]}, state}

      MapSet.member?(state.loading, model_identifier) ->
        {:reply, {:error, :already_loading}, state}

      true ->
        state = %{state | loading: MapSet.put(state.loading, model_identifier)}

        case do_load_model(model_identifier) do
          {:ok, model_info} ->
            state = %{
              state
              | models: Map.put(state.models, model_identifier, model_info),
                loading: MapSet.delete(state.loading, model_identifier)
            }

            {:reply, {:ok, model_info}, state}

          {:error, _reason} = error ->
            state = %{state | loading: MapSet.delete(state.loading, model_identifier)}
            {:reply, error, state}
        end
    end
  end

  def handle_call({:get_model_info, model_identifier}, _from, state) do
    case Map.get(state.models, model_identifier) do
      nil -> {:reply, {:error, :not_loaded}, state}
      info -> {:reply, {:ok, info}, state}
    end
  end

  def handle_call(:list_loaded_models, _from, state) do
    models = Map.keys(state.models)
    {:reply, models, state}
  end

  def handle_call({:unload_model, model_identifier}, _from, state) do
    if Map.has_key?(state.models, model_identifier) do
      state = %{state | models: Map.delete(state.models, model_identifier)}
      {:reply, :ok, state}
    else
      {:reply, {:error, :not_loaded}, state}
    end
  end

  # Private functions

  defp do_load_model(model_identifier) do
    Logger.info("Loading model: #{model_identifier}")

    try do
      # Determine if this is a HuggingFace model or local path
      {repository_id, opts} = parse_model_identifier(model_identifier)

      # Load the model with Bumblebee
      with {:ok, model_info} <- Bumblebee.load_model(repository_id, opts),
           {:ok, tokenizer} <- Bumblebee.load_tokenizer(repository_id, opts),
           {:ok, generation_config} <- Bumblebee.load_generation_config(repository_id, opts) do
        # Create serving for text generation
        serving =
          Bumblebee.Text.generation(
            model_info,
            tokenizer,
            generation_config,
            compile: [batch_size: 1, sequence_length: 1_028],
            stream: true,
            defn_options: [compiler: determine_backend()]
          )

        model_data = %{
          model_info: model_info,
          tokenizer: tokenizer,
          generation_config: generation_config,
          serving: serving,
          repository_id: repository_id,
          loaded_at: DateTime.utc_now()
        }

        Logger.info("Successfully loaded model: #{model_identifier}")
        {:ok, model_data}
      else
        {:error, reason} ->
          Logger.error("Failed to load model #{model_identifier}: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Exception loading model #{model_identifier}: #{inspect(e)}")
        {:error, {:exception, e}}
    end
  end

  defp parse_model_identifier(identifier) do
    cond do
      # Local file path
      String.starts_with?(identifier, "/") or String.starts_with?(identifier, "~/") ->
        path = Path.expand(identifier)
        {path, [cache_dir: @model_cache_dir]}

      # HuggingFace model ID
      String.contains?(identifier, "/") ->
        {identifier, [cache_dir: @model_cache_dir]}

      # Shorthand for common models
      true ->
        case identifier do
          "llama2" -> {"meta-llama/Llama-2-7b-hf", [cache_dir: @model_cache_dir]}
          "mistral" -> {"mistralai/Mistral-7B-v0.1", [cache_dir: @model_cache_dir]}
          "phi" -> {"microsoft/phi-2", [cache_dir: @model_cache_dir]}
          _ -> {identifier, [cache_dir: @model_cache_dir]}
        end
    end
  end

  defp determine_backend() do
    cond do
      Code.ensure_loaded?(EXLA) -> EXLA.Backend
      Code.ensure_loaded?(Ortex) -> Ortex.Backend
      true -> Nx.BinaryBackend
    end
  end
end
