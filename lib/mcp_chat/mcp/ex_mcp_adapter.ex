defmodule MCPChat.MCP.ExMCPAdapter do
  @moduledoc """
  Adapter that wraps ExMCP to work with MCPChat's existing MCP interface.

  This adapter allows mcp_chat to use the ex_mcp library while maintaining
  compatibility with the existing MCPChat.MCP interface.
  """

  use GenServer
  require Logger

  defstruct [
    :server_info,
    :capabilities,
    :tools,
    :resources,
    :prompts,
    :pending_requests,
    :callback_pid,
    :ex_mcp_client,
    :transport_config
  ]

  # Client API - matches MCPChat.MCP.Client interface

  def start_link(config, opts \\ []) do
    GenServer.start_link(__MODULE__, {config, opts})
  end

  def initialize(client, client_info) do
    GenServer.cast(client, {:initialize, client_info})
  end

  def list_tools(client) do
    GenServer.call(client, :list_tools)
  end

  def call_tool(client, name, arguments) do
    GenServer.call(client, {:call_tool, name, arguments})
  end

  def list_resources(client) do
    GenServer.call(client, :list_resources)
  end

  def read_resource(client, uri) do
    GenServer.call(client, {:read_resource, uri})
  end

  def list_prompts(client) do
    GenServer.call(client, :list_prompts)
  end

  def get_prompt(client, name, arguments \\ %{}) do
    GenServer.call(client, {:get_prompt, name, arguments})
  end

  def stop(client) do
    GenServer.stop(client)
  end

  # Server Callbacks

  @impl true
  def init({config, opts}) do
    callback_pid = Keyword.get(opts, :callback_pid, self())

    state = %__MODULE__{
      server_info: nil,
      capabilities: %{},
      tools: [],
      resources: [],
      prompts: [],
      pending_requests: %{},
      callback_pid: callback_pid,
      ex_mcp_client: nil,
      transport_config: config
    }

    # Start ExMCP client with appropriate transport
    case start_ex_mcp_client(config) do
      {:ok, ex_mcp_client} ->
        new_state = %{state | ex_mcp_client: ex_mcp_client}
        {:ok, new_state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_cast({:initialize, _client_info}, state) do
    # ExMCP clients auto-initialize, so we just need to get server info
    case ExMCP.Client.server_info(state.ex_mcp_client) do
      {:ok, server_info} ->
        # Send initialization complete message to callback
        send(state.callback_pid, {:mcp_initialized, server_info})

        new_state = %{state | server_info: server_info, capabilities: Map.get(server_info, "capabilities", %{})}
        {:noreply, new_state}

      {:error, reason} ->
        send(state.callback_pid, {:mcp_error, reason})
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:list_tools, _from, state) do
    case ExMCP.Client.list_tools(state.ex_mcp_client) do
      {:ok, tools} ->
        new_state = %{state | tools: tools}
        {:reply, {:ok, tools}, new_state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:call_tool, name, arguments}, _from, state) do
    case ExMCP.Client.call_tool(state.ex_mcp_client, name, arguments) do
      {:ok, result} ->
        {:reply, {:ok, result}, state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call(:list_resources, _from, state) do
    case ExMCP.Client.list_resources(state.ex_mcp_client) do
      {:ok, resources} ->
        new_state = %{state | resources: resources}
        {:reply, {:ok, resources}, new_state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:read_resource, uri}, _from, state) do
    case ExMCP.Client.read_resource(state.ex_mcp_client, uri) do
      {:ok, content} ->
        {:reply, {:ok, content}, state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call(:list_prompts, _from, state) do
    case ExMCP.Client.list_prompts(state.ex_mcp_client) do
      {:ok, prompts} ->
        new_state = %{state | prompts: prompts}
        {:reply, {:ok, prompts}, new_state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:get_prompt, name, arguments}, _from, state) do
    case ExMCP.Client.get_prompt(state.ex_mcp_client, name, arguments) do
      {:ok, prompt} ->
        {:reply, {:ok, prompt}, state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call(:get_status, _from, state) do
    status =
      if state.ex_mcp_client do
        # Check if the ExMCP client process is alive
        if Process.alive?(state.ex_mcp_client) do
          :connected
        else
          :disconnected
        end
      else
        :disconnected
      end

    {:reply, {:ok, status}, state}
  end

  def handle_call(:get_tools, _from, state) do
    result =
      if state.ex_mcp_client do
        ExMCP.Client.list_tools(state.ex_mcp_client)
      else
        {:error, :not_connected}
      end

    {:reply, result, state}
  end

  def handle_call(:get_resources, _from, state) do
    result =
      if state.ex_mcp_client do
        case ExMCP.Client.list_resources(state.ex_mcp_client) do
          {:ok, {"resources", resources}} -> {:ok, resources}
          {:ok, resources} when is_list(resources) -> {:ok, resources}
          error -> error
        end
      else
        {:error, :not_connected}
      end

    {:reply, result, state}
  end

  def handle_call(:get_prompts, _from, state) do
    result =
      if state.ex_mcp_client do
        case ExMCP.Client.list_prompts(state.ex_mcp_client) do
          {:ok, {"prompts", prompts}} -> {:ok, prompts}
          {:ok, prompts} when is_list(prompts) -> {:ok, prompts}
          error -> error
        end
      else
        {:error, :not_connected}
      end

    {:reply, result, state}
  end

  # Additional functions for ServerManager compatibility

  def get_status(server_ref) when is_pid(server_ref) do
    GenServer.call(server_ref, :get_status)
  end

  def get_status(server_name) when is_binary(server_name) do
    # For string names, we need to look up the PID from the ServerManager
    {:error, :invalid_server_reference}
  end

  def get_tools(server_ref) when is_pid(server_ref) do
    GenServer.call(server_ref, :get_tools)
  end

  def get_tools(server_name) when is_binary(server_name) do
    {:error, :invalid_server_reference}
  end

  def get_resources(server_ref) when is_pid(server_ref) do
    GenServer.call(server_ref, :get_resources)
  end

  def get_resources(server_name) when is_binary(server_name) do
    {:error, :invalid_server_reference}
  end

  def get_prompts(server_ref) when is_pid(server_ref) do
    GenServer.call(server_ref, :get_prompts)
  end

  def get_prompts(server_name) when is_binary(server_name) do
    {:error, :invalid_server_reference}
  end

  @impl true
  def terminate(_reason, state) do
    if state.ex_mcp_client do
      GenServer.stop(state.ex_mcp_client)
    end

    :ok
  end

  # Private helper functions

  defp start_ex_mcp_client(config) do
    # Convert MCPChat config format to ExMCP format
    case convert_config(config) do
      {:error, reason} ->
        {:error, reason}

      ex_mcp_config ->
        case ExMCP.Client.start_link(ex_mcp_config) do
          {:ok, client} ->
            {:ok, client}

          error ->
            error
        end
    end
  end

  defp convert_config(config) do
    # Convert MCPChat MCP configuration to ExMCP format
    # Ensure config is a map
    config_map = if is_list(config), do: Enum.into(config, %{}), else: config

    case determine_transport(config_map) do
      {:websocket, _url} ->
        {:error, :websocket_not_supported}

      {:stdio, command_config} ->
        build_stdio_config(command_config)

      {:sse, sse_config} ->
        build_sse_config(sse_config)

      {:beam, beam_config} ->
        build_beam_config(beam_config)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_stdio_config(command_config) do
    # Parse command to get the proper executable and args
    {cmd, args} = parse_command_for_exmcp(command_config.command, command_config.args || [])

    [
      transport: ExMCP.Transport.Stdio,
      command: [cmd | args],
      env: command_config.env || %{}
    ]
  end

  defp build_sse_config(sse_config) do
    [
      transport: ExMCP.Transport.SSE,
      url: sse_config.url,
      headers: Map.to_list(sse_config.headers || %{})
    ]
  end

  defp build_beam_config(beam_config) do
    [
      transport: ExMCP.Transport.Beam,
      target: beam_config.target
    ]
  end

  defp determine_transport(config) do
    cond do
      has_explicit_transport?(config) ->
        handle_explicit_transport(config)

      has_url_config?(config) ->
        handle_url_config(config)

      has_command_config?(config) ->
        handle_stdio_config(config)

      has_beam_target?(config) ->
        handle_beam_config(config)

      true ->
        {:error, :unknown_transport}
    end
  end

  defp parse_command_for_exmcp(command, args) when is_list(command) do
    # Command is already a list
    [cmd | cmd_args] = command
    {cmd, cmd_args ++ args}
  end

  defp parse_command_for_exmcp(command, args) when is_binary(command) do
    # Check if command contains spaces
    if String.contains?(command, " ") do
      # Split the command string
      parts = String.split(command, " ", trim: true)
      [cmd | cmd_args] = parts
      {cmd, cmd_args ++ args}
    else
      {command, args}
    end
  end

  defp parse_command_for_exmcp(command, args) do
    {to_string(command), args}
  end

  # Transport determination helpers

  defp has_explicit_transport?(config) do
    Map.has_key?(config, :transport) or Map.has_key?(config, "transport")
  end

  defp has_url_config?(config) do
    Map.has_key?(config, :url) or Map.has_key?(config, "url")
  end

  defp has_command_config?(config) do
    Map.has_key?(config, :command) or Map.has_key?(config, "command")
  end

  defp has_beam_target?(config) do
    Map.has_key?(config, :target) or Map.has_key?(config, "target")
  end

  defp handle_explicit_transport(config) do
    transport = Map.get(config, :transport) || Map.get(config, "transport")

    case transport do
      :stdio -> build_stdio_transport_config(config)
      :sse -> build_sse_transport_config(config)
      :beam -> build_beam_transport_config(config)
      _ -> {:error, :unknown_transport}
    end
  end

  defp handle_url_config(config) do
    url = Map.get(config, :url) || Map.get(config, "url")

    if String.starts_with?(url, "ws://") or String.starts_with?(url, "wss://") do
      {:websocket, url}
    else
      {:sse, %{url: url, headers: Map.get(config, :headers, %{})}}
    end
  end

  defp handle_stdio_config(config) do
    {:stdio, build_stdio_command_config(config)}
  end

  defp handle_beam_config(config) do
    {:beam, %{target: Map.get(config, :target) || Map.get(config, "target")}}
  end

  defp build_stdio_transport_config(config) do
    command = Map.get(config, :command) || Map.get(config, "command")
    {cmd, args} = parse_command_config(command, config)

    {:stdio,
     %{
       command: cmd,
       args: args,
       env: Map.get(config, :env, %{}) || Map.get(config, "env", %{})
     }}
  end

  defp build_sse_transport_config(config) do
    {:sse,
     %{
       url: Map.get(config, :url) || Map.get(config, "url"),
       headers: Map.get(config, :headers, %{})
     }}
  end

  defp build_beam_transport_config(config) do
    {:beam, %{target: Map.get(config, :target) || Map.get(config, "target")}}
  end

  defp build_stdio_command_config(config) do
    command = Map.get(config, :command) || Map.get(config, "command")
    {cmd, args} = parse_command_config(command, config)

    %{
      command: cmd,
      args: args,
      env: Map.get(config, :env, %{}) || Map.get(config, "env", %{})
    }
  end

  defp parse_command_config(command, config) do
    case command do
      [cmd | args] when is_list(args) -> {cmd, args}
      cmd when is_binary(cmd) -> {cmd, Map.get(config, :args, [])}
      _ -> {command, []}
    end
  end
end
