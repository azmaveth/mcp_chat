defmodule MCPChat.MCP.ServerPersistence do
  @moduledoc """
  Handles persistence of MCP server connections.
  """

  require Logger

  @connections_file Path.expand("~/.mcp_chat/connected_servers.json")

  @doc """
  Save a server configuration to persistent storage.
  """
  def save_server(server_config) do
    ensure_directory()

    servers = load_all_servers()

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

    case save_to_file(updated_servers) do
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
  def remove_server(server_name) do
    ensure_directory()

    servers = load_all_servers()
    updated_servers = Enum.reject(servers, &(&1["name"] == server_name))

    if length(servers) != length(updated_servers) do
      case save_to_file(updated_servers) do
        :ok ->
          Logger.info("Removed server configuration: #{server_name}")
          :ok

        {:error, reason} ->
          Logger.error("Failed to remove server configuration: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, :not_found}
    end
  end

  @doc """
  Load all saved server configurations.
  """
  def load_all_servers() do
    ensure_directory()

    if File.exists?(@connections_file) do
      case File.read(@connections_file) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, servers} when is_list(servers) ->
              servers

            _ ->
              Logger.warning("Invalid connected_servers.json format, returning empty list")
              []
          end

        {:error, reason} ->
          Logger.error("Failed to read connected_servers.json: #{inspect(reason)}")
          []
      end
    else
      []
    end
  end

  @doc """
  Get a specific server configuration by name.
  """
  def get_server(server_name) do
    servers = load_all_servers()
    Enum.find(servers, &(&1["name"] == server_name))
  end

  @doc """
  Check if a server is saved.
  """
  def server_saved?(server_name) do
    servers = load_all_servers()
    Enum.any?(servers, &(&1["name"] == server_name))
  end

  @doc """
  Update server status (for marking as connected/disconnected).
  """
  def update_server_status(server_name, status) do
    case get_server(server_name) do
      nil ->
        {:error, :not_found}

      server ->
        updated_server = Map.put(server, "status", status)
        save_server(updated_server)
    end
  end

  # Private functions

  defp ensure_directory() do
    dir = Path.dirname(@connections_file)
    File.mkdir_p!(dir)
  end

  defp save_to_file(servers) do
    content = Jason.encode!(servers, pretty: true)
    File.write(@connections_file, content)
  end
end
