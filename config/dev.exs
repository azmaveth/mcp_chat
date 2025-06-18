import Config

# Configure your database
# config :mcp_chat, MCPChat.Repo,
#   username: "postgres",
#   password: "postgres",
#   hostname: "localhost",
#   database: "mcp_chat_dev",
#   stacktrace: true,
#   show_sensitive_data_on_connection_error: true,
#   pool_size: 10

# For development, we disable any cache and enable
# debugging and code reloading.
config :mcp_chat, MCPChatWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "mcp_chat_secret_key_base_for_development_only_change_in_production_this_is_64_chars",
  watchers: [],
  # Start the server
  server: true

# Enable dev routes for dashboard and mailbox
config :mcp_chat, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime
