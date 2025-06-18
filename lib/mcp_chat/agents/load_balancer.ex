defmodule MCPChat.Agents.LoadBalancer do
  @moduledoc """
  Intelligent load balancer for distributed agent orchestration.

  Provides smart agent placement and task distribution across the cluster
  based on node capacity, agent capabilities, and current load.
  """

  use GenServer
  require Logger

  alias MCPChat.Agents.{DistributedRegistry, ClusterManager}

  @default_config %{
    load_check_interval: 10_000,
    rebalance_threshold: 0.8,
    max_agents_per_node: 100,
    load_calculation_window: 60_000,
    # :least_loaded, :capability_aware, :round_robin
    placement_strategy: :least_loaded,
    enable_automatic_rebalancing: true
  }

  defstruct [
    :config,
    :load_check_timer,
    :node_loads,
    :placement_history,
    :rebalance_stats
  ]

  @doc """
  Start the load balancer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Find the best node to place a new agent.
  """
  def find_best_node_for_agent(agent_spec, requirements \\ %{}) do
    GenServer.call(__MODULE__, {:find_best_node, agent_spec, requirements})
  end

  @doc """
  Get current load distribution across the cluster.
  """
  def get_load_distribution do
    GenServer.call(__MODULE__, :get_load_distribution)
  end

  @doc """
  Trigger immediate load balancing.
  """
  def trigger_rebalancing do
    GenServer.call(__MODULE__, :trigger_rebalancing, 30_000)
  end

  @doc """
  Get load balancer statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Update placement strategy.
  """
  def set_placement_strategy(strategy) do
    GenServer.call(__MODULE__, {:set_placement_strategy, strategy})
  end

  # GenServer callbacks

  def init(opts) do
    config = build_config(opts)

    state = %__MODULE__{
      config: config,
      node_loads: %{},
      placement_history: [],
      rebalance_stats: %{
        total_rebalances: 0,
        successful_moves: 0,
        failed_moves: 0,
        last_rebalance: nil
      }
    }

    # Schedule load checking
    timer = schedule_load_check(config.load_check_interval)
    state = %{state | load_check_timer: timer}

    Logger.info("Load balancer started with strategy: #{config.placement_strategy}")
    {:ok, state}
  end

  def handle_call({:find_best_node, agent_spec, requirements}, _from, state) do
    {best_node, placement_info} = select_best_node(agent_spec, requirements, state)

    # Update placement history
    placement_record = %{
      timestamp: System.system_time(:millisecond),
      agent_spec: agent_spec,
      selected_node: best_node,
      placement_info: placement_info,
      requirements: requirements
    }

    new_history = [placement_record | Enum.take(state.placement_history, 99)]
    new_state = %{state | placement_history: new_history}

    {:reply, {:ok, best_node, placement_info}, new_state}
  end

  def handle_call(:get_load_distribution, _from, state) do
    distribution = calculate_current_load_distribution(state)
    {:reply, distribution, state}
  end

  def handle_call(:trigger_rebalancing, _from, state) do
    result = perform_rebalancing(state)
    new_state = update_rebalance_stats(state, result)
    {:reply, result, new_state}
  end

  def handle_call(:get_stats, _from, state) do
    stats = %{
      placement_history_count: length(state.placement_history),
      rebalance_stats: state.rebalance_stats,
      current_strategy: state.config.placement_strategy,
      node_loads: state.node_loads,
      config: state.config
    }

    {:reply, stats, state}
  end

  def handle_call({:set_placement_strategy, strategy}, _from, state) do
    new_config = %{state.config | placement_strategy: strategy}
    new_state = %{state | config: new_config}

    Logger.info("Placement strategy changed to: #{strategy}")
    {:reply, :ok, new_state}
  end

  def handle_info(:check_load, state) do
    # Update node load information
    new_loads = collect_node_loads()
    new_state = %{state | node_loads: new_loads}

    # Check if rebalancing is needed
    if should_rebalance?(new_loads, state.config) and state.config.enable_automatic_rebalancing do
      Logger.info("Triggering automatic rebalancing")
      result = perform_rebalancing(new_state)
      final_state = update_rebalance_stats(new_state, result)

      # Reschedule
      timer = schedule_load_check(state.config.load_check_interval)
      final_state = %{final_state | load_check_timer: timer}

      {:noreply, final_state}
    else
      # Reschedule
      timer = schedule_load_check(state.config.load_check_interval)
      new_state = %{new_state | load_check_timer: timer}

      {:noreply, new_state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp build_config(opts) do
    user_config = Keyword.get(opts, :config, %{})
    Map.merge(@default_config, user_config)
  end

  defp schedule_load_check(interval) do
    Process.send_after(self(), :check_load, interval)
  end

  defp select_best_node(agent_spec, requirements, state) do
    cluster_status = ClusterManager.cluster_status()
    available_nodes = cluster_status.connected_nodes

    case state.config.placement_strategy do
      :least_loaded ->
        select_least_loaded_node(available_nodes, agent_spec, requirements, state)

      :capability_aware ->
        select_capability_aware_node(available_nodes, agent_spec, requirements, state)

      :round_robin ->
        select_round_robin_node(available_nodes, agent_spec, requirements, state)

      _ ->
        # Fallback to least loaded
        select_least_loaded_node(available_nodes, agent_spec, requirements, state)
    end
  end

  defp select_least_loaded_node(nodes, _agent_spec, _requirements, state) do
    node_loads = state.node_loads

    best_node =
      nodes
      |> Enum.map(fn node ->
        load = Map.get(node_loads, node, %{cpu: 0, memory: 0, agents: 0})
        total_load = calculate_total_load(load)
        {node, total_load}
      end)
      |> Enum.min_by(fn {_node, load} -> load end)
      |> elem(0)

    placement_info = %{
      strategy: :least_loaded,
      load_scores: Map.get(node_loads, best_node, %{}),
      reason: "Selected node with lowest overall load"
    }

    {best_node, placement_info}
  end

  defp select_capability_aware_node(nodes, agent_spec, requirements, state) do
    # Find nodes that can support the required capabilities
    required_capabilities = Map.get(requirements, :capabilities, [])

    capable_nodes =
      if Enum.empty?(required_capabilities) do
        nodes
      else
        Enum.filter(nodes, fn node ->
          node_has_capabilities?(node, required_capabilities)
        end)
      end

    if Enum.empty?(capable_nodes) do
      # Fallback to least loaded if no capable nodes
      select_least_loaded_node(nodes, agent_spec, requirements, state)
    else
      # Among capable nodes, select the least loaded
      node_loads = state.node_loads

      best_node =
        capable_nodes
        |> Enum.map(fn node ->
          load = Map.get(node_loads, node, %{cpu: 0, memory: 0, agents: 0})
          total_load = calculate_total_load(load)
          {node, total_load}
        end)
        |> Enum.min_by(fn {_node, load} -> load end)
        |> elem(0)

      placement_info = %{
        strategy: :capability_aware,
        capable_nodes: capable_nodes,
        required_capabilities: required_capabilities,
        reason: "Selected capable node with lowest load"
      }

      {best_node, placement_info}
    end
  end

  defp select_round_robin_node(nodes, _agent_spec, _requirements, state) do
    # Simple round-robin based on placement history
    last_placements = Enum.take(state.placement_history, length(nodes))
    recent_nodes = Enum.map(last_placements, & &1.selected_node)

    best_node =
      nodes
      |> Enum.find(fn node -> node not in recent_nodes end)
      |> case do
        # All nodes used recently, pick random
        nil -> Enum.random(nodes)
        node -> node
      end

    placement_info = %{
      strategy: :round_robin,
      recent_placements: length(last_placements),
      reason: "Round-robin selection"
    }

    {best_node, placement_info}
  end

  defp collect_node_loads do
    cluster_status = ClusterManager.cluster_status()

    cluster_status.connected_nodes
    |> Enum.map(fn node ->
      load_info = get_node_load_info(node)
      {node, load_info}
    end)
    |> Enum.into(%{})
  end

  defp get_node_load_info(node) do
    if node == Node.self() do
      # Local node - get detailed information
      %{
        cpu: get_cpu_usage(),
        memory: get_memory_usage_percentage(),
        agents: get_local_agent_count(),
        timestamp: System.system_time(:millisecond)
      }
    else
      # Remote node - try to get information via RPC
      try do
        :rpc.call(node, __MODULE__, :get_local_load_info, [], 5000)
      catch
        :exit, _ ->
          %{cpu: 0, memory: 0, agents: 0, error: :rpc_failed}
      end
    end
  end

  @doc """
  Get local node load information (called via RPC).
  """
  def get_local_load_info do
    %{
      cpu: get_cpu_usage(),
      memory: get_memory_usage_percentage(),
      agents: get_local_agent_count(),
      timestamp: System.system_time(:millisecond)
    }
  end

  defp calculate_total_load(load_info) do
    cpu = Map.get(load_info, :cpu, 0)
    memory = Map.get(load_info, :memory, 0)
    agents = Map.get(load_info, :agents, 0)

    # Weighted load calculation
    cpu * 0.4 + memory * 0.4 + agents / 10 * 0.2
  end

  defp node_has_capabilities?(node, required_capabilities) do
    try do
      agents_on_node = DistributedRegistry.list_agents_on_node(node)

      available_capabilities =
        agents_on_node
        |> Enum.flat_map(fn {_key, _pid, meta} ->
          Map.get(meta, :capabilities, [])
        end)
        |> Enum.uniq()

      Enum.all?(required_capabilities, fn cap -> cap in available_capabilities end)
    rescue
      _ -> false
    end
  end

  defp should_rebalance?(node_loads, config) do
    if map_size(node_loads) <= 1 do
      false
    else
      loads = Map.values(node_loads)
      total_loads = Enum.map(loads, &calculate_total_load/1)

      max_load = Enum.max(total_loads)
      min_load = Enum.min(total_loads)

      # Rebalance if the difference exceeds threshold
      max_load - min_load > config.rebalance_threshold
    end
  end

  defp perform_rebalancing(_state) do
    try do
      # Use the distributed supervisor's rebalancing
      case MCPChat.Agents.DistributedSupervisor.rebalance_cluster() do
        {:ok, result} -> {:ok, result}
        other -> {:ok, other}
      end
    rescue
      error -> {:error, {:rebalance_failed, error}}
    end
  end

  defp update_rebalance_stats(state, result) do
    current_stats = state.rebalance_stats

    new_stats =
      case result do
        {:ok, %{moves_successful: successful, moves_attempted: attempted}} ->
          %{
            current_stats
            | total_rebalances: current_stats.total_rebalances + 1,
              successful_moves: current_stats.successful_moves + successful,
              failed_moves: current_stats.failed_moves + (attempted - successful),
              last_rebalance: System.system_time(:millisecond)
          }

        {:ok, _} ->
          %{
            current_stats
            | total_rebalances: current_stats.total_rebalances + 1,
              last_rebalance: System.system_time(:millisecond)
          }

        {:error, _} ->
          %{
            current_stats
            | total_rebalances: current_stats.total_rebalances + 1,
              last_rebalance: System.system_time(:millisecond)
          }
      end

    %{state | rebalance_stats: new_stats}
  end

  defp calculate_current_load_distribution(state) do
    cluster_status = ClusterManager.cluster_status()

    distribution =
      cluster_status.connected_nodes
      |> Enum.map(fn node ->
        load = Map.get(state.node_loads, node, %{})
        total_load = calculate_total_load(load)

        {node,
         %{
           load: load,
           total_load: total_load,
           agent_count: Map.get(load, :agents, 0)
         }}
      end)
      |> Enum.into(%{})

    %{
      nodes: distribution,
      cluster_size: length(cluster_status.connected_nodes),
      total_agents: Enum.sum(Enum.map(distribution, fn {_, info} -> info.agent_count end)),
      average_load: calculate_average_load(distribution),
      load_variance: calculate_load_variance(distribution)
    }
  end

  defp calculate_average_load(distribution) do
    if map_size(distribution) == 0 do
      0
    else
      total = Enum.sum(Enum.map(distribution, fn {_, info} -> info.total_load end))
      total / map_size(distribution)
    end
  end

  defp calculate_load_variance(distribution) do
    if map_size(distribution) <= 1 do
      0
    else
      loads = Enum.map(distribution, fn {_, info} -> info.total_load end)
      avg = Enum.sum(loads) / length(loads)

      variance =
        loads
        |> Enum.map(fn load -> :math.pow(load - avg, 2) end)
        |> Enum.sum()
        |> Kernel./(length(loads))

      :math.sqrt(variance)
    end
  end

  defp get_cpu_usage do
    # Simple CPU usage approximation
    case :cpu_sup.util() do
      {:error, _} -> 0
      usage when is_number(usage) -> usage
      _ -> 0
    end
  end

  defp get_memory_usage_percentage do
    memory = :erlang.memory()
    total = Keyword.get(memory, :total, 1)
    # Approximate system memory limit (this is simplified)
    # 1GB default
    system_limit = 1_000_000_000

    total / system_limit * 100
  end

  defp get_local_agent_count do
    try do
      DistributedRegistry.list_agents_on_node(Node.self())
      |> length()
    rescue
      _ -> 0
    end
  end
end
