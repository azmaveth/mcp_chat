defmodule MCPChat.MCP.StdioClient do
  @moduledoc """
  MCP client that communicates via stdio (stdin/stdout) with a server process.
  """
  use GenServer

  # alias MCPChat.MCP.Protocol

  require Logger

  defstruct [
    :port,
    :server_info,
    :capabilities,
    :tools,
    :resources,
    :prompts,
    :pending_requests,
    :callback_pid,
    :buffer,
    :request_id
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def initialize(client, client_info) do
    GenServer.call(client, {:initialize, client_info}, 10_000)
  end

  def list_tools(client) do
    GenServer.call(client, :list_tools, 10_000)
  end

  def call_tool(client, name, arguments) do
    GenServer.call(client, {:call_tool, name, arguments}, 30_000)
  end

  def list_resources(client) do
    GenServer.call(client, :list_resources, 10_000)
  end

  def read_resource(client, uri) do
    GenServer.call(client, {:read_resource, uri}, 30_000)
  end

  def list_prompts(client) do
    GenServer.call(client, :list_prompts, 10_000)
  end

  def get_prompt(client, name, arguments \\ %{}) do
    GenServer.call(client, {:get_prompt, name, arguments}, 10_000)
  end

  def set_port(client, port) do
    GenServer.call(client, {:set_port, port})
  end

  def start_port(client, command, env \\ %{}) do
    GenServer.call(client, {:start_port, command, env})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      port: nil,
      server_info: nil,
      capabilities: %{},
      tools: [],
      resources: [],
      prompts: [],
      pending_requests: %{},
      callback_pid: Keyword.get(opts, :callback_pid, self()),
      buffer: "",
      request_id: 1
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:set_port, port}, _from, state) do
    Logger.warning("set_port is deprecated, use start_port instead")
    {:reply, :ok, %{state | port: port}}
  end

  @impl true
  def handle_call({:start_port, command, env}, _from, state) do
    case start_port_process(command, env) do
      {:ok, port} ->
        {:reply, :ok, %{state | port: port}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:initialize, client_info}, from, state) do
    if state.port do
      request_id = state.request_id

      message = %{
        jsonrpc: "2.0",
        method: "initialize",
        params: %{
          protocolVersion: "2024-11-05",
          capabilities: client_info[:capabilities] || %{},
          clientInfo: client_info
        },
        id: request_id
      }

      new_state = %{
        state
        | pending_requests: Map.put(state.pending_requests, request_id, {:initialize, from}),
          request_id: request_id + 1
      }

      Logger.debug("Sending initialize request: #{inspect(message)}")
      send_json_rpc(new_state.port, message)
      {:noreply, new_state}
    else
      {:reply, {:error, :no_port}, state}
    end
  end

  @impl true
  def handle_call(:list_tools, from, state) do
    if state.port do
      request_id = state.request_id

      message = %{
        jsonrpc: "2.0",
        method: "tools/list",
        params: %{},
        id: request_id
      }

      new_state = %{
        state
        | pending_requests: Map.put(state.pending_requests, request_id, {:list_tools, from}),
          request_id: request_id + 1
      }

      send_json_rpc(new_state.port, message)
      {:noreply, new_state}
    else
      {:reply, {:error, :no_port}, state}
    end
  end

  @impl true
  def handle_call({:call_tool, name, arguments}, from, state) do
    if state.port do
      request_id = state.request_id

      message = %{
        jsonrpc: "2.0",
        method: "tools/call",
        params: %{
          name: name,
          arguments: arguments
        },
        id: request_id
      }

      new_state = %{
        state
        | pending_requests: Map.put(state.pending_requests, request_id, {:call_tool, from}),
          request_id: request_id + 1
      }

      send_json_rpc(new_state.port, message)
      {:noreply, new_state}
    else
      {:reply, {:error, :no_port}, state}
    end
  end

  @impl true
  def handle_call(:list_resources, from, state) do
    if state.port do
      request_id = state.request_id

      message = %{
        jsonrpc: "2.0",
        method: "resources/list",
        params: %{},
        id: request_id
      }

      new_state = %{
        state
        | pending_requests: Map.put(state.pending_requests, request_id, {:list_resources, from}),
          request_id: request_id + 1
      }

      send_json_rpc(new_state.port, message)
      {:noreply, new_state}
    else
      {:reply, {:error, :no_port}, state}
    end
  end

  @impl true
  def handle_call({:read_resource, uri}, from, state) do
    if state.port do
      request_id = state.request_id

      message = %{
        jsonrpc: "2.0",
        method: "resources/read",
        params: %{uri: uri},
        id: request_id
      }

      new_state = %{
        state
        | pending_requests: Map.put(state.pending_requests, request_id, {:read_resource, from}),
          request_id: request_id + 1
      }

      send_json_rpc(new_state.port, message)
      {:noreply, new_state}
    else
      {:reply, {:error, :no_port}, state}
    end
  end

  @impl true
  def handle_call(:list_prompts, from, state) do
    if state.port do
      request_id = state.request_id

      message = %{
        jsonrpc: "2.0",
        method: "prompts/list",
        params: %{},
        id: request_id
      }

      new_state = %{
        state
        | pending_requests: Map.put(state.pending_requests, request_id, {:list_prompts, from}),
          request_id: request_id + 1
      }

      send_json_rpc(new_state.port, message)
      {:noreply, new_state}
    else
      {:reply, {:error, :no_port}, state}
    end
  end

  @impl true
  def handle_call({:get_prompt, name, arguments}, from, state) do
    if state.port do
      request_id = state.request_id

      message = %{
        jsonrpc: "2.0",
        method: "prompts/get",
        params: %{
          name: name,
          arguments: arguments
        },
        id: request_id
      }

      new_state = %{
        state
        | pending_requests: Map.put(state.pending_requests, request_id, {:get_prompt, from}),
          request_id: request_id + 1
      }

      send_json_rpc(new_state.port, message)
      {:noreply, new_state}
    else
      {:reply, {:error, :no_port}, state}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    Logger.debug("Received raw data from port: #{inspect(data)}")

    # Accumulate data in buffer
    buffer = state.buffer <> data

    # Split by newlines and process complete messages
    {lines, remaining} = split_lines(buffer)

    Logger.debug("Buffer lines: #{inspect(lines)}")
    Logger.debug("Remaining buffer: #{inspect(remaining)}")

    new_state = Enum.reduce(lines, state, &process_line/2)

    {:noreply, %{new_state | buffer: remaining}}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("Port exited with status: #{status}")

    if state.callback_pid do
      send(state.callback_pid, {:mcp_disconnected, self(), {:exit_status, status}})
    end

    {:noreply, %{state | port: nil}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :port, port, reason}, %{port: port} = state) do
    Logger.warning("Port died: #{inspect(reason)}")

    if state.callback_pid do
      send(state.callback_pid, {:mcp_disconnected, self(), reason})
    end

    {:noreply, %{state | port: nil}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("StdioClient received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp send_json_rpc(port, message) do
    json = Jason.encode!(message)
    Logger.debug("Sending to port: #{json}")
    Port.command(port, json <> "\n")
  end

  defp split_lines(data) do
    lines = String.split(data, "\n")

    case List.last(lines) do
      "" ->
        # Data ended with newline, all lines are complete
        {Enum.drop(lines, -1), ""}

      partial ->
        # Last line is incomplete
        {Enum.drop(lines, -1), partial}
    end
  end

  defp process_line("", state), do: state

  defp process_line(line, state) do
    # Skip non-JSON lines (server startup messages)
    if String.starts_with?(line, "{") do
      case Jason.decode(line) do
        {:ok, message} ->
          Logger.debug("Successfully parsed JSON: #{inspect(message)}")
          handle_json_rpc_message(message, state)

        {:error, reason} ->
          Logger.error("Failed to decode JSON-RPC message: #{inspect(reason)}")
          Logger.error("Raw line: #{inspect(line)}")
          state
      end
    else
      # Log non-JSON output but don't fail
      Logger.debug("MCP server output: #{line}")
      state
    end
  end

  defp handle_json_rpc_message(%{"id" => id} = message, state) when not is_nil(id) do
    # This is a response to one of our requests
    Logger.debug("Received response: #{inspect(message)}")

    case Map.pop(state.pending_requests, id) do
      {nil, _} ->
        Logger.warning("Received response for unknown request ID: #{id}")
        state

      {{request_type, from}, pending} ->
        {result, new_state} =
          case message do
            %{"result" => result} ->
              {res, updated_state} = process_result(request_type, result, state)
              {res, updated_state}

            %{"error" => error} ->
              {{:error, error}, state}
          end

        GenServer.reply(from, result)
        %{new_state | pending_requests: pending}
    end
  end

  defp handle_json_rpc_message(%{"method" => method, "params" => params}, state) do
    # This is a notification from the server
    if state.callback_pid do
      send(state.callback_pid, {:mcp_notification, self(), method, params})
    end

    state
  end

  defp handle_json_rpc_message(message, state) do
    Logger.debug("Unhandled JSON-RPC message: #{inspect(message)}")
    state
  end

  defp process_result(:initialize, result, state) do
    server_info = Map.get(result, "serverInfo", %{})
    capabilities = Map.get(result, "capabilities", %{})

    new_state = %{state | server_info: server_info, capabilities: capabilities}

    # Send the initialized notification to the server (required by MCP protocol)
    initialized_message = %{
      jsonrpc: "2.0",
      method: "notifications/initialized",
      params: %{}
    }

    send_json_rpc(state.port, initialized_message)

    # Send initialization complete notification to callback
    if state.callback_pid do
      send(state.callback_pid, {:mcp_initialized, self()})
    end

    {{:ok, %{server_info: server_info, capabilities: capabilities}}, new_state}
  end

  defp process_result(:list_tools, %{"tools" => tools}, state) do
    new_state = %{state | tools: tools}
    {{:ok, tools}, new_state}
  end

  defp process_result(:call_tool, result, state) do
    # Tool call results can have various formats
    res =
      case result do
        %{"content" => content} -> {:ok, content}
        %{"text" => text} -> {:ok, text}
        _ -> {:ok, result}
      end

    {res, state}
  end

  defp process_result(:list_resources, %{"resources" => resources}, state) do
    new_state = %{state | resources: resources}
    {{:ok, resources}, new_state}
  end

  defp process_result(:read_resource, %{"contents" => contents}, state) do
    {{:ok, contents}, state}
  end

  defp process_result(:list_prompts, %{"prompts" => prompts}, state) do
    new_state = %{state | prompts: prompts}
    {{:ok, prompts}, new_state}
  end

  defp process_result(:get_prompt, %{"messages" => messages}, state) do
    {{:ok, messages}, state}
  end

  defp process_result(_, result, state) do
    {{:ok, result}, state}
  end

  defp start_port_process([cmd | args], env) do
    # Convert env map to list of {"KEY", "VALUE"} tuples
    env_list = Enum.map(env, fn {k, v} -> {to_string(k), to_string(v)} end)

    # Find the executable
    case System.find_executable(cmd) do
      nil ->
        {:error, {:executable_not_found, cmd}}

      executable ->
        # Start the port
        port_opts = [
          :binary,
          :exit_status,
          :stream,
          :stderr_to_stdout,
          {:env, env_list},
          {:args, args}
        ]

        try do
          port = Port.open({:spawn_executable, executable}, port_opts)
          Logger.debug("Started port process for #{cmd}")
          {:ok, port}
        catch
          :error, reason ->
            {:error, reason}
        end
    end
  end
end
