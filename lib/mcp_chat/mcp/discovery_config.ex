defmodule MCPChat.MCP.DiscoveryConfig do
  @moduledoc """
  Known MCP server configurations for quick setup.

  Loads server configurations from priv/known_servers.json at compile time.
  """

  # Load the JSON file at compile time
  @external_resource Path.join([__DIR__, "..", "..", "..", "priv", "known_servers.json"])

  @known_servers_json File.read!(@external_resource)
  @known_servers (case Jason.decode(@known_servers_json) do
                    {:ok, %{"servers" => servers}} ->
                      # Convert string keys to atoms for easier access
                      Enum.map(servers, fn server ->
                        server
                        |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
                        |> Map.new()
                      end)

                    _ ->
                      # Fallback to empty list if parsing fails
                      []
                  end)

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

  @doc """
  Get the path to the known servers configuration file.
  """
  def config_file_path() do
    Application.app_dir(:mcp_chat, ["priv", "known_servers.json"])
  end
end
