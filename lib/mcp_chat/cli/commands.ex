defmodule MCPChat.CLI.Commands do
  @moduledoc """
  CLI command router.

  This module routes commands to the appropriate command handler modules,
  significantly reducing the complexity and size of the original monolithic module.
  """

  require Logger

  alias MCPChat.CLI.Commands.{
    Session,
    Utility,
    LLM,
    MCP,
    Context,
    Alias,
    Notification,
    TUI,
    ConcurrentTools
  }

  # Map of command to handler module
  @command_handlers %{
    # Session commands
    "new" => Session,
    "save" => Session,
    "load" => Session,
    "sessions" => Session,
    "history" => Session,

    # Utility commands
    "help" => Utility,
    "clear" => Utility,
    "config" => Utility,
    "cost" => Utility,
    "export" => Utility,

    # LLM commands
    "backend" => LLM,
    "model" => LLM,
    "models" => LLM,
    "loadmodel" => LLM,
    "unloadmodel" => LLM,
    "acceleration" => LLM,

    # MCP commands
    "mcp" => MCP,

    # Context commands
    "context" => Context,
    "system" => Context,
    "tokens" => Context,
    "strategy" => Context,

    # Alias command
    "alias" => Alias,

    # Notification command
    "notification" => Notification,

    # TUI command
    "tui" => TUI,

    # Concurrent tools command
    "concurrent" => ConcurrentTools
  }

  @doc """
  Get command completions for a partial command string.
  """
  def get_completions(partial) do
    # Get all available commands
    all_commands =
      @command_handlers
      |> Map.keys()
      |> Kernel.++(["exit", "quit"])
      |> Kernel.++(Map.keys(MCPChat.Alias.ExAliasAdapter.list_aliases()))

    # Filter by prefix
    all_commands
    |> Enum.filter(&String.starts_with?(&1, partial))
    |> Enum.sort()
    |> Enum.uniq()
  end

  @doc """
  Handle a command by routing it to the appropriate handler.
  """
  def handle_command(command) do
    [cmd | args] = String.split(command, " ", parts: 2)
    args = List.wrap(args) |> List.flatten()

    # Check if it's an alias first
    if MCPChat.Alias.ExAliasAdapter.is_alias?(cmd) do
      case Alias.execute_alias(cmd, args) do
        {:execute, expanded_command} ->
          # Recursively handle the expanded command
          handle_command(expanded_command)

        _ ->
          :ok
      end
    else
      # Route to appropriate handler
      case Map.get(@command_handlers, cmd) do
        nil ->
          handle_special_command(cmd, args)

        handler_module ->
          case handler_module.handle_command(cmd, args) do
            :ok ->
              :ok

            {:error, message} ->
              MCPChat.CLI.Renderer.show_error(message)
              :ok
          end
      end
    end
  end

  # Handle special commands that don't fit the pattern
  defp handle_special_command("exit", _args), do: :exit
  defp handle_special_command("quit", _args), do: :exit

  defp handle_special_command(cmd, _args) do
    MCPChat.CLI.Renderer.show_error("Unknown command: /#{cmd}")
    MCPChat.CLI.Renderer.show_info("Type /help for available commands")
    :ok
  end
end
