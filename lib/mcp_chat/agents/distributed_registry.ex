defmodule MCPChat.Agents.DistributedRegistry do
  @moduledoc """
  Distributed agent registry using Horde for cross-node agent discovery.

  Provides a distributed key-value store for agent registration and discovery
  across the cluster with eventual consistency.
  """

  use Horde.Registry

  @doc """
  Start the distributed registry.
  """
  def start_link(init_arg) do
    Horde.Registry.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Register an agent with the distributed registry.
  """
  def register_agent(agent_id, _agent_pid, metadata \\ %{}) do
    Horde.Registry.register(__MODULE__, agent_id, metadata)
  end

  @doc """
  Unregister an agent from the distributed registry.
  """
  def unregister_agent(agent_id) do
    Horde.Registry.unregister(__MODULE__, agent_id)
  end

  @doc """
  Look up an agent by ID across the cluster.
  """
  def lookup(agent_id) do
    Horde.Registry.lookup(__MODULE__, agent_id)
  end

  @doc """
  Get all registered agents across the cluster.
  """
  def list_agents do
    Horde.Registry.select(__MODULE__, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
  end

  @doc """
  Get agents by type across the cluster.
  """
  def list_agents_by_type(agent_type) do
    pattern = {{:"$1", :"$2", %{type: agent_type}}, [], [{{:"$1", :"$2"}}]}
    Horde.Registry.select(__MODULE__, [pattern])
  end

  @doc """
  Get agents on a specific node.
  """
  def list_agents_on_node(node) do
    list_agents()
    |> Enum.filter(fn {_key, pid, _meta} -> node(pid) == node end)
  end

  @doc """
  Find agents with specific capabilities.
  """
  def find_agents_with_capability(capability) do
    pattern =
      {{:"$1", :"$2", %{capabilities: :"$3"}}, [{:is_list, :"$3"}, {:>, {:length, :"$3"}, 0}],
       [{{:"$1", :"$2", :"$3"}}]}

    Horde.Registry.select(__MODULE__, [pattern])
    |> Enum.filter(fn {_key, _pid, capabilities} ->
      capability in capabilities
    end)
  end

  @doc """
  Update agent metadata.
  """
  def update_agent_metadata(agent_id, new_metadata) do
    case lookup(agent_id) do
      [{pid, _old_metadata}] ->
        # Re-register with new metadata
        unregister_agent(agent_id)
        register_agent(agent_id, pid, new_metadata)

      [] ->
        {:error, :agent_not_found}
    end
  end

  @doc """
  Get registry statistics.
  """
  def get_stats do
    all_agents = list_agents()

    node_distribution =
      all_agents
      |> Enum.map(fn {_key, pid, _meta} -> node(pid) end)
      |> Enum.frequencies()

    type_distribution =
      all_agents
      |> Enum.map(fn {_key, _pid, meta} -> Map.get(meta, :type, :unknown) end)
      |> Enum.frequencies()

    capability_distribution =
      all_agents
      |> Enum.flat_map(fn {_key, _pid, meta} ->
        Map.get(meta, :capabilities, [])
      end)
      |> Enum.frequencies()

    %{
      total_agents: length(all_agents),
      cluster_nodes: map_size(node_distribution),
      node_distribution: node_distribution,
      type_distribution: type_distribution,
      capability_distribution: capability_distribution,
      members: Horde.Registry.members(__MODULE__)
    }
  end

  @doc """
  Find the best agent for a task based on load and capabilities.
  """
  def find_best_agent_for_task(required_capabilities, task_metadata \\ %{}) do
    candidates =
      required_capabilities
      |> Enum.reduce(list_agents(), fn capability, agents ->
        Enum.filter(agents, fn {_key, _pid, meta} ->
          capability in Map.get(meta, :capabilities, [])
        end)
      end)

    if Enum.empty?(candidates) do
      {:error, :no_suitable_agent}
    else
      best_agent = select_best_candidate(candidates, task_metadata)
      {:ok, best_agent}
    end
  end

  @doc """
  Monitor an agent and handle cleanup on exit.
  """
  def monitor_agent(agent_id) do
    case lookup(agent_id) do
      [{pid, _metadata}] ->
        ref = Process.monitor(pid)
        {:ok, ref}

      [] ->
        {:error, :agent_not_found}
    end
  end

  # Horde.Registry callbacks

  @impl Horde.Registry
  def init(init_arg) do
    [keys: :unique, members: get_cluster_members()]
    |> Keyword.merge(init_arg)
    |> Horde.Registry.init()
  end

  # Private functions

  defp get_cluster_members do
    # Get cluster members from configuration or discovery
    case Application.get_env(:mcp_chat, :cluster_members) do
      nil -> [__MODULE__]
      members when is_list(members) -> Enum.map(members, &{__MODULE__, &1})
      _ -> [__MODULE__]
    end
  end

  defp select_best_candidate(candidates, task_metadata) do
    # Simple load-based selection - in practice you could use more sophisticated algorithms
    priority = Map.get(task_metadata, :priority, :normal)

    candidates
    |> Enum.map(fn {key, pid, meta} ->
      load_score = calculate_load_score(pid, meta)
      capability_score = calculate_capability_score(meta, task_metadata)

      total_score =
        case priority do
          :high -> capability_score * 2 + (100 - load_score)
          :low -> 100 - load_score
          _ -> capability_score + (100 - load_score)
        end

      {key, pid, meta, total_score}
    end)
    |> Enum.max_by(fn {_, _, _, score} -> score end)
    |> case do
      {key, pid, meta, _score} -> {key, pid, meta}
    end
  end

  defp calculate_load_score(pid, metadata) do
    # Try to get current load from agent
    base_load = Map.get(metadata, :current_load, 0)

    # Check message queue length as additional load indicator
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, queue_len} ->
        # Cap at 50
        queue_load = min(queue_len * 10, 50)
        min(base_load + queue_load, 100)

      nil ->
        # Process not available, max load
        100
    end
  end

  defp calculate_capability_score(metadata, task_metadata) do
    agent_capabilities = Map.get(metadata, :capabilities, [])
    required_capabilities = Map.get(task_metadata, :required_capabilities, [])
    preferred_capabilities = Map.get(task_metadata, :preferred_capabilities, [])

    # Score based on capability match
    required_score =
      required_capabilities
      |> Enum.count(fn cap -> cap in agent_capabilities end)
      # 20 points per required capability
      |> Kernel.*(20)

    preferred_score =
      preferred_capabilities
      |> Enum.count(fn cap -> cap in agent_capabilities end)
      # 10 points per preferred capability
      |> Kernel.*(10)

    # Bonus for specialized agents
    specialization_score =
      case Map.get(metadata, :specialization) do
        spec when is_atom(spec) ->
          if spec in required_capabilities, do: 15, else: 0

        _ ->
          0
      end

    required_score + preferred_score + specialization_score
  end

  @doc """
  Agent convenience functions for self-registration.
  """
  def register_self(agent_id, metadata \\ %{}) do
    register_agent(agent_id, self(), metadata)
  end

  def unregister_self(agent_id) do
    unregister_agent(agent_id)
  end

  def update_self_metadata(agent_id, new_metadata) do
    update_agent_metadata(agent_id, new_metadata)
  end

  @doc """
  Health check functions.
  """
  def health_check do
    try do
      stats = get_stats()

      %{
        status: :healthy,
        total_agents: stats.total_agents,
        cluster_size: stats.cluster_nodes,
        members: length(stats.members),
        timestamp: System.system_time(:millisecond)
      }
    rescue
      error ->
        %{
          status: :unhealthy,
          error: inspect(error),
          timestamp: System.system_time(:millisecond)
        }
    end
  end

  def ping_agents do
    list_agents()
    |> Enum.map(fn {key, pid, _meta} ->
      if Process.alive?(pid) do
        try do
          GenServer.call(pid, :ping, 1000)
          {key, :ok}
        catch
          :exit, _ -> {key, :timeout}
        end
      else
        {key, :dead}
      end
    end)
  end
end
