defmodule MCPChat.MCP.ServerManager.Core do
  @moduledoc """
  Functional core for managing MCP server connections.
  Contains pure functions without GenServer state management.

  Updated to use Server structs for enhanced status tracking and background connections.
  """

  alias MCPChat.ConfigProvider
  alias MCPChat.LoggerProvider
  alias MCPChat.MCP.{BuiltinResources, HealthMonitor, ServerPersistence, ServerWrapper}
  alias MCPChat.MCP.ServerManager.Server

  @type server_state :: %{
          servers: %{String.t() => Server.t()},
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
  def new_state do
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
  Starts configured servers with background connections and returns updated state.

  Servers are immediately added to state in 'connecting' status, then connection
  attempts happen in the background to avoid blocking startup.
  """
  @spec start_configured_servers(server_state(), keyword()) :: {server_state(), {:ok, integer()}}
  def start_configured_servers(state, opts \\ []) do
    config_provider = Keyword.get(opts, :config_provider, ConfigProvider.Default)
    servers_config = config_provider.get([:mcp, :servers]) || []

    # Create Server structs for all configured servers in 'connecting' state
    servers_map =
      servers_config
      |> Enum.map(fn config ->
        name = config["name"] || config[:name] || "unnamed_server"
        {name, Server.new(name, config)}
      end)
      |> Enum.into(%{})

    # Merge with existing servers (preserving any already connected ones)
    new_servers = Map.merge(state.servers, servers_map)
    new_state = %{state | servers: new_servers}

    # Note: Actual connection attempts will be triggered asynchronously
    # by the GenServer after returning from this function
    {new_state, {:ok, map_size(servers_map)}}
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
    # Get status from Server structs
    connected_servers =
      state.servers
      |> Enum.map(fn {name, server} ->
        %{name: name, status: server.status}
      end)

    # Add built-in server (always available)
    builtin_server = %{
      name: "builtin",
      status: :connected
    }

    [builtin_server | connected_servers]
  end

  @doc """
  Gets status of a specific server.
  """
  @spec get_server(server_state(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_server(state, name) do
    if name == "builtin" do
      get_builtin_server_info()
    else
      get_external_server_status(state, name)
    end
  end

  defp get_builtin_server_info do
    {:ok,
     %{
       status: "running",
       server_name: "MCP Chat Built-in Resources",
       description: "Built-in documentation, prompts, and resources",
       transport: "internal",
       capabilities: %{
         resources: true,
         prompts: true
       }
     }}
  end

  defp get_external_server_status(state, name) do
    case Map.get(state.servers, name) do
      nil ->
        {:error, :not_found}

      pid ->
        get_server_status_from_pid(pid)
    end
  end

  defp get_server_status_from_pid(pid) do
    case Server.get_status(pid) do
      {:error, reason} -> {:error, reason}
      status -> {:ok, status}
    end
  end

  @doc """
  Lists all tools from connected servers only.
  """
  @spec list_all_tools(server_state()) :: list()
  def list_all_tools(state) do
    state.servers
    |> Enum.filter(fn {_name, server} -> Server.connected?(server) end)
    |> Enum.map(fn {name, server} ->
      tools = Server.get_tools(server)
      Enum.map(tools, &Map.put(&1, :server, name))
    end)
    |> List.flatten()
  end

  @doc """
  Calls a tool on a specific server with health tracking.
  """
  @spec call_tool(server_state(), String.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def call_tool(state, server_name, tool_name, arguments) do
    case Map.get(state.servers, server_name) do
      nil ->
        {:error, :server_not_found}

      server ->
        if Server.connected?(server) do
          call_tool_with_health_tracking(server.pid, server_name, tool_name, arguments)
        else
          {:error, :server_not_connected}
        end
    end
  end

  defp call_tool_with_health_tracking(pid, server_name, tool_name, arguments) do
    start_time = System.monotonic_time(:millisecond)

    case ServerWrapper.call_tool(pid, tool_name, arguments) do
      {:ok, result} = success ->
        response_time = System.monotonic_time(:millisecond) - start_time
        HealthMonitor.record_success(server_name, response_time)
        success

      {:error, _reason} = error ->
        HealthMonitor.record_failure(server_name)
        error
    end
  end

  @doc """
  Lists all resources from connected servers only.
  """
  @spec list_all_resources(server_state()) :: list()
  def list_all_resources(state) do
    # Get resources from connected servers only
    server_resources =
      state.servers
      |> Enum.filter(fn {_name, server} -> Server.connected?(server) end)
      |> Enum.map(fn {name, server} ->
        resources = Server.get_resources(server)
        Enum.map(resources, &Map.put(&1, :server, name))
      end)
      |> List.flatten()

    # Add built-in resources
    builtin_resources =
      BuiltinResources.list_resources()
      |> Enum.map(&Map.put(&1, "server", "builtin"))

    server_resources ++ builtin_resources
  end

  @doc """
  Reads a resource from a specific server.
  """
  @spec read_resource(server_state(), String.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def read_resource(state, server_name, uri) do
    # Check if it's a built-in resource
    if server_name == "builtin" do
      BuiltinResources.read_resource(uri)
    else
      do_read_resource_from_server(state, server_name, uri)
    end
  end

  defp do_read_resource_from_server(state, server_name, uri) do
    case Map.get(state.servers, server_name) do
      nil ->
        {:error, :server_not_found}

      server ->
        if Server.connected?(server) do
          ServerWrapper.read_resource(server.pid, uri)
        else
          {:error, :server_not_connected}
        end
    end
  end

  @doc """
  Lists all prompts from connected servers only.
  """
  @spec list_all_prompts(server_state()) :: list()
  def list_all_prompts(state) do
    # Get prompts from connected servers only
    server_prompts =
      state.servers
      |> Enum.filter(fn {_name, server} -> Server.connected?(server) end)
      |> Enum.map(fn {name, server} ->
        prompts = Server.get_prompts(server)
        Enum.map(prompts, &Map.put(&1, :server, name))
      end)
      |> List.flatten()

    # Add built-in prompts
    builtin_prompts =
      BuiltinResources.list_prompts()
      |> Enum.map(&Map.put(&1, "server", "builtin"))

    server_prompts ++ builtin_prompts
  end

  @doc """
  Gets a prompt from a specific server.
  """
  @spec get_prompt(server_state(), String.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def get_prompt(state, server_name, prompt_name, arguments) do
    # Check if it's a built-in prompt
    if server_name == "builtin" do
      BuiltinResources.get_prompt(prompt_name)
    else
      do_get_prompt_from_server(state, server_name, prompt_name, arguments)
    end
  end

  defp do_get_prompt_from_server(state, server_name, prompt_name, arguments) do
    case Map.get(state.servers, server_name) do
      nil ->
        {:error, :server_not_found}

      server ->
        if Server.connected?(server) do
          ServerWrapper.get_prompt(server.pid, prompt_name, arguments)
        else
          {:error, :server_not_connected}
        end
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
    saved_servers = ServerPersistence.load_all_servers()
    auto_connect_servers = Enum.filter(saved_servers, &(&1["auto_connect"] == true))

    Enum.reduce(auto_connect_servers, state, fn server_config, acc_state ->
      process_auto_connect_server(server_config, acc_state, logger_provider)
    end)
  end

  # Private Functions

  defp process_auto_connect_server(server_config, acc_state, logger_provider) do
    # Check if server is already started
    if Map.has_key?(acc_state.servers, server_config["name"]) do
      acc_state
    else
      attempt_auto_connect(server_config, acc_state, logger_provider)
    end
  end

  defp attempt_auto_connect(server_config, acc_state, logger_provider) do
    logger_provider.info("Auto-connecting to saved server: #{server_config["name"]}")

    case start_server_supervised(server_config, acc_state.supervisor, logger_provider) do
      {:ok, {name, pid}} ->
        %{acc_state | servers: Map.put(acc_state.servers, name, pid)}

      {:error, reason} ->
        logger_provider.warning("Failed to auto-connect server #{server_config["name"]}: #{inspect(reason)}")
        acc_state
    end
  end

  @spec start_server_supervised(map(), pid(), module()) :: {:ok, {String.t(), pid()}} | {:error, term()}
  defp start_server_supervised(config, supervisor, logger_provider) do
    case build_server_config(config) do
      {:ok, server_config} ->
        start_server_with_config(server_config, supervisor, logger_provider)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Builds server configuration for background connection.
  """
  def build_server_config(config, server_name) do
    # Use the provided name or extract from config
    name = server_name || extract_server_name(config)

    cond do
      name && has_command?(config) ->
        build_stdio_config(config, name)

      name && has_url?(config) ->
        build_sse_config(config, name)

      true ->
        {:error, :invalid_config}
    end
  end

  defp build_server_config(config) do
    name = extract_server_name(config)

    cond do
      name && has_command?(config) ->
        build_stdio_config(config, name)

      name && has_url?(config) ->
        build_sse_config(config, name)

      true ->
        {:error, :invalid_config}
    end
  end

  defp extract_server_name(config) do
    config[:name] || config["name"]
  end

  defp has_command?(config), do: config[:command] || config["command"]
  defp has_url?(config), do: config[:url] || config["url"]

  defp build_stdio_config(config, name) do
    command = extract_command(config)
    env = extract_env(config)
    {:ok, %{name: name, command: command, transport: :stdio, env: env}}
  end

  defp build_sse_config(config, name) do
    url = extract_url(config)
    {:ok, %{name: name, url: url, transport: :sse}}
  end

  defp extract_command(config), do: config[:command] || config["command"]
  defp extract_url(config), do: config[:url] || config["url"]
  defp extract_env(config), do: config[:env] || config["env"] || %{}

  defp start_server_with_config(server_config, supervisor, logger_provider) do
    child_spec = build_child_spec(server_config)

    case DynamicSupervisor.start_child(supervisor, child_spec) do
      {:ok, pid} ->
        {:ok, {server_config.name, pid}}

      {:error, reason} ->
        logger_provider.error("Failed to start MCP server #{server_config.name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_child_spec(server_config) do
    %{
      id: {ServerWrapper, server_config.name},
      start: {ServerWrapper, :start_link, [server_config, []]},
      restart: :temporary
    }
  end

  # New functions for background connection management

  @doc """
  Gets servers that are in connecting state and ready for connection attempts.
  """
  @spec get_connecting_servers(server_state()) :: [Server.t()]
  def get_connecting_servers(state) do
    state.servers
    |> Enum.filter(fn {_name, server} -> server.status == :connecting end)
    |> Enum.map(fn {_name, server} -> server end)
  end

  @doc """
  Updates server state after successful connection.
  """
  @spec mark_server_connected(server_state(), String.t(), pid(), reference(), map()) :: server_state()
  def mark_server_connected(state, server_name, pid, monitor_ref, capabilities \\ %{}) do
    case Map.get(state.servers, server_name) do
      nil ->
        state

      server ->
        updated_server = Server.mark_connected(server, pid, monitor_ref, capabilities)
        %{state | servers: Map.put(state.servers, server_name, updated_server)}
    end
  end

  @doc """
  Updates server state after failed connection.
  """
  @spec mark_server_failed(server_state(), String.t(), term()) :: server_state()
  def mark_server_failed(state, server_name, error) do
    case Map.get(state.servers, server_name) do
      nil ->
        state

      server ->
        updated_server = Server.mark_failed(server, error)
        %{state | servers: Map.put(state.servers, server_name, updated_server)}
    end
  end

  @doc """
  Updates server state after disconnection.
  """
  @spec mark_server_disconnected(server_state(), String.t()) :: server_state()
  def mark_server_disconnected(state, server_name) do
    case Map.get(state.servers, server_name) do
      nil ->
        state

      server ->
        updated_server = Server.mark_disconnected(server)
        %{state | servers: Map.put(state.servers, server_name, updated_server)}
    end
  end

  @doc """
  Gets server by name, returning the Server struct.
  """
  @spec get_server_info(server_state(), String.t()) :: {:ok, Server.t()} | {:error, :not_found}
  def get_server_info(state, server_name) do
    case Map.get(state.servers, server_name) do
      nil -> {:error, :not_found}
      server -> {:ok, server}
    end
  end

  @doc """
  Lists all servers with their status information.
  """
  @spec list_servers_with_status(server_state()) :: [%{name: String.t(), server: Server.t()}]
  def list_servers_with_status(state) do
    builtin_server = %{
      name: "builtin",
      server: %Server{
        name: "builtin",
        config: %{},
        status: :connected,
        capabilities: %{tools: [], resources: [], prompts: []}
      }
    }

    server_list =
      state.servers
      |> Enum.map(fn {name, server} -> %{name: name, server: server} end)

    [builtin_server | server_list]
  end

  @doc """
  Records a successful operation for health tracking.
  """
  @spec record_server_success(server_state(), String.t(), non_neg_integer()) :: server_state()
  def record_server_success(state, server_name, response_time_ms) do
    case Map.get(state.servers, server_name) do
      nil ->
        state

      server ->
        updated_server = Server.record_success(server, response_time_ms)
        %{state | servers: Map.put(state.servers, server_name, updated_server)}
    end
  end

  @doc """
  Records a failed operation for health tracking.
  """
  @spec record_server_failure(server_state(), String.t()) :: server_state()
  def record_server_failure(state, server_name) do
    case Map.get(state.servers, server_name) do
      nil ->
        state

      server ->
        updated_server = Server.record_failure(server)
        %{state | servers: Map.put(state.servers, server_name, updated_server)}
    end
  end
end
