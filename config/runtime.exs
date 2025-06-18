import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.

# The block below contains prod specific runtime configuration.

if config_env() == :prod do
  # Start the phoenix server if environment is set and running in a release
  if System.get_env("PHX_SERVER") do
    config :mcp_chat, MCPChatWeb.Endpoint, server: true
  end

  if System.get_env("SECRET_KEY_BASE") do
    config :mcp_chat, MCPChatWeb.Endpoint, secret_key_base: System.get_env("SECRET_KEY_BASE")
  end

  # Configure your endpoint
  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :mcp_chat, MCPChatWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ]
end
