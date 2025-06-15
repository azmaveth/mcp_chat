defmodule MCPChat.MCP.NotificationRegistry do
  @moduledoc """
  Registry for notification handlers. Manages registration and dispatch
  of notifications to appropriate handlers.
  """
  use GenServer
  require Logger

  defstruct handlers: %{}, handler_states: %{}

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a handler module for specific notification types.
  """
  def register_handler(handler_module, types, args \\ []) when is_list(types) do
    GenServer.call(__MODULE__, {:register_handler, handler_module, types, args})
  end

  @doc """
  Unregisters a handler module.
  """
  def unregister_handler(handler_module) do
    GenServer.call(__MODULE__, {:unregister_handler, handler_module})
  end

  @doc """
  Dispatches a notification to all registered handlers.
  """
  def dispatch_notification(server_name, method, params) do
    GenServer.cast(__MODULE__, {:dispatch, server_name, method, params})
  end

  @doc """
  Gets the list of registered handlers.
  """
  def list_handlers do
    GenServer.call(__MODULE__, :list_handlers)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Register default notification handlers after startup
    Process.send_after(self(), :register_default_handlers, 100)
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:register_handler, handler_module, types, args}, _from, state) do
    case handler_module.init(args) do
      {:ok, handler_state} ->
        # Register handler for each notification type
        new_handlers =
          Enum.reduce(types, state.handlers, fn type, acc ->
            Map.update(acc, type, [handler_module], &[handler_module | &1])
          end)

        new_handler_states = Map.put(state.handler_states, handler_module, handler_state)

        Logger.info("Registered notification handler: #{inspect(handler_module)} for types: #{inspect(types)}")

        {:reply, :ok, %{state | handlers: new_handlers, handler_states: new_handler_states}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:unregister_handler, handler_module}, _from, state) do
    # Remove from all notification types
    new_handlers =
      Enum.reduce(state.handlers, %{}, fn {type, handlers}, acc ->
        filtered = Enum.filter(handlers, &(&1 != handler_module))
        if filtered == [], do: acc, else: Map.put(acc, type, filtered)
      end)

    # Clean up handler state
    handler_state = Map.get(state.handler_states, handler_module)

    if handler_state && function_exported?(handler_module, :terminate, 2) do
      handler_module.terminate(:normal, handler_state)
    end

    new_handler_states = Map.delete(state.handler_states, handler_module)

    Logger.info("Unregistered notification handler: #{inspect(handler_module)}")

    {:reply, :ok, %{state | handlers: new_handlers, handler_states: new_handler_states}}
  end

  def handle_call(:list_handlers, _from, state) do
    handlers_info =
      Enum.map(state.handlers, fn {type, handlers} ->
        {type, Enum.map(handlers, &inspect/1)}
      end)
      |> Enum.into(%{})

    {:reply, handlers_info, state}
  end

  @impl true
  def handle_cast({:dispatch, server_name, method, params}, state) do
    type = method_to_type(method)

    if type do
      handle_known_notification(type, server_name, params, state)
    else
      Logger.debug("Unknown notification method: #{method}")
      {:noreply, state}
    end
  end

  defp handle_known_notification(type, server_name, params, state) do
    handlers = Map.get(state.handlers, type, [])
    new_handler_states = process_handlers(handlers, server_name, type, params, state.handler_states)
    {:noreply, %{state | handler_states: new_handler_states}}
  end

  defp process_handlers(handlers, server_name, type, params, handler_states) do
    Enum.reduce(handlers, handler_states, fn handler, acc ->
      process_single_handler(handler, server_name, type, params, acc)
    end)
  end

  defp process_single_handler(handler, server_name, type, params, handler_states) do
    handler_state = Map.get(handler_states, handler)

    case handler.handle_notification(server_name, type, params, handler_state) do
      {:ok, new_state} ->
        Map.put(handler_states, handler, new_state)

      {:error, reason, new_state} ->
        Logger.error("Handler #{inspect(handler)} failed: #{inspect(reason)}")
        Map.put(handler_states, handler, new_state)
    end
  end

  @impl true
  def handle_info(:register_default_handlers, state) do
    # Register ComprehensiveNotificationHandler for all notification types
    notification_types = [
      :server_connected,
      :server_disconnected,
      :server_error,
      :resources_list_changed,
      :resource_added,
      :resource_removed,
      :resources_updated,
      :tools_list_changed,
      :tool_added,
      :tool_removed,
      :prompts_list_changed,
      :prompt_added,
      :prompt_removed,
      :progress,
      :progress_start,
      :progress_complete,
      :progress_error,
      :custom_notification
    ]

    handler_module = MCPChat.MCP.Handlers.ComprehensiveNotificationHandler

    case handler_module.init([]) do
      {:ok, handler_state} ->
        # Register handler for each notification type
        new_handlers =
          Enum.reduce(notification_types, state.handlers, fn type, acc ->
            Map.update(acc, type, [handler_module], &[handler_module | &1])
          end)

        new_handler_states = Map.put(state.handler_states, handler_module, handler_state)

        Logger.info(
          "Registered notification handler: #{inspect(handler_module)} for types: #{inspect(notification_types)}"
        )

        {:noreply, %{state | handlers: new_handlers, handler_states: new_handler_states}}

      {:error, reason} ->
        Logger.error("Failed to register ComprehensiveNotificationHandler: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  # Private Functions

  defp method_to_type(method) do
    case method do
      "notifications/resources/list_changed" -> :resources_list_changed
      "notifications/resources/updated" -> :resources_updated
      "notifications/tools/list_changed" -> :tools_list_changed
      "notifications/prompts/list_changed" -> :prompts_list_changed
      "notifications/progress" -> :progress
      _ -> nil
    end
  end
end
