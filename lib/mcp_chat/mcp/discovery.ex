defmodule MCPChat.MCP.Discovery do
  @moduledoc """
  MCP server auto-discovery functionality.

  Discovers MCP servers through:
  - Local filesystem scanning for known server patterns
  - Environment variable inspection
  - Well-known locations
  - Package manager integration (npm, pip, etc.)
  """

  require Logger

  @doc """
  Discover all available MCP servers.

  Returns a list of discovered server configurations.
  """
  def discover_servers(options \\ []) do
    methods = Keyword.get(options, :methods, [:quick_setup, :npm, :env, :known_locations])

    methods
    |> Enum.flat_map(&discover_by_method/1)
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
  """
  def discover_npm_servers() do
    case System.cmd("npm", ["list", "-g", "--depth=0", "--json"], stderr_to_stdout: true) do
      {output, 0} ->
        parse_npm_packages(output)

      {error, _} ->
        Logger.debug("Failed to list npm packages: #{error}")
        []
    end
  end

  @doc """
  Discover servers from environment variables.
  """
  def discover_env_servers() do
    System.get_env()
    |> Enum.filter(fn {key, _value} ->
      String.contains?(key, "MCP") || String.ends_with?(key, "_SERVER")
    end)
    |> Enum.map(&parse_env_server/1)
    |> Enum.reject(&is_nil/1)
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
  """
  def test_server(server_config) do
    case server_config do
      %{command: command} ->
        test_stdio_server(command)

      %{url: url} ->
        test_sse_server(url)

      _ ->
        false
    end
  end

  @doc """
  Get metadata about a discovered server.
  """
  def get_server_metadata(server_config) do
    # Try to get server info by starting it temporarily
    case start_temporary_server(server_config) do
      {:ok, info} ->
        Map.merge(server_config, %{
          metadata: %{
            name: info[:name],
            version: info[:version],
            description: info[:description],
            capabilities: info[:capabilities]
          }
        })

      _ ->
        server_config
    end
  end

  # Private functions

  defp discover_by_method(:quick_setup), do: quick_setup_servers()
  defp discover_by_method(:npm), do: discover_npm_servers()
  defp discover_by_method(:env), do: discover_env_servers()
  defp discover_by_method(:known_locations), do: discover_known_locations()
  defp discover_by_method(_), do: []

  defp parse_npm_packages(json_output) do
    case Jason.decode(json_output) do
      {:ok, %{"dependencies" => deps}} ->
        deps
        |> Enum.filter(fn {name, _} ->
          String.contains?(name, "mcp") ||
            String.contains?(name, "modelcontextprotocol")
        end)
        |> Enum.map(&npm_package_to_server_config/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp npm_package_to_server_config({package_name, _info}) do
    # Map known MCP npm packages to server configurations
    case package_name do
      "@modelcontextprotocol/server-filesystem" ->
        %{
          name: "filesystem-auto",
          command: ["npx", "-y", package_name, System.get_env("HOME", "/tmp")],
          source: :npm,
          auto_discovered: true
        }

      "@modelcontextprotocol/server-github" ->
        if System.get_env("GITHUB_TOKEN") do
          %{
            name: "github-auto",
            command: ["npx", "-y", package_name],
            env: %{"GITHUB_TOKEN" => System.get_env("GITHUB_TOKEN")},
            source: :npm,
            auto_discovered: true
          }
        else
          nil
        end

      "@modelcontextprotocol/server-postgres" ->
        if System.get_env("DATABASE_URL") do
          %{
            name: "postgres-auto",
            command: ["npx", "-y", package_name, System.get_env("DATABASE_URL")],
            source: :npm,
            auto_discovered: true
          }
        else
          nil
        end

      "@modelcontextprotocol/server-" <> rest ->
        # Generic pattern for other MCP servers
        %{
          name: "#{rest}-auto",
          command: ["npx", "-y", package_name],
          source: :npm,
          auto_discovered: true
        }

      _ ->
        nil
    end
  end

  defp parse_env_server({key, value}) do
    cond do
      String.ends_with?(key, "_MCP_SERVER") ->
        # Format: MYAPP_MCP_SERVER=command args
        name =
          key
          |> String.replace_suffix("_MCP_SERVER", "")
          |> String.downcase()

        %{
          name: "#{name}-env",
          command: String.split(value, " "),
          source: :env,
          auto_discovered: true
        }

      String.ends_with?(key, "_SERVER_URL") ->
        # Format: MYAPP_SERVER_URL=http://localhost:8_080
        name =
          key
          |> String.replace_suffix("_SERVER_URL", "")
          |> String.downcase()

        %{
          name: "#{name}-env",
          url: value,
          source: :env,
          auto_discovered: true
        }

      true ->
        nil
    end
  end

  defp scan_directory(dir) do
    File.ls!(dir)
    |> Enum.map(&Path.join(dir, &1))
    |> Enum.filter(&File.dir?/1)
    |> Enum.map(&check_mcp_server_directory/1)
    |> Enum.reject(&is_nil/1)
  end

  defp check_mcp_server_directory(dir) do
    # Check for common MCP server patterns
    cond do
      # Node.js based server
      File.exists?(Path.join(dir, "package.json")) &&
          File.exists?(Path.join(dir, "mcp.json")) ->
        parse_nodejs_server(dir)

      # Python based server
      File.exists?(Path.join(dir, "pyproject.toml")) &&
          File.exists?(Path.join(dir, "mcp.json")) ->
        parse_python_server(dir)

      # Executable server
      executable = find_executable(dir) ->
        %{
          name: Path.basename(dir) <> "-local",
          command: [executable],
          source: :local,
          auto_discovered: true
        }

      true ->
        nil
    end
  end

  defp parse_nodejs_server(dir) do
    with {:ok, mcp_json} <- File.read(Path.join(dir, "mcp.json")),
         {:ok, mcp_config} <- Jason.decode(mcp_json) do
      %{
        name: mcp_config["name"] || Path.basename(dir),
        command: ["node", Path.join(dir, mcp_config["main"] || "index.js")],
        source: :local,
        auto_discovered: true
      }
    else
      _ -> nil
    end
  end

  defp parse_python_server(dir) do
    with {:ok, mcp_json} <- File.read(Path.join(dir, "mcp.json")),
         {:ok, mcp_config} <- Jason.decode(mcp_json) do
      %{
        name: mcp_config["name"] || Path.basename(dir),
        command: ["python", "-m", mcp_config["module"] || Path.basename(dir)],
        source: :local,
        auto_discovered: true
      }
    else
      _ -> nil
    end
  end

  defp find_executable(dir) do
    ["mcp-server", "server", Path.basename(dir)]
    |> Enum.map(&Path.join(dir, &1))
    |> Enum.find(&File.exists?/1)
  end

  defp test_stdio_server(command) do
    # Try to run the command with --help or --version
    [cmd | args] = command

    case System.cmd(cmd, args ++ ["--version"], stderr_to_stdout: true) do
      {_, 0} ->
        true

      _ ->
        case System.cmd(cmd, args ++ ["--help"], stderr_to_stdout: true) do
          {_, 0} -> true
          _ -> false
        end
    end
  rescue
    _ -> false
  end

  defp test_sse_server(url) do
    # Try to connect to the SSE endpoint
    case Req.get(url <> "/sse", max_retries: 0, receive_timeout: 5_000) do
      {:ok, %{status: status}} when status in 200..299 -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp start_temporary_server(_server_config) do
    # Start a server temporarily to get its info
    # This would use the existing MCP client infrastructure
    # For now, return a placeholder
    {:error, :not_implemented}
  end
end
