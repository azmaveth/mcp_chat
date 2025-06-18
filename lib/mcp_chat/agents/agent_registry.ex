defmodule MCPChat.Agents.AgentRegistry do
  @moduledoc """
  Agent Registry manages agent discovery, routing, and coordination.

  This module provides:
  - Agent registration and discovery
  - Capability-based agent lookup
  - Agent health monitoring
  - Load balancing for similar agents
  - Agent metadata management
  """

  use GenServer
  require Logger

  @registry_table :agent_registry
  @capabilities_table :agent_capabilities
  @health_check_interval 30_000

  # Public API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register an agent with its capabilities.
  """
  def register_agent(agent_id, agent_type, pid, capabilities \\ []) do
    GenServer.call(__MODULE__, {:register_agent, agent_id, agent_type, pid, capabilities})
  end

  @doc """
  Unregister an agent.
  """
  def unregister_agent(agent_id) do
    GenServer.call(__MODULE__, {:unregister_agent, agent_id})
  end

  @doc """
  Get the PID of a specific agent.
  """
  def get_agent_pid(agent_id) do
    case :ets.lookup(@registry_table, agent_id) do
      [{^agent_id, agent_info}] ->
        if Process.alive?(agent_info.pid) do
          {:ok, agent_info.pid}
        else
          {:error, :agent_dead}
        end

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Find agents by type.
  """
  def find_agents_by_type(agent_type) do
    GenServer.call(__MODULE__, {:find_agents_by_type, agent_type})
  end

  @doc """
  Find agents by capability.
  """
  def find_agents_by_capability(capability) do
    GenServer.call(__MODULE__, {:find_agents_by_capability, capability})
  end

  @doc """
  Get the best agent for a specific task.
  """
  def find_best_agent_for_task(task_spec) do
    GenServer.call(__MODULE__, {:find_best_agent_for_task, task_spec})
  end

  @doc """
  List all registered agents.
  """
  def list_all_agents do
    case :ets.tab2list(@registry_table) do
      agents when is_list(agents) ->
        {:ok,
         Enum.map(agents, fn {agent_id, info} ->
           %{
             agent_id: agent_id,
             agent_type: info.agent_type,
             status: if(Process.alive?(info.pid), do: :alive, else: :dead),
             capabilities: info.capabilities,
             registered_at: info.registered_at,
             pid: info.pid
           }
         end)}

      _ ->
        {:ok, []}
    end
  end

  @doc """
  Get detailed agent information.
  """
  def get_agent_info(agent_id) do
    case :ets.lookup(@registry_table, agent_id) do
      [{^agent_id, info}] ->
        # Get current status from the agent
        status =
          if Process.alive?(info.pid) do
            try do
              GenServer.call(info.pid, :get_status, 1000)
            rescue
              _ -> %{status: :unresponsive}
            end
          else
            %{status: :dead}
          end

        {:ok, Map.merge(info, status)}

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Update agent capabilities.
  """
  def update_agent_capabilities(agent_id, new_capabilities) do
    GenServer.call(__MODULE__, {:update_capabilities, agent_id, new_capabilities})
  end

  @doc """
  Get registry statistics.
  """
  def get_registry_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # GenServer implementation

  def init(_opts) do
    # Create ETS tables for fast lookups
    :ets.new(@registry_table, [:set, :public, :named_table, {:read_concurrency, true}])
    :ets.new(@capabilities_table, [:bag, :public, :named_table, {:read_concurrency, true}])

    # Schedule periodic health checks
    Process.send_after(self(), :health_check, @health_check_interval)

    Logger.info("Agent Registry started")

    {:ok,
     %{
       agent_count: 0,
       registrations: 0,
       unregistrations: 0,
       health_checks: 0,
       dead_agents_cleaned: 0
     }}
  end

  def handle_call({:register_agent, agent_id, agent_type, pid, capabilities}, _from, state) do
    # Check if agent already exists
    case :ets.lookup(@registry_table, agent_id) do
      [{^agent_id, existing_info}] ->
        if Process.alive?(existing_info.pid) do
          {:reply, {:error, :already_registered}, state}
        else
          # Clean up dead agent and register new one
          cleanup_dead_agent(agent_id)
          do_register_agent(agent_id, agent_type, pid, capabilities, state)
        end

      [] ->
        do_register_agent(agent_id, agent_type, pid, capabilities, state)
    end
  end

  def handle_call({:unregister_agent, agent_id}, _from, state) do
    case :ets.lookup(@registry_table, agent_id) do
      [{^agent_id, _info}] ->
        cleanup_dead_agent(agent_id)

        new_state = %{
          state
          | agent_count: max(0, state.agent_count - 1),
            unregistrations: state.unregistrations + 1
        }

        Logger.debug("Agent unregistered", agent_id: agent_id)
        {:reply, :ok, new_state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:find_agents_by_type, agent_type}, _from, state) do
    agents = find_agents_matching(fn info -> info.agent_type == agent_type end)
    {:reply, {:ok, agents}, state}
  end

  def handle_call({:find_agents_by_capability, capability}, _from, state) do
    # Use capabilities table for efficient lookup
    matches = :ets.lookup(@capabilities_table, capability)

    agent_ids = Enum.map(matches, fn {_cap, agent_id} -> agent_id end)

    agents =
      agent_ids
      |> Enum.map(fn agent_id ->
        case :ets.lookup(@registry_table, agent_id) do
          [{^agent_id, info}] ->
            if Process.alive?(info.pid), do: info, else: nil

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:reply, {:ok, agents}, state}
  end

  def handle_call({:find_best_agent_for_task, task_spec}, _from, state) do
    # Find agents that can handle this task type
    required_capabilities = extract_required_capabilities(task_spec)

    candidates =
      required_capabilities
      |> Enum.flat_map(fn cap ->
        case find_agents_by_capability(cap) do
          {:ok, agents} -> agents
          _ -> []
        end
      end)
      |> Enum.uniq_by(& &1.agent_id)
      |> Enum.filter(fn info -> Process.alive?(info.pid) end)

    # Score and rank candidates
    best_agent =
      candidates
      |> Enum.map(&score_agent_for_task(&1, task_spec))
      |> Enum.max_by(fn {_info, score} -> score end, fn -> nil end)

    case best_agent do
      {agent_info, _score} -> {:reply, {:ok, agent_info}, state}
      nil -> {:reply, {:error, :no_suitable_agent}, state}
    end
  end

  def handle_call({:update_capabilities, agent_id, new_capabilities}, _from, state) do
    case :ets.lookup(@registry_table, agent_id) do
      [{^agent_id, info}] ->
        # Remove old capability mappings
        Enum.each(info.capabilities, fn cap ->
          :ets.delete_object(@capabilities_table, {cap, agent_id})
        end)

        # Add new capability mappings
        Enum.each(new_capabilities, fn cap ->
          :ets.insert(@capabilities_table, {cap, agent_id})
        end)

        # Update agent info
        updated_info = %{info | capabilities: new_capabilities}
        :ets.insert(@registry_table, {agent_id, updated_info})

        Logger.debug("Updated agent capabilities",
          agent_id: agent_id,
          capabilities: new_capabilities
        )

        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:get_stats, _from, state) do
    alive_agents = count_alive_agents()

    stats =
      Map.merge(state, %{
        alive_agents: alive_agents,
        total_registered: state.agent_count
      })

    {:reply, stats, state}
  end

  def handle_info(:health_check, state) do
    # Check for dead agents and clean them up
    dead_agents = find_dead_agents()

    Enum.each(dead_agents, fn agent_id ->
      Logger.warning("Cleaning up dead agent", agent_id: agent_id)
      cleanup_dead_agent(agent_id)
    end)

    dead_count = length(dead_agents)

    new_state = %{
      state
      | health_checks: state.health_checks + 1,
        dead_agents_cleaned: state.dead_agents_cleaned + dead_count,
        agent_count: max(0, state.agent_count - dead_count)
    }

    # Schedule next health check
    Process.send_after(self(), :health_check, @health_check_interval)

    {:noreply, new_state}
  end

  # Private helper functions

  defp do_register_agent(agent_id, agent_type, pid, capabilities, state) do
    # Monitor the agent process
    Process.monitor(pid)

    # Create agent info
    agent_info = %{
      agent_id: agent_id,
      agent_type: agent_type,
      pid: pid,
      capabilities: capabilities,
      registered_at: DateTime.utc_now(),
      health_status: :healthy
    }

    # Store in registry
    :ets.insert(@registry_table, {agent_id, agent_info})

    # Store capability mappings
    Enum.each(capabilities, fn capability ->
      :ets.insert(@capabilities_table, {capability, agent_id})
    end)

    new_state = %{
      state
      | agent_count: state.agent_count + 1,
        registrations: state.registrations + 1
    }

    Logger.info("Agent registered",
      agent_id: agent_id,
      agent_type: agent_type,
      capabilities: capabilities
    )

    {:reply, :ok, new_state}
  end

  defp cleanup_dead_agent(agent_id) do
    case :ets.lookup(@registry_table, agent_id) do
      [{^agent_id, info}] ->
        # Remove capability mappings
        Enum.each(info.capabilities, fn cap ->
          :ets.delete_object(@capabilities_table, {cap, agent_id})
        end)

        # Remove from registry
        :ets.delete(@registry_table, agent_id)

      [] ->
        :ok
    end
  end

  defp find_agents_matching(predicate) do
    :ets.tab2list(@registry_table)
    |> Enum.filter(fn {_agent_id, info} ->
      Process.alive?(info.pid) and predicate.(info)
    end)
    |> Enum.map(fn {_agent_id, info} -> info end)
  end

  defp find_dead_agents do
    :ets.tab2list(@registry_table)
    |> Enum.filter(fn {_agent_id, info} -> not Process.alive?(info.pid) end)
    |> Enum.map(fn {agent_id, _info} -> agent_id end)
  end

  defp count_alive_agents do
    :ets.tab2list(@registry_table)
    |> Enum.count(fn {_agent_id, info} -> Process.alive?(info.pid) end)
  end

  defp extract_required_capabilities(task_spec) do
    case task_spec do
      %{type: :code_generation} -> [:code_writing, :language_analysis]
      %{type: :code_review} -> [:code_analysis, :pattern_detection]
      %{type: :documentation} -> [:documentation_writing, :code_analysis]
      %{type: :testing} -> [:test_writing, :code_analysis]
      %{type: :research} -> [:research, :data_analysis]
      %{required_capabilities: caps} -> caps
      _ -> [:general]
    end
  end

  defp score_agent_for_task(agent_info, task_spec) do
    base_score = 50

    # Score based on capability match
    required_caps = extract_required_capabilities(task_spec)

    capability_score =
      required_caps
      |> Enum.count(fn cap -> cap in agent_info.capabilities end)
      |> Kernel.*(20)

    # Score based on agent type relevance
    type_score =
      case {agent_info.agent_type, task_spec[:type]} do
        {:coder, :code_generation} -> 30
        {:reviewer, :code_review} -> 30
        {:documenter, :documentation} -> 30
        {:tester, :testing} -> 30
        {:researcher, :research} -> 30
        _ -> 10
      end

    # Score based on current load (prefer less busy agents)
    load_score =
      try do
        %{active_tasks: active_tasks} = GenServer.call(agent_info.pid, :get_status, 1000)
        max(0, 20 - active_tasks * 5)
      rescue
        _ -> 0
      end

    total_score = base_score + capability_score + type_score + load_score
    {agent_info, total_score}
  end
end
