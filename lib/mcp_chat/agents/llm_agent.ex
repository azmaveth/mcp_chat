defmodule MCPChat.Agents.LLMAgent do
  @moduledoc """
  Specialized agent for LLM management and model operations.

  This agent handles:
  - Model discovery and recommendations
  - Backend switching with validation
  - Performance analysis and optimization
  - Intelligent model selection based on task requirements
  """

  use GenServer, restart: :temporary
  require Logger

  alias MCPChat.Events.AgentEvents
  alias MCPChat.Session

  # Public API

  def start_link({session_id, task_spec}) do
    GenServer.start_link(__MODULE__, {session_id, task_spec})
  end

  @doc "Get available LLM commands this agent can handle"
  def available_commands do
    %{
      "backend" => %{
        description: "Switch LLM backend with intelligent validation",
        usage: "/backend [provider]",
        examples: ["/backend", "/backend anthropic", "/backend openai"],
        capabilities: [:validation, :auto_configuration, :cost_analysis]
      },
      "model" => %{
        description: "Advanced model management with AI recommendations",
        usage: "/model [subcommand|name]",
        subcommands: %{
          "list" => "List available models with capabilities",
          "recommend" => "Get AI-powered model recommendations",
          "compare" => "Compare models across multiple dimensions",
          "capabilities" => "Analyze model capabilities",
          "switch" => "Switch model with compatibility checking"
        },
        examples: [
          "/model recommend vision streaming",
          "/model compare gpt-4 claude-3-opus",
          "/model capabilities claude-3-sonnet"
        ]
      },
      "models" => %{
        description: "List all available models with smart filtering",
        usage: "/models [--provider <name>] [--capability <cap>]",
        examples: ["/models", "/models --provider openai", "/models --capability vision"]
      },
      "acceleration" => %{
        description: "Hardware acceleration analysis and optimization",
        usage: "/acceleration [analyze|optimize|status]",
        examples: ["/acceleration", "/acceleration analyze", "/acceleration optimize"]
      }
    }
  end

  # GenServer implementation

  def init({session_id, task_spec}) do
    # Validate task spec
    case validate_llm_task(task_spec) do
      :ok ->
        Logger.info("Starting LLM agent", session_id: session_id, command: task_spec.command)

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
        Logger.error("Invalid LLM task spec", reason: inspect(reason))
        {:stop, {:invalid_task, reason}}
    end
  end

  def handle_info(:execute_command, state) do
    try do
      # Broadcast execution started
      broadcast_event(state.session_id, %AgentEvents.ToolExecutionStarted{
        session_id: state.session_id,
        execution_id: generate_execution_id(),
        tool_name: "llm_#{state.task_spec.command}",
        args: state.task_spec.args,
        agent_pid: self(),
        started_at: state.started_at,
        estimated_duration: estimate_duration(state.task_spec.command),
        timestamp: DateTime.utc_now()
      })

      # Execute the specific LLM command
      result = execute_llm_command(state.task_spec.command, state.task_spec.args, state)

      # Broadcast completion
      broadcast_event(state.session_id, %AgentEvents.ToolExecutionCompleted{
        session_id: state.session_id,
        execution_id: state.execution_id || generate_execution_id(),
        tool_name: "llm_#{state.task_spec.command}",
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
          tool_name: "llm_#{state.task_spec.command}",
          error: format_error(error),
          duration_ms: DateTime.diff(DateTime.utc_now(), state.started_at, :millisecond),
          agent_pid: self()
        })

        {:stop, :normal, %{state | stage: :failed}}
    end
  end

  # Command execution functions

  defp execute_llm_command("backend", args, state) do
    update_progress(state, 10, :analyzing_backends)

    case args do
      [] ->
        # Show current backend and available options with analysis
        current_backend = Session.get_session_backend()
        available_backends = ExLLM.supported_providers()

        update_progress(state, 50, :analyzing_performance)

        # Analyze backend performance and costs
        analysis = analyze_backend_performance(available_backends)

        update_progress(state, 100, :completed)

        %{
          current_backend: current_backend,
          available_backends: available_backends,
          performance_analysis: analysis,
          recommendations: generate_backend_recommendations(analysis)
        }

      [backend_name] ->
        # Switch to specified backend with validation
        update_progress(state, 20, :validating_backend)

        case validate_backend(backend_name) do
          {:ok, backend_info} ->
            update_progress(state, 60, :switching_backend)

            # TODO: Perform the switch with Gateway API
            Logger.warning("Backend switching not yet implemented with Gateway API")

            update_progress(state, 90, :verifying_switch)

            # Verify the switch worked
            verify_result = verify_backend_switch(backend_name)

            update_progress(state, 100, :completed)

            Map.merge(backend_info, %{switch_result: verify_result})

          {:error, reason} ->
            %{error: reason, available_backends: ExLLM.supported_providers()}
        end
    end
  end

  defp execute_llm_command("model", args, state) do
    update_progress(state, 10, :loading_models)

    case args do
      [] ->
        # Show current model with detailed info
        {backend, model} = Session.get_session_backend_and_model()

        update_progress(state, 40, :analyzing_capabilities)
        capabilities = get_model_capabilities(model)

        update_progress(state, 70, :generating_insights)
        insights = generate_model_insights(model, capabilities)

        update_progress(state, 100, :completed)

        %{
          current_model: model,
          current_backend: backend,
          capabilities: capabilities,
          insights: insights
        }

      ["recommend" | features] ->
        # AI-powered model recommendations
        execute_model_recommendation(features, state)

      ["compare" | models] ->
        # Compare multiple models
        execute_model_comparison(models, state)

      ["capabilities", model_name] ->
        # Get detailed capabilities for specific model
        execute_capability_analysis(model_name, state)

      [model_name] ->
        # Switch to specified model
        execute_model_switch(model_name, state)
    end
  end

  defp execute_llm_command("models", args, state) do
    update_progress(state, 20, :discovering_models)

    # Parse filter arguments
    filters = parse_model_filters(args)

    update_progress(state, 50, :applying_filters)

    # Get all models and apply filters  
    all_models = get_all_available_models()
    filtered_models = apply_model_filters(all_models, filters)

    update_progress(state, 80, :enriching_data)

    # Enrich with capability data
    enriched_models = enrich_models_with_capabilities(filtered_models)

    update_progress(state, 100, :completed)

    %{
      total_models: length(all_models),
      filtered_models: length(enriched_models),
      models: enriched_models,
      filters_applied: filters
    }
  end

  defp execute_llm_command("acceleration", args, state) do
    update_progress(state, 20, :detecting_hardware)

    # Analyze hardware acceleration capabilities
    hardware_info = detect_hardware_acceleration()

    update_progress(state, 50, :testing_performance)

    case args do
      ["analyze"] ->
        # Deep analysis mode
        performance_metrics = run_acceleration_benchmarks()
        update_progress(state, 100, :completed)

        %{
          hardware: hardware_info,
          performance: performance_metrics,
          recommendations: generate_acceleration_recommendations(hardware_info, performance_metrics)
        }

      ["optimize"] ->
        # Optimization mode
        optimization_results = optimize_acceleration_settings(hardware_info)
        update_progress(state, 100, :completed)

        %{
          hardware: hardware_info,
          optimizations_applied: optimization_results,
          expected_improvement: calculate_expected_improvement(optimization_results)
        }

      _ ->
        # Status mode (default)
        update_progress(state, 100, :completed)

        %{
          hardware: hardware_info,
          status: determine_acceleration_status(hardware_info)
        }
    end
  end

  # Helper functions

  defp validate_llm_task(task_spec) do
    required_fields = [:command, :args]

    cond do
      not is_map(task_spec) ->
        {:error, :task_spec_must_be_map}

      not Enum.all?(required_fields, &Map.has_key?(task_spec, &1)) ->
        {:error, :missing_required_fields}

      task_spec.command not in ["backend", "model", "models", "acceleration"] ->
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

  defp estimate_duration(command) do
    case command do
      # 5 seconds
      "backend" -> 5_000
      # 8 seconds
      "model" -> 8_000
      # 12 seconds
      "models" -> 12_000
      # 15 seconds
      "acceleration" -> 15_000
      # 10 seconds default
      _ -> 10_000
    end
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
  # In a real implementation, these would contain actual logic

  defp analyze_backend_performance(_backends) do
    %{
      anthropic: %{latency: "250ms", cost_per_token: 0.00001, reliability: 0.99},
      openai: %{latency: "180ms", cost_per_token: 0.000015, reliability: 0.98}
    }
  end

  defp generate_backend_recommendations(_analysis) do
    [
      "OpenAI: Best for speed and general tasks",
      "Anthropic: Best for complex reasoning and safety"
    ]
  end

  defp validate_backend(backend_name) do
    available = ExLLM.supported_providers()
    backend_atom = String.to_atom(backend_name)

    if backend_atom in available do
      {:ok, %{name: backend_name, status: "available", configured: true}}
    else
      {:error, "Backend #{backend_name} not available"}
    end
  end

  defp verify_backend_switch(backend_name) do
    current = Session.get_session_backend()

    if to_string(current) == backend_name do
      %{success: true, switched_to: backend_name}
    else
      %{success: false, error: "Switch failed", current: current}
    end
  end

  defp get_model_capabilities(_model) do
    %{
      max_tokens: 4096,
      supports_vision: true,
      supports_function_calling: true,
      context_window: 200_000
    }
  end

  defp generate_model_insights(_model, _capabilities) do
    [
      "Excellent for complex reasoning tasks",
      "Strong vision capabilities",
      "Supports advanced function calling"
    ]
  end

  # Helper function to get all available models across providers
  defp get_all_available_models do
    providers = ExLLM.supported_providers()

    providers
    |> Enum.filter(&ExLLM.configured?/1)
    |> Enum.flat_map(fn provider ->
      case ExLLM.list_models(provider) do
        {:ok, models} ->
          Enum.map(models, fn model ->
            %{
              id: model.id,
              name: model.name,
              provider: provider
            }
          end)

        {:error, _} ->
          []
      end
    end)
  end

  # Additional stub functions...
  defp execute_model_recommendation(_features, _state), do: %{recommended: ["claude-3-opus", "gpt-4"]}
  defp execute_model_comparison(_models, _state), do: %{comparison: "Model comparison results"}
  defp execute_capability_analysis(_model, _state), do: %{capabilities: "Full capability analysis"}
  defp execute_model_switch(_model, _state), do: %{switched: true}
  defp parse_model_filters(_args), do: %{}
  defp apply_model_filters(models, _filters), do: models
  defp enrich_models_with_capabilities(models), do: models
  defp detect_hardware_acceleration, do: %{gpu: "NVIDIA RTX 4090", cuda: true}
  defp run_acceleration_benchmarks, do: %{tokens_per_second: 150}
  defp generate_acceleration_recommendations(_hw, _perf), do: ["Enable CUDA", "Use GPU acceleration"]
  defp optimize_acceleration_settings(_hw), do: %{cuda_enabled: true}
  defp calculate_expected_improvement(_opts), do: "2.5x speedup expected"
  defp determine_acceleration_status(_hw), do: "Optimal"
end
