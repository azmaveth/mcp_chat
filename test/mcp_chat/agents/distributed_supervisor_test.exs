defmodule MCPChat.Agents.DistributedSupervisorTest do
  use ExUnit.Case, async: false

  alias MCPChat.Agents.{DistributedSupervisor, DistributedRegistry}

  setup do
    # Note: These tests assume Horde is available and working
    # In a real test environment, you might want to use mocks
    :ok
  end

  describe "DistributedSupervisor" do
    test "starts successfully" do
      # The supervisor should already be started by the application
      assert Process.whereis(DistributedSupervisor) != nil
    end

    test "can list agents" do
      agents = DistributedSupervisor.list_agents()
      assert is_list(agents)
    end

    test "provides cluster status" do
      status = DistributedSupervisor.cluster_status()

      assert is_map(status)
      assert Map.has_key?(status, :members)
      assert Map.has_key?(status, :total_agents)
      assert Map.has_key?(status, :node_distribution)
      assert Map.has_key?(status, :cluster_size)
    end

    test "can trigger rebalancing" do
      result = DistributedSupervisor.rebalance_cluster()

      # Should return either :balanced or rebalancing results
      case result do
        {:ok, :balanced} -> :ok
        {:ok, %{moves_attempted: _, moves_successful: _, target_per_node: _}} -> :ok
        other -> flunk("Unexpected rebalance result: #{inspect(other)}")
      end
    end
  end

  describe "Agent Management" do
    test "handles agent not found gracefully" do
      result = DistributedSupervisor.find_agent("non_existent_agent")
      assert result == {:error, :not_found}
    end

    test "can stop non-existent agent gracefully" do
      result = DistributedSupervisor.stop_agent("non_existent_agent")
      assert result == {:error, :agent_not_found}
    end
  end

  describe "Error Handling" do
    test "gracefully handles registry unavailability" do
      # Test should not crash even if registry is not available
      agents = DistributedSupervisor.list_agents()
      assert is_list(agents)
    end
  end
end
