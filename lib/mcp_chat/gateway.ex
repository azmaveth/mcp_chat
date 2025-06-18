defmodule MCPChat.Gateway do
  @moduledoc """
  Main API gateway for MCP Chat operations.

  This module provides a clean, stateless API that abstracts the underlying
  agent architecture. It routes requests to appropriate agents and handles
  the coordination between main session agents and specialized subagents.
  """

  require Logger

  # Session Management API

  @doc "Create a new chat session"
  def create_session(user_id, opts \\ []) do
    session_id = if opts[:session_id], do: opts[:session_id], else: generate_session_id(user_id)

    case MCPChat.Agents.SessionManager.start_session(session_id, [user_id: user_id] ++ opts) do
      {:ok, pid} ->
        Logger.info("Created session", session_id: session_id, user_id: user_id, pid: inspect(pid))

        # Broadcast session created event
        Phoenix.PubSub.broadcast(
          MCPChat.PubSub,
          "system:sessions",
          {:session_created, %{id: session_id, user_id: user_id, created_at: DateTime.utc_now()}}
        )

        {:ok, session_id}

      error ->
        Logger.error("Failed to create session", user_id: user_id, error: inspect(error))
        error
    end
  end

  @doc "Destroy an existing session"
  def destroy_session(session_id) do
    case MCPChat.Agents.SessionManager.stop_session(session_id) do
      :ok ->
        Logger.info("Destroyed session", session_id: session_id)
        :ok

      error ->
        Logger.error("Failed to destroy session", session_id: session_id, error: inspect(error))
        error
    end
  end

  @doc "Get the current state of a session"
  def get_session_state(session_id) do
    case MCPChat.Agents.SessionManager.get_session_pid(session_id) do
      {:ok, pid} ->
        GenServer.call(pid, :get_full_state)

      {:error, :not_found} ->
        {:error, :session_not_found}
    end
  end

  @doc "Get a session (alias for get_session_state)"
  def get_session(session_id) do
    get_session_state(session_id)
  end

  @doc "List all active sessions"
  def list_active_sessions do
    MCPChat.Agents.SessionManager.list_active_sessions()
  end

  @doc "Get session statistics"
  def get_session_stats do
    MCPChat.Agents.SessionManager.get_session_stats()
  end

  # Message Handling API

  @doc "Send a user message to a session"
  def send_message(session_id, content) do
    case MCPChat.Agents.SessionManager.get_session_pid(session_id) do
      {:ok, pid} ->
        GenServer.cast(pid, {:send_message, content})

        # Broadcast message event for real-time updates
        Phoenix.PubSub.broadcast(MCPChat.PubSub, "session:#{session_id}", %{
          type: :message_added,
          message: %{
            id: generate_message_id(),
            role: :user,
            content: content,
            timestamp: DateTime.utc_now()
          }
        })

        :ok

      {:error, :not_found} ->
        {:error, :session_not_found}
    end
  end

  @doc "Get message history for a session"
  def get_message_history(session_id, opts \\ []) do
    case MCPChat.Agents.SessionManager.get_session_pid(session_id) do
      {:ok, pid} ->
        GenServer.call(pid, {:get_messages, opts})

      {:error, :not_found} ->
        {:error, :session_not_found}
    end
  end

  # Tool Execution API

  @doc "Execute an MCP tool, routing to appropriate agent based on complexity"
  def execute_tool(session_id, tool_name, args, opts \\ []) do
    case classify_tool_execution(tool_name, args, opts) do
      :fast ->
        # Execute immediately in session context
        execute_fast_tool(session_id, tool_name, args, opts)

      :heavy ->
        # Spawn subagent for heavy work
        execute_heavy_tool(session_id, tool_name, args, opts)
    end
  end

  @doc "Get the status of a tool execution"
  def get_tool_execution_status(session_id, execution_id) do
    case MCPChat.Agents.SessionManager.get_subagent_info(execution_id) do
      {:ok, info} when info.session_id == session_id ->
        if Process.alive?(info.agent_pid) do
          MCPChat.Agents.ToolExecutorAgent.get_progress(info.agent_pid)
        else
          {:error, :execution_completed}
        end

      {:ok, _info} ->
        {:error, :access_denied}

      {:error, :subagent_not_found} ->
        {:error, :execution_not_found}
    end
  end

  @doc "Cancel a running tool execution"
  def cancel_tool_execution(session_id, execution_id) do
    case MCPChat.Agents.SessionManager.get_subagent_info(execution_id) do
      {:ok, info} when info.session_id == session_id and info.agent_type == :tool_executor ->
        if Process.alive?(info.agent_pid) do
          MCPChat.Agents.ToolExecutorAgent.cancel_execution(info.agent_pid)
        else
          {:error, :execution_already_completed}
        end

      {:ok, _info} ->
        {:error, :access_denied}

      {:error, :subagent_not_found} ->
        {:error, :execution_not_found}
    end
  end

  # Command Execution API

  @doc "Execute a slash command"
  def execute_command(session_id, command_string) do
    case MCPChat.Agents.SessionManager.get_session_pid(session_id) do
      {:ok, pid} ->
        GenServer.call(pid, {:execute_command, command_string})

      {:error, :not_found} ->
        {:error, :session_not_found}
    end
  end

  @doc "Resolve a permission request"
  def resolve_permission(session_id, request_id, decision) do
    case MCPChat.Agents.SessionManager.get_session_pid(session_id) do
      {:ok, pid} ->
        GenServer.cast(pid, {:resolve_permission, request_id, decision})
        :ok

      {:error, :not_found} ->
        {:error, :session_not_found}
    end
  end

  # Export API

  @doc "Request export of session data"
  def request_export(session_id, format, options \\ %{}) do
    export_spec = %{
      format: format,
      options: options,
      include_metadata: Map.get(options, :include_metadata, true),
      include_attachments: Map.get(options, :include_attachments, false)
    }

    case MCPChat.Agents.SessionManager.spawn_subagent(session_id, :export, export_spec) do
      {:ok, subagent_id, agent_pid} ->
        {:ok,
         %{
           export_id: subagent_id,
           agent_pid: agent_pid,
           estimated_duration: estimate_export_duration(format, options)
         }}

      error ->
        Logger.error("Failed to start export",
          session_id: session_id,
          format: format,
          error: inspect(error)
        )

        error
    end
  end

  @doc "Get export status"
  def get_export_status(session_id, export_id) do
    case MCPChat.Agents.SessionManager.get_subagent_info(export_id) do
      {:ok, info} when info.session_id == session_id and info.agent_type == :export ->
        %{
          export_id: export_id,
          status: if(Process.alive?(info.agent_pid), do: :running, else: :completed),
          started_at: info.started_at,
          agent_pid: info.agent_pid
        }

      {:ok, _info} ->
        {:error, :access_denied}

      {:error, :subagent_not_found} ->
        {:error, :export_not_found}
    end
  end

  # MCP Server Management API

  @doc "Connect to an MCP server"
  def connect_mcp_server(session_id, server_config) do
    case MCPChat.Agents.SessionManager.get_session_pid(session_id) do
      {:ok, pid} ->
        GenServer.call(pid, {:connect_mcp_server, server_config})

      {:error, :not_found} ->
        {:error, :session_not_found}
    end
  end

  @doc "List available MCP tools for a server"
  def list_mcp_tools(session_id, server_name) do
    case MCPChat.Agents.SessionManager.get_session_pid(session_id) do
      {:ok, pid} ->
        GenServer.call(pid, {:list_mcp_tools, server_name})

      {:error, :not_found} ->
        {:error, :session_not_found}
    end
  end

  # System Management API

  @doc "Get agent pool status"
  def get_agent_pool_status do
    MCPChat.Agents.AgentPool.get_pool_status()
  end

  @doc "Get maintenance statistics"
  def get_maintenance_stats do
    MCPChat.Agents.MaintenanceAgent.get_maintenance_stats()
  end

  @doc "Force maintenance cleanup (admin function)"
  def force_maintenance_cleanup(deep_clean \\ false) do
    MCPChat.Agents.MaintenanceAgent.force_cleanup(deep_clean)
  end

  @doc "List subagents for a session"
  def list_session_subagents(session_id) do
    MCPChat.Agents.SessionManager.list_session_subagents(session_id)
  end

  @doc "Get system health information"
  def get_system_health do
    agent_pool_status = get_agent_pool_status()
    session_stats = get_session_stats()
    maintenance_stats = get_maintenance_stats()

    %{
      timestamp: DateTime.utc_now(),
      sessions: session_stats,
      agent_pool: agent_pool_status,
      maintenance: maintenance_stats,
      memory_usage: :erlang.memory(),
      process_count: :erlang.system_info(:process_count)
    }
  end

  # Private helper functions

  defp generate_session_id(user_id) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    random = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    "#{user_id}_#{timestamp}_#{random}"
  end

  defp classify_tool_execution(tool_name, args, opts) do
    # Check explicit override first
    case Keyword.get(opts, :execution_type) do
      type when type in [:fast, :heavy] -> type
      _ -> classify_by_heuristics(tool_name, args)
    end
  end

  defp classify_by_heuristics(tool_name, args) do
    cond do
      # Known heavy tools
      tool_name in ["analyze_codebase", "process_large_file", "generate_report", "extract_documentation"] ->
        :heavy

      # Large argument sets suggest complex operations
      is_map(args) and map_size(args) > 10 ->
        :heavy

      # File operations with large files
      is_map(args) and Map.has_key?(args, "file_size") and args["file_size"] > 1_000_000 ->
        :heavy

      # Default to fast execution
      true ->
        :fast
    end
  end

  defp execute_fast_tool(session_id, tool_name, args, opts) do
    case MCPChat.Agents.SessionManager.get_session_pid(session_id) do
      {:ok, pid} ->
        timeout = Keyword.get(opts, :timeout, 30_000)
        GenServer.call(pid, {:execute_tool, tool_name, args}, timeout)

      {:error, :not_found} ->
        {:error, :session_not_found}
    end
  end

  defp execute_heavy_tool(session_id, tool_name, args, opts) do
    task_spec = %{
      tool_name: tool_name,
      args: args,
      # 5 minutes default
      timeout: Keyword.get(opts, :timeout, 300_000),
      priority: Keyword.get(opts, :priority, :normal)
    }

    case MCPChat.Agents.SessionManager.spawn_subagent(session_id, :tool_executor, task_spec) do
      {:ok, subagent_id, agent_pid} ->
        {:ok, :async,
         %{
           execution_id: subagent_id,
           agent_pid: agent_pid,
           estimated_duration: estimate_tool_duration(tool_name, args)
         }}

      error ->
        Logger.error("Failed to spawn tool executor",
          session_id: session_id,
          tool_name: tool_name,
          error: inspect(error)
        )

        error
    end
  end

  defp estimate_tool_duration(tool_name, _args) do
    case tool_name do
      # 2 minutes
      "analyze_codebase" -> 120_000
      # 1 minute
      "process_large_file" -> 60_000
      # 1.5 minutes
      "generate_report" -> 90_000
      # 45 seconds
      "extract_documentation" -> 45_000
      # 30 seconds default
      _ -> 30_000
    end
  end

  defp estimate_export_duration(format, options) do
    base_time =
      case format do
        # 30 seconds
        "pdf" -> 30_000
        # 5 seconds
        "json" -> 5_000
        # 10 seconds
        "markdown" -> 10_000
        # 15 seconds
        "html" -> 15_000
        # 20 seconds default
        _ -> 20_000
      end

    # Adjust based on options
    multiplier =
      cond do
        Map.get(options, :include_attachments, false) -> 2.0
        Map.get(options, :include_metadata, true) -> 1.2
        true -> 1.0
      end

    round(base_time * multiplier)
  end

  defp generate_message_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  # Additional functions needed by web UI

  @doc "List all sessions (stub for web UI)"
  def list_sessions do
    list_active_sessions()
  end

  @doc "Archive a session (stub for web UI)"
  def archive_session(session_id) do
    # For now, just mark it as archived in memory
    Logger.info("Archiving session", session_id: session_id)
    {:ok, :archived}
  end

  @doc "Restore an archived session (stub for web UI)"
  def restore_session(session_id) do
    # For now, just mark it as restored
    Logger.info("Restoring session", session_id: session_id)
    {:ok, :restored}
  end
end
