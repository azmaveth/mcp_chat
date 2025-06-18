# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
import Config

# Configure the MCP Chat Web UI
config :mcp_chat, MCPChatWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: MCPChatWeb.ErrorHTML, json: MCPChatWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MCPChat.PubSub,
  live_view: [signing_salt: "mcp_chat_live_view_salt"]

# Configure Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
