# MCP Chat Agent Architecture with Subagents
## Pure OTP Implementation with Custom Worker Agents

### Executive Summary

This document outlines the implementation of a pure OTP agent architecture for MCP Chat that provides the ability to spawn specialized subagents for different types of work while maintaining the session-based core design.

**Key Features:**
- 🎯 **Main Agent**: Session GenServers for interactive chat
- 🤖 **Subagents**: Specialized worker GenServers for specific tasks
- 🔄 **Agent Pool**: Resource management for concurrent operations
- 📊 **Agent Monitoring**: Built-in observability and health checks
- 🔧 **Pure OTP**: No external dependencies, leverages supervision trees

---

## 1. Agent Architecture Overview

### 1.1 Agent Hierarchy

```
MCPChat.Application
├── Phoenix.PubSub (Event Broadcasting)
├── MCPChat.SessionManager (Main Agent Controller)
│   ├── Registry (Session Discovery)
│   └── DynamicSupervisor (Session Lifecycle)
│       └── MCPChat.Session (Main Agents)
│
├── MCPChat.AgentSupervisor (Subagent Controller)
│   ├── MCPChat.MaintenanceAgent (Scheduled Tasks)
│   ├── MCPChat.AgentPool (Resource Management)
│   ├── MCPChat.ToolExecutorSupervisor (Heavy Work)
│   │   └── MCPChat.ToolExecutorAgent (Dynamic Workers)
│   └── MCPChat.ExportSupervisor (Data Export)
│       └── MCPChat.ExportAgent (Dynamic Workers)
│
└── MCPChat.AgentMonitor (Observability)
```

### 1.2 Agent Types and Responsibilities

| Agent Type | Purpose | Lifecycle | Example Use Cases |
|------------|---------|-----------|-------------------|
| **Main Agent** | Interactive chat session | Long-lived | User conversations, real-time LLM |
| **Maintenance Agent** | System upkeep | Singleton | Session cleanup, log rotation |
| **Tool Executor Agent** | Heavy MCP tools | Task-specific | Code analysis, file processing |
| **Export Agent** | Data export | Task-specific | Chat history export, reports |
| **Monitor Agent** | System observability | Singleton | Health checks, metrics |

---

## 2. Core Agent Implementation

### 2.1 Enhanced Session Manager

```elixir
defmodule MCPChat.SessionManager do
  use GenServer
  
  @registry_name MCPChat.SessionRegistry
  
  # Public API
  def start_session(session_id, opts \\ []) do
    GenServer.call(__MODULE__, {:start_session, session_id, opts})
  end
  
  def stop_session(session_id) do
    GenServer.call(__MODULE__, {:stop_session, session_id})
  end
  
  def get_session_pid(session_id) do
    case Registry.lookup(@registry_name, session_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end
  
  def list_active_sessions do
    Registry.select(@registry_name, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])
  end
  
  def spawn_subagent(session_id, agent_type, task_spec) do
    GenServer.call(__MODULE__, {:spawn_subagent, session_id, agent_type, task_spec})
  end
  
  # GenServer implementation
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    {:ok, %{
      active_sessions: %{},
      subagent_tracking: %{}
    }}
  end
  
  def handle_call({:start_session, session_id, opts}, _from, state) do
    case DynamicSupervisor.start_child(
           MCPChat.SessionSupervisor,
           {MCPChat.Session, [session_id: session_id] ++ opts}
         ) do
      {:ok, pid} ->
        # Register the session
        Registry.register(@registry_name, session_id, %{
          started_at: DateTime.utc_now(),
          opts: opts
        })
        
        new_state = %{state | 
          active_sessions: Map.put(state.active_sessions, session_id, pid)
        }
        
        {:reply, {:ok, pid}, new_state}
        
      error ->
        {:reply, error, state}
    end
  end
  
  def handle_call({:spawn_subagent, session_id, agent_type, task_spec}, _from, state) do
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
        
        new_state = %{state |
          subagent_tracking: Map.put(state.subagent_tracking, subagent_id, tracking_info)
        }
        
        {:reply, {:ok, subagent_id, agent_pid}, new_state}
        
      error ->
        {:reply, error, state}
    end
  end
  
  defp route_subagent_request(:tool_executor, session_id, task_spec) do
    MCPChat.AgentPool.request_tool_execution(session_id, task_spec)
  end
  
  defp route_subagent_request(:export, session_id, task_spec) do
    MCPChat.ExportAgent.start_export(session_id, task_spec)
  end
  
  defp route_subagent_request(agent_type, _session_id, _task_spec) do
    {:error, {:unknown_agent_type, agent_type}}
  end
  
  defp generate_subagent_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  # Via tuple for session addressing
  def via_tuple(session_id) do
    {:via, Registry, {@registry_name, session_id}}
  end
end
```

### 2.2 Agent Pool for Resource Management

```elixir
defmodule MCPChat.AgentPool do
  use GenServer
  
  @default_max_concurrent 3
  @default_queue_timeout 30_000
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def request_tool_execution(session_id, task_spec) do
    GenServer.call(__MODULE__, {:request_execution, session_id, task_spec})
  end
  
  def get_pool_status do
    GenServer.call(__MODULE__, :get_status)
  end
  
  def init(opts) do
    max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)
    
    # Create ETS table for monitoring active workers
    :ets.new(:agent_pool_workers, [
      :set, :public, :named_table,
      {:read_concurrency, true}
    ])
    
    {:ok, %{
      max_concurrent: max_concurrent,
      active_workers: %{},
      queue: :queue.new(),
      worker_count: 0,
      total_completed: 0
    }}
  end
  
  def handle_call({:request_execution, session_id, task_spec}, from, state) do
    if state.worker_count < state.max_concurrent do
      # Start worker immediately
      case start_tool_worker(session_id, task_spec) do
        {:ok, worker_pid} ->
          Process.monitor(worker_pid)
          
          # Track in ETS for monitoring
          :ets.insert(:agent_pool_workers, {
            worker_pid,
            session_id,
            task_spec,
            DateTime.utc_now(),
            from
          })
          
          new_state = %{state |
            active_workers: Map.put(state.active_workers, worker_pid, {session_id, task_spec, from}),
            worker_count: state.worker_count + 1
          }
          
          {:reply, {:ok, worker_pid}, new_state}
          
        error ->
          {:reply, error, state}
      end
    else
      # Queue the request
      queue_item = {session_id, task_spec, from, DateTime.utc_now()}
      new_queue = :queue.in(queue_item, state.queue)
      
      {:noreply, %{state | queue: new_queue}}
    end
  end
  
  def handle_call(:get_status, _from, state) do
    queue_length = :queue.len(state.queue)
    
    status = %{
      active_workers: state.worker_count,
      max_concurrent: state.max_concurrent,
      queue_length: queue_length,
      total_completed: state.total_completed,
      worker_details: get_worker_details()
    }
    
    {:reply, status, state}
  end
  
  def handle_info({:DOWN, _ref, :process, worker_pid, reason}, state) do
    # Worker finished, clean up and start next queued work
    :ets.delete(:agent_pool_workers, worker_pid)
    
    {session_id, task_spec, from} = Map.get(state.active_workers, worker_pid)
    
    # Reply to the original caller if worker crashed
    if reason != :normal do
      GenServer.reply(from, {:error, {:worker_crashed, reason}})
    end
    
    new_workers = Map.delete(state.active_workers, worker_pid)
    new_count = state.worker_count - 1
    
    # Start next queued work if any
    case :queue.out(state.queue) do
      {{:value, {queued_session_id, queued_task_spec, queued_from, _queued_at}}, new_queue} ->
        case start_tool_worker(queued_session_id, queued_task_spec) do
          {:ok, new_worker_pid} ->
            Process.monitor(new_worker_pid)
            
            :ets.insert(:agent_pool_workers, {
              new_worker_pid,
              queued_session_id,
              queued_task_spec,
              DateTime.utc_now(),
              queued_from
            })
            
            GenServer.reply(queued_from, {:ok, new_worker_pid})
            
            {:noreply, %{state |
              active_workers: Map.put(new_workers, new_worker_pid, {queued_session_id, queued_task_spec, queued_from}),
              queue: new_queue,
              worker_count: new_count + 1,
              total_completed: state.total_completed + 1
            }}
            
          _error ->
            # Failed to start queued worker, reply with error
            GenServer.reply(queued_from, {:error, :failed_to_start_worker})
            
            {:noreply, %{state |
              active_workers: new_workers,
              queue: new_queue,
              worker_count: new_count,
              total_completed: state.total_completed + 1
            }}
        end
        
      {:empty, _} ->
        {:noreply, %{state |
          active_workers: new_workers,
          worker_count: new_count,
          total_completed: state.total_completed + 1
        }}
    end
  end
  
  defp start_tool_worker(session_id, task_spec) do
    DynamicSupervisor.start_child(
      MCPChat.ToolExecutorSupervisor,
      {MCPChat.ToolExecutorAgent, {session_id, task_spec}}
    )
  end
  
  defp get_worker_details do
    :ets.tab2list(:agent_pool_workers)
    |> Enum.map(fn {pid, session_id, task_spec, started_at, _from} ->
      %{
        pid: pid,
        session_id: session_id,
        tool_name: task_spec.tool_name,
        started_at: started_at,
        duration_ms: DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
      }
    end)
  end
end
```

### 2.3 Tool Executor Agent

```elixir
defmodule MCPChat.ToolExecutorAgent do
  use GenServer, restart: :temporary
  
  def start_link({session_id, task_spec}) do
    GenServer.start_link(__MODULE__, {session_id, task_spec})
  end
  
  def init({session_id, task_spec}) do
    # Send work to self to avoid blocking supervision tree
    send(self(), :execute_tool)
    
    {:ok, %{
      session_id: session_id,
      task_spec: task_spec,
      started_at: DateTime.utc_now(),
      progress: 0,
      stage: :starting
    }}
  end
  
  def handle_info(:execute_tool, state) do
    try do
      # Broadcast tool execution started
      broadcast_tool_event(state.session_id, %MCPChat.Events.ToolExecutionStarted{
        session_id: state.session_id,
        tool_name: state.task_spec.tool_name,
        agent_pid: self(),
        started_at: state.started_at
      })
      
      # Execute the tool with progress tracking
      result = execute_tool_with_progress(
        state.task_spec,
        progress_callback: &update_progress/2
      )
      
      # Broadcast successful completion
      broadcast_tool_event(state.session_id, %MCPChat.Events.ToolExecutionCompleted{
        session_id: state.session_id,
        tool_name: state.task_spec.tool_name,
        result: result,
        duration_ms: DateTime.diff(DateTime.utc_now(), state.started_at, :millisecond),
        agent_pid: self()
      })
      
      {:stop, :normal, state}
      
    rescue
      error ->
        # Broadcast error
        broadcast_tool_event(state.session_id, %MCPChat.Events.ToolExecutionFailed{
          session_id: state.session_id,
          tool_name: state.task_spec.tool_name,
          error: error,
          agent_pid: self()
        })
        
        {:stop, :normal, state}
    end
  end
  
  def handle_cast({:update_progress, progress, stage}, state) do
    new_state = %{state | progress: progress, stage: stage}
    
    # Broadcast progress update
    broadcast_tool_event(state.session_id, %MCPChat.Events.ToolExecutionProgress{
      session_id: state.session_id,
      tool_name: state.task_spec.tool_name,
      progress: progress,
      stage: stage,
      agent_pid: self()
    })
    
    {:noreply, new_state}
  end
  
  defp execute_tool_with_progress(task_spec, opts) do
    progress_callback = Keyword.get(opts, :progress_callback)
    
    case task_spec.tool_name do
      "analyze_codebase" ->
        execute_codebase_analysis(task_spec.args, progress_callback)
        
      "process_large_file" ->
        execute_file_processing(task_spec.args, progress_callback)
        
      "generate_report" ->
        execute_report_generation(task_spec.args, progress_callback)
        
      tool_name ->
        # Fallback to regular MCP tool execution
        MCPChat.MCP.execute_tool(tool_name, task_spec.args)
    end
  end
  
  defp execute_codebase_analysis(args, progress_callback) do
    repo_url = args["repo_url"]
    
    progress_callback.(self(), {10, :cloning})
    clone_result = clone_repository(repo_url)
    
    progress_callback.(self(), {30, :analyzing})
    analysis_result = analyze_code_structure(clone_result.path)
    
    progress_callback.(self(), {60, :scanning_dependencies})
    deps_result = scan_dependencies(clone_result.path)
    
    progress_callback.(self(), {80, :generating_report})
    report = generate_analysis_report(analysis_result, deps_result)
    
    progress_callback.(self(), {100, :complete})
    
    %{
      repository: repo_url,
      analysis: analysis_result,
      dependencies: deps_result,
      report: report
    }
  end
  
  defp update_progress(agent_pid, {progress, stage}) do
    GenServer.cast(agent_pid, {:update_progress, progress, stage})
  end
  
  defp broadcast_tool_event(session_id, event) do
    Phoenix.PubSub.broadcast(MCPChat.PubSub, "session:#{session_id}", event)
  end
  
  # Placeholder implementations
  defp clone_repository(url), do: %{path: "/tmp/repo"}
  defp analyze_code_structure(path), do: %{files: 100, functions: 250}
  defp scan_dependencies(path), do: %{total: 50, outdated: 5}
  defp generate_analysis_report(analysis, deps), do: "Analysis complete"
end
```

---

## 3. Specialized Agents

### 3.1 Maintenance Agent

```elixir
defmodule MCPChat.MaintenanceAgent do
  use GenServer
  
  @cleanup_interval :timer.hours(1)   # Run every hour
  @deep_clean_hour 2                  # Deep clean at 2 AM
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def force_cleanup do
    GenServer.cast(__MODULE__, :force_cleanup)
  end
  
  def get_maintenance_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  def init(_opts) do
    schedule_next_maintenance()
    
    {:ok, %{
      last_cleanup: nil,
      cleanup_count: 0,
      stats: %{
        sessions_cleaned: 0,
        logs_rotated: 0,
        temp_files_deleted: 0
      }
    }}
  end
  
  def handle_info(:maintenance, state) do
    Logger.info("Starting scheduled maintenance")
    
    current_hour = DateTime.utc_now().hour
    is_deep_clean = current_hour == @deep_clean_hour
    
    stats = perform_maintenance(is_deep_clean)
    
    new_state = %{state |
      last_cleanup: DateTime.utc_now(),
      cleanup_count: state.cleanup_count + 1,
      stats: merge_stats(state.stats, stats)
    }
    
    schedule_next_maintenance()
    
    Logger.info("Maintenance completed", stats: stats)
    {:noreply, new_state}
  end
  
  def handle_cast(:force_cleanup, state) do
    Logger.info("Performing forced maintenance")
    
    stats = perform_maintenance(true)
    
    new_state = %{state |
      last_cleanup: DateTime.utc_now(),
      cleanup_count: state.cleanup_count + 1,
      stats: merge_stats(state.stats, stats)
    }
    
    {:noreply, new_state}
  end
  
  def handle_call(:get_stats, _from, state) do
    response = %{
      last_cleanup: state.last_cleanup,
      cleanup_count: state.cleanup_count,
      cumulative_stats: state.stats
    }
    
    {:reply, response, state}
  end
  
  defp perform_maintenance(is_deep_clean) do
    tasks = [
      &cleanup_inactive_sessions/0,
      &cleanup_temp_files/0
    ]
    
    tasks = if is_deep_clean do
      [&rotate_logs/0, &cleanup_old_exports/0 | tasks]
    else
      tasks
    end
    
    Enum.reduce(tasks, %{}, fn task, acc_stats ->
      case task.() do
        {:ok, stats} -> Map.merge(acc_stats, stats)
        {:error, reason} -> 
          Logger.error("Maintenance task failed: #{inspect(reason)}")
          acc_stats
      end
    end)
  end
  
  defp cleanup_inactive_sessions do
    cutoff_time = DateTime.utc_now() |> DateTime.add(-24, :hour)
    
    sessions_cleaned = MCPChat.SessionManager.list_active_sessions()
    |> Enum.filter(&session_inactive_since?(&1, cutoff_time))
    |> Enum.count(fn session_id ->
      case MCPChat.SessionManager.stop_session(session_id) do
        :ok -> true
        _ -> false
      end
    end)
    
    {:ok, %{sessions_cleaned: sessions_cleaned}}
  end
  
  defp cleanup_temp_files do
    temp_dir = System.tmp_dir!()
    pattern = Path.join(temp_dir, "mcp_chat_*")
    
    files_deleted = Path.wildcard(pattern)
    |> Enum.count(fn file ->
      case File.rm_rf(file) do
        {:ok, _} -> true
        _ -> false
      end
    end)
    
    {:ok, %{temp_files_deleted: files_deleted}}
  end
  
  defp rotate_logs do
    # Rotate application logs
    logs_rotated = 1  # Placeholder
    {:ok, %{logs_rotated: logs_rotated}}
  end
  
  defp cleanup_old_exports do
    # Remove exports older than 7 days
    {:ok, %{old_exports_cleaned: 0}}
  end
  
  defp session_inactive_since?(session_id, cutoff_time) do
    # Check if session has been inactive since cutoff_time
    # This would need to integrate with actual session activity tracking
    false
  end
  
  defp merge_stats(current_stats, new_stats) do
    Map.merge(current_stats, new_stats, fn _key, v1, v2 -> v1 + v2 end)
  end
  
  defp schedule_next_maintenance do
    Process.send_after(self(), :maintenance, @cleanup_interval)
  end
end
```

### 3.2 Export Agent

```elixir
defmodule MCPChat.ExportAgent do
  use GenServer, restart: :temporary
  
  def start_export(session_id, export_spec) do
    DynamicSupervisor.start_child(
      MCPChat.ExportSupervisor,
      {__MODULE__, {session_id, export_spec}}
    )
  end
  
  def start_link({session_id, export_spec}) do
    GenServer.start_link(__MODULE__, {session_id, export_spec})
  end
  
  def init({session_id, export_spec}) do
    export_id = generate_export_id()
    
    # Start export immediately
    send(self(), :start_export)
    
    {:ok, %{
      session_id: session_id,
      export_spec: export_spec,
      export_id: export_id,
      started_at: DateTime.utc_now(),
      progress: 0
    }}
  end
  
  def handle_info(:start_export, state) do
    try do
      # Broadcast export started
      broadcast_export_event(state.session_id, %MCPChat.Events.ExportStarted{
        session_id: state.session_id,
        export_id: state.export_id,
        format: state.export_spec.format,
        started_at: state.started_at
      })
      
      # Generate export with progress tracking
      export_result = generate_export(
        state.session_id,
        state.export_spec,
        progress_callback: &update_export_progress/3
      )
      
      # Store export for download
      storage_result = store_export_result(state.export_id, export_result)
      
      # Broadcast completion
      broadcast_export_event(state.session_id, %MCPChat.Events.ExportCompleted{
        session_id: state.session_id,
        export_id: state.export_id,
        download_url: storage_result.download_url,
        file_size: storage_result.file_size,
        duration_ms: DateTime.diff(DateTime.utc_now(), state.started_at, :millisecond)
      })
      
      {:stop, :normal, state}
      
    rescue
      error ->
        broadcast_export_event(state.session_id, %MCPChat.Events.ExportFailed{
          session_id: state.session_id,
          export_id: state.export_id,
          error: inspect(error)
        })
        
        {:stop, :normal, state}
    end
  end
  
  def handle_cast({:update_progress, progress}, state) do
    broadcast_export_event(state.session_id, %MCPChat.Events.ExportProgress{
      session_id: state.session_id,
      export_id: state.export_id,
      progress: progress
    })
    
    {:noreply, %{state | progress: progress}}
  end
  
  defp generate_export(session_id, export_spec, opts) do
    progress_callback = Keyword.get(opts, :progress_callback)
    
    case export_spec.format do
      "pdf" -> generate_pdf_export(session_id, export_spec, progress_callback)
      "json" -> generate_json_export(session_id, export_spec, progress_callback)
      "markdown" -> generate_markdown_export(session_id, export_spec, progress_callback)
      format -> {:error, {:unsupported_format, format}}
    end
  end
  
  defp generate_pdf_export(session_id, export_spec, progress_callback) do
    progress_callback.(self(), session_id, 10)
    
    # Get session data
    {:ok, session_data} = MCPChat.Gateway.get_session_state(session_id)
    
    progress_callback.(self(), session_id, 30)
    
    # Generate PDF content
    pdf_content = render_pdf_content(session_data, export_spec)
    
    progress_callback.(self(), session_id, 70)
    
    # Write to file
    export_path = generate_export_path(session_id, "pdf")
    File.write!(export_path, pdf_content)
    
    progress_callback.(self(), session_id, 100)
    
    %{
      file_path: export_path,
      content_type: "application/pdf",
      size: byte_size(pdf_content)
    }
  end
  
  defp update_export_progress(agent_pid, session_id, progress) do
    GenServer.cast(agent_pid, {:update_progress, progress})
  end
  
  defp broadcast_export_event(session_id, event) do
    Phoenix.PubSub.broadcast(MCPChat.PubSub, "session:#{session_id}", event)
  end
  
  defp generate_export_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
  
  defp generate_export_path(session_id, format) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    filename = "chat_export_#{session_id}_#{timestamp}.#{format}"
    Path.join(System.tmp_dir(), filename)
  end
  
  defp store_export_result(export_id, export_result) do
    # Store in exports registry for later download
    :ets.insert(:export_registry, {export_id, export_result, DateTime.utc_now()})
    
    %{
      download_url: "/exports/#{export_id}",
      file_size: export_result.size
    }
  end
  
  # Placeholder implementations
  defp render_pdf_content(session_data, _export_spec) do
    "PDF content for #{length(session_data.messages)} messages"
  end
  
  defp generate_json_export(session_id, export_spec, progress_callback) do
    # JSON export implementation
    %{file_path: "/tmp/export.json", content_type: "application/json", size: 1024}
  end
  
  defp generate_markdown_export(session_id, export_spec, progress_callback) do
    # Markdown export implementation
    %{file_path: "/tmp/export.md", content_type: "text/markdown", size: 512}
  end
end
```

---

## 4. Updated Application Supervision Tree

```elixir
defmodule MCPChat.Application do
  use Application
  
  def start(_type, _args) do
    children = [
      # Core infrastructure
      {Phoenix.PubSub, name: MCPChat.PubSub},
      
      # Session management (Main Agents)
      {Registry, keys: :unique, name: MCPChat.SessionRegistry},
      {DynamicSupervisor, name: MCPChat.SessionSupervisor, strategy: :one_for_one},
      MCPChat.SessionManager,
      
      # Agent infrastructure (Subagents)
      MCPChat.AgentSupervisor,
      
      # Telemetry and monitoring
      MCPChat.Telemetry,
      
      # Optional: Web interface
      # MCPChatWeb.Endpoint
    ]
    
    opts = [strategy: :one_for_one, name: MCPChat.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

defmodule MCPChat.AgentSupervisor do
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    children = [
      # Singleton agents
      MCPChat.MaintenanceAgent,
      MCPChat.AgentPool,
      MCPChat.AgentMonitor,
      
      # Dynamic supervisors for worker agents
      {DynamicSupervisor, name: MCPChat.ToolExecutorSupervisor, strategy: :one_for_one},
      {DynamicSupervisor, name: MCPChat.ExportSupervisor, strategy: :one_for_one},
      
      # ETS tables for tracking
      %{
        id: :export_registry,
        start: {:ets, :new, [:export_registry, [:set, :public, :named_table]]}
      }
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

---

## 5. Updated Gateway API

```elixir
defmodule MCPChat.Gateway do
  # Enhanced API with subagent support
  
  def execute_tool(session_id, tool_name, args, opts \\ []) do
    case classify_tool_type(tool_name, args) do
      :fast ->
        # Execute immediately in session context
        execute_fast_tool(session_id, tool_name, args)
        
      :heavy ->
        # Spawn subagent for heavy work
        task_spec = %{
          tool_name: tool_name,
          args: args,
          timeout: Keyword.get(opts, :timeout, 300_000)  # 5 minutes
        }
        
        case MCPChat.SessionManager.spawn_subagent(session_id, :tool_executor, task_spec) do
          {:ok, subagent_id, agent_pid} ->
            {:ok, :async, %{subagent_id: subagent_id, agent_pid: agent_pid}}
            
          error ->
            error
        end
    end
  end
  
  def request_export(session_id, format, options \\ %{}) do
    export_spec = %{
      format: format,
      options: options,
      include_metadata: Map.get(options, :include_metadata, true)
    }
    
    case MCPChat.SessionManager.spawn_subagent(session_id, :export, export_spec) do
      {:ok, subagent_id, agent_pid} ->
        {:ok, %{export_id: subagent_id, agent_pid: agent_pid}}
        
      error ->
        error
    end
  end
  
  def get_agent_pool_status do
    MCPChat.AgentPool.get_pool_status()
  end
  
  def get_maintenance_stats do
    MCPChat.MaintenanceAgent.get_maintenance_stats()
  end
  
  defp classify_tool_type(tool_name, args) do
    case tool_name do
      "analyze_codebase" -> :heavy
      "process_large_file" -> :heavy
      "generate_report" -> :heavy
      _ when map_size(args) > 10 -> :heavy  # Heuristic
      _ -> :fast
    end
  end
  
  defp execute_fast_tool(session_id, tool_name, args) do
    case MCPChat.SessionManager.get_session_pid(session_id) do
      {:ok, pid} ->
        GenServer.call(pid, {:execute_tool, tool_name, args})
      error ->
        error
    end
  end
end
```

This pure OTP agent architecture gives you exactly what you wanted: a long-running main agent that can spawn specialized subagents for different types of work, all managed through proper supervision trees without external dependencies.

The implementation provides:
- 🎯 **Resource management** through the AgentPool
- 🔄 **Real-time progress updates** via PubSub
- 📊 **Built-in monitoring** and observability
- 🛠 **Clean separation** between interactive and background work
- 🔧 **Pure OTP** - no external dependencies

Would you like me to continue implementing the monitoring components and event schemas, or focus on a specific part of this architecture?