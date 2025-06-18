defmodule MCPChat.CLI.Commands.AgentCommands do
  @moduledoc """
  CLI commands for multi-agent system management.

  This module provides commands for:
  - Agent spawning and management
  - Task delegation to agents
  - Agent status monitoring
  - Workflow execution
  - Agent collaboration
  """

  alias MCPChat.Agents.{AgentRegistry, AgentCoordinator, BaseAgent}
  alias MCPChat.Agents.{CoderAgent, ReviewerAgent, DocumenterAgent, TesterAgent, ResearcherAgent}
  alias MCPChat.CLI.Helpers
  alias MCPChat.Session

  @doc """
  Handle agent-related commands.
  """
  def handle_command(["agent" | subcommand], session) do
    case subcommand do
      ["spawn" | args] -> handle_agent_spawn(args, session)
      ["list"] -> handle_agent_list(session)
      ["status" | args] -> handle_agent_status(args, session)
      ["stop" | args] -> handle_agent_stop(args, session)
      ["task" | args] -> handle_agent_task(args, session)
      ["workflow" | args] -> handle_agent_workflow(args, session)
      ["collaborate" | args] -> handle_agent_collaborate(args, session)
      ["capabilities" | args] -> handle_agent_capabilities(args, session)
      ["help"] -> handle_agent_help(session)
      [] -> handle_agent_help(session)
      _ -> {:error, "Unknown agent command. Use '/agent help' for available commands."}
    end
  end

  defp handle_agent_spawn(args, session) do
    case parse_spawn_args(args) do
      {:ok, %{type: agent_type, id: agent_id, context: context}} ->
        case spawn_agent(agent_type, agent_id, context) do
          {:ok, pid} ->
            message = """
            ✅ **Agent Spawned Successfully**

            **Agent ID:** `#{agent_id}`
            **Agent Type:** `#{agent_type}`
            **PID:** `#{inspect(pid)}`
            **Context:** #{format_context(context)}

            The agent is now ready to receive tasks. Use `/agent task #{agent_id} <task_spec>` to delegate tasks.
            """

            {:ok, message, session}

          {:error, reason} ->
            {:error, "Failed to spawn agent: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_agent_list(session) do
    case AgentRegistry.list_all_agents() do
      {:ok, agents} ->
        if Enum.empty?(agents) do
          message = """
          📋 **No Active Agents**

          No agents are currently running. Use `/agent spawn <type> [id] [context]` to create agents.

          **Available Agent Types:**
          - `coder` - Code generation and modification
          - `reviewer` - Code review and quality analysis  
          - `documenter` - Documentation generation
          - `tester` - Test generation and validation
          - `researcher` - Research and information gathering
          """

          {:ok, message, session}
        else
          message = """
          📋 **Active Agents**

          #{format_agent_list(agents)}

          Use `/agent status <agent_id>` for detailed information about a specific agent.
          """

          {:ok, message, session}
        end

      {:error, reason} ->
        {:error, "Failed to list agents: #{inspect(reason)}"}
    end
  end

  defp handle_agent_status(args, session) do
    case args do
      [agent_id] ->
        case AgentRegistry.get_agent_info(agent_id) do
          {:ok, agent_info} ->
            message = """
            📊 **Agent Status: #{agent_id}**

            #{format_agent_status(agent_info)}
            """

            {:ok, message, session}

          {:error, :not_found} ->
            {:error, "Agent '#{agent_id}' not found. Use '/agent list' to see active agents."}

          {:error, reason} ->
            {:error, "Failed to get agent status: #{inspect(reason)}"}
        end

      [] ->
        # Show overall system status
        case AgentRegistry.get_registry_stats() do
          stats ->
            message = """
            🏗️ **Agent System Status**

            #{format_system_status(stats)}
            """

            {:ok, message, session}
        end

      _ ->
        {:error, "Usage: /agent status [agent_id]"}
    end
  end

  defp handle_agent_stop(args, session) do
    case args do
      [agent_id] ->
        case AgentRegistry.get_agent_pid(agent_id) do
          {:ok, pid} ->
            GenServer.stop(pid, :normal)
            AgentRegistry.unregister_agent(agent_id)

            message = """
            🛑 **Agent Stopped**

            Agent `#{agent_id}` has been stopped and removed from the registry.
            """

            {:ok, message, session}

          {:error, :not_found} ->
            {:error, "Agent '#{agent_id}' not found."}

          {:error, reason} ->
            {:error, "Failed to stop agent: #{inspect(reason)}"}
        end

      [] ->
        {:error, "Usage: /agent stop <agent_id>"}

      _ ->
        {:error, "Usage: /agent stop <agent_id>"}
    end
  end

  defp handle_agent_task(args, session) do
    case parse_task_args(args) do
      {:ok, %{task_spec: task_spec}} ->
        case AgentCoordinator.delegate_task(task_spec, retry_on_failure: true) do
          {:ok, result, assigned_agent_id} ->
            message = """
            ✅ **Task Completed Successfully**

            **Task Type:** `#{task_spec[:type]}`
            **Assigned Agent:** `#{assigned_agent_id}`
            **Duration:** #{calculate_task_duration(result)}

            **Result:**
            #{format_task_result(result)}
            """

            {:ok, message, session}

          {:error, reason} ->
            {:error, "Task execution failed: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_agent_workflow(args, session) do
    case parse_workflow_args(args) do
      {:ok, %{action: action, workflow_spec: workflow_spec, context: context}} ->
        case action do
          :execute ->
            case AgentCoordinator.execute_workflow(workflow_spec, context) do
              {:ok, result} ->
                message = """
                🔄 **Workflow Completed**

                **Workflow ID:** `#{result.workflow_id}`
                **Status:** `#{result.status}`
                **Duration:** #{result.duration_ms}ms
                **Steps Completed:** #{map_size(result.results)}

                **Results:**
                #{format_workflow_results(result.results)}
                """

                {:ok, message, session}

              {:error, reason} ->
                {:error, "Workflow execution failed: #{inspect(reason)}"}
            end

          :status ->
            case AgentCoordinator.get_workflows_status() do
              status ->
                message = """
                📊 **Workflow System Status**

                #{format_workflow_status(status)}
                """

                {:ok, message, session}
            end

          :cancel ->
            workflow_id = workflow_spec[:workflow_id]

            case AgentCoordinator.cancel_workflow(workflow_id) do
              :ok ->
                message = "🛑 Workflow `#{workflow_id}` has been cancelled."
                {:ok, message, session}

              {:error, reason} ->
                {:error, "Failed to cancel workflow: #{inspect(reason)}"}
            end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_agent_collaborate(args, session) do
    case parse_collaboration_args(args) do
      {:ok, %{agent_ids: agent_ids, collaboration_spec: spec}} ->
        case AgentCoordinator.create_collaboration(agent_ids, spec) do
          {:ok, collaboration_id} ->
            message = """
            🤝 **Collaboration Started**

            **Collaboration ID:** `#{collaboration_id}`
            **Participating Agents:** #{Enum.join(agent_ids, ", ")}
            **Collaboration Type:** `#{spec[:type] || "general"}`

            Agents have been notified and can now collaborate on the specified task.
            """

            {:ok, message, session}

          {:error, reason} ->
            {:error, "Failed to create collaboration: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_agent_capabilities(args, session) do
    case args do
      [] ->
        # Show all agent types and their capabilities
        message = """
        🛠️ **Agent Capabilities Overview**

        #{format_all_agent_capabilities()}
        """

        {:ok, message, session}

      [agent_type] ->
        case get_agent_capabilities(agent_type) do
          {:ok, capabilities} ->
            message = """
            🛠️ **#{String.capitalize(agent_type)} Agent Capabilities**

            #{format_agent_capabilities(capabilities)}
            """

            {:ok, message, session}

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, "Usage: /agent capabilities [agent_type]"}
    end
  end

  defp handle_agent_help(session) do
    help_text = """
    🤖 **Agent System Commands**

    **Agent Management:**
    • `/agent spawn <type> [id] [context]` - Spawn a new agent
    • `/agent list` - List all active agents
    • `/agent status [agent_id]` - Show agent or system status
    • `/agent stop <agent_id>` - Stop and remove an agent

    **Task Delegation:**
    • `/agent task <task_type> [options]` - Delegate a task to an agent
    • `/agent workflow execute <workflow_spec>` - Execute a multi-agent workflow
    • `/agent workflow status` - Show workflow system status
    • `/agent workflow cancel <workflow_id>` - Cancel a running workflow

    **Collaboration:**
    • `/agent collaborate <agent_ids> <collaboration_spec>` - Create agent collaboration

    **Information:**
    • `/agent capabilities [agent_type]` - Show agent capabilities
    • `/agent help` - Show this help message

    **Available Agent Types:**
    • `coder` - Code generation, refactoring, optimization
    • `reviewer` - Code review, quality analysis, security auditing
    • `documenter` - Documentation generation and maintenance
    • `tester` - Test generation, validation, quality assurance
    • `researcher` - Research, analysis, information gathering

    **Examples:**
    ```
    /agent spawn coder my-coder-1
    /agent task code_generation type:function language:elixir spec:"HTTP client function"
    /agent workflow execute steps:[{type:code_generation},{type:code_review}]
    /agent collaborate coder-1,reviewer-1 type:code_review_session
    ```
    """

    {:ok, help_text, session}
  end

  # Helper functions for parsing arguments

  defp parse_spawn_args(args) do
    case args do
      [agent_type] ->
        agent_id = generate_agent_id(agent_type)
        {:ok, %{type: String.to_atom(agent_type), id: agent_id, context: %{}}}

      [agent_type, agent_id] ->
        {:ok, %{type: String.to_atom(agent_type), id: agent_id, context: %{}}}

      [agent_type, agent_id | context_args] ->
        case parse_context(context_args) do
          {:ok, context} ->
            {:ok, %{type: String.to_atom(agent_type), id: agent_id, context: context}}

          {:error, reason} ->
            {:error, reason}
        end

      [] ->
        {:error, "Usage: /agent spawn <type> [id] [context]"}

      _ ->
        {:error, "Usage: /agent spawn <type> [id] [context]"}
    end
  end

  defp parse_task_args(args) do
    case args do
      [task_type | options] ->
        case parse_task_options(options) do
          {:ok, task_options} ->
            task_spec = Map.put(task_options, :type, String.to_atom(task_type))
            {:ok, %{task_spec: task_spec}}

          {:error, reason} ->
            {:error, reason}
        end

      [] ->
        {:error, "Usage: /agent task <task_type> [options]"}
    end
  end

  defp parse_workflow_args(args) do
    case args do
      ["execute" | workflow_spec_args] ->
        case parse_workflow_spec(workflow_spec_args) do
          {:ok, workflow_spec} ->
            {:ok, %{action: :execute, workflow_spec: workflow_spec, context: %{}}}

          {:error, reason} ->
            {:error, reason}
        end

      ["status"] ->
        {:ok, %{action: :status, workflow_spec: nil, context: %{}}}

      ["cancel", workflow_id] ->
        {:ok, %{action: :cancel, workflow_spec: %{workflow_id: workflow_id}, context: %{}}}

      _ ->
        {:error, "Usage: /agent workflow <execute|status|cancel> [args]"}
    end
  end

  defp parse_collaboration_args(args) do
    case args do
      [agent_ids_str | spec_args] ->
        agent_ids = String.split(agent_ids_str, ",") |> Enum.map(&String.trim/1)

        case parse_collaboration_spec(spec_args) do
          {:ok, spec} ->
            {:ok, %{agent_ids: agent_ids, collaboration_spec: spec}}

          {:error, reason} ->
            {:error, reason}
        end

      [] ->
        {:error, "Usage: /agent collaborate <agent_ids> <collaboration_spec>"}
    end
  end

  # Helper functions for spawning agents

  defp spawn_agent(agent_type, agent_id, context) do
    agent_module =
      case agent_type do
        :coder -> CoderAgent
        :reviewer -> ReviewerAgent
        :documenter -> DocumenterAgent
        :tester -> TesterAgent
        :researcher -> ResearcherAgent
        _ -> {:error, "Unknown agent type: #{agent_type}"}
      end

    case agent_module do
      {:error, reason} ->
        {:error, reason}

      module ->
        case DynamicSupervisor.start_child(
               MCPChat.AgentSupervisor,
               {module, {agent_id, context}}
             ) do
          {:ok, pid} ->
            {:ok, pid}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # Helper functions for formatting output

  defp format_context(context) when map_size(context) == 0, do: "*(empty)*"
  defp format_context(context), do: "#{inspect(context)}"

  defp format_agent_list(agents) do
    agents
    |> Enum.map(fn agent ->
      status_emoji =
        case agent.status do
          :alive -> "🟢"
          :dead -> "🔴"
          _ -> "🟡"
        end

      "#{status_emoji} **#{agent.agent_id}** (`#{agent.agent_type}`) - #{format_capabilities_brief(agent.capabilities)}"
    end)
    |> Enum.join("\n")
  end

  defp format_agent_status(agent_info) do
    """
    **Agent ID:** `#{agent_info.agent_id}`
    **Type:** `#{agent_info.agent_type}`
    **Status:** `#{agent_info.status}`
    **Uptime:** #{agent_info.uptime_ms}ms
    **Active Tasks:** #{agent_info.active_tasks}
    **Total Tasks Completed:** #{agent_info.task_history}

    **Capabilities:**
    #{format_capabilities_list(agent_info.capabilities)}
    """
  end

  defp format_system_status(stats) do
    """
    **Active Agents:** #{stats.alive_agents}
    **Total Registered:** #{stats.total_registered}
    **Registrations:** #{stats.registrations}
    **Unregistrations:** #{stats.unregistrations}
    **Health Checks:** #{stats.health_checks}
    **Dead Agents Cleaned:** #{stats.dead_agents_cleaned}
    """
  end

  defp format_task_result(result) do
    case result do
      {:ok, data} when is_map(data) ->
        data
        |> Enum.map(fn {k, v} -> "**#{k}:** #{inspect(v)}" end)
        |> Enum.join("\n")

      {:ok, data} ->
        "#{inspect(data)}"

      other ->
        "#{inspect(other)}"
    end
  end

  defp format_workflow_results(results) do
    results
    |> Enum.map(fn {step_index, result} ->
      "**Step #{step_index}:** #{format_task_result(result)}"
    end)
    |> Enum.join("\n")
  end

  defp format_workflow_status(status) do
    """
    **Active Workflows:** #{status.active_workflows}
    **Active Collaborations:** #{status.active_collaborations}
    **Total Workflows:** #{status.total_workflows}
    **Total Collaborations:** #{status.total_collaborations}

    #{if not Enum.empty?(status.workflows) do
      "**Current Workflows:**\n" <> (status.workflows |> Enum.map(fn w -> "• `#{w.id}` - #{w.status} (#{Float.round(w.progress, 1)}%)" end) |> Enum.join("\n"))
    else
      "No active workflows"
    end}
    """
  end

  defp format_all_agent_capabilities do
    [
      {"coder", CoderAgent.get_capabilities()},
      {"reviewer", ReviewerAgent.get_capabilities()},
      {"documenter", DocumenterAgent.get_capabilities()},
      {"tester", TesterAgent.get_capabilities()},
      {"researcher", ResearcherAgent.get_capabilities()}
    ]
    |> Enum.map(fn {type, caps} ->
      "**#{String.capitalize(type)} Agent:**\n#{format_capabilities_list(caps)}"
    end)
    |> Enum.join("\n\n")
  end

  defp format_capabilities_brief(capabilities) do
    capabilities
    |> Enum.take(3)
    |> Enum.map(&to_string/1)
    |> Enum.join(", ")
    |> then(fn brief ->
      if length(capabilities) > 3 do
        brief <> ", ..."
      else
        brief
      end
    end)
  end

  defp format_capabilities_list(capabilities) do
    capabilities
    |> Enum.map(fn cap -> "• `#{cap}`" end)
    |> Enum.join("\n")
  end

  defp format_agent_capabilities(capabilities) do
    format_capabilities_list(capabilities)
  end

  # Utility functions

  defp generate_agent_id(agent_type) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{agent_type}_#{timestamp}_#{random}"
  end

  defp parse_context(context_args) do
    # Parse key:value pairs from context arguments
    try do
      context =
        context_args
        |> Enum.reduce(%{}, fn arg, acc ->
          case String.split(arg, ":", parts: 2) do
            [key, value] -> Map.put(acc, String.to_atom(key), value)
            [key] -> Map.put(acc, String.to_atom(key), true)
          end
        end)

      {:ok, context}
    rescue
      _ -> {:error, "Invalid context format. Use key:value pairs."}
    end
  end

  defp parse_task_options(options) do
    try do
      task_options =
        options
        |> Enum.reduce(%{}, fn opt, acc ->
          case String.split(opt, ":", parts: 2) do
            [key, value] ->
              # Try to parse common value types
              parsed_value =
                case value do
                  "true" ->
                    true

                  "false" ->
                    false

                  val ->
                    if String.match?(val, ~r/^\d+$/), do: String.to_integer(val), else: val
                end

              Map.put(acc, String.to_atom(key), parsed_value)

            [key] ->
              Map.put(acc, String.to_atom(key), true)
          end
        end)

      {:ok, task_options}
    rescue
      _ -> {:error, "Invalid task options format. Use key:value pairs."}
    end
  end

  defp parse_workflow_spec(spec_args) do
    # Simple workflow spec parsing - in a real implementation this would be more sophisticated
    try do
      workflow_spec = %{
        steps: [
          %{type: :code_generation, language: "elixir"},
          %{type: :code_review, review_type: :quality}
        ]
      }

      {:ok, workflow_spec}
    rescue
      _ -> {:error, "Invalid workflow specification."}
    end
  end

  defp parse_collaboration_spec(spec_args) do
    case parse_task_options(spec_args) do
      {:ok, options} -> {:ok, options}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_agent_capabilities(agent_type) do
    case String.to_atom(agent_type) do
      :coder -> {:ok, CoderAgent.get_capabilities()}
      :reviewer -> {:ok, ReviewerAgent.get_capabilities()}
      :documenter -> {:ok, DocumenterAgent.get_capabilities()}
      :tester -> {:ok, TesterAgent.get_capabilities()}
      :researcher -> {:ok, ResearcherAgent.get_capabilities()}
      _ -> {:error, "Unknown agent type: #{agent_type}"}
    end
  end

  defp calculate_task_duration(result) do
    # Extract duration from result metadata if available
    case result do
      {:ok, %{metadata: %{duration_ms: duration}}} -> "#{duration}ms"
      {:ok, %{metadata: %{generated_at: timestamp}}} -> "completed at #{timestamp}"
      _ -> "unknown"
    end
  end
end
