defmodule MCPChat.MCP.NotificationHandler do
  @moduledoc """
  Behaviour and registry for handling MCP server notifications.

  Notifications include:
  - Resource changes (list_changed, updated)
  - Tool changes (list_changed)
  - Prompt changes (list_changed)
  - Progress updates
  """

  @type notification_type ::
          :resources_list_changed
          | :resources_updated
          | :tools_list_changed
          | :prompts_list_changed
          | :progress

  @type handler_result :: :ok | {:error, term()}

  @doc """
  Handles a notification from an MCP server.

  The handler receives:
  - The server name that sent the notification
  - The notification type
  - The notification parameters
  - The handler state

  Returns {:ok, new_state} or {:error, reason, state}.
  """
  @callback handle_notification(
              server_name :: String.t(),
              type :: notification_type(),
              params :: map(),
              state :: term()
            ) :: {:ok, term()} | {:error, term(), term()}

  @doc """
  Initializes the handler state.
  """
  @callback init(args :: term()) :: {:ok, term()} | {:error, term()}

  @doc """
  Optional callback for cleanup when handler is removed.
  """
  @callback terminate(reason :: term(), state :: term()) :: :ok
  @optional_callbacks [terminate: 2]
end
