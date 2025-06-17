defmodule MCPChat.Agents.MCPAgent do
  @moduledoc """
  Specialized agent for MCP server operations and tool management.

  This agent handles:
  - MCP server discovery and connection management
  - Tool execution with progress monitoring
  - Resource discovery and intelligent caching
  - Prompt management and server-side AI generation
  """

  use GenServer, restart: :temporary
  require Logger

  alias MCPChat.Events.AgentEvents

  # Public API

  def start_link({session_id, task_spec}) do
    GenServer.start_link(__MODULE__, {session_id, task_spec})
  end

  @doc "Get available MCP commands this agent can handle"
  def available_commands do
    %{
      "mcp" => %{
        description: "Advanced MCP server and tool management",
        usage: "/mcp [subcommand] [args...]",
        subcommands: %{
          "discover" => "Intelligent server discovery with auto-configuration",
          "connect" => "Validated server connections with health monitoring",
          "tools" => "Capability-aware tool listing and analysis",
          "tool" => "Monitored tool execution with progress tracking",
          "resources" => "Resource discovery with intelligent caching",
          "resource" => "Enhanced resource reading with metadata",
          "prompts" => "Prompt discovery and capability analysis",
          "prompt" => "Intelligent prompt retrieval and optimization",
          "sample" => "Server-side AI generation with context awareness"
        },
        examples: [
          "/mcp discover",
          "/mcp connect filesystem --auto-config",
          "/mcp tool filesystem read_file --with-progress",
          "/mcp sample server \"analyze this code\""
        ],
        capabilities: [:auto_discovery, :health_monitoring, :progress_tracking, :ai_integration]
      }
    }
  end

  # GenServer implementation

  def init({session_id, task_spec}) do
    # Validate task spec
    case validate_mcp_task(task_spec) do
      :ok ->
        Logger.info("Starting MCP agent", session_id: session_id, command: task_spec.command)

        # Send work to self to avoid blocking supervision tree
        send(self(), :execute_command)

        {:ok,
         %{
           session_id: session_id,
           task_spec: task_spec,
           started_at: DateTime.utc_now(),
           progress: 0,
           stage: :starting
         }}

      {:error, reason} ->
        Logger.error("Invalid MCP task spec", reason: inspect(reason))
        {:stop, {:invalid_task, reason}}
    end
  end

  def handle_info(:execute_command, state) do
    try do
      # Broadcast execution started
      broadcast_event(state.session_id, %AgentEvents.ToolExecutionStarted{
        session_id: state.session_id,
        execution_id: generate_execution_id(),
        tool_name: "mcp_#{state.task_spec.command}",
        args: state.task_spec.args,
        agent_pid: self(),
        started_at: state.started_at,
        estimated_duration: estimate_duration(state.task_spec.command, state.task_spec.args),
        timestamp: DateTime.utc_now()
      })

      # Execute the specific MCP command
      result = execute_mcp_command(state.task_spec.command, state.task_spec.args, state)

      # Broadcast completion
      broadcast_event(state.session_id, %AgentEvents.ToolExecutionCompleted{
        session_id: state.session_id,
        execution_id: state.execution_id || generate_execution_id(),
        tool_name: "mcp_#{state.task_spec.command}",
        result: result,
        duration_ms: DateTime.diff(DateTime.utc_now(), state.started_at, :millisecond),
        agent_pid: self()
      })

      {:stop, :normal, %{state | progress: 100, stage: :completed}}
    rescue
      error ->
        # Broadcast failure
        broadcast_event(state.session_id, %AgentEvents.ToolExecutionFailed{
          session_id: state.session_id,
          execution_id: state.execution_id || generate_execution_id(),
          tool_name: "mcp_#{state.task_spec.command}",
          error: format_error(error),
          duration_ms: DateTime.diff(DateTime.utc_now(), state.started_at, :millisecond),
          agent_pid: self()
        })

        {:stop, :normal, %{state | stage: :failed}}
    end
  end

  def handle_cast({:update_progress, progress, stage}, state) do
    # Broadcast progress update
    broadcast_event(state.session_id, %AgentEvents.ToolExecutionProgress{
      session_id: state.session_id,
      execution_id: state.execution_id || generate_execution_id(),
      progress: progress,
      stage: stage,
      agent_pid: self()
    })

    {:noreply, %{state | progress: progress, stage: stage}}
  end

  # Command execution functions

  defp execute_mcp_command("discover", args, state) do
    update_progress(state, 10, :scanning_config)

    # Parse discovery options
    options = parse_discovery_options(args)

    update_progress(state, 30, :discovering_servers)

    # Discover available MCP servers
    discovered_servers = discover_mcp_servers(options)

    update_progress(state, 60, :analyzing_capabilities)

    # Analyze server capabilities
    server_analysis = analyze_server_capabilities(discovered_servers)

    update_progress(state, 90, :generating_recommendations)

    # Generate connection recommendations
    recommendations = generate_connection_recommendations(server_analysis)

    update_progress(state, 100, :completed)

    %{
      discovered_servers: length(discovered_servers),
      servers: discovered_servers,
      analysis: server_analysis,
      recommendations: recommendations,
      auto_config_available: options[:auto_config]
    }
  end

  defp execute_mcp_command("connect", [server_name | args], state) do
    update_progress(state, 15, :validating_server)

    # Parse connection options
    options = parse_connection_options(args)

    # Validate server exists
    case validate_server_exists(server_name) do
      {:ok, server_info} ->
        update_progress(state, 40, :establishing_connection)

        # Attempt connection with intelligent retry
        case connect_with_retry(server_name, server_info, options) do
          {:ok, connection_result} ->
            update_progress(state, 70, :testing_capabilities)

            # Test basic capabilities
            capability_test = test_server_capabilities(server_name)

            update_progress(state, 90, :configuring_monitoring)

            # Set up health monitoring
            monitoring_result = setup_health_monitoring(server_name)

            update_progress(state, 100, :completed)

            %{
              server: server_name,
              connection: connection_result,
              capabilities: capability_test,
              monitoring: monitoring_result,
              health_check_interval: options[:health_interval] || 30_000
            }

          {:error, reason} ->
            %{
              error: "Connection failed: #{reason}",
              server: server_name,
              troubleshooting: generate_connection_troubleshooting(server_name, reason)
            }
        end

      {:error, reason} ->
        %{
          error: "Server validation failed: #{reason}",
          available_servers: list_available_servers()
        }
    end
  end

  defp execute_mcp_command("tools", args, state) do
    update_progress(state, 20, :discovering_tools)

    # Parse tool listing options
    options = parse_tool_options(args)
    server_filter = options[:server]

    # Get tools from all or specific servers
    tools =
      if server_filter do
        get_tools_from_server(server_filter)
      else
        get_tools_from_all_servers()
      end

    update_progress(state, 50, :analyzing_capabilities)

    # Analyze tool capabilities and group by category
    tool_analysis = analyze_tool_capabilities(tools)

    update_progress(state, 80, :generating_insights)

    # Generate usage insights and recommendations
    usage_insights = generate_tool_usage_insights(tool_analysis)

    update_progress(state, 100, :completed)

    %{
      total_tools: length(tools),
      tools: tools,
      categories: tool_analysis.categories,
      capabilities: tool_analysis.capabilities,
      insights: usage_insights,
      server_filter: server_filter
    }
  end

  defp execute_mcp_command("tool", [server_name, tool_name | args], state) do
    update_progress(state, 10, :validating_tool)

    # Validate tool exists on server
    case validate_tool_exists(server_name, tool_name) do
      {:ok, tool_info} ->
        update_progress(state, 30, :preparing_execution)

        # Parse tool arguments
        tool_args = parse_tool_arguments(args, tool_info)

        update_progress(state, 50, :executing_tool)

        # Execute tool with progress monitoring
        execution_result = execute_tool_with_monitoring(server_name, tool_name, tool_args, state)

        update_progress(state, 90, :processing_results)

        # Process and enhance results
        processed_results = process_tool_results(execution_result, tool_info)

        update_progress(state, 100, :completed)

        %{
          server: server_name,
          tool: tool_name,
          args: tool_args,
          execution: execution_result,
          results: processed_results,
          performance_metrics: calculate_tool_performance(execution_result)
        }

      {:error, reason} ->
        %{
          error: "Tool validation failed: #{reason}",
          available_tools: get_tools_from_server(server_name)
        }
    end
  end

  defp execute_mcp_command("resources", args, state) do
    update_progress(state, 20, :discovering_resources)

    # Parse resource discovery options
    options = parse_resource_options(args)
    server_filter = options[:server]

    # Discover resources from servers
    resources =
      if server_filter do
        get_resources_from_server(server_filter)
      else
        get_resources_from_all_servers()
      end

    update_progress(state, 50, :analyzing_resources)

    # Analyze resource types and metadata
    resource_analysis = analyze_resource_metadata(resources)

    update_progress(state, 80, :optimizing_cache)

    # Optimize resource caching strategy
    caching_strategy = optimize_resource_caching(resource_analysis)

    update_progress(state, 100, :completed)

    %{
      total_resources: length(resources),
      resources: resources,
      types: resource_analysis.types,
      metadata: resource_analysis.metadata,
      caching_strategy: caching_strategy,
      cache_stats: get_cache_statistics()
    }
  end

  defp execute_mcp_command("resource", [server_name, resource_uri | _args], state) do
    update_progress(state, 15, :validating_resource)

    # Validate resource exists
    case validate_resource_exists(server_name, resource_uri) do
      {:ok, resource_info} ->
        update_progress(state, 40, :checking_cache)

        # Check cache first
        case check_resource_cache(server_name, resource_uri) do
          {:hit, cached_content} ->
            update_progress(state, 100, :completed)

            %{
              server: server_name,
              uri: resource_uri,
              content: cached_content,
              source: :cache,
              metadata: resource_info
            }

          :miss ->
            update_progress(state, 70, :fetching_resource)

            # Fetch from server
            case fetch_resource_content(server_name, resource_uri) do
              {:ok, content} ->
                update_progress(state, 90, :updating_cache)

                # Update cache
                cache_resource_content(server_name, resource_uri, content)

                update_progress(state, 100, :completed)

                %{
                  server: server_name,
                  uri: resource_uri,
                  content: content,
                  source: :server,
                  metadata: resource_info
                }

              {:error, reason} ->
                %{
                  error: "Resource fetch failed: #{reason}",
                  server: server_name,
                  uri: resource_uri
                }
            end
        end

      {:error, reason} ->
        %{
          error: "Resource validation failed: #{reason}",
          available_resources: get_resources_from_server(server_name)
        }
    end
  end

  defp execute_mcp_command("prompts", args, state) do
    update_progress(state, 25, :discovering_prompts)

    # Parse prompt discovery options
    options = parse_prompt_options(args)
    server_filter = options[:server]

    # Discover prompts from servers
    prompts =
      if server_filter do
        get_prompts_from_server(server_filter)
      else
        get_prompts_from_all_servers()
      end

    update_progress(state, 60, :analyzing_prompts)

    # Analyze prompt capabilities and complexity
    prompt_analysis = analyze_prompt_capabilities(prompts)

    update_progress(state, 85, :generating_recommendations)

    # Generate usage recommendations
    usage_recommendations = generate_prompt_recommendations(prompt_analysis)

    update_progress(state, 100, :completed)

    %{
      total_prompts: length(prompts),
      prompts: prompts,
      categories: prompt_analysis.categories,
      complexity_levels: prompt_analysis.complexity,
      recommendations: usage_recommendations
    }
  end

  defp execute_mcp_command("prompt", [server_name, prompt_name | args], state) do
    update_progress(state, 20, :validating_prompt)

    # Validate prompt exists
    case validate_prompt_exists(server_name, prompt_name) do
      {:ok, prompt_info} ->
        update_progress(state, 50, :preparing_prompt)

        # Parse prompt arguments
        prompt_args = parse_prompt_arguments(args, prompt_info)

        update_progress(state, 80, :retrieving_prompt)

        # Retrieve prompt with context
        prompt_result = retrieve_prompt_with_context(server_name, prompt_name, prompt_args)

        update_progress(state, 100, :completed)

        %{
          server: server_name,
          prompt: prompt_name,
          args: prompt_args,
          content: prompt_result.content,
          metadata: prompt_result.metadata,
          optimization_suggestions: suggest_prompt_optimizations(prompt_result)
        }

      {:error, reason} ->
        %{
          error: "Prompt validation failed: #{reason}",
          available_prompts: get_prompts_from_server(server_name)
        }
    end
  end

  defp execute_mcp_command("sample", [server_name, prompt_name | context_args], state) do
    update_progress(state, 15, :validating_sampling)

    # Validate server supports sampling
    case validate_sampling_capability(server_name) do
      {:ok, sampling_info} ->
        update_progress(state, 40, :preparing_context)

        # Prepare sampling context
        context = prepare_sampling_context(context_args)

        update_progress(state, 60, :executing_sampling)

        # Execute server-side AI sampling
        sampling_result = execute_server_sampling(server_name, prompt_name, context, state)

        update_progress(state, 90, :processing_response)

        # Process and enhance the response
        processed_response = process_sampling_response(sampling_result)

        update_progress(state, 100, :completed)

        %{
          server: server_name,
          prompt: prompt_name,
          context: context,
          response: processed_response,
          server_info: sampling_info,
          performance: calculate_sampling_performance(sampling_result)
        }

      {:error, reason} ->
        %{
          error: "Sampling not supported: #{reason}",
          alternative_servers: find_sampling_capable_servers()
        }
    end
  end

  # Helper functions

  defp validate_mcp_task(task_spec) do
    required_fields = [:command, :args]
    valid_commands = ["discover", "connect", "tools", "tool", "resources", "resource", "prompts", "prompt", "sample"]

    cond do
      not is_map(task_spec) ->
        {:error, :task_spec_must_be_map}

      not Enum.all?(required_fields, &Map.has_key?(task_spec, &1)) ->
        {:error, :missing_required_fields}

      task_spec.command not in valid_commands ->
        {:error, :unsupported_command}

      true ->
        :ok
    end
  end

  defp update_progress(_state, progress, stage) do
    GenServer.cast(self(), {:update_progress, progress, stage})
  end

  defp broadcast_event(session_id, event) do
    Phoenix.PubSub.broadcast(MCPChat.PubSub, "session:#{session_id}", event)
  end

  defp estimate_duration(command, args) do
    base_time =
      case command do
        # 8 seconds
        "discover" -> 8_000
        # 5 seconds
        "connect" -> 5_000
        # 6 seconds
        "tools" -> 6_000
        # 10 seconds (depends on tool)
        "tool" -> 10_000
        # 7 seconds
        "resources" -> 7_000
        # 4 seconds
        "resource" -> 4_000
        # 5 seconds
        "prompts" -> 5_000
        # 3 seconds
        "prompt" -> 3_000
        # 15 seconds (AI generation)
        "sample" -> 15_000
        # 8 seconds default
        _ -> 8_000
      end

    # Adjust based on arguments (more complex operations take longer)
    len = length(args)

    adjustment =
      cond do
        len == 0 -> 0
        len >= 1 and len <= 3 -> 2_000
        true -> 5_000
      end

    base_time + adjustment
  end

  defp generate_execution_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp format_error(error) do
    case error do
      %{message: message} -> message
      binary when is_binary(error) -> binary
      _ -> inspect(error)
    end
  end

  # Stub implementations for demonstration
  # In a real implementation, these would contain actual MCP client logic

  defp parse_discovery_options(_args), do: %{auto_config: true}
  defp discover_mcp_servers(_options), do: [%{name: "filesystem", type: "stdio", status: "available"}]
  defp analyze_server_capabilities(servers), do: %{total: length(servers), by_type: %{stdio: 1}}
  defp generate_connection_recommendations(_analysis), do: ["Connect to filesystem for file operations"]

  defp parse_connection_options(_args), do: %{health_interval: 30_000}
  defp validate_server_exists(name), do: {:ok, %{name: name, configured: true}}
  defp connect_with_retry(name, _info, _opts), do: {:ok, %{connected: true, server: name}}
  defp test_server_capabilities(_name), do: %{tools: 5, resources: 10, prompts: 2}
  defp setup_health_monitoring(_name), do: %{monitoring: true, interval: 30_000}

  defp generate_connection_troubleshooting(_name, _reason),
    do: ["Check server configuration", "Verify network connectivity"]

  defp list_available_servers, do: ["filesystem", "web", "database"]

  defp parse_tool_options(_args), do: %{}
  defp get_tools_from_server(_server), do: [%{name: "read_file", description: "Read file contents"}]
  defp get_tools_from_all_servers, do: [%{name: "read_file", server: "filesystem"}]
  defp analyze_tool_capabilities(_tools), do: %{categories: ["file_operations"], capabilities: ["read", "write"]}
  defp generate_tool_usage_insights(_analysis), do: ["Most used: file operations", "Recommend: setup file watchers"]

  defp validate_tool_exists(_server, _tool), do: {:ok, %{name: "read_file", args: ["path"]}}
  defp parse_tool_arguments(_args, _info), do: %{path: "/tmp/example.txt"}
  defp execute_tool_with_monitoring(_server, _tool, _args, _state), do: %{success: true, output: "File contents"}
  defp process_tool_results(result, _info), do: result
  defp calculate_tool_performance(_result), do: %{duration_ms: 150, tokens_processed: 100}

  defp parse_resource_options(_args), do: %{}
  defp get_resources_from_server(_server), do: [%{uri: "file:///tmp", type: "directory"}]
  defp get_resources_from_all_servers, do: [%{uri: "file:///tmp", server: "filesystem"}]
  defp analyze_resource_metadata(_resources), do: %{types: ["file", "directory"], metadata: %{total_size: "1GB"}}
  defp optimize_resource_caching(_analysis), do: %{strategy: "LRU", max_size: "100MB"}
  defp get_cache_statistics, do: %{hit_rate: 0.85, size: "25MB"}

  defp validate_resource_exists(_server, _uri), do: {:ok, %{type: "file", size: 1024}}
  defp check_resource_cache(_server, _uri), do: :miss
  defp fetch_resource_content(_server, _uri), do: {:ok, "Resource content"}
  defp cache_resource_content(_server, _uri, _content), do: :ok

  defp parse_prompt_options(_args), do: %{}
  defp get_prompts_from_server(_server), do: [%{name: "analyze_code", description: "Analyze code quality"}]
  defp get_prompts_from_all_servers, do: [%{name: "analyze_code", server: "code_analyzer"}]
  defp analyze_prompt_capabilities(_prompts), do: %{categories: ["analysis"], complexity: ["medium"]}
  defp generate_prompt_recommendations(_analysis), do: ["Use analyze_code for code review"]

  defp validate_prompt_exists(_server, _prompt), do: {:ok, %{name: "analyze_code", args: ["code"]}}
  defp parse_prompt_arguments(_args, _info), do: %{code: "def hello, do: :world"}
  defp retrieve_prompt_with_context(_server, _prompt, _args), do: %{content: "Analyze this code", metadata: %{}}
  defp suggest_prompt_optimizations(_result), do: ["Add more context", "Specify language"]

  defp validate_sampling_capability(_server), do: {:ok, %{ai_model: "gpt-4", supports_streaming: true}}
  defp prepare_sampling_context(args), do: %{text: Enum.join(args, " ")}
  defp execute_server_sampling(_server, _prompt, _context, _state), do: %{response: "AI generated response"}
  defp process_sampling_response(result), do: result
  defp calculate_sampling_performance(_result), do: %{duration_ms: 3000, tokens: 150}
  defp find_sampling_capable_servers, do: ["openai_server", "anthropic_server"]
end
