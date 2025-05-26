defmodule MCPChat.MCP.ServerWrapper do
  @moduledoc """
  Wrapper that starts either a standard ExMCP client or a NotificationClient
  based on configuration.
  """

  use GenServer

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

  def get_tools(wrapper) do
    GenServer.call(wrapper, :get_tools)
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
    # Check if notifications are enabled
    notifications_enabled = MCPChat.Config.get_runtime("notifications.enabled", false)

    # Prepare client options
    client_opts = build_client_opts(config)

    # Start appropriate client
    {:ok, client_pid} =
      if notifications_enabled do
        MCPChat.MCP.NotificationClient.start_link(client_opts)
      else
        ExMCP.Client.start_link(client_opts)
      end

    # Monitor the client
    Process.monitor(client_pid)

    {:ok, %{client: client_pid, config: config, type: if(notifications_enabled, do: :notification, else: :standard)}}
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
    {:stop, {:client_died, reason}, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp forward_to_client(state, fun) do
    try do
      result = fun.(state.client)
      {:reply, result, state}
    rescue
      e ->
        {:reply, {:error, e}, state}
    end
  end

  defp build_client_opts(config) do
    base_opts = [
      server_name: config.name || config[:name]
    ]

    cond do
      config[:command] || config["command"] ->
        # Stdio transport
        base_opts ++
          [
            transport: :stdio,
            command: config[:command] || config["command"],
            env: config[:env] || config["env"] || %{}
          ]

      config[:url] || config["url"] ->
        # SSE transport
        base_opts ++
          [
            transport: :sse,
            url: config[:url] || config["url"]
          ]

      true ->
        raise "Invalid server config: missing command or url"
    end
  end
end
