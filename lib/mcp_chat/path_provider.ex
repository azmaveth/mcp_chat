defmodule MCPChat.PathProvider do
  @moduledoc """
  Behaviour for path providers and a default implementation.

  This allows modules to receive file paths through dependency injection
  rather than using hardcoded paths, making them more portable and testable.
  """

  @doc """
  Gets the base configuration directory.
  """
  @callback config_dir() :: String.t()

  @doc """
  Gets the path for a specific file type within the config directory.
  """
  @callback get_path(file_type :: atom()) :: {:ok, String.t()} | {:error, term()}

  @doc """
  Gets all configured paths.
  """
  @callback get_all_paths() :: map()

  alias MCPChat.Error

  defmodule Default do
    @moduledoc """
    Default path provider that uses standard application directories.
    """
    @behaviour MCPChat.PathProvider

    @impl true
    def config_dir() do
      Path.expand("~/.config/mcp_chat")
    end

    @impl true
    def get_path(file_type) do
      case file_type do
        :config_file ->
          {:ok, Path.join(config_dir(), "config.toml")}

        :aliases_file ->
          {:ok, Path.join(config_dir(), "aliases.json")}

        :sessions_dir ->
          {:ok, Path.join(config_dir(), "sessions")}

        :history_file ->
          {:ok, Path.join(config_dir(), "history")}

        :model_cache_dir ->
          {:ok, Path.expand("~/.mcp_chat/models")}

        :server_connections_file ->
          {:ok, Path.expand("~/.mcp_chat/connected_servers.json")}

        :mcp_discovery_dirs ->
          {:ok, [
            Path.expand("~/.mcp/servers"),
            "/usr/local/share/mcp/servers",
            "/opt/homebrew/share/mcp/servers",
            Path.expand("~/mcp-servers"),
            Path.expand("~/projects/mcp-servers")
          ]}

        _ ->
          {:error, {:invalid_file_type, file_type}}
      end
    end

    @impl true
    def get_all_paths() do
      %{
        config_dir: config_dir(),
        config_file: get_path(:config_file),
        aliases_file: get_path(:aliases_file),
        sessions_dir: get_path(:sessions_dir),
        history_file: get_path(:history_file),
        model_cache_dir: get_path(:model_cache_dir),
        server_connections_file: get_path(:server_connections_file),
        mcp_discovery_dirs: get_path(:mcp_discovery_dirs)
      }
    end
  end

  defmodule Static do
    @moduledoc """
    Static path provider for testing and library usage.

    Usage:
        paths = %{
          config_dir: "/tmp/test_config",
          aliases_file: "/tmp/test_aliases.json"
        }
        {:ok, provider} = MCPChat.PathProvider.Static.start_link(paths)
        MCPChat.Alias.start_link(path_provider: provider)
    """
    use Agent

    def start_link(paths) do
      Agent.start_link(fn -> paths end)
    end

    def config_dir(provider) do
      Agent.get(provider, &Map.get(&1, :config_dir, "/tmp/mcp_chat_test"))
    end

    def get_path(provider, file_type) do
      Agent.get(provider, fn paths ->
        case Map.get(paths, file_type) do
          nil ->
            default_path(Map.get(paths, :config_dir, "/tmp/mcp_chat_test"), file_type)
          path ->
            {:ok, path}
        end
      end)
    end

    def get_all_paths(provider) do
      Agent.get(provider, & &1)
    end

    defp default_path(base_dir, file_type) do
      case file_type do
        :config_file -> {:ok, Path.join(base_dir, "config.toml")}
        :aliases_file -> {:ok, Path.join(base_dir, "aliases.json")}
        :sessions_dir -> {:ok, Path.join(base_dir, "sessions")}
        :history_file -> {:ok, Path.join(base_dir, "history")}
        :model_cache_dir -> {:ok, Path.join(base_dir, "models")}
        :server_connections_file -> {:ok, Path.join(base_dir, "connected_servers.json")}
        :mcp_discovery_dirs -> {:ok, [Path.join(base_dir, "mcp_servers")]}
        _ -> {:error, {:invalid_file_type, file_type}}
      end
    end
  end
end
