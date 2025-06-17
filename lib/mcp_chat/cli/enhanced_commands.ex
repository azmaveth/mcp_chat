defmodule MCPChat.CLI.EnhancedCommands do
  @moduledoc """
  Enhanced command system that integrates with the agent architecture.

  This module provides:
  - Dynamic command discovery from connected agents
  - Real-time command execution with progress updates
  - Intelligent help system with context-aware suggestions
  - Command routing between local CLI and remote agents
  """

  require Logger

  alias MCPChat.CLI.{AgentCommandBridge, Renderer}
  alias MCPChat.CLI.Commands
  alias MCPChat.Events.AgentEvents

  @doc """
  Enhanced command handling with agent integration.
  """
  def handle_command(command_string, session_id \\ "default") do
    {command, args} = parse_command(command_string)

    case AgentCommandBridge.route_command(command, args) do
      {:local, cmd, args} ->
        handle_local_command(cmd, args)

      {:agent, agent_type, cmd, args} ->
        handle_agent_command(agent_type, cmd, args, session_id)

      {:unknown, cmd, _args} ->
        handle_unknown_command(cmd, session_id)
    end
  end

  @doc """
  Enhanced help command with agent discovery.
  """
  def show_enhanced_help(session_id \\ "default") do
    help_data = AgentCommandBridge.generate_enhanced_help(session_id)

    Renderer.show_text("## Available Commands\n")

    # Show agent status
    if help_data.session_active do
      Renderer.show_success("✓ Agent session active - #{help_data.total_count} commands available")
    else
      Renderer.show_warning("⚠ No active agent session - limited commands available")
    end

    IO.puts("")

    # Local Commands Section
    Renderer.show_text("### Local Commands (CLI)")
    show_command_table(help_data.local_commands)

    IO.puts("")

    # Agent Commands Section  
    Renderer.show_text("### AI Agent Commands")

    if map_size(help_data.agent_commands) > 0 do
      show_command_table(help_data.agent_commands)
    else
      Renderer.show_info("No agents connected. Use `/mcp connect` to add capabilities.")
    end

    IO.puts("")

    # Usage hints
    Renderer.show_text("### Usage Tips")
    IO.puts("• Type `/help <command>` for detailed help")
    IO.puts("• Agent commands provide real-time progress updates")
    IO.puts("• Use `/config` to see current session configuration")
    IO.puts("• Use `/mcp discover` to find available AI capabilities")

    :ok
  end

  @doc """
  Get command completions with agent awareness.
  """
  def get_enhanced_completions(partial, session_id \\ "default") do
    commands = AgentCommandBridge.discover_available_commands(session_id)

    commands.all
    |> Enum.filter(&String.starts_with?(&1, partial))
    |> Enum.sort()
    |> add_completion_hints()
  end

  # Private functions

  defp parse_command(command_string) do
    [cmd | args] =
      command_string
      |> String.trim()
      |> String.split(" ", parts: 2)

    args = if args == [], do: [], else: List.wrap(args) |> List.flatten()
    {cmd, args}
  end

  defp handle_local_command(command, args) do
    # Route to existing command system
    Commands.handle_command("#{command} #{Enum.join(args, " ")}")
  end

  defp handle_agent_command(agent_type, command, args, session_id) do
    Renderer.show_info("🤖 Executing with #{agent_type} agent...")

    case AgentCommandBridge.execute_agent_command(agent_type, command, args, session_id) do
      {:ok, agent_pid} ->
        # Show progress and wait for completion
        monitor_agent_execution(agent_pid, session_id)

      {:error, :pool_full} ->
        Renderer.show_warning("⏳ Agent pool is busy. Queuing your request...")

      # Could implement queuing feedback here

      {:error, reason} ->
        Renderer.show_error("Failed to execute command: #{inspect(reason)}")
    end
  end

  defp handle_unknown_command(command, session_id) do
    Renderer.show_error("Unknown command: /#{command}")

    # Intelligent suggestions based on similarity
    suggestions = suggest_similar_commands(command, session_id)

    if length(suggestions) > 0 do
      Renderer.show_info("Did you mean:")

      suggestions
      |> Enum.take(3)
      |> Enum.each(fn cmd ->
        IO.puts("  /#{cmd}")
      end)
    end

    Renderer.show_info("Type /help for available commands")
  end

  defp monitor_agent_execution(agent_pid, session_id) do
    receive do
      %AgentEvents.ToolExecutionStarted{agent_pid: ^agent_pid} = event ->
        Renderer.show_info("🚀 Started: #{event.tool_name}")

        if event.estimated_duration do
          duration_sec = div(event.estimated_duration, 1000)
          Renderer.show_info("⏱ Estimated duration: #{duration_sec}s")
        end

        monitor_agent_execution(agent_pid, session_id)

      %AgentEvents.ToolExecutionProgress{agent_pid: ^agent_pid} = event ->
        show_progress(event.progress, event.stage)
        monitor_agent_execution(agent_pid, session_id)

      %AgentEvents.ToolExecutionCompleted{agent_pid: ^agent_pid} = event ->
        Renderer.show_success("✅ Completed: #{event.tool_name}")
        display_agent_result(event.result)

      %AgentEvents.ToolExecutionFailed{agent_pid: ^agent_pid} = event ->
        Renderer.show_error("❌ Failed: #{event.tool_name}")
        Renderer.show_error("Error: #{event.error}")
    after
      # 30 second timeout
      30_000 ->
        Renderer.show_warning("⏰ Command taking longer than expected...")
        monitor_agent_execution(agent_pid, session_id)
    end
  end

  defp show_progress(progress, stage) do
    bar_length = 20
    filled = round(progress * bar_length / 100)
    empty = bar_length - filled

    bar = String.duplicate("█", filled) <> String.duplicate("░", empty)
    stage_text = stage |> to_string() |> String.replace("_", " ") |> String.capitalize()

    IO.write("\r🔄 [#{bar}] #{progress}% - #{stage_text}")

    if progress >= 100 do
      IO.write("\n")
    end
  end

  defp display_agent_result(result) when is_map(result) do
    # Format structured results nicely
    result
    |> Enum.each(fn {key, value} ->
      IO.puts("#{key |> to_string() |> String.capitalize()}: #{format_value(value)}")
    end)
  end

  defp display_agent_result(result) when is_binary(result) do
    IO.puts(result)
  end

  defp display_agent_result(result) do
    IO.puts(inspect(result))
  end

  defp format_value(value) when is_list(value) do
    "#{length(value)} items"
  end

  defp format_value(value) when is_map(value) do
    "#{map_size(value)} properties"
  end

  defp format_value(value) do
    to_string(value)
  end

  defp show_command_table(commands) do
    commands
    |> Enum.sort_by(fn {cmd, _desc} -> cmd end)
    |> Enum.each(fn {cmd, desc} ->
      IO.puts("  /#{String.pad_trailing(cmd, 15)} - #{desc}")
    end)
  end

  defp add_completion_hints(completions) do
    # Add contextual hints to completions
    completions
    |> Enum.map(fn cmd ->
      case cmd do
        "mcp" -> "#{cmd} (AI server management)"
        "model" -> "#{cmd} (AI model selection)"
        "backend" -> "#{cmd} (LLM backend switching)"
        _ -> cmd
      end
    end)
  end

  defp suggest_similar_commands(input_command, session_id) do
    available = AgentCommandBridge.discover_available_commands(session_id)

    available.all
    |> Enum.map(fn cmd -> {cmd, string_similarity(input_command, cmd)} end)
    |> Enum.filter(fn {_cmd, similarity} -> similarity > 0.5 end)
    |> Enum.sort_by(fn {_cmd, similarity} -> similarity end, :desc)
    |> Enum.map(fn {cmd, _similarity} -> cmd end)
  end

  defp string_similarity(str1, str2) do
    # Simple similarity calculation (Jaro-Winkler would be better)
    longer = if String.length(str1) > String.length(str2), do: str1, else: str2
    shorter = if String.length(str1) <= String.length(str2), do: str1, else: str2

    if String.length(longer) == 0 do
      1.0
    else
      matches = count_common_chars(shorter, longer)
      matches / String.length(longer)
    end
  end

  defp count_common_chars(str1, str2) do
    str1_chars = String.graphemes(str1)
    str2_chars = String.graphemes(str2)

    str1_chars
    |> Enum.count(fn char -> char in str2_chars end)
  end
end
