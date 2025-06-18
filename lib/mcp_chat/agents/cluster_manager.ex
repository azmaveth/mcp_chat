defmodule MCPChat.Agents.ClusterManager do
  @moduledoc """
  Cluster management for distributed agent orchestration.

  Handles node discovery, cluster formation, and cross-node communication
  for the distributed agent system.
  """

  use GenServer
  require Logger

  alias MCPChat.Agents.{DistributedSupervisor, DistributedRegistry}

  @default_config %{
    node_name: Node.self(),
    # :static, :multicast, :kubernetes
    cluster_strategy: :static,
    heartbeat_interval: 5_000,
    node_timeout: 15_000,
    cluster_members: [],
    multicast_port: 45_892,
    kubernetes_namespace: "default",
    auto_connect: true
  }

  defstruct [
    :config,
    :heartbeat_timer,
    :cluster_nodes,
    :node_status,
    :last_heartbeat
  ]

  @doc """
  Start the cluster manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get current cluster status.
  """
  def cluster_status do
    GenServer.call(__MODULE__, :cluster_status)
  end

  @doc """
  Get node health information.
  """
  def node_health do
    GenServer.call(__MODULE__, :node_health)
  end

  @doc """
  Connect to a specific node.
  """
  def connect_node(node_name) do
    GenServer.call(__MODULE__, {:connect_node, node_name})
  end

  @doc """
  Disconnect from a specific node.
  """
  def disconnect_node(node_name) do
    GenServer.call(__MODULE__, {:disconnect_node, node_name})
  end

  @doc """
  Force cluster rebalancing.
  """
  def rebalance_cluster do
    GenServer.call(__MODULE__, :rebalance_cluster, 30_000)
  end

  @doc """
  Get cluster topology information.
  """
  def cluster_topology do
    GenServer.call(__MODULE__, :cluster_topology)
  end

  @doc """
  Broadcast message to all cluster nodes.
  """
  def broadcast(message) do
    GenServer.cast(__MODULE__, {:broadcast, message})
  end

  # GenServer callbacks

  def init(opts) do
    config = build_config(opts)

    # Set up node monitoring
    :net_kernel.monitor_nodes(true)

    # Initialize cluster state
    state = %__MODULE__{
      config: config,
      cluster_nodes: MapSet.new([Node.self()]),
      node_status: %{Node.self() => :healthy},
      last_heartbeat: System.system_time(:millisecond)
    }

    # Start cluster formation
    if config.auto_connect do
      send(self(), :form_cluster)
    end

    # Schedule heartbeat
    timer = schedule_heartbeat(config.heartbeat_interval)
    state = %{state | heartbeat_timer: timer}

    Logger.info("Cluster manager started for node: #{config.node_name}")
    {:ok, state}
  end

  def handle_call(:cluster_status, _from, state) do
    status = %{
      node: Node.self(),
      cluster_size: MapSet.size(state.cluster_nodes),
      connected_nodes: MapSet.to_list(state.cluster_nodes),
      node_status: state.node_status,
      agent_distribution: get_agent_distribution(),
      last_heartbeat: state.last_heartbeat
    }

    {:reply, status, state}
  end

  def handle_call(:node_health, _from, state) do
    health = %{
      node: Node.self(),
      status: Map.get(state.node_status, Node.self(), :unknown),
      uptime: get_node_uptime(),
      memory_usage: get_memory_usage(),
      agent_count: get_local_agent_count(),
      registry_health: DistributedRegistry.health_check(),
      last_heartbeat: state.last_heartbeat
    }

    {:reply, health, state}
  end

  def handle_call({:connect_node, node_name}, _from, state) do
    result = connect_to_node(node_name)

    new_state =
      case result do
        :ok ->
          update_cluster_nodes(state, node_name, :connected)

        {:error, _reason} ->
          state
      end

    {:reply, result, new_state}
  end

  def handle_call({:disconnect_node, node_name}, _from, state) do
    result = disconnect_from_node(node_name)
    new_state = update_cluster_nodes(state, node_name, :disconnected)

    {:reply, result, new_state}
  end

  def handle_call(:rebalance_cluster, _from, state) do
    result = DistributedSupervisor.rebalance_cluster()
    {:reply, result, state}
  end

  def handle_call(:cluster_topology, _from, state) do
    topology = build_cluster_topology(state)
    {:reply, topology, state}
  end

  def handle_cast({:broadcast, message}, state) do
    # Send message to all connected nodes
    cluster_nodes = MapSet.delete(state.cluster_nodes, Node.self())

    Enum.each(cluster_nodes, fn node ->
      spawn(fn ->
        try do
          GenServer.cast({__MODULE__, node}, {:receive_broadcast, Node.self(), message})
        catch
          :exit, reason ->
            Logger.warning("Failed to broadcast to #{node}: #{inspect(reason)}")
        end
      end)
    end)

    {:noreply, state}
  end

  def handle_cast({:receive_broadcast, from_node, message}, state) do
    Logger.debug("Received broadcast from #{from_node}: #{inspect(message)}")

    # Handle different broadcast message types
    case message do
      {:heartbeat, node_info} ->
        handle_node_heartbeat(from_node, node_info, state)

      {:agent_moved, agent_info} ->
        handle_agent_movement(from_node, agent_info, state)

      {:cluster_event, event} ->
        handle_cluster_event(from_node, event, state)

      _ ->
        Logger.debug("Unknown broadcast message type: #{inspect(message)}")
        {:noreply, state}
    end
  end

  def handle_info(:form_cluster, state) do
    case state.config.cluster_strategy do
      :static ->
        form_static_cluster(state)

      :multicast ->
        form_multicast_cluster(state)

      :kubernetes ->
        form_kubernetes_cluster(state)

      _ ->
        Logger.warning("Unknown cluster strategy: #{state.config.cluster_strategy}")
        {:noreply, state}
    end
  end

  def handle_info(:heartbeat, state) do
    # Send heartbeat to cluster
    node_info = %{
      status: :healthy,
      agent_count: get_local_agent_count(),
      memory_usage: get_memory_usage(),
      timestamp: System.system_time(:millisecond)
    }

    broadcast({:heartbeat, node_info})

    # Check for dead nodes
    new_state = check_node_health(state)

    # Reschedule heartbeat
    timer = schedule_heartbeat(state.config.heartbeat_interval)
    new_state = %{new_state | heartbeat_timer: timer, last_heartbeat: System.system_time(:millisecond)}

    {:noreply, new_state}
  end

  def handle_info({:nodeup, node}, state) do
    Logger.info("Node connected: #{node}")
    new_state = update_cluster_nodes(state, node, :connected)
    {:noreply, new_state}
  end

  def handle_info({:nodedown, node}, state) do
    Logger.warning("Node disconnected: #{node}")
    new_state = update_cluster_nodes(state, node, :disconnected)
    {:noreply, new_state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp build_config(opts) do
    user_config = Keyword.get(opts, :config, %{})
    Map.merge(@default_config, user_config)
  end

  defp schedule_heartbeat(interval) do
    Process.send_after(self(), :heartbeat, interval)
  end

  defp form_static_cluster(state) do
    cluster_members = state.config.cluster_members

    results =
      Enum.map(cluster_members, fn member ->
        case connect_to_node(member) do
          :ok -> {member, :connected}
          {:error, reason} -> {member, {:failed, reason}}
        end
      end)

    successful_connections =
      results
      |> Enum.filter(fn {_, status} -> status == :connected end)
      |> Enum.map(fn {node, _} -> node end)

    new_cluster_nodes =
      state.cluster_nodes
      |> MapSet.union(MapSet.new(successful_connections))

    new_state = %{state | cluster_nodes: new_cluster_nodes}

    Logger.info("Static cluster formed: #{inspect(MapSet.to_list(new_cluster_nodes))}")
    {:noreply, new_state}
  end

  defp form_multicast_cluster(state) do
    # Simplified multicast discovery - in practice you'd use UDP multicast
    Logger.info("Multicast cluster discovery not implemented yet")
    {:noreply, state}
  end

  defp form_kubernetes_cluster(state) do
    # Kubernetes pod discovery - in practice you'd use Kubernetes API
    Logger.info("Kubernetes cluster discovery not implemented yet")
    {:noreply, state}
  end

  defp connect_to_node(node_name) do
    case Node.connect(node_name) do
      true ->
        :ok

      false ->
        {:error, :connection_failed}

      :ignored ->
        {:error, :connection_ignored}
    end
  end

  defp disconnect_from_node(node_name) do
    case Node.disconnect(node_name) do
      true -> :ok
      false -> {:error, :disconnect_failed}
      :ignored -> {:error, :disconnect_ignored}
    end
  end

  defp update_cluster_nodes(state, node, action) do
    {new_cluster_nodes, new_status} =
      case action do
        :connected ->
          {MapSet.put(state.cluster_nodes, node), Map.put(state.node_status, node, :healthy)}

        :disconnected ->
          {MapSet.delete(state.cluster_nodes, node), Map.delete(state.node_status, node)}
      end

    %{state | cluster_nodes: new_cluster_nodes, node_status: new_status}
  end

  defp get_agent_distribution do
    try do
      DistributedRegistry.get_stats()
    rescue
      _ -> %{error: "Registry unavailable"}
    end
  end

  defp get_local_agent_count do
    try do
      DistributedRegistry.list_agents_on_node(Node.self())
      |> length()
    rescue
      _ -> 0
    end
  end

  defp get_node_uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_ms
  end

  defp get_memory_usage do
    memory = :erlang.memory()

    %{
      total: Keyword.get(memory, :total, 0),
      processes: Keyword.get(memory, :processes, 0),
      system: Keyword.get(memory, :system, 0)
    }
  end

  defp build_cluster_topology(state) do
    nodes = MapSet.to_list(state.cluster_nodes)

    # Build adjacency information
    connections =
      Enum.map(nodes, fn node ->
        connected_to =
          if node == Node.self() do
            MapSet.delete(state.cluster_nodes, Node.self())
            |> MapSet.to_list()
          else
            # Would query remote node for its connections
            []
          end

        {node, connected_to}
      end)
      |> Enum.into(%{})

    %{
      nodes: nodes,
      connections: connections,
      node_status: state.node_status,
      cluster_size: length(nodes)
    }
  end

  defp handle_node_heartbeat(from_node, _node_info, state) do
    # Update node status based on heartbeat
    new_status = Map.put(state.node_status, from_node, :healthy)
    new_state = %{state | node_status: new_status}

    {:noreply, new_state}
  end

  defp handle_agent_movement(_from_node, _agent_info, state) do
    # Handle notification of agent movement between nodes
    {:noreply, state}
  end

  defp handle_cluster_event(_from_node, _event, state) do
    # Handle cluster-wide events
    {:noreply, state}
  end

  defp check_node_health(state) do
    current_time = System.system_time(:millisecond)
    _timeout_threshold = current_time - state.config.node_timeout

    # Mark nodes as unhealthy if they haven't sent heartbeat recently
    new_status =
      state.node_status
      |> Enum.map(fn {node, status} ->
        if node == Node.self() do
          {node, :healthy}
        else
          # In practice, you'd track last heartbeat time per node
          {node, status}
        end
      end)
      |> Enum.into(%{})

    %{state | node_status: new_status}
  end
end
