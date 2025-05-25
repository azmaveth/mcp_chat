# Ensure tools application is started (required for meck)
Application.ensure_all_started(:tools)

# Start the application
Application.ensure_all_started(:mcp_chat)

ExUnit.start()
