defmodule MCPChat.Agents.DistributedSupervisor do
  @moduledoc """
  Distributed agent supervisor using Horde for cross-node agent management.

  Provides fault-tolerant, distributed supervision of agents across multiple nodes
  with automatic failover and load balancing.
  """

  use Horde.DynamicSupervisor

  @doc """
  Start the distributed supervisor.
  """
  def start_link(init_arg) do
    Horde.DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Start an agent on the distributed cluster.
  """
  def start_agent(agent_spec, opts \\ []) do
    child_spec = build_child_spec(agent_spec, opts)
    Horde.DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @doc """
  Start an agent with a specific ID for discovery.
  """
  def start_agent_with_id(agent_id, agent_spec, opts \\ []) do
    child_spec = build_child_spec_with_id(agent_id, agent_spec, opts)
    Horde.DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @doc """
  Stop an agent by ID.
  """
  def stop_agent(agent_id) do
    case find_agent(agent_id) do
      {:ok, pid} ->
        Horde.DynamicSupervisor.terminate_child(__MODULE__, pid)

      {:error, :not_found} ->
        {:error, :agent_not_found}
    end
  end

  @doc """
  Find an agent by ID across the cluster.
  """
  def find_agent(agent_id) do
    case MCPChat.Agents.DistributedRegistry.lookup(agent_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  List all agents in the cluster.
  """
  def list_agents do
    Horde.DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} -> pid end)
    |> Enum.filter(&Process.alive?/1)
    |> Enum.map(&get_agent_info/1)
    |> Enum.filter(&(&1 != nil))
  end

  @doc """
  Get cluster status and agent distribution.
  """
  def cluster_status do
    members = Horde.DynamicSupervisor.members(__MODULE__)
    children = Horde.DynamicSupervisor.which_children(__MODULE__)

    node_distribution =
      children
      |> Enum.map(fn {_, pid, _, _} -> node(pid) end)
      |> Enum.frequencies()

    %{
      members: members,
      total_agents: length(children),
      node_distribution: node_distribution,
      cluster_size: length(members)
    }
  end

  @doc """
  Rebalance agents across cluster nodes.
  """
  def rebalance_cluster do
    status = cluster_status()

    if needs_rebalancing?(status) do
      perform_rebalancing(status)
    else
      {:ok, :balanced}
    end
  end

  # Horde.DynamicSupervisor callbacks

  @impl Horde.DynamicSupervisor
  def init(init_arg) do
    [strategy: :one_for_one, members: get_cluster_members()]
    |> Keyword.merge(init_arg)
    |> Horde.DynamicSupervisor.init()
  end

  # Private functions

  defp build_child_spec(agent_spec, opts) do
    %{
      id: make_ref(),
      start: agent_spec,
      restart: Keyword.get(opts, :restart, :permanent),
      shutdown: Keyword.get(opts, :shutdown, 5000),
      type: :worker
    }
  end

  defp build_child_spec_with_id(agent_id, agent_spec, opts) do
    %{
      id: agent_id,
      start: agent_spec,
      restart: Keyword.get(opts, :restart, :permanent),
      shutdown: Keyword.get(opts, :shutdown, 5000),
      type: :worker
    }
  end

  defp get_cluster_members do
    # Get cluster members from configuration or discovery
    case Application.get_env(:mcp_chat, :cluster_members) do
      nil -> [__MODULE__]
      members when is_list(members) -> Enum.map(members, &{__MODULE__, &1})
      _ -> [__MODULE__]
    end
  end

  defp get_agent_info(pid) do
    try do
      case GenServer.call(pid, :get_info, 1000) do
        {:ok, info} -> Map.put(info, :pid, pid)
        _ -> nil
      end
    catch
      :exit, _ -> nil
    end
  end

  defp needs_rebalancing?(%{node_distribution: distribution, cluster_size: size})
       when size > 1 do
    if map_size(distribution) == 0 do
      false
    else
      max_agents = Enum.max(Map.values(distribution))
      min_agents = Enum.min(Map.values(distribution))

      # Rebalance if difference is more than 2 agents
      max_agents - min_agents > 2
    end
  end

  defp needs_rebalancing?(_), do: false

  defp perform_rebalancing(status) do
    # Simple rebalancing strategy: move agents from overloaded nodes
    # to underloaded nodes

    target_per_node = div(status.total_agents, status.cluster_size)

    moves =
      status.node_distribution
      |> Enum.filter(fn {_node, count} -> count > target_per_node + 1 end)
      |> Enum.flat_map(fn {node, count} ->
        excess = count - target_per_node

        get_agents_on_node(node)
        |> Enum.take(excess)
        |> Enum.map(&{&1, find_target_node(status.node_distribution, target_per_node)})
      end)

    results =
      Enum.map(moves, fn {agent_pid, target_node} ->
        move_agent_to_node(agent_pid, target_node)
      end)

    success_count = Enum.count(results, &match?({:ok, _}, &1))

    {:ok,
     %{
       moves_attempted: length(moves),
       moves_successful: success_count,
       target_per_node: target_per_node
     }}
  end

  defp get_agents_on_node(target_node) do
    Horde.DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} -> pid end)
    |> Enum.filter(fn pid -> node(pid) == target_node end)
  end

  defp find_target_node(distribution, target_per_node) do
    distribution
    |> Enum.find(fn {_node, count} -> count < target_per_node end)
    |> case do
      {node, _} ->
        node

      nil ->
        # If no node is under target, pick the one with least agents
        {node, _} = Enum.min_by(distribution, fn {_, count} -> count end)
        node
    end
  end

  defp move_agent_to_node(agent_pid, target_node) do
    # This is a simplified version - in practice, you'd need to:
    # 1. Get agent state
    # 2. Stop agent on current node
    # 3. Start agent on target node
    # 4. Restore agent state

    try do
      # Get agent specification and state
      case GenServer.call(agent_pid, :get_migration_data, 5000) do
        {:ok, migration_data} ->
          # Stop current agent
          Horde.DynamicSupervisor.terminate_child(__MODULE__, agent_pid)

          # Start on target node
          child_spec = %{
            id: make_ref(),
            start: {migration_data.module, :start_link, [migration_data.state]},
            restart: :permanent
          }

          # Use Horde's distribution to start on target node
          case Horde.DynamicSupervisor.start_child(__MODULE__, child_spec) do
            {:ok, new_pid} ->
              {:ok, %{old_pid: agent_pid, new_pid: new_pid, target_node: target_node}}

            error ->
              error
          end

        error ->
          error
      end
    catch
      :exit, reason -> {:error, {:migration_failed, reason}}
    end
  end
end
