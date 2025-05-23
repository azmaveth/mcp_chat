defmodule MCPChat.Config do
  @moduledoc """
  Configuration management for MCP Chat.
  Loads and manages configuration from TOML files.
  """
  use GenServer

  @default_config_path "~/.config/mcp_chat/config.toml"

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get(key) when is_atom(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  def get(path) when is_list(path) do
    GenServer.call(__MODULE__, {:get_path, path})
  end

  def reload() do
    GenServer.cast(__MODULE__, :reload)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config_path =
      Keyword.get(opts, :config_path, @default_config_path)
      |> Path.expand()

    state = %{
      config_path: config_path,
      config: %{}
    }

    {:ok, state, {:continue, :load_config}}
  end

  @impl true
  def handle_continue(:load_config, state) do
    config = load_config(state.config_path)
    {:noreply, %{state | config: config}}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    value = Map.get(state.config, key)
    {:reply, value, state}
  end

  @impl true
  def handle_call({:get_path, path}, _from, state) do
    value = get_in(state.config, path)
    {:reply, value, state}
  end

  @impl true
  def handle_cast(:reload, state) do
    config = load_config(state.config_path)
    {:noreply, %{state | config: config}}
  end

  # Private Functions

  defp load_config(path) do
    if File.exists?(path) do
      case Toml.decode_file(path) do
        {:ok, config} ->
          atomize_keys(config)

        {:error, reason} ->
          IO.warn("Failed to load config from #{path}: #{inspect(reason)}")
          default_config()
      end
    else
      ensure_config_dir(path)
      config = default_config()
      save_config(path, config)
      config
    end
  end

  defp ensure_config_dir(path) do
    dir = Path.dirname(path)
    File.mkdir_p!(dir)
  end

  defp save_config(path, config) do
    # For now, we'll save a basic TOML format
    content = """
    # MCP Chat Configuration
    # Generated automatically

    [llm]
    default = "#{config.llm.default}"

    [llm.anthropic]
    api_key = "#{config.llm.anthropic.api_key}"
    model = "#{config.llm.anthropic.model}"
    max_tokens = #{config.llm.anthropic.max_tokens}

    [ui]
    theme = "#{config.ui.theme}"
    history_size = #{config.ui.history_size}
    """

    File.write!(path, content)
  end

  defp default_config() do
    %{
      llm: %{
        default: "anthropic",
        anthropic: %{
          api_key: System.get_env("ANTHROPIC_API_KEY", ""),
          model: "claude-sonnet-4-20_250_514",
          max_tokens: 4_096
        },
        openai: %{
          api_key: System.get_env("OPENAI_API_KEY", ""),
          model: "gpt-4"
        },
        local: %{
          model_path: "models/llama-2-7b",
          device: "cpu"
        }
      },
      mcp: %{
        servers: []
      },
      mcp_server: %{
        stdio_enabled: false,
        sse_enabled: false,
        sse_port: 8_080
      },
      ui: %{
        theme: "dark",
        history_size: 1_000
      }
    }
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      {String.to_atom(k), atomize_keys(v)}
    end)
  end

  defp atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end

  defp atomize_keys(value), do: value

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      {to_string(k), stringify_keys(v)}
    end)
  end

  defp stringify_keys(list) when is_list(list) do
    Enum.map(list, &stringify_keys/1)
  end

  defp stringify_keys(value), do: value
end
