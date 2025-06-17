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

      # Resource pool management
      MCPChat.Agents.AgentPool,

      # Dynamic supervisors for spawned agents
      {DynamicSupervisor, strategy: :one_for_one, name: MCPChat.ToolExecutorSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: MCPChat.ExportSupervisor}
    ]

    opts = [strategy: :rest_for_one]
    Supervisor.init(children, opts)
  end
end
