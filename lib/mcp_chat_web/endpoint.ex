defmodule MCPChatWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :mcp_chat

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_mcp_chat_key",
    signing_salt: "mcp_chat_salt",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]
  )

  # Serve at "/" the static files from "priv/static" directory.
  plug(Plug.Static,
    at: "/",
    from: :mcp_chat,
    gzip: false,
    only: MCPChatWeb.static_paths()
  )

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  # Disabled for now to avoid undefined function errors

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(MCPChatWeb.Router)
end
