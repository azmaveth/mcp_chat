defmodule MCPChat.CLI.AgentCommandBridge do
  @moduledoc """
  Bridge between CLI commands and the agent architecture.

  This module handles command routing, agent discovery, and real-time
  updates from agents back to the CLI/TUI interface.
  """

  use GenServer
  require Logger

  alias MCPChat.Agents.{AgentPool, SessionManager}
  alias MCPChat.Events.AgentEvents
  alias MCPChat.CLI.Renderer

  # Commands that should be handled by agents
  @agent_commands %{
    # LLM Management
    "backend" => :llm_agent,
    "model" => :llm_agent,
    "models" => :llm_agent,
    "acceleration" => :llm_agent,

    # MCP Operations  
    "mcp" => :mcp_agent,

    # AI-Powered Analysis
    "cost" => :analysis_agent,
    "stats" => :analysis_agent,
    "export" => :export_agent,
    "concurrent" => :tool_agent
  }

  # Commands that stay in CLI
  @local_commands %{
    "help" => :local,
    "clear" => :local,
    "config" => :local,
    "tui" => :local,
    "notification" => :local,
    "alias" => :local,
    "new" => :local,
    "save" => :local,
    "load" => :local,
    "sessions" => :local,
    "history" => :local,
    "context" => :local,
    "system" => :local,
    "tokens" => :local,
    "strategy" => :local,
    "resume" => :local,
    "recovery" => :local
  }

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Route a command to either local handling or agent execution.
  Returns the command classification and routing information.
  """
  def route_command(command, args) do
    case classify_command(command) do
      {:local, _} ->
        {:local, command, args}

      {:agent, agent_type} ->
        {:agent, agent_type, command, args}

      {:unknown, _} ->
        {:unknown, command, args}
    end
  end

  @doc """
  Execute a command through the appropriate agent.
  Returns a stream of events for real-time updates.
  """
  def execute_agent_command(agent_type, command, args, session_id \\ "default") do
    task_spec = %{
      command: command,
      args: args,
      session_id: session_id,
      agent_type: agent_type
    }

    case AgentPool.request_tool_execution(session_id, task_spec) do
      {:ok, agent_pid} ->
        # Subscribe to events for this execution
        Phoenix.PubSub.subscribe(MCPChat.PubSub, "session:#{session_id}")
        {:ok, agent_pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get available commands by querying connected agents.
  """
  def discover_available_commands(session_id \\ "default") do
    local_commands = Map.keys(@local_commands)

    # Query agents for their available commands
    agent_commands =
      case SessionManager.get_session_pid(session_id) do
        {:ok, _pid} ->
          # In a real implementation, this would query actual agents
          # For now, return the static list
          Map.keys(@agent_commands)

        {:error, _} ->
          # No active session, return basic agent commands
          Map.keys(@agent_commands)
      end

    %{
      local: local_commands,
      agent: agent_commands,
      all: local_commands ++ agent_commands
    }
  end

  @doc """
  Generate enhanced help that includes agent capabilities.
  """
  def generate_enhanced_help(session_id \\ "default") do
    commands = discover_available_commands(session_id)

    %{
      local_commands: get_local_command_help(),
      agent_commands: get_agent_command_help(session_id),
      total_count: length(commands.all),
      session_active: SessionManager.get_session_pid(session_id) != {:error, :not_found}
    }
  end

  # Private functions

  defp classify_command(command) do
    cond do
      Map.has_key?(@local_commands, command) ->
        {:local, @local_commands[command]}

      Map.has_key?(@agent_commands, command) ->
        {:agent, @agent_commands[command]}

      true ->
        {:unknown, nil}
    end
  end

  defp get_local_command_help do
    # This would integrate with existing command modules
    # to get their help descriptions
    %{
      "help" => "Show available commands and agent status",
      "clear" => "Clear the screen",
      "config" => "Show current configuration",
      "new" => "Start a new conversation",
      "save" => "Save current session",
      "context" => "Manage conversation context"
      # ... etc
    }
  end

  defp get_agent_command_help(session_id) do
    # This would query actual agents for their capabilities
    # For now, return static descriptions
    %{
      "backend" => "Switch LLM backend (AI-powered selection)",
      "model" => "Model management with intelligent recommendations",
      "mcp" => "MCP server operations with auto-discovery",
      "cost" => "AI-powered cost analysis and optimization",
      "stats" => "Intelligent session analytics"
      # ... etc
    }
  end

  # GenServer callbacks

  def init(opts) do
    # Subscribe to agent events to track command availability
    Phoenix.PubSub.subscribe(MCPChat.PubSub, "agent_events")

    state = %{
      active_commands: %{},
      connected_agents: %{},
      command_history: []
    }

    {:ok, state}
  end

  def handle_info({:agent_connected, agent_type, agent_pid}, state) do
    Logger.info("Agent connected: #{agent_type} (#{inspect(agent_pid)})")

    new_state = put_in(state.connected_agents[agent_type], agent_pid)
    {:noreply, new_state}
  end

  def handle_info({:agent_disconnected, agent_type}, state) do
    Logger.info("Agent disconnected: #{agent_type}")

    new_state = Map.delete(state.connected_agents, agent_type)
    {:noreply, put_in(state, [:connected_agents], new_state)}
  end

  def handle_info(%AgentEvents.ToolExecutionCompleted{} = event, state) do
    # Command completed successfully
    Logger.debug("Command completed: #{event.tool_name}")
    {:noreply, state}
  end

  def handle_info(%AgentEvents.ToolExecutionFailed{} = event, state) do
    # Command failed
    Logger.warning("Command failed: #{event.tool_name} - #{event.error}")
    {:noreply, state}
  end

  def handle_info(_event, state) do
    {:noreply, state}
  end
end
