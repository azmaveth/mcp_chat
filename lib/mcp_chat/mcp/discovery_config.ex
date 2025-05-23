defmodule MCPChat.MCP.DiscoveryConfig do
  @moduledoc """
  Known MCP server configurations for quick setup.
  """

  @known_servers [
    %{
      id: "filesystem",
      name: "filesystem",
      package: "@modelcontextprotocol/server-filesystem",
      description: "Access and manage local files",
      command: ["npx", "-y", "@modelcontextprotocol/server-filesystem", "$HOME"],
      requires: []
    },
    %{
      id: "github",
      name: "github",
      package: "@modelcontextprotocol/server-github",
      description: "Interact with GitHub repositories",
      command: ["npx", "-y", "@modelcontextprotocol/server-github"],
      requires: ["GITHUB_TOKEN"],
      env_keys: ["GITHUB_TOKEN"]
    },
    %{
      id: "postgres",
      name: "postgres",
      package: "@modelcontextprotocol/server-postgres",
      description: "Query PostgreSQL databases",
      command: ["npx", "-y", "@modelcontextprotocol/server-postgres", "$DATABASE_URL"],
      requires: ["DATABASE_URL"]
    },
    %{
      id: "sqlite",
      name: "sqlite",
      package: "@modelcontextprotocol/server-sqlite",
      description: "Query SQLite databases",
      command: ["npx", "-y", "@modelcontextprotocol/server-sqlite", "*.db"],
      requires: []
    },
    %{
      id: "google-drive",
      name: "google-drive",
      package: "@modelcontextprotocol/server-google-drive",
      description: "Access Google Drive files",
      command: ["npx", "-y", "@modelcontextprotocol/server-google-drive"],
      requires: ["GOOGLE_DRIVE_API_KEY"]
    },
    %{
      id: "memory",
      name: "memory",
      package: "@modelcontextprotocol/server-memory",
      description: "Persistent memory/knowledge base",
      command: ["npx", "-y", "@modelcontextprotocol/server-memory"],
      requires: []
    },
    %{
      id: "puppeteer",
      name: "puppeteer",
      package: "@modelcontextprotocol/server-puppeteer",
      description: "Browser automation and web scraping",
      command: ["npx", "-y", "@modelcontextprotocol/server-puppeteer"],
      requires: []
    },
    %{
      id: "playwright",
      name: "playwright",
      package: "@modelcontextprotocol/server-playwright",
      description: "Browser automation and testing",
      command: ["npx", "-y", "@modelcontextprotocol/server-playwright"],
      requires: []
    }
  ]

  @doc """
  Get all known server configurations.
  """
  def known_servers, do: @known_servers

  @doc """
  Get a specific server configuration by ID.
  """
  def get_server(id) do
    Enum.find(@known_servers, fn server -> server.id == id end)
  end

  @doc """
  Check if required environment variables are set for a server.
  """
  def check_requirements(server) do
    missing =
      server[:requires]
      |> List.wrap()
      |> Enum.filter(fn var -> is_nil(System.get_env(var)) end)

    case missing do
      [] -> :ok
      vars -> {:error, {:missing_env_vars, vars}}
    end
  end

  @doc """
  Build a complete server configuration.
  """
  def build_config(server) do
    # Expand environment variables in command
    command =
      Enum.map(server.command, fn arg ->
        if String.starts_with?(arg, "$") do
          var_name = String.slice(arg, 1..-1//1)
          System.get_env(var_name, arg)
        else
          arg
        end
      end)

    base = %{
      name: server.name,
      command: command,
      source: :quick_setup,
      auto_discovered: true
    }

    # Build env map from env_keys
    if server[:env_keys] do
      env =
        server.env_keys
        |> Enum.map(fn key -> {key, System.get_env(key)} end)
        |> Enum.filter(fn {_, val} -> val != nil end)
        |> Map.new()

      if map_size(env) > 0 do
        Map.put(base, :env, env)
      else
        base
      end
    else
      base
    end
  end
end
