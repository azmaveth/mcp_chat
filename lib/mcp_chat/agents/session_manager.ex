defmodule MCPChat.Agents.SessionManager do
  @moduledoc """
  Enhanced Session Manager that provides subagent spawning capabilities.

  This module manages both main session agents and coordinates the spawning
  of specialized subagents for different types of work.
  """

  use GenServer
  require Logger

  @registry_name MCPChat.SessionRegistry

  # Public API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Start a new session with the given ID and options"
  def start_session(session_id, opts \\ []) do
    GenServer.call(__MODULE__, {:start_session, session_id, opts})
  end

  @doc "Stop an existing session"
  def stop_session(session_id) do
    GenServer.call(__MODULE__, {:stop_session, session_id})
  end

  @doc "Get the PID of a session"
  def get_session_pid(session_id) do
    case Registry.lookup(@registry_name, session_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc "List all active session IDs"
  def list_active_sessions do
    Registry.select(@registry_name, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])
  end

  @doc "Get session count and basic stats"
  def get_session_stats do
    GenServer.call(__MODULE__, :get_session_stats)
  end

  @doc "Spawn a subagent for a specific session and task type"
  def spawn_subagent(session_id, agent_type, task_spec) do
    GenServer.call(__MODULE__, {:spawn_subagent, session_id, agent_type, task_spec})
  end

  @doc "Get information about active subagents"
  def get_subagent_info(subagent_id) do
    GenServer.call(__MODULE__, {:get_subagent_info, subagent_id})
  end

  @doc "List all subagents for a session"
  def list_session_subagents(session_id) do
    GenServer.call(__MODULE__, {:list_session_subagents, session_id})
  end

  # Via tuple for session addressing
  def via_tuple(session_id) do
    {:via, Registry, {@registry_name, session_id}}
  end

  # GenServer implementation

  def init(_opts) do
    Logger.info("Starting Session Manager")

    {:ok,
     %{
       active_sessions: %{},
       subagent_tracking: %{},
       session_stats: %{
         total_started: 0,
         total_stopped: 0,
         subagents_spawned: 0
       }
     }}
  end

  def handle_call({:start_session, session_id, opts}, _from, state) do
    case get_session_pid(session_id) do
      {:ok, _existing_pid} ->
        {:reply, {:error, :session_already_exists}, state}

      {:error, :not_found} ->
        case MCPChat.Session.start_link([session_id: session_id] ++ opts) do
          {:ok, pid} ->
            # Register the session
            Registry.register(@registry_name, session_id, %{
              started_at: DateTime.utc_now(),
              opts: opts
            })

            new_state = %{
              state
              | active_sessions: Map.put(state.active_sessions, session_id, pid),
                session_stats: %{state.session_stats | total_started: state.session_stats.total_started + 1}
            }

            Logger.info("Started session", session_id: session_id, pid: inspect(pid))
            {:reply, {:ok, pid}, new_state}

          error ->
            Logger.error("Failed to start session", session_id: session_id, error: inspect(error))
            {:reply, error, state}
        end
    end
  end

  def handle_call({:stop_session, session_id}, _from, state) do
    case Map.get(state.active_sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      pid ->
        # Stop all subagents for this session first
        subagents_to_stop =
          state.subagent_tracking
          |> Enum.filter(fn {_id, info} -> info.session_id == session_id end)
          |> Enum.map(fn {id, info} -> {id, info.agent_pid} end)

        Enum.each(subagents_to_stop, fn {_id, agent_pid} ->
          if Process.alive?(agent_pid) do
            DynamicSupervisor.terminate_child(get_supervisor_for_agent(agent_pid), agent_pid)
          end
        end)

        # Remove subagent tracking
        new_subagent_tracking =
          state.subagent_tracking
          |> Enum.reject(fn {_id, info} -> info.session_id == session_id end)
          |> Map.new()

        # Stop the session
        case GenServer.stop(pid, :normal) do
          :ok ->
            new_state = %{
              state
              | active_sessions: Map.delete(state.active_sessions, session_id),
                subagent_tracking: new_subagent_tracking,
                session_stats: %{state.session_stats | total_stopped: state.session_stats.total_stopped + 1}
            }

            Logger.info("Stopped session", session_id: session_id, subagents_stopped: length(subagents_to_stop))
            {:reply, :ok, new_state}

          error ->
            {:reply, error, state}
        end
    end
  end

  def handle_call(:get_session_stats, _from, state) do
    current_active = map_size(state.active_sessions)
    active_subagents = map_size(state.subagent_tracking)

    stats =
      Map.merge(state.session_stats, %{
        currently_active: current_active,
        active_subagents: active_subagents
      })

    {:reply, stats, state}
  end

  def handle_call({:spawn_subagent, session_id, agent_type, task_spec}, _from, state) do
    # Verify session exists
    case Map.get(state.active_sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      _session_pid ->
        case route_subagent_request(agent_type, session_id, task_spec) do
          {:ok, agent_pid} ->
            # Track the subagent relationship
            subagent_id = generate_subagent_id()

            tracking_info = %{
              session_id: session_id,
              agent_type: agent_type,
              agent_pid: agent_pid,
              task_spec: task_spec,
              started_at: DateTime.utc_now()
            }

            # Monitor the subagent
            Process.monitor(agent_pid)

            new_state = %{
              state
              | subagent_tracking: Map.put(state.subagent_tracking, subagent_id, tracking_info),
                session_stats: %{state.session_stats | subagents_spawned: state.session_stats.subagents_spawned + 1}
            }

            Logger.info("Spawned subagent",
              subagent_id: subagent_id,
              session_id: session_id,
              agent_type: agent_type,
              task: inspect(task_spec)
            )

            {:reply, {:ok, subagent_id, agent_pid}, new_state}

          error ->
            Logger.error("Failed to spawn subagent",
              session_id: session_id,
              agent_type: agent_type,
              error: inspect(error)
            )

            {:reply, error, state}
        end
    end
  end

  def handle_call({:get_subagent_info, subagent_id}, _from, state) do
    case Map.get(state.subagent_tracking, subagent_id) do
      nil -> {:reply, {:error, :subagent_not_found}, state}
      info -> {:reply, {:ok, info}, state}
    end
  end

  def handle_call({:list_session_subagents, session_id}, _from, state) do
    subagents =
      state.subagent_tracking
      |> Enum.filter(fn {_id, info} -> info.session_id == session_id end)
      |> Enum.map(fn {id, info} ->
        {id,
         %{
           agent_type: info.agent_type,
           agent_pid: info.agent_pid,
           started_at: info.started_at,
           task_spec: info.task_spec,
           alive: Process.alive?(info.agent_pid)
         }}
      end)

    {:reply, subagents, state}
  end

  # Handle subagent process termination
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Find and remove the terminated subagent
    case find_subagent_by_pid(state.subagent_tracking, pid) do
      {subagent_id, info} ->
        new_tracking = Map.delete(state.subagent_tracking, subagent_id)

        Logger.info("Subagent terminated",
          subagent_id: subagent_id,
          session_id: info.session_id,
          agent_type: info.agent_type,
          reason: reason
        )

        {:noreply, %{state | subagent_tracking: new_tracking}}

      nil ->
        # Not a tracked subagent, ignore
        {:noreply, state}
    end
  end

  # Private helper functions

  defp route_subagent_request(:tool_executor, session_id, task_spec) do
    MCPChat.Agents.AgentPool.request_tool_execution(session_id, task_spec)
  end

  defp route_subagent_request(:export, session_id, task_spec) do
    MCPChat.Agents.ExportAgent.start_export(session_id, task_spec)
  end

  defp route_subagent_request(:maintenance, _session_id, task_spec) do
    # Maintenance tasks are global, not session-specific
    MCPChat.Agents.MaintenanceAgent.schedule_task(task_spec)
  end

  defp route_subagent_request(agent_type, _session_id, _task_spec) do
    {:error, {:unknown_agent_type, agent_type}}
  end

  defp generate_subagent_id do
    timestamp = System.system_time(:microsecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "subagent_#{timestamp}_#{random}"
  end

  defp find_subagent_by_pid(tracking, pid) do
    Enum.find(tracking, fn {_id, info} -> info.agent_pid == pid end)
  end

  defp get_supervisor_for_agent(agent_pid) do
    # This is a simplified version - in practice you might need more sophisticated
    # logic to determine which supervisor manages which agent
    cond do
      agent_belongs_to_supervisor?(agent_pid, MCPChat.ToolExecutorSupervisor) ->
        MCPChat.ToolExecutorSupervisor

      agent_belongs_to_supervisor?(agent_pid, MCPChat.ExportSupervisor) ->
        MCPChat.ExportSupervisor

      true ->
        # Default fallback
        MCPChat.ToolExecutorSupervisor
    end
  end

  defp agent_belongs_to_supervisor?(agent_pid, supervisor) do
    # Check if the agent is a child of the given supervisor
    case DynamicSupervisor.which_children(supervisor) do
      children when is_list(children) ->
        Enum.any?(children, fn {_, pid, _, _} -> pid == agent_pid end)

      _ ->
        false
    end
  rescue
    _ -> false
  end
end
