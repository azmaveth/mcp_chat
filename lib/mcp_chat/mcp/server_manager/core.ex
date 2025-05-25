defmodule MCPChat.MCP.ServerManager.Core do
  @moduledoc """
  Functional core for managing MCP server connections.
  Contains pure functions without GenServer state management.
  """

  alias MCPChat.MCP.Server
  alias MCPChat.ConfigProvider
  alias MCPChat.LoggerProvider

  @type server_state :: %{
          servers: map(),
          supervisor: pid() | nil
        }

  @type server_config :: %{
          name: String.t(),
          command: String.t() | nil,
          url: String.t() | nil,
          env: map(),
          auto_connect: boolean()
        }

  # Core Functions

  @doc """
  Creates initial server manager state.
  """
  @spec new_state() :: server_state()
  def new_state() do
    %{
      servers: %{},
      supervisor: nil
    }
  end

  @doc """
  Updates state with supervisor reference.
  """
  @spec set_supervisor(server_state(), pid()) :: server_state()
  def set_supervisor(state, supervisor) do
    %{state | supervisor: supervisor}
  end

  @doc """
  Starts configured servers and returns updated state.
  """
  @spec start_configured_servers(server_state(), keyword()) :: {server_state(), {:ok, integer()}}
  def start_configured_servers(state, opts \\ []) do
    config_provider = Keyword.get(opts, :config_provider, ConfigProvider.Default)
    logger_provider = Keyword.get(opts, :logger_provider, LoggerProvider.Default)
    servers = config_provider.get([:mcp, :servers]) || []

    # Start each configured server
    results = Enum.map(servers, &start_server_supervised(&1, state.supervisor, logger_provider))

    # Update state with started servers
    new_servers =
      results
      |> Enum.filter(fn {status, _} -> status == :ok end)
      |> Enum.map(fn {:ok, {name, pid}} -> {name, pid} end)
      |> Enum.into(state.servers)

    new_state = %{state | servers: new_servers}

    {new_state, {:ok, map_size(new_servers)}}
  end

  @doc """
  Starts a single server and returns updated state.
  """
  @spec start_server(server_state(), server_config(), keyword()) :: {server_state(), {:ok, pid()} | {:error, term()}}
  def start_server(state, config, opts \\ []) do
    logger_provider = Keyword.get(opts, :logger_provider, LoggerProvider.Default)

    case start_server_supervised(config, state.supervisor, logger_provider) do
      {:ok, {name, pid}} ->
        new_servers = Map.put(state.servers, name, pid)
        {%{state | servers: new_servers}, {:ok, pid}}

      {:error, reason} ->
        {state, {:error, reason}}
    end
  end

  @doc """
  Stops a server and returns updated state.
  """
  @spec stop_server(server_state(), String.t()) :: {server_state(), :ok | {:error, :not_found}}
  def stop_server(state, name) do
    case Map.get(state.servers, name) do
      nil ->
        {state, {:error, :not_found}}

      pid ->
        DynamicSupervisor.terminate_child(state.supervisor, pid)
        new_servers = Map.delete(state.servers, name)
        {%{state | servers: new_servers}, :ok}
    end
  end

  @doc """
  Lists all server statuses.
  """
  @spec list_servers(server_state()) :: list()
  def list_servers(state) do
    state.servers
    |> Enum.map(fn {name, _pid} ->
      case Server.get_status(name) do
        {:error, _} -> nil
        status -> status
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Gets status of a specific server.
  """
  @spec get_server(server_state(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_server(state, name) do
    case Map.get(state.servers, name) do
      nil ->
        {:error, :not_found}

      _pid ->
        case Server.get_status(name) do
          {:error, reason} -> {:error, reason}
          status -> {:ok, status}
        end
    end
  end

  @doc """
  Lists all tools from all servers.
  """
  @spec list_all_tools(server_state()) :: list()
  def list_all_tools(state) do
    state.servers
    |> Enum.map(fn {name, _pid} ->
      case Server.get_tools(name) do
        {:ok, tools} -> Enum.map(tools, &Map.put(&1, :server, name))
        _ -> []
      end
    end)
    |> List.flatten()
  end

  @doc """
  Calls a tool on a specific server.
  """
  @spec call_tool(server_state(), String.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def call_tool(state, server_name, tool_name, arguments) do
    if Map.has_key?(state.servers, server_name) do
      Server.call_tool(server_name, tool_name, arguments)
    else
      {:error, :server_not_found}
    end
  end

  @doc """
  Lists all resources from all servers.
  """
  @spec list_all_resources(server_state()) :: list()
  def list_all_resources(state) do
    state.servers
    |> Enum.map(fn {name, _pid} ->
      case Server.get_resources(name) do
        {:ok, resources} -> Enum.map(resources, &Map.put(&1, :server, name))
        _ -> []
      end
    end)
    |> List.flatten()
  end

  @doc """
  Reads a resource from a specific server.
  """
  @spec read_resource(server_state(), String.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def read_resource(state, server_name, uri) do
    if Map.has_key?(state.servers, server_name) do
      Server.read_resource(server_name, uri)
    else
      {:error, :server_not_found}
    end
  end

  @doc """
  Lists all prompts from all servers.
  """
  @spec list_all_prompts(server_state()) :: list()
  def list_all_prompts(state) do
    state.servers
    |> Enum.map(fn {name, _pid} ->
      case Server.get_prompts(name) do
        {:ok, prompts} -> Enum.map(prompts, &Map.put(&1, :server, name))
        _ -> []
      end
    end)
    |> List.flatten()
  end

  @doc """
  Gets a prompt from a specific server.
  """
  @spec get_prompt(server_state(), String.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def get_prompt(state, server_name, prompt_name, arguments) do
    if Map.has_key?(state.servers, server_name) do
      Server.get_prompt(server_name, prompt_name, arguments)
    else
      {:error, :server_not_found}
    end
  end

  @doc """
  Handles server process death by removing it from state.
  """
  @spec handle_server_death(server_state(), pid(), keyword()) :: server_state()
  def handle_server_death(state, pid, opts \\ []) do
    logger_provider = Keyword.get(opts, :logger_provider, LoggerProvider.Default)

    case Enum.find(state.servers, fn {_name, server_pid} -> server_pid == pid end) do
      {name, _} ->
        logger_provider.warning("MCP server #{name} died")
        %{state | servers: Map.delete(state.servers, name)}

      nil ->
        state
    end
  end

  @doc """
  Starts auto-connect servers and returns updated state.
  """
  @spec start_auto_connect_servers(server_state(), keyword()) :: server_state()
  def start_auto_connect_servers(state, opts \\ []) do
    logger_provider = Keyword.get(opts, :logger_provider, LoggerProvider.Default)
    saved_servers = MCPChat.MCP.ServerPersistence.load_all_servers()
    auto_connect_servers = Enum.filter(saved_servers, &(&1["auto_connect"] == true))

    Enum.reduce(auto_connect_servers, state, fn server_config, acc_state ->
      # Check if server is already started
      if Map.has_key?(acc_state.servers, server_config["name"]) do
        acc_state
      else
        logger_provider.info("Auto-connecting to saved server: #{server_config["name"]}")

        case start_server_supervised(server_config, acc_state.supervisor, logger_provider) do
          {:ok, {name, pid}} ->
            %{acc_state | servers: Map.put(acc_state.servers, name, pid)}

          {:error, reason} ->
            logger_provider.warning("Failed to auto-connect server #{server_config["name"]}: #{inspect(reason)}")
            acc_state
        end
      end
    end)
  end

  # Private Functions

  @spec start_server_supervised(map(), pid(), module()) :: {:ok, {String.t(), pid()}} | {:error, term()}
  defp start_server_supervised(config, supervisor, logger_provider \\ LoggerProvider.Default) do
    name = config[:name] || config["name"]
    command = config[:command] || config["command"]
    url = config[:url] || config["url"]
    env = config[:env] || config["env"] || %{}

    cond do
      name && command ->
        # Stdio transport
        child_spec = %{
          id: {Server, name},
          start:
            {Server, :start_link,
             [
               [
                 name: name,
                 command: command,
                 env: env,
                 auto_connect: true
               ]
             ]},
          restart: :temporary
        }

        case DynamicSupervisor.start_child(supervisor, child_spec) do
          {:ok, pid} ->
            {:ok, {name, pid}}

          {:error, reason} ->
            logger_provider.error("Failed to start MCP server #{name}: #{inspect(reason)}")
            {:error, reason}
        end

      name && url ->
        # SSE transport
        child_spec = %{
          id: {Server, name},
          start:
            {Server, :start_link,
             [
               [
                 name: name,
                 url: url,
                 auto_connect: true
               ]
             ]},
          restart: :temporary
        }

        case DynamicSupervisor.start_child(supervisor, child_spec) do
          {:ok, pid} ->
            {:ok, {name, pid}}

          {:error, reason} ->
            logger_provider.error("Failed to start MCP server #{name}: #{inspect(reason)}")
            {:error, reason}
        end

      true ->
        {:error, :invalid_config}
    end
  end
end
