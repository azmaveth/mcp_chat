defmodule MCPChat.MCP.Discovery do
  @moduledoc """
  MCP server auto-discovery functionality for MCPChat.

  This module provides MCPChat-specific discovery features on top of ExMCP.Discovery:
  - Quick setup servers from known configurations
  - MCPChat-specific server validation
  - Integration with MCPChat's path providers

  For generic discovery functionality, see ExMCP.Discovery.
  """

  require Logger

  @doc """
  Discover all available MCP servers.

  Uses ExMCP.Discovery for generic discovery and adds MCPChat-specific sources.

  ## Options

  - `:methods` - List of discovery methods. Defaults to all available methods.
    MCPChat-specific: `:quick_setup`
    Generic (from ExMCP): `:npm`, `:env`, `:config`, `:well_known`
  """
  def discover_servers(options \\ []) do
    methods = Keyword.get(options, :methods, [:quick_setup, :npm, :env, :well_known])

    # Separate MCPChat-specific methods from generic ones
    {mcp_chat_methods, ex_mcp_methods} =
      Enum.split_with(methods, &(&1 in [:quick_setup]))

    # Get servers from MCPChat-specific methods
    mcp_chat_servers =
      mcp_chat_methods
      |> Enum.flat_map(&discover_by_method/1)

    # Get servers from ExMCP discovery
    ex_mcp_servers =
      if ex_mcp_methods != [] do
        # Map :known_locations to :well_known for ExMCP compatibility
        mapped_methods =
          Enum.map(ex_mcp_methods, fn
            :known_locations -> :well_known
            method -> method
          end)

        ExMCP.Discovery.discover_servers(methods: mapped_methods)
      else
        []
      end

    # Combine and deduplicate
    (mcp_chat_servers ++ ex_mcp_servers)
    |> Enum.uniq_by(& &1.name)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Get quick setup servers with availability check.
  """
  def quick_setup_servers() do
    MCPChat.MCP.DiscoveryConfig.known_servers()
    |> Enum.map(fn server ->
      case MCPChat.MCP.DiscoveryConfig.check_requirements(server) do
        :ok ->
          config = MCPChat.MCP.DiscoveryConfig.build_config(server)
          Map.put(config, :status, :available)

        {:error, {:missing_env_vars, vars}} ->
          %{
            name: server.name,
            description: server.description,
            package: server.package,
            status: :missing_requirements,
            missing: vars,
            source: :quick_setup
          }
      end
    end)
  end

  @doc """
  Discover npm-based MCP servers.

  Delegates to ExMCP.Discovery.discover_npm_packages/0
  """
  @deprecated "Use ExMCP.Discovery.discover_npm_packages/0 directly"
  def discover_npm_servers() do
    ExMCP.Discovery.discover_npm_packages()
  end

  @doc """
  Discover servers from environment variables.

  Delegates to ExMCP.Discovery.discover_from_env/0
  """
  @deprecated "Use ExMCP.Discovery.discover_from_env/0 directly"
  def discover_env_servers() do
    ExMCP.Discovery.discover_from_env()
  end

  @doc """
  Discover servers in well-known locations.
  """
  def discover_known_locations(opts \\ []) do
    path_provider = Keyword.get(opts, :path_provider, MCPChat.PathProvider.Default)

    locations =
      case path_provider do
        MCPChat.PathProvider.Default ->
          case MCPChat.PathProvider.Default.get_path(:mcp_discovery_dirs) do
            {:ok, dirs} -> dirs
            # fallback
            {:error, _} -> [Path.expand("~/.mcp/servers")]
          end

        provider when is_pid(provider) ->
          case MCPChat.PathProvider.Static.get_path(provider, :mcp_discovery_dirs) do
            {:ok, dirs} -> dirs
            # fallback
            {:error, _} -> ["/tmp/mcp_chat_test/mcp_servers"]
          end

        provider ->
          case provider.get_path(:mcp_discovery_dirs) do
            {:ok, dirs} -> dirs
            # fallback
            {:error, _} -> [Path.expand("~/.mcp/servers")]
          end
      end

    locations
    |> Enum.filter(&File.dir?/1)
    |> Enum.flat_map(&scan_directory/1)
  end

  @doc """
  Test if a discovered server is reachable/valid.

  Delegates to ExMCP.Discovery.test_server/1
  """
  def test_server(server_config) do
    ExMCP.Discovery.test_server(server_config)
  end

  @doc """
  Get metadata about a discovered server.

  Currently delegates to ExMCP.Discovery.get_server_metadata/1
  In the future, this could be enhanced with MCPChat-specific metadata.
  """
  def get_server_metadata(server_config) do
    ExMCP.Discovery.get_server_metadata(server_config)
  end

  # Private functions

  # MCPChat-specific discovery methods
  defp discover_by_method(:quick_setup), do: quick_setup_servers()
  defp discover_by_method(_), do: []

  # These implementations have been moved to ExMCP.Discovery
  # Keeping them here for backward compatibility if needed

  # Legacy private functions - kept for backward compatibility
  # These are now handled by ExMCP.Discovery but may be referenced elsewhere

  defp scan_directory(dir) do
    # Delegate to ExMCP's enhanced directory scanning
    ExMCP.Discovery.discover_from_well_known()
    |> Enum.filter(fn server ->
      Map.get(server, :base_dir, "") |> String.starts_with?(dir)
    end)
  end
end
