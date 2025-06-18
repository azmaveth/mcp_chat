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
    AgentCommands,
    Alias,
    ConcurrentTools,
    Context,
    LLM,
    MCP,
    NativeFilesystem,
    Notification,
    PlanMode,
    Session,
    ToolTest,
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
    "concurrent" => ConcurrentTools,

    # Native filesystem command
    "fs" => NativeFilesystem,

    # Tool testing command
    "tooltest" => ToolTest,

    # Plan Mode command
    "plan" => PlanMode,

    # Agent commands
    "agent" => AgentCommands
  }

  @doc """
  Get command completions for a partial command string.
  """
  def get_completions(partial) do
    # Get all available commands
    alias_names =
      case ExAliasAdapter.list_aliases() do
        aliases when is_list(aliases) ->
          Enum.map(aliases, & &1.name)

        aliases when is_map(aliases) ->
          Map.keys(aliases)

        _ ->
          []
      end

    all_commands =
      @command_handlers
      |> Map.keys()
      |> Kernel.++(["exit", "quit"])
      |> Kernel.++(alias_names)

    # Filter by prefix
    all_commands
    |> Enum.filter(&String.starts_with?(&1, partial))
    |> Enum.sort()
    |> Enum.uniq()
  end

  @doc """
  Handle a command by routing it to the appropriate handler.

  This now supports both legacy command handling and new agent-based commands.
  """
  def handle_command(command) do
    {cmd, args} = parse_command(command)

    if ExAliasAdapter.alias?(cmd) do
      handle_alias_command(cmd, args)
    else
      # Check if we should use the enhanced command system
      if use_enhanced_commands?() do
        MCPChat.CLI.EnhancedCommands.handle_command(command)
      else
        route_to_handler(cmd, args)
      end
    end
  end

  @doc """
  Enhanced help command that includes agent capabilities.
  """
  def show_enhanced_help(session_id \\ "default") do
    if use_enhanced_commands?() do
      MCPChat.CLI.EnhancedCommands.show_enhanced_help(session_id)
    else
      # Fallback to original help
      case Map.get(@command_handlers, "help") do
        nil -> :ok
        handler_module -> handler_module.handle_command("help", [])
      end
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

  # Determine whether to use the enhanced agent-based command system
  defp use_enhanced_commands? do
    # Default to enhanced commands (agent architecture) unless explicitly disabled
    # This makes the agent architecture the primary command system

    case System.get_env("MCP_ENHANCED_COMMANDS") do
      "false" ->
        false

      # Explicit legacy mode
      "legacy" ->
        false

      _ ->
        # Default to enhanced commands if agent architecture is available
        # Fall back to legacy only if agents aren't running
        Process.whereis(MCPChat.Agents.AgentSupervisor) != nil
    end
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
