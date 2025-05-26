# Ensure tools application is started (required for meck)
Application.ensure_all_started(:tools)

# Compile test support files
Code.compile_file("test/support/test_config.ex")

# Start the application
Application.ensure_all_started(:mcp_chat)

ExUnit.start()
