defmodule MCPChat.Agents.ToolExecutorAgent do
  @moduledoc """
  Specialized agent for executing long-running MCP tools.

  This agent handles heavy computational tasks that would otherwise block
  the main session GenServer. It provides:
  - Progress tracking and real-time updates
  - Error handling and recovery
  - Resource isolation from session processes
  - Integration with the session's PubSub events
  """

  use GenServer, restart: :temporary
  require Logger

  # Public API

  def start_link({session_id, task_spec}) do
    GenServer.start_link(__MODULE__, {session_id, task_spec})
  end

  @doc "Get current progress of a running tool execution"
  def get_progress(agent_pid) when is_pid(agent_pid) do
    GenServer.call(agent_pid, :get_progress)
  end

  @doc "Cancel a running tool execution"
  def cancel_execution(agent_pid) when is_pid(agent_pid) do
    GenServer.call(agent_pid, :cancel)
  end

  # GenServer implementation

  def init({session_id, task_spec}) do
    # Validate task spec
    case validate_task_spec(task_spec) do
      :ok ->
        # Send work to self to avoid blocking supervision tree
        send(self(), :execute_tool)

        Logger.info("Starting tool execution",
          session_id: session_id,
          tool_name: task_spec.tool_name,
          agent_pid: inspect(self())
        )

        {:ok,
         %{
           session_id: session_id,
           task_spec: task_spec,
           started_at: DateTime.utc_now(),
           progress: 0,
           stage: :starting,
           cancelled: false,
           result: nil
         }}

      {:error, reason} ->
        Logger.error("Invalid task spec",
          session_id: session_id,
          reason: inspect(reason),
          task_spec: inspect(task_spec)
        )

        {:stop, {:invalid_task_spec, reason}}
    end
  end

  def handle_info(:execute_tool, %{cancelled: true} = state) do
    # Tool was cancelled before execution started
    {:stop, :normal, state}
  end

  def handle_info(:execute_tool, state) do
    try do
      # Broadcast tool execution started
      broadcast_tool_event(state.session_id, %MCPChat.Events.AgentEvents.ToolExecutionStarted{
        session_id: state.session_id,
        tool_name: state.task_spec.tool_name,
        agent_pid: self(),
        started_at: state.started_at,
        estimated_duration: estimate_duration(state.task_spec)
      })

      # Execute the tool with progress tracking
      result =
        execute_tool_with_progress(
          state.task_spec,
          progress_callback: &update_progress/3,
          cancellation_check: &check_cancellation/1
        )

      duration_ms = DateTime.diff(DateTime.utc_now(), state.started_at, :millisecond)

      # Broadcast successful completion
      broadcast_tool_event(state.session_id, %MCPChat.Events.AgentEvents.ToolExecutionCompleted{
        session_id: state.session_id,
        tool_name: state.task_spec.tool_name,
        result: result,
        duration_ms: duration_ms,
        agent_pid: self()
      })

      Logger.info("Tool execution completed",
        session_id: state.session_id,
        tool_name: state.task_spec.tool_name,
        duration_ms: duration_ms
      )

      {:stop, :normal, %{state | result: result, progress: 100, stage: :completed}}
    rescue
      error ->
        duration_ms = DateTime.diff(DateTime.utc_now(), state.started_at, :millisecond)

        # Broadcast error
        broadcast_tool_event(state.session_id, %MCPChat.Events.AgentEvents.ToolExecutionFailed{
          session_id: state.session_id,
          tool_name: state.task_spec.tool_name,
          error: format_error(error),
          duration_ms: duration_ms,
          agent_pid: self()
        })

        Logger.error("Tool execution failed",
          session_id: state.session_id,
          tool_name: state.task_spec.tool_name,
          error: inspect(error),
          duration_ms: duration_ms
        )

        {:stop, :normal, %{state | stage: :failed}}
    end
  end

  def handle_call(:get_progress, _from, state) do
    progress_info = %{
      progress: state.progress,
      stage: state.stage,
      started_at: state.started_at,
      cancelled: state.cancelled,
      duration_ms: DateTime.diff(DateTime.utc_now(), state.started_at, :millisecond)
    }

    {:reply, progress_info, state}
  end

  def handle_call(:cancel, _from, state) do
    Logger.info("Tool execution cancelled",
      session_id: state.session_id,
      tool_name: state.task_spec.tool_name,
      progress: state.progress
    )

    # Broadcast cancellation
    broadcast_tool_event(state.session_id, %MCPChat.Events.AgentEvents.ToolExecutionCancelled{
      session_id: state.session_id,
      tool_name: state.task_spec.tool_name,
      progress_at_cancellation: state.progress,
      agent_pid: self()
    })

    new_state = %{state | cancelled: true, stage: :cancelled}
    {:stop, :normal, new_state}
  end

  def handle_cast({:update_progress, progress, stage}, state) do
    new_state = %{state | progress: progress, stage: stage}

    # Broadcast progress update
    broadcast_tool_event(state.session_id, %MCPChat.Events.AgentEvents.ToolExecutionProgress{
      session_id: state.session_id,
      tool_name: state.task_spec.tool_name,
      progress: progress,
      stage: stage,
      estimated_completion: estimate_completion_time(new_state),
      agent_pid: self()
    })

    {:noreply, new_state}
  end

  # Private implementation functions

  defp execute_tool_with_progress(task_spec, opts) do
    progress_callback = Keyword.get(opts, :progress_callback)
    cancellation_check = Keyword.get(opts, :cancellation_check)

    case task_spec.tool_name do
      "analyze_codebase" ->
        execute_codebase_analysis(task_spec.args, progress_callback, cancellation_check)

      "process_large_file" ->
        execute_file_processing(task_spec.args, progress_callback, cancellation_check)

      "generate_report" ->
        execute_report_generation(task_spec.args, progress_callback, cancellation_check)

      "extract_documentation" ->
        execute_documentation_extraction(task_spec.args, progress_callback, cancellation_check)

      tool_name ->
        # Fallback to regular MCP tool execution with basic progress
        progress_callback.(self(), 0, :starting)
        result = MCPChat.LLM.ToolBridge.execute_function(tool_name, task_spec.args)
        progress_callback.(self(), 100, :completed)
        result
    end
  end

  defp execute_codebase_analysis(args, progress_callback, cancellation_check) do
    repo_url = args["repo_url"]
    analysis_options = Map.get(args, "options", %{})

    progress_callback.(self(), 10, :cloning)
    cancellation_check.(self())
    clone_result = clone_repository(repo_url)

    progress_callback.(self(), 30, :analyzing_structure)
    cancellation_check.(self())
    structure_result = analyze_code_structure(clone_result.path, analysis_options)

    progress_callback.(self(), 50, :scanning_dependencies)
    cancellation_check.(self())
    deps_result = scan_dependencies(clone_result.path)

    progress_callback.(self(), 70, :analyzing_complexity)
    cancellation_check.(self())
    complexity_result = analyze_complexity(clone_result.path, analysis_options)

    progress_callback.(self(), 90, :generating_report)
    cancellation_check.(self())
    report = generate_analysis_report(structure_result, deps_result, complexity_result)

    progress_callback.(self(), 100, :completed)

    %{
      repository: repo_url,
      analysis: %{
        structure: structure_result,
        dependencies: deps_result,
        complexity: complexity_result
      },
      report: report,
      metadata: %{
        analyzed_at: DateTime.utc_now(),
        options: analysis_options
      }
    }
  end

  defp execute_file_processing(args, progress_callback, cancellation_check) do
    file_path = args["file_path"]
    processing_type = Map.get(args, "type", "analyze")

    progress_callback.(self(), 10, :reading_file)
    cancellation_check.(self())
    file_content = read_large_file(file_path)

    progress_callback.(self(), 30, :preprocessing)
    cancellation_check.(self())
    preprocessed = preprocess_content(file_content, processing_type)

    progress_callback.(self(), 60, :processing)
    cancellation_check.(self())
    result = process_content(preprocessed, processing_type)

    progress_callback.(self(), 90, :formatting_output)
    cancellation_check.(self())
    formatted_result = format_processing_result(result, processing_type)

    progress_callback.(self(), 100, :completed)

    %{
      file_path: file_path,
      processing_type: processing_type,
      result: formatted_result,
      stats: %{
        file_size: byte_size(file_content),
        processing_time: DateTime.utc_now()
      }
    }
  end

  defp execute_report_generation(args, progress_callback, cancellation_check) do
    session_id = args["session_id"]
    report_type = Map.get(args, "type", "full")

    progress_callback.(self(), 10, :gathering_data)
    cancellation_check.(self())
    session_data = gather_session_data(session_id)

    progress_callback.(self(), 30, :analyzing_conversations)
    cancellation_check.(self())
    conversation_analysis = analyze_conversations(session_data)

    progress_callback.(self(), 60, :generating_insights)
    cancellation_check.(self())
    insights = generate_insights(conversation_analysis, report_type)

    progress_callback.(self(), 80, :formatting_report)
    cancellation_check.(self())
    report = format_report(insights, report_type)

    progress_callback.(self(), 100, :completed)

    %{
      session_id: session_id,
      report_type: report_type,
      report: report,
      insights: insights,
      generated_at: DateTime.utc_now()
    }
  end

  defp execute_documentation_extraction(args, progress_callback, cancellation_check) do
    source_path = args["source_path"]
    extraction_type = Map.get(args, "type", "api")

    progress_callback.(self(), 10, :scanning_files)
    cancellation_check.(self())
    files = scan_documentation_files(source_path)

    progress_callback.(self(), 30, :parsing_content)
    cancellation_check.(self())
    parsed_content = parse_documentation_content(files, extraction_type)

    progress_callback.(self(), 60, :extracting_structure)
    cancellation_check.(self())
    structure = extract_documentation_structure(parsed_content)

    progress_callback.(self(), 80, :generating_index)
    cancellation_check.(self())
    index = generate_documentation_index(structure)

    progress_callback.(self(), 100, :completed)

    %{
      source_path: source_path,
      extraction_type: extraction_type,
      documentation: structure,
      index: index,
      stats: %{
        files_processed: length(files),
        extracted_at: DateTime.utc_now()
      }
    }
  end

  defp update_progress(agent_pid, progress, stage) do
    GenServer.cast(agent_pid, {:update_progress, progress, stage})
  end

  defp check_cancellation(agent_pid) do
    case GenServer.call(agent_pid, :get_progress, 1000) do
      %{cancelled: true} -> throw(:cancelled)
      _ -> :ok
    end
  rescue
    # Ignore errors, assume not cancelled
    _ -> :ok
  end

  defp broadcast_tool_event(session_id, event) do
    Phoenix.PubSub.broadcast(MCPChat.PubSub, "session:#{session_id}", event)
  end

  defp validate_task_spec(task_spec) do
    _required_fields = [:tool_name]

    cond do
      not is_map(task_spec) ->
        {:error, :task_spec_must_be_map}

      not Map.has_key?(task_spec, :tool_name) ->
        {:error, :missing_tool_name}

      not is_binary(task_spec.tool_name) ->
        {:error, :tool_name_must_be_string}

      Map.get(task_spec, :args) && not is_map(task_spec.args) ->
        {:error, :args_must_be_map}

      true ->
        :ok
    end
  end

  defp estimate_duration(task_spec) do
    # Provide rough estimates based on tool type
    case task_spec.tool_name do
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

  defp estimate_completion_time(state) do
    if state.progress > 0 do
      elapsed_ms = DateTime.diff(DateTime.utc_now(), state.started_at, :millisecond)
      estimated_total_ms = round(elapsed_ms / state.progress * 100)
      remaining_ms = estimated_total_ms - elapsed_ms

      DateTime.add(DateTime.utc_now(), remaining_ms, :millisecond)
    else
      nil
    end
  end

  defp format_error(error) do
    case error do
      %{message: message} -> message
      binary when is_binary(error) -> binary
      _ -> inspect(error)
    end
  end

  # Placeholder implementations for demonstration
  # In a real implementation, these would contain actual logic

  defp clone_repository(repo_url) do
    # Simulate cloning delay
    :timer.sleep(2000)
    %{path: "/tmp/cloned_repo", url: repo_url}
  end

  defp analyze_code_structure(_path, _options) do
    :timer.sleep(3000)

    %{
      files: 150,
      functions: 250,
      classes: 45,
      lines_of_code: 12500
    }
  end

  defp scan_dependencies(_path) do
    :timer.sleep(2000)

    %{
      total: 50,
      outdated: 5,
      security_issues: 2
    }
  end

  defp analyze_complexity(_path, _options) do
    :timer.sleep(2000)

    %{
      average_complexity: 3.2,
      high_complexity_functions: 12,
      maintainability_index: 75
    }
  end

  defp generate_analysis_report(structure, deps, complexity) do
    "Comprehensive analysis complete: #{structure.files} files, #{deps.total} dependencies, complexity #{complexity.average_complexity}"
  end

  defp read_large_file(file_path) do
    :timer.sleep(1000)
    "Large file content from #{file_path}"
  end

  defp preprocess_content(content, _type) do
    :timer.sleep(1500)
    String.upcase(content)
  end

  defp process_content(content, _type) do
    :timer.sleep(3000)
    %{processed: content, word_count: 1000}
  end

  defp format_processing_result(result, _type) do
    "Processed: #{result.word_count} words"
  end

  defp gather_session_data(session_id) do
    :timer.sleep(1000)
    %{messages: [], metadata: %{session_id: session_id}}
  end

  defp analyze_conversations(_data) do
    :timer.sleep(2000)
    %{total_messages: 25, topics: ["AI", "Programming"]}
  end

  defp generate_insights(_analysis, _type) do
    :timer.sleep(2000)
    %{key_insights: ["Productive session", "Technical focus"]}
  end

  defp format_report(insights, _type) do
    "Report: #{length(insights.key_insights)} key insights"
  end

  defp scan_documentation_files(_source_path) do
    :timer.sleep(1000)
    ["README.md", "API.md", "CHANGELOG.md"]
  end

  defp parse_documentation_content(files, _type) do
    :timer.sleep(2000)
    Enum.map(files, &{&1, "parsed content"})
  end

  defp extract_documentation_structure(parsed_content) do
    :timer.sleep(1500)
    %{sections: length(parsed_content), toc: "Table of Contents"}
  end

  defp generate_documentation_index(structure) do
    :timer.sleep(500)
    %{index: "Generated index", sections: structure.sections}
  end
end
