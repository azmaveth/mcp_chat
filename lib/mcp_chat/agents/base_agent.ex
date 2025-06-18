defmodule MCPChat.Agents.BaseAgent do
  @moduledoc """
  Base behavior and common functionality for all specialized agents.

  This module defines the core agent contract and provides shared functionality:
  - Agent lifecycle management (spawn, run, pause, stop)
  - Inter-agent messaging and coordination
  - Capability system for dynamic agent discovery
  - Event publishing for monitoring and coordination
  - State management and persistence
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      use GenServer, restart: :temporary
      require Logger

      alias MCPChat.Events.AgentEvents
      alias MCPChat.Agents.{AgentRegistry, AgentCoordinator}

      @agent_type Keyword.get(opts, :agent_type, :generic)
      @default_capabilities Keyword.get(opts, :capabilities, [])
      @default_timeout Keyword.get(opts, :timeout, 30_000)

      # Behaviour callbacks that must be implemented
      @callback get_capabilities() :: [atom()]
      @callback can_handle_task?(map()) :: boolean()
      @callback execute_task(map(), map()) :: {:ok, term()} | {:error, term()}
      @callback get_agent_info() :: map()

      @doc """
      Start the agent with initial context.
      """
      def start_link({agent_id, context}) do
        GenServer.start_link(__MODULE__, {agent_id, context}, name: via_registry(agent_id))
      end

      @doc """
      Get the agent type for this agent.
      """
      def agent_type, do: @agent_type

      @doc """
      Get default capabilities for this agent.
      """
      def default_capabilities, do: @default_capabilities

      # GenServer implementation with agent lifecycle

      def init({agent_id, context}) do
        Logger.info("Starting #{@agent_type} agent", agent_id: agent_id)

        # Register with agent registry
        AgentRegistry.register_agent(agent_id, @agent_type, self())

        # Initialize agent-specific state
        case init_agent_state(agent_id, context) do
          {:ok, agent_state} ->
            state = %{
              agent_id: agent_id,
              agent_type: @agent_type,
              status: :initializing,
              started_at: DateTime.utc_now(),
              context: context,
              agent_state: agent_state,
              capabilities: get_capabilities(),
              tasks: %{},
              task_counter: 0,
              subscriptions: []
            }

            # Complete initialization
            send(self(), :complete_initialization)

            {:ok, state}

          {:error, reason} ->
            Logger.error("Failed to initialize #{@agent_type} agent",
              agent_id: agent_id,
              reason: inspect(reason)
            )

            {:stop, {:init_failed, reason}}
        end
      end

      def handle_info(:complete_initialization, state) do
        # Mark as ready and publish event
        new_state = %{state | status: :ready}

        publish_event(new_state, %AgentEvents.AgentStarted{
          agent_id: state.agent_id,
          agent_type: @agent_type,
          capabilities: state.capabilities,
          started_at: state.started_at,
          pid: self()
        })

        Logger.info("#{@agent_type} agent ready", agent_id: state.agent_id)

        {:noreply, new_state}
      end

      # Task execution handling

      def handle_call({:execute_task, task_spec}, from, state) do
        if can_handle_task?(task_spec) do
          task_id = generate_task_id(state)

          Logger.info("Executing task",
            agent_id: state.agent_id,
            agent_type: @agent_type,
            task_id: task_id,
            task_type: task_spec[:type]
          )

          # Update state with new task
          task_info = %{
            id: task_id,
            spec: task_spec,
            from: from,
            started_at: DateTime.utc_now(),
            status: :running
          }

          new_state = %{
            state
            | tasks: Map.put(state.tasks, task_id, task_info),
              task_counter: state.task_counter + 1,
              status: :busy
          }

          # Execute task asynchronously
          send(self(), {:do_execute_task, task_id})

          {:noreply, new_state}
        else
          {:reply, {:error, :cannot_handle_task}, state}
        end
      end

      def handle_call(:get_status, _from, state) do
        status = %{
          agent_id: state.agent_id,
          agent_type: @agent_type,
          status: state.status,
          started_at: state.started_at,
          uptime_ms: DateTime.diff(DateTime.utc_now(), state.started_at, :millisecond),
          capabilities: state.capabilities,
          active_tasks: map_size(state.tasks),
          task_history: state.task_counter
        }

        {:reply, status, state}
      end

      def handle_call({:send_message, target_agent_id, message}, _from, state) do
        case AgentRegistry.get_agent_pid(target_agent_id) do
          {:ok, target_pid} ->
            result = GenServer.call(target_pid, {:receive_message, state.agent_id, message})
            {:reply, result, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      end

      def handle_call({:receive_message, from_agent_id, message}, _from, state) do
        Logger.debug("Received message",
          agent_id: state.agent_id,
          from: from_agent_id,
          message_type: message[:type]
        )

        # Handle the message
        case handle_agent_message(from_agent_id, message, state) do
          {:ok, response, new_state} ->
            {:reply, {:ok, response}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      end

      # Async task execution

      def handle_info({:do_execute_task, task_id}, state) do
        case Map.get(state.tasks, task_id) do
          nil ->
            Logger.warning("Task not found", task_id: task_id)
            {:noreply, state}

          task_info ->
            # Execute the task
            try do
              result = execute_task(task_info.spec, state)

              # Complete the task
              GenServer.reply(task_info.from, result)

              # Update state
              completed_task = %{task_info | status: :completed, completed_at: DateTime.utc_now()}
              new_tasks = Map.put(state.tasks, task_id, completed_task)

              # Update agent status
              new_status = if map_size(new_tasks) == 1, do: :ready, else: :busy

              new_state = %{state | tasks: new_tasks, status: new_status}

              # Publish task completion event
              publish_event(new_state, %AgentEvents.TaskCompleted{
                agent_id: state.agent_id,
                task_id: task_id,
                result: result,
                duration_ms: DateTime.diff(DateTime.utc_now(), task_info.started_at, :millisecond)
              })

              {:noreply, new_state}
            rescue
              error ->
                Logger.error("Task execution failed",
                  agent_id: state.agent_id,
                  task_id: task_id,
                  error: inspect(error)
                )

                # Reply with error
                GenServer.reply(task_info.from, {:error, {:task_failed, error}})

                # Update task as failed
                failed_task = %{task_info | status: :failed, error: error, completed_at: DateTime.utc_now()}
                new_tasks = Map.put(state.tasks, task_id, failed_task)
                new_status = if map_size(new_tasks) == 1, do: :ready, else: :busy

                new_state = %{state | tasks: new_tasks, status: new_status}

                # Publish task failure event
                publish_event(new_state, %AgentEvents.TaskFailed{
                  agent_id: state.agent_id,
                  task_id: task_id,
                  error: inspect(error),
                  duration_ms: DateTime.diff(DateTime.utc_now(), task_info.started_at, :millisecond)
                })

                {:noreply, new_state}
            end
        end
      end

      # Agent coordination messages

      def handle_info({:agent_coordination, message}, state) do
        case handle_coordination_message(message, state) do
          {:ok, new_state} -> {:noreply, new_state}
          :ignore -> {:noreply, state}
        end
      end

      # Graceful shutdown

      def terminate(reason, state) do
        Logger.info("Shutting down #{@agent_type} agent",
          agent_id: state.agent_id,
          reason: inspect(reason)
        )

        # Unregister from agent registry
        AgentRegistry.unregister_agent(state.agent_id)

        # Publish shutdown event
        publish_event(state, %AgentEvents.AgentStopped{
          agent_id: state.agent_id,
          agent_type: @agent_type,
          reason: inspect(reason),
          uptime_ms: DateTime.diff(DateTime.utc_now(), state.started_at, :millisecond)
        })

        # Clean up agent-specific resources
        cleanup_agent_state(state.agent_state, state)

        :ok
      end

      # Helper functions

      defp via_registry(agent_id) do
        {:via, Registry, {AgentRegistry, agent_id}}
      end

      defp generate_task_id(state) do
        "#{state.agent_id}_task_#{state.task_counter + 1}"
      end

      defp publish_event(state, event) do
        Phoenix.PubSub.broadcast(MCPChat.PubSub, "agents", event)
        Phoenix.PubSub.broadcast(MCPChat.PubSub, "agent:#{state.agent_id}", event)
      end

      # Default implementations (can be overridden)

      def init_agent_state(_agent_id, _context) do
        {:ok, %{}}
      end

      def handle_agent_message(_from_agent_id, message, state) do
        Logger.debug("Received unhandled message", message: inspect(message))
        {:ok, %{status: "received"}, state}
      end

      def handle_coordination_message(_message, _state) do
        :ignore
      end

      def cleanup_agent_state(_agent_state, _state) do
        :ok
      end

      defoverridable init_agent_state: 2,
                     handle_agent_message: 3,
                     handle_coordination_message: 2,
                     cleanup_agent_state: 2
    end
  end

  @doc """
  Defines the agent behavior contract.
  """
  defmacro defagent(name, do: block) do
    quote do
      defmodule unquote(name) do
        use MCPChat.Agents.BaseAgent

        unquote(block)
      end
    end
  end
end
