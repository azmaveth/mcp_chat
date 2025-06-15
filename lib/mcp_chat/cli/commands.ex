defmodule MCPChat.CLI.Commands do
  @moduledoc """
  CLI command router.

  This module routes commands to the appropriate command handler modules,
  significantly reducing the complexity and size of the original monolithic module.
  """

  require Logger

  alias MCPChat.Alias.ExAliasAdapter
  alias MCPChat.CLI.{Commands, Renderer}
  alias Commands.{
    Alias,
    ConcurrentTools,
    Context,
    LLM,
    MCP,
    Notification,
    Session,
    TUI,
    Utility
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
    "stats" => Utility,
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
      |> Kernel.++(Map.keys(ExAliasAdapter.list_aliases()))

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
    {cmd, args} = parse_command(command)

    if ExAliasAdapter.is_alias?(cmd) do
      handle_alias_command(cmd, args)
    else
      route_to_handler(cmd, args)
    end
  end

  defp parse_command(command) do
    [cmd | args] = String.split(command, " ", parts: 2)
    args = List.wrap(args) |> List.flatten()
    {cmd, args}
  end

  defp handle_alias_command(cmd, args) do
    case Alias.execute_alias(cmd, args) do
      {:execute, expanded_command} ->
        handle_command(expanded_command)

      _ ->
        :ok
    end
  end

  defp route_to_handler(cmd, args) do
    case Map.get(@command_handlers, cmd) do
      nil -> handle_special_command(cmd, args)
      handler_module -> execute_handler(handler_module, cmd, args)
    end
  end

  defp execute_handler(handler_module, cmd, args) do
    log_debug_handler_call(handler_module, cmd, args)

    case handler_module.handle_command(cmd, args) do
      :ok -> :continue
      {:error, message} -> handle_error_response(message)
      other -> handle_unexpected_response(other)
    end
  end

  defp log_debug_handler_call(handler_module, cmd, args) do
    if System.get_env("MCP_DEBUG") == "1" do
      IO.puts("[DEBUG] Calling handler: #{inspect(handler_module)}.handle_command(#{inspect(cmd)}, #{inspect(args)})")
    end
  end

  defp handle_error_response(message) do
    Renderer.show_error(message)
    :continue
  end

  defp handle_unexpected_response(other) do
    if System.get_env("MCP_DEBUG") == "1" do
      IO.puts("[DEBUG] Unexpected return from handler: #{inspect(other)}")
    end

    :continue
  end

  # Handle special commands that don't fit the pattern
  defp handle_special_command("exit", _args), do: :exit
  defp handle_special_command("quit", _args), do: :exit

  defp handle_special_command(cmd, _args) do
    Renderer.show_error("Unknown command: /#{cmd}")
    Renderer.show_info("Type /help for available commands")
    :continue
  end
end
