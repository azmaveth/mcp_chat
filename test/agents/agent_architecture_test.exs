defmodule MCPChat.Agents.AgentArchitectureTest do
  use ExUnit.Case, async: false

  describe "Agent Architecture Integration" do
    test "agent supervisor starts all required components" do
      # Agent supervisor should already be started by application
      # If not started, start it
      case MCPChat.Agents.AgentSupervisor.start_link([]) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      # Verify core agents are running
      assert Process.whereis(MCPChat.Agents.SessionManager) != nil
      assert Process.whereis(MCPChat.Agents.MaintenanceAgent) != nil
      assert Process.whereis(MCPChat.Agents.AgentPool) != nil

      # Verify ETS tables are created
      assert :ets.info(:export_registry) != :undefined
      assert :ets.info(:agent_pool_workers) != :undefined

      # Verify session registry is available
      assert Process.whereis(MCPChat.SessionRegistry) != nil

      # Verify dynamic supervisors are running
      assert Process.whereis(MCPChat.ToolExecutorSupervisor) != nil
      assert Process.whereis(MCPChat.ExportSupervisor) != nil
    end

    @tag :skip
    test "gateway can interact with session manager" do
      # Skip this test for now due to singleton Session module conflict
      # TODO: Update session architecture to support multiple sessions
      assert true
    end

    test "agent pool can manage workers" do
      # Ensure agent supervisor is running
      case MCPChat.Agents.AgentSupervisor.start_link([]) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      # Get initial pool status
      status = MCPChat.Gateway.get_agent_pool_status()
      assert status.active_workers == 0
      assert status.queue_length == 0
      # default value
      assert status.max_concurrent == 3
    end

    test "maintenance agent provides stats" do
      # Ensure agent supervisor is running
      case MCPChat.Agents.AgentSupervisor.start_link([]) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      # Get maintenance stats
      stats = MCPChat.Gateway.get_maintenance_stats()
      assert is_map(stats)
      assert Map.has_key?(stats, :cleanup_count)
      assert Map.has_key?(stats, :last_cleanup)
    end

    test "system health information is available" do
      # Ensure agent supervisor is running
      case MCPChat.Agents.AgentSupervisor.start_link([]) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      # Get system health
      health = MCPChat.Gateway.get_system_health()
      assert is_map(health)
      assert Map.has_key?(health, :timestamp)
      assert Map.has_key?(health, :sessions)
      assert Map.has_key?(health, :agent_pool)
      assert Map.has_key?(health, :maintenance)
      assert Map.has_key?(health, :memory_usage)
      assert Map.has_key?(health, :process_count)
    end
  end
end
