import Config

# Configure your database
# config :mcp_chat, MCPChat.Repo,
#   username: "postgres",
#   password: "postgres",
#   hostname: "localhost",
#   database: "mcp_chat_test#{System.get_env("MIX_TEST_PARTITION")}",
#   pool: Ecto.Adapters.SQL.Sandbox,
#   pool_size: 10

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :mcp_chat, MCPChatWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "mcp_chat_secret_key_base_for_testing_only_change_in_production_this_is_64_chars",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
