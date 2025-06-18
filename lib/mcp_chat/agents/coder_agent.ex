defmodule MCPChat.Agents.CoderAgent do
  @moduledoc """
  Specialized agent for code generation and modification tasks.

  This agent handles:
  - Code generation from specifications
  - Code refactoring and optimization
  - Function and module creation
  - Code style improvements
  - Language-specific code transformations
  """

  use MCPChat.Agents.BaseAgent,
    agent_type: :coder,
    capabilities: [:code_writing, :refactoring, :optimization, :language_analysis]

  alias MCPChat.Gateway

  # Required BaseAgent callbacks

  @impl true
  def get_capabilities do
    [
      :code_writing,
      :refactoring,
      :optimization,
      :language_analysis,
      :function_generation,
      :module_creation,
      :code_style_improvement,
      :api_design,
      :error_fixing
    ]
  end

  @impl true
  def can_handle_task?(task_spec) do
    case task_spec[:type] do
      :code_generation ->
        true

      :refactoring ->
        true

      :function_creation ->
        true

      :module_creation ->
        true

      :code_optimization ->
        true

      :bug_fixing ->
        true

      :api_design ->
        true

      _ ->
        # Check if required capabilities match
        required_caps = task_spec[:required_capabilities] || []
        Enum.any?(required_caps, &(&1 in get_capabilities()))
    end
  end

  @impl true
  def execute_task(task_spec, agent_state) do
    Logger.info("Coder agent executing task",
      agent_id: agent_state[:agent_id],
      task_type: task_spec[:type]
    )

    case task_spec[:type] do
      :code_generation ->
        execute_code_generation(task_spec, agent_state)

      :refactoring ->
        execute_refactoring(task_spec, agent_state)

      :function_creation ->
        execute_function_creation(task_spec, agent_state)

      :module_creation ->
        execute_module_creation(task_spec, agent_state)

      :code_optimization ->
        execute_code_optimization(task_spec, agent_state)

      :bug_fixing ->
        execute_bug_fixing(task_spec, agent_state)

      :api_design ->
        execute_api_design(task_spec, agent_state)

      _ ->
        {:error, :unsupported_task_type}
    end
  end

  @impl true
  def get_agent_info do
    %{
      name: "Coder Agent",
      description: "Specialized in code generation, refactoring, and optimization",
      version: "1.0.0",
      supported_languages: [
        "Elixir",
        "JavaScript",
        "TypeScript",
        "Python",
        "Rust",
        "Go",
        "Java",
        "C#"
      ],
      features: [
        "Code generation from specifications",
        "Automated refactoring",
        "Performance optimization",
        "Code quality improvements",
        "API design assistance",
        "Bug fixing and error resolution"
      ]
    }
  end

  # Agent-specific implementations

  @impl true
  def init_agent_state(agent_id, context) do
    state = %{
      agent_id: agent_id,
      context: context,
      active_projects: %{},
      code_history: [],
      optimization_cache: %{},
      language_preferences: %{
        default: "elixir",
        style_guides: %{
          "elixir" => :community,
          "javascript" => :standard,
          "python" => :pep8
        }
      }
    }

    {:ok, state}
  end

  # Task execution functions

  defp execute_code_generation(task_spec, agent_state) do
    %{
      specification: spec,
      language: language,
      context: context
    } = task_spec

    Logger.debug("Generating code", language: language, spec_size: String.length(spec))

    # Use LLM to generate code
    prompt = build_code_generation_prompt(spec, language, context)

    case call_llm_for_code_generation(prompt, agent_state) do
      {:ok, generated_code} ->
        # Validate and format the generated code
        case validate_and_format_code(generated_code, language) do
          {:ok, formatted_code} ->
            # Store in history
            store_code_in_history(agent_state, %{
              type: :generation,
              language: language,
              specification: spec,
              code: formatted_code,
              timestamp: DateTime.utc_now()
            })

            {:ok,
             %{
               code: formatted_code,
               language: language,
               metadata: %{
                 lines_generated: count_lines(formatted_code),
                 complexity_estimate: estimate_complexity(formatted_code),
                 generated_at: DateTime.utc_now()
               }
             }}

          {:error, validation_error} ->
            {:error, {:code_validation_failed, validation_error}}
        end

      {:error, llm_error} ->
        {:error, {:llm_generation_failed, llm_error}}
    end
  end

  defp execute_refactoring(task_spec, agent_state) do
    %{
      original_code: code,
      refactoring_type: refactor_type,
      language: language
    } = task_spec

    Logger.debug("Refactoring code",
      refactor_type: refactor_type,
      language: language,
      code_size: String.length(code)
    )

    case refactor_type do
      :extract_function ->
        extract_functions_from_code(code, language, task_spec)

      :simplify_conditions ->
        simplify_conditional_logic(code, language, task_spec)

      :optimize_performance ->
        optimize_code_performance(code, language, task_spec)

      :improve_readability ->
        improve_code_readability(code, language, task_spec)

      :modularize ->
        modularize_code_structure(code, language, task_spec)

      _ ->
        # Generic refactoring using LLM
        generic_refactoring(code, language, refactor_type, agent_state)
    end
  end

  defp execute_function_creation(task_spec, agent_state) do
    %{
      function_description: description,
      parameters: params,
      return_type: return_type,
      language: language
    } = task_spec

    Logger.debug("Creating function",
      language: language,
      param_count: length(params || [])
    )

    # Generate function signature
    signature = generate_function_signature(description, params, return_type, language)

    # Generate function body
    case generate_function_body(description, signature, language, agent_state) do
      {:ok, function_code} ->
        # Add documentation
        documented_function = add_function_documentation(function_code, description, language)

        {:ok,
         %{
           function_code: documented_function,
           signature: signature,
           language: language,
           documentation: extract_documentation(documented_function),
           metadata: %{
             created_at: DateTime.utc_now(),
             parameter_count: length(params || []),
             estimated_complexity: estimate_function_complexity(function_code)
           }
         }}

      {:error, reason} ->
        {:error, {:function_generation_failed, reason}}
    end
  end

  defp execute_module_creation(task_spec, agent_state) do
    %{
      module_description: description,
      functions: functions,
      language: language,
      module_type: module_type
    } = task_spec

    Logger.debug("Creating module",
      language: language,
      function_count: length(functions || []),
      module_type: module_type
    )

    # Generate module structure
    case generate_module_structure(description, functions, language, module_type) do
      {:ok, module_code} ->
        # Add module documentation
        documented_module = add_module_documentation(module_code, description, language)

        {:ok,
         %{
           module_code: documented_module,
           language: language,
           module_type: module_type,
           functions: functions,
           metadata: %{
             created_at: DateTime.utc_now(),
             function_count: length(functions || []),
             lines_of_code: count_lines(documented_module),
             module_complexity: estimate_module_complexity(documented_module)
           }
         }}

      {:error, reason} ->
        {:error, {:module_generation_failed, reason}}
    end
  end

  defp execute_code_optimization(task_spec, agent_state) do
    %{
      code: code,
      optimization_targets: targets,
      language: language
    } = task_spec

    Logger.debug("Optimizing code",
      language: language,
      targets: targets,
      code_size: String.length(code)
    )

    optimizations =
      Enum.map(targets, fn target ->
        case target do
          :performance -> optimize_for_performance(code, language)
          :memory -> optimize_for_memory(code, language)
          :readability -> optimize_for_readability(code, language)
          :maintainability -> optimize_for_maintainability(code, language)
          _ -> {:ok, code}
        end
      end)

    # Aggregate successful optimizations
    case aggregate_optimizations(optimizations, code) do
      {:ok, optimized_code} ->
        improvements = analyze_optimization_improvements(code, optimized_code, targets)

        {:ok,
         %{
           original_code: code,
           optimized_code: optimized_code,
           improvements: improvements,
           optimization_targets: targets,
           metadata: %{
             optimization_ratio: calculate_optimization_ratio(code, optimized_code),
             optimized_at: DateTime.utc_now()
           }
         }}

      {:error, reason} ->
        {:error, {:optimization_failed, reason}}
    end
  end

  defp execute_bug_fixing(task_spec, agent_state) do
    %{
      buggy_code: code,
      error_description: error_desc,
      language: language,
      test_cases: test_cases
    } = task_spec

    Logger.debug("Fixing bug",
      language: language,
      error_type: error_desc[:type] || "unknown"
    )

    # Analyze the bug
    case analyze_bug(code, error_desc, language) do
      {:ok, bug_analysis} ->
        # Generate fix
        case generate_bug_fix(code, bug_analysis, language, agent_state) do
          {:ok, fixed_code} ->
            # Validate fix with test cases if provided
            validation_result =
              if test_cases do
                validate_fix_with_tests(fixed_code, test_cases, language)
              else
                {:ok, :no_tests_provided}
              end

            {:ok,
             %{
               original_code: code,
               fixed_code: fixed_code,
               bug_analysis: bug_analysis,
               test_validation: validation_result,
               metadata: %{
                 fixed_at: DateTime.utc_now(),
                 bug_type: bug_analysis[:type],
                 fix_confidence: bug_analysis[:confidence] || 0.8
               }
             }}

          {:error, reason} ->
            {:error, {:fix_generation_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:bug_analysis_failed, reason}}
    end
  end

  defp execute_api_design(task_spec, agent_state) do
    %{
      api_description: description,
      endpoints: endpoints,
      language: language,
      api_style: style
    } = task_spec

    Logger.debug("Designing API",
      language: language,
      endpoint_count: length(endpoints || []),
      style: style
    )

    case generate_api_design(description, endpoints, language, style) do
      {:ok, api_code} ->
        # Generate API documentation
        documentation = generate_api_documentation(api_code, description, endpoints)

        {:ok,
         %{
           api_code: api_code,
           documentation: documentation,
           endpoints: endpoints,
           api_style: style,
           metadata: %{
             designed_at: DateTime.utc_now(),
             endpoint_count: length(endpoints || []),
             complexity_score: calculate_api_complexity(api_code, endpoints)
           }
         }}

      {:error, reason} ->
        {:error, {:api_design_failed, reason}}
    end
  end

  # Helper functions (stub implementations for now)

  defp build_code_generation_prompt(spec, language, context) do
    """
    Generate #{language} code for the following specification:

    #{spec}

    Context: #{inspect(context)}

    Please provide clean, well-documented, and idiomatic #{language} code.
    """
  end

  defp call_llm_for_code_generation(prompt, _agent_state) do
    # In a real implementation, this would call the LLM through Gateway
    # For now, return a mock response
    {:ok, "# Generated code placeholder\ndef example_function:\n    pass"}
  end

  defp validate_and_format_code(code, _language) do
    # Stub implementation
    {:ok, code}
  end

  defp store_code_in_history(_agent_state, _entry) do
    :ok
  end

  defp count_lines(code) do
    String.split(code, "\n") |> length()
  end

  defp estimate_complexity(_code) do
    # Stub
    :medium
  end

  # Additional stub implementations for all the helper functions...
  defp extract_functions_from_code(code, _language, _spec), do: {:ok, code}
  defp simplify_conditional_logic(code, _language, _spec), do: {:ok, code}
  defp optimize_code_performance(code, _language, _spec), do: {:ok, code}
  defp improve_code_readability(code, _language, _spec), do: {:ok, code}
  defp modularize_code_structure(code, _language, _spec), do: {:ok, code}
  defp generic_refactoring(code, _language, _type, _state), do: {:ok, code}
  defp generate_function_signature(_desc, _params, _return, _lang), do: "function_signature"
  defp generate_function_body(_desc, _sig, _lang, _state), do: {:ok, "function_body"}
  defp add_function_documentation(code, _desc, _lang), do: code
  defp extract_documentation(_code), do: "Documentation"
  defp estimate_function_complexity(_code), do: :low
  defp generate_module_structure(_desc, _funcs, _lang, _type), do: {:ok, "module_code"}
  defp add_module_documentation(code, _desc, _lang), do: code
  defp estimate_module_complexity(_code), do: :medium
  defp optimize_for_performance(code, _lang), do: {:ok, code}
  defp optimize_for_memory(code, _lang), do: {:ok, code}
  defp optimize_for_readability(code, _lang), do: {:ok, code}
  defp optimize_for_maintainability(code, _lang), do: {:ok, code}
  defp aggregate_optimizations(_opts, code), do: {:ok, code}
  defp analyze_optimization_improvements(_orig, _opt, _targets), do: %{performance: "+10%"}
  defp calculate_optimization_ratio(_orig, _opt), do: 1.1
  defp analyze_bug(_code, _error, _lang), do: {:ok, %{type: :logic_error, confidence: 0.9}}
  defp generate_bug_fix(code, _analysis, _lang, _state), do: {:ok, code}
  defp validate_fix_with_tests(_code, _tests, _lang), do: {:ok, :all_passed}
  defp generate_api_design(_desc, _endpoints, _lang, _style), do: {:ok, "api_code"}
  defp generate_api_documentation(_code, _desc, _endpoints), do: "API Documentation"
  defp calculate_api_complexity(_code, _endpoints), do: length(_endpoints || []) * 2
end
