defmodule MCPChat.MCP.ServerWrapper do
  @moduledoc """
  Wrapper that manages MCP server connections.

  For stdio transport:
  - Starts a StdioProcessManager to manage the OS process
  - Starts either a standard ExMCP client or NotificationClient to communicate with it

  For other transports:
  - Directly starts the appropriate client
  """

  use GenServer
  require Logger

  def start_link(config, opts \\ []) do
    GenServer.start_link(__MODULE__, {config, opts})
  end

  # Delegate functions to underlying client
  def get_status(wrapper) do
    GenServer.call(wrapper, :get_status)
  end

  def call_tool(wrapper, tool, args) do
    GenServer.call(wrapper, {:call_tool, tool, args})
  end

  def get_tools(wrapper, timeout \\ 10_000) do
    GenServer.call(wrapper, :get_tools, timeout)
  end

  @doc """
  Wait for the server to be ready for MCP calls.
  """
  def wait_for_ready(wrapper, timeout \\ 10_000) do
    GenServer.call(wrapper, :wait_for_ready, timeout)
  end

  def get_resources(wrapper) do
    GenServer.call(wrapper, :get_resources)
  end

  def read_resource(wrapper, uri) do
    GenServer.call(wrapper, {:read_resource, uri})
  end

  def get_prompts(wrapper) do
    GenServer.call(wrapper, :get_prompts)
  end

  def get_prompt(wrapper, name, args) do
    GenServer.call(wrapper, {:get_prompt, name, args})
  end

  @impl true
  def init({config, _opts}) do
    notifications_enabled = MCPChat.Config.get_runtime("notifications.enabled", false)
    transport = determine_transport(config)

    case transport do
      :stdio ->
        init_stdio_transport(config, notifications_enabled)

      _ ->
        init_other_transport(config, notifications_enabled, transport)
    end
  end

  defp init_stdio_transport(config, notifications_enabled) do
    # Start process manager for stdio transport
    process_manager = start_stdio_process_manager(config)
    client_opts = build_client_opts(config, process_manager)
    client_pid = start_client(client_opts, notifications_enabled)

    Process.monitor(client_pid)

    {:ok,
     %{
       client: client_pid,
       process_manager: process_manager,
       config: config,
       type: get_client_type(notifications_enabled),
       transport: :stdio
     }}
  end

  defp init_other_transport(config, notifications_enabled, transport) do
    client_opts = build_client_opts(config)
    client_pid = start_client(client_opts, notifications_enabled)

    Process.monitor(client_pid)

    {:ok,
     %{
       client: client_pid,
       process_manager: nil,
       config: config,
       type: get_client_type(notifications_enabled),
       transport: transport
     }}
  end

  defp start_stdio_process_manager(config) do
    command = config[:command] || config["command"]
    env = config[:env] || config["env"] || %{}
    {cmd, args} = parse_command(command)

    process_manager_opts = [
      command: cmd,
      args: args,
      env: Map.to_list(env),
      auto_start: true
    ]

    {:ok, process_manager} = MCPChat.MCP.StdioProcessManager.start_link(process_manager_opts)
    Process.monitor(process_manager)
    process_manager
  end

  defp start_client(client_opts, notifications_enabled) do
    {:ok, client_pid} =
      if notifications_enabled do
        MCPChat.MCP.NotificationClient.start_link(client_opts)
      else
        ExMCP.Client.start_link(client_opts)
      end

    client_pid
  end

  defp get_client_type(notifications_enabled) do
    if notifications_enabled, do: :notification, else: :standard
  end

  # Forward all calls to the underlying client
  @impl true
  def handle_call(:get_status, _from, state) do
    # Special handling for status
    if Process.alive?(state.client) do
      {:reply, :connected, state}
    else
      {:reply, :disconnected, state}
    end
  end

  def handle_call({:call_tool, tool, args}, _from, state) do
    forward_to_client(state, fn client ->
      if state.type == :notification do
        MCPChat.MCP.NotificationClient.call_tool(client, tool, args)
      else
        ExMCP.Client.call_tool(client, tool, args)
      end
    end)
  end

  def handle_call(:get_tools, _from, state) do
    forward_to_client(state, fn client ->
      if state.type == :notification do
        MCPChat.MCP.NotificationClient.list_tools(client)
      else
        ExMCP.Client.list_tools(client)
      end
    end)
  end

  def handle_call(:wait_for_ready, _from, state) do
    # Check if the client process is alive and responsive
    if Process.alive?(state.client) do
      # Use async task with timeout to avoid hanging GenServer
      task =
        Task.async(fn ->
          try do
            if state.type == :notification do
              MCPChat.MCP.NotificationClient.list_tools(state.client)
            else
              ExMCP.Client.list_tools(state.client)
            end
          catch
            :exit, _ -> {:error, :timeout}
            _ -> {:error, :exception}
          end
        end)

      case Task.yield(task, 3_000) || Task.shutdown(task) do
        {:ok, {:ok, _}} -> {:reply, :ready, state}
        {:ok, {:error, _}} -> {:reply, {:error, :not_ready}, state}
        _ -> {:reply, {:error, :not_ready}, state}
      end
    else
      {:reply, {:error, :not_ready}, state}
    end
  end

  def handle_call(:get_resources, _from, state) do
    forward_to_client(state, fn client ->
      if state.type == :notification do
        MCPChat.MCP.NotificationClient.list_resources(client)
      else
        ExMCP.Client.list_resources(client)
      end
    end)
  end

  def handle_call({:read_resource, uri}, _from, state) do
    forward_to_client(state, fn client ->
      if state.type == :notification do
        MCPChat.MCP.NotificationClient.read_resource(client, uri)
      else
        ExMCP.Client.read_resource(client, uri)
      end
    end)
  end

  def handle_call(:get_prompts, _from, state) do
    forward_to_client(state, fn client ->
      if state.type == :notification do
        MCPChat.MCP.NotificationClient.list_prompts(client)
      else
        ExMCP.Client.list_prompts(client)
      end
    end)
  end

  def handle_call({:get_prompt, name, args}, _from, state) do
    forward_to_client(state, fn client ->
      if state.type == :notification do
        MCPChat.MCP.NotificationClient.get_prompt(client, name, args)
      else
        ExMCP.Client.get_prompt(client, name, args)
      end
    end)
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) when pid == state.client do
    # Client died, stop this wrapper too
    Logger.warning("MCP client died: #{inspect(reason)}")
    {:stop, {:client_died, reason}, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) when pid == state.process_manager do
    # Process manager died (stdio transport only)
    Logger.error("MCP process manager died: #{inspect(reason)}")
    # The client will likely die too, but we'll stop proactively
    {:stop, {:process_manager_died, reason}, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("ServerWrapper terminating: #{inspect(reason)}")

    # Stop the process manager if we have one (stdio transport)
    if state[:process_manager] do
      MCPChat.MCP.StdioProcessManager.stop_process(state.process_manager)
    end

    :ok
  end

  # Private Functions

  defp parse_command(command) do
    parts = String.split(command, " ", trim: true)

    case parts do
      [] -> {"", []}
      [cmd] -> {cmd, []}
      [cmd | args] -> {cmd, args}
    end
  end

  defp forward_to_client(state, fun) do
    try do
      result = fun.(state.client)
      {:reply, result, state}
    rescue
      e ->
        {:reply, {:error, e}, state}
    end
  end

  defp determine_transport(config) do
    cond do
      config[:command] || config["command"] ->
        :stdio

      config[:url] || config["url"] ->
        determine_url_transport(config)

      config[:target] || config["target"] ->
        :beam

      true ->
        :unknown
    end
  end

  defp determine_url_transport(config) do
    url = config[:url] || config["url"]

    if String.starts_with?(url, "ws://") or String.starts_with?(url, "wss://") do
      :websocket
    else
      :sse
    end
  end

  defp build_client_opts(config, process_manager \\ nil) do
    base_opts = [
      server_name: config[:name] || config["name"]
    ]

    cond do
      process_manager != nil ->
        build_managed_stdio_opts(base_opts, process_manager)

      config[:command] || config["command"] ->
        build_stdio_opts(base_opts, config)

      config[:url] || config["url"] ->
        build_sse_opts(base_opts, config)

      true ->
        raise "Invalid server config: missing command or url"
    end
  end

  defp build_managed_stdio_opts(base_opts, process_manager) do
    base_opts ++
      [
        transport: MCPChat.MCP.Transport.ManagedStdio,
        process_manager: process_manager
      ]
  end

  defp build_stdio_opts(base_opts, config) do
    base_opts ++
      [
        transport: :stdio,
        command: config[:command] || config["command"],
        env: config[:env] || config["env"] || %{}
      ]
  end

  defp build_sse_opts(base_opts, config) do
    base_opts ++
      [
        transport: :sse,
        url: config[:url] || config["url"]
      ]
  end
end
