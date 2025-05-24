defmodule MCPChat.MCP.ServerPersistence do
  @moduledoc """
  Handles persistence of MCP server connections.
  """

  require Logger

  # Legacy file path for backward compatibility
  @connections_file Path.expand("~/.mcp_chat/connected_servers.json")

  @doc """
  Save a server configuration to persistent storage.
  """
  def save_server(server_config, file_path \\ nil) do
    file_path = file_path || saved_servers_file()
    ensure_directory(file_path)

    servers = load_all_servers(file_path)

    # Convert to map with string keys for consistency
    server_config = stringify_keys(server_config)

    # Update or add the server config
    updated_servers =
      case Enum.find_index(servers, &(&1["name"] == server_config["name"])) do
        nil ->
          # Add new server
          servers ++ [server_config]

        index ->
          # Update existing server
          List.replace_at(servers, index, server_config)
      end

    case save_to_file(updated_servers, file_path) do
      :ok ->
        Logger.info("Saved server configuration: #{server_config["name"]}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to save server configuration: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Remove a server configuration from persistent storage.
  """
  def remove_server(server_name, file_path \\ nil) do
    file_path = file_path || saved_servers_file()
    ensure_directory(file_path)

    servers = load_all_servers(file_path)
    updated_servers = Enum.reject(servers, &(&1["name"] == server_name))

    if length(servers) != length(updated_servers) do
      case save_to_file(updated_servers, file_path) do
        :ok ->
          Logger.info("Removed server configuration: #{server_name}")
          :ok

        {:error, reason} ->
          Logger.error("Failed to remove server configuration: #{inspect(reason)}")
          {:error, reason}
      end
    else
      # Return :ok even if server not found for consistency
      :ok
    end
  end

  @doc """
  Load all saved server configurations.
  """
  def load_all_servers(file_path \\ nil) do
    file_path = file_path || saved_servers_file()
    ensure_directory(file_path)

    if File.exists?(file_path) do
      case File.read(file_path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, servers} when is_list(servers) ->
              # Return with atom keys for consistency
              Enum.map(servers, &atomize_keys/1)

            _ ->
              Logger.warning("Failed to parse saved servers file, returning empty list")
              []
          end

        {:error, reason} ->
          Logger.error("Failed to read saved servers file: #{inspect(reason)}")
          []
      end
    else
      []
    end
  end

  @doc """
  Get a specific server configuration by name.
  """
  def get_server(server_name, file_path \\ nil) do
    servers = load_all_servers(file_path)
    Enum.find(servers, &(&1.name == server_name || &1[:name] == server_name))
  end

  @doc """
  Check if a server is saved.
  """
  def server_saved?(server_name, file_path \\ nil) do
    servers = load_all_servers(file_path)
    Enum.any?(servers, &(&1.name == server_name || &1[:name] == server_name))
  end

  @doc """
  Update server status (for marking as connected/disconnected).
  """
  def update_server_status(server_name, status, file_path \\ nil) do
    case get_server(server_name, file_path) do
      nil ->
        {:error, :not_found}

      server ->
        updated_server = Map.put(server, :status, status)
        save_server(updated_server, file_path)
    end
  end

  @doc """
  Get the path to the saved servers file.
  """
  def saved_servers_file() do
    Path.join(MCPChat.Config.config_dir(), "saved_servers.json")
  end

  @doc """
  Convert string keys to atoms in a map.
  """
  def atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
      {k, v} -> {k, v}
    end)
  end

  def atomize_keys(value), do: value

  # Private functions

  defp ensure_directory(file_path) do
    dir = Path.dirname(file_path)
    File.mkdir_p!(dir)
  end

  defp save_to_file(servers, file_path) do
    content = Jason.encode!(servers, pretty: true)
    File.write(file_path, content)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp stringify_keys(value), do: value
end
