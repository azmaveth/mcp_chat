defmodule MCPChat.Agents.AgentSupervisor do
  @moduledoc """
  Main supervisor for the agent architecture.

  This supervisor coordinates all agent-related supervisors and ensures
  proper startup order and fault tolerance for the agent system.
  """

  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting Agent Architecture Supervisor")

    # Create ETS tables needed by agents
    :ets.new(:export_registry, [:set, :public, :named_table])
    :ets.new(:agent_pool_workers, [:set, :public, :named_table])

    children = [
      # Session registry for agent coordination
      {Registry, keys: :unique, name: MCPChat.SessionRegistry},

      # Core agent managers
      MCPChat.Agents.SessionManager,
      MCPChat.Agents.MaintenanceAgent,

      # Multi-Agent Orchestration System
      MCPChat.Agents.AgentRegistry,
      MCPChat.Agents.AgentCoordinator,

      # Resource pool management
      MCPChat.Agents.AgentPool,

      # Dynamic supervisors for spawned agents
      {DynamicSupervisor, strategy: :one_for_one, name: MCPChat.ToolExecutorSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: MCPChat.ExportSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: MCPChat.AgentSupervisor}
    ]

    opts = [strategy: :rest_for_one]
    Supervisor.init(children, opts)
  end

  # Web UI support functions

  @doc "List all agents"
  def list_agents do
    # Get all children from the supervisor
    children = Supervisor.which_children(__MODULE__)

    agents =
      Enum.flat_map(children, fn
        {MCPChat.Agents.SessionManager, pid, :worker, _} when is_pid(pid) ->
          # Get all sessions from SessionManager
          case MCPChat.Agents.SessionManager.list_all_sessions() do
            {:ok, sessions} ->
              Enum.map(sessions, fn {session_id, session_pid} ->
                {session_id, session_pid, :session}
              end)

            _ ->
              []
          end

        {MCPChat.Agents.MaintenanceAgent, pid, :worker, _} when is_pid(pid) ->
          [{"maintenance_agent", pid, :maintenance}]

        {MCPChat.Agents.AgentPool, pid, :worker, _} when is_pid(pid) ->
          [{"agent_pool", pid, :pool}]

        _ ->
          []
      end)

    {:ok, agents}
  end

  @doc "Get a specific agent"
  def get_agent(agent_id) do
    case MCPChat.Agents.SessionManager.get_session_pid(agent_id) do
      {:ok, pid} ->
        {:ok, {pid, :session}}

      {:error, :not_found} ->
        # Check if it's a special agent
        case agent_id do
          "maintenance_agent" ->
            case Process.whereis(MCPChat.Agents.MaintenanceAgent) do
              nil -> {:error, :not_found}
              pid -> {:ok, {pid, :maintenance}}
            end

          "agent_pool" ->
            case Process.whereis(MCPChat.Agents.AgentPool) do
              nil -> {:error, :not_found}
              pid -> {:ok, {pid, :pool}}
            end

          _ ->
            {:error, :not_found}
        end
    end
  end

  @doc "Stop an agent"
  def stop_agent(agent_id) do
    Logger.info("Stopping agent", agent_id: agent_id)

    case get_agent(agent_id) do
      {:ok, {pid, :session}} ->
        MCPChat.Agents.SessionManager.stop_session(agent_id)

      {:ok, {_pid, type}} ->
        Logger.warning("Cannot stop system agent", agent_id: agent_id, type: type)
        {:error, :cannot_stop_system_agent}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Start an agent"
  def start_agent(agent_id, type, opts) do
    Logger.info("Starting agent", agent_id: agent_id, type: type)

    case type do
      :session ->
        user_id = Keyword.get(opts, :user_id, "system")
        MCPChat.Agents.SessionManager.start_session(agent_id, [user_id: user_id] ++ opts)

      _ ->
        {:error, :unsupported_agent_type}
    end
  end

  @doc "Start an LLM agent for a session"
  def start_llm_agent(session_id) do
    Logger.info("Starting LLM agent", session_id: session_id)

    # In the actual implementation, this would create a session
    # For now, use the session manager
    case MCPChat.Agents.SessionManager.get_session_pid(session_id) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, :not_found} ->
        MCPChat.Agents.SessionManager.start_session(session_id, user_id: "system")
    end
  end
end
