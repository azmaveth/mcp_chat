defmodule Mix.Tasks.McpChat.Run do
  @moduledoc """
  Run MCP Chat in interactive mode with full terminal support.

  ## Usage

      mix mcp_chat.run

  This starts MCP Chat with IEx-like terminal support, including:
  - Arrow key navigation
  - Emacs keybindings
  - Command history
  - Tab completion
  """

  use Mix.Task

  @shortdoc "Run MCP Chat with interactive terminal support"

  @impl Mix.Task
  def run(_args) do
    # Force advanced readline mode for Mix task since we want full terminal support
    System.put_env("MCP_READLINE_MODE", "advanced")

    # Ensure the application is started
    Mix.Task.run("app.start", [])

    # Run the main function in a separate process to avoid Mix task termination
    task =
      Task.async(fn ->
        MCPChat.main()
      end)

    # Wait for the task to complete
    Task.await(task, :infinity)
  end
end
