defmodule MCPChat.MCP.NotificationClient do
  @moduledoc """
  Extended MCP client that handles notifications and integrates with
  the notification registry.
  """
  use GenServer
  require Logger

  alias MCPChat.MCP.ProgressTracker

  defstruct [
    :client_pid,
    :server_name,
    :transport_mod,
    :transport_opts,
    :notification_registry
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Wraps ExMCP.Client functions with notification support.
  """
  def call_tool(client, name, arguments, opts \\ []) do
    GenServer.call(client, {:call_tool, name, arguments, opts}, 30_000)
  end

  def list_tools(client) do
    GenServer.call(client, :list_tools)
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

  def create_message(client, params) do
    GenServer.call(client, {:create_message, params}, 60_000)
  end

  def server_info(client) do
    GenServer.call(client, :server_info)
  end

  def server_capabilities(client) do
    GenServer.call(client, :server_capabilities)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    server_name = Keyword.fetch!(opts, :server_name)
    registry = Keyword.get(opts, :notification_registry, MCPChat.MCP.NotificationRegistry)

    # Start a custom ExMCP client with a notification receiver
    {:ok, client_pid} = start_custom_client(opts, self())

    state = %__MODULE__{
      client_pid: client_pid,
      server_name: server_name,
      transport_mod: Keyword.get(opts, :transport),
      transport_opts: opts,
      notification_registry: registry
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:call_tool, name, arguments, opts}, _from, state) do
    # Generate progress token if requested
    progress_token =
      if Keyword.get(opts, :with_progress, false) do
        {:ok, token} =
          ProgressTracker.start_operation(
            state.server_name,
            name
          )

        token
      else
        Keyword.get(opts, :progress_token)
      end

    # Forward to ExMCP client
    result =
      if progress_token do
        ExMCP.Client.call_tool(state.client_pid, name, arguments, progress_token: progress_token)
      else
        ExMCP.Client.call_tool(state.client_pid, name, arguments)
      end

    # Complete operation on success
    if progress_token && match?({:ok, _}, result) do
      ProgressTracker.complete_operation(progress_token)
    end

    {:reply, result, state}
  end

  def handle_call(:list_tools, _from, state) do
    result = ExMCP.Client.list_tools(state.client_pid)
    {:reply, result, state}
  end

  def handle_call(:list_resources, _from, state) do
    result = ExMCP.Client.list_resources(state.client_pid)
    {:reply, result, state}
  end

  def handle_call({:read_resource, uri}, _from, state) do
    result = ExMCP.Client.read_resource(state.client_pid, uri)
    {:reply, result, state}
  end

  def handle_call(:list_prompts, _from, state) do
    result = ExMCP.Client.list_prompts(state.client_pid)
    {:reply, result, state}
  end

  def handle_call({:get_prompt, name, arguments}, _from, state) do
    result = ExMCP.Client.get_prompt(state.client_pid, name, arguments)
    {:reply, result, state}
  end

  def handle_call({:create_message, params}, _from, state) do
    result = ExMCP.Client.create_message(state.client_pid, params)
    {:reply, result, state}
  end

  def handle_call(:server_info, _from, state) do
    result = ExMCP.Client.server_info(state.client_pid)
    {:reply, result, state}
  end

  def handle_call(:server_capabilities, _from, state) do
    result = ExMCP.Client.server_capabilities(state.client_pid)
    {:reply, result, state}
  end

  @impl true
  def handle_info({:notification, method, params}, state) do
    # Dispatch to notification registry
    state.notification_registry.dispatch_notification(
      state.server_name,
      method,
      params
    )

    {:noreply, state}
  end

  # Private Functions

  defp start_custom_client(opts, _notification_receiver) do
    # We need to intercept notifications from the ExMCP.Client
    # This is a simplified approach - in practice, we might need to
    # extend ExMCP.Client or use a custom transport wrapper

    # For now, just use the standard client
    # Future enhancement: Create a wrapper transport that forwards notifications
    ExMCP.Client.start_link(opts)
  end
end
