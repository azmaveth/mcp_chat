defmodule MCPChat.Agents.ReviewerAgent do
  @moduledoc """
  Specialized agent for code review and quality analysis.

  This agent handles:
  - Code quality analysis and scoring
  - Best practices verification
  - Security vulnerability detection
  - Performance issue identification
  - Code style and convention checking
  - Technical debt assessment
  """

  use MCPChat.Agents.BaseAgent,
    agent_type: :reviewer,
    capabilities: [:code_analysis, :quality_assessment, :security_analysis, :performance_analysis]

  # Required BaseAgent callbacks

  @impl true
  def get_capabilities do
    [
      :code_analysis,
      :quality_assessment,
      :security_analysis,
      :performance_analysis,
      :best_practices_check,
      :style_checking,
      :complexity_analysis,
      :maintainability_assessment,
      :test_coverage_analysis,
      :dependency_analysis,
      :pattern_detection,
      :anti_pattern_detection,
      :technical_debt_assessment
    ]
  end

  @impl true
  def can_handle_task?(task_spec) do
    case task_spec[:type] do
      :code_review ->
        true

      :quality_analysis ->
        true

      :security_audit ->
        true

      :performance_analysis ->
        true

      :style_check ->
        true

      :complexity_analysis ->
        true

      :dependency_audit ->
        true

      :technical_debt_analysis ->
        true

      _ ->
        # Check if required capabilities match
        required_caps = task_spec[:required_capabilities] || []
        Enum.any?(required_caps, &(&1 in get_capabilities()))
    end
  end

  @impl true
  def execute_task(task_spec, agent_state) do
    Logger.info("Reviewer agent executing task",
      agent_id: agent_state[:agent_id],
      task_type: task_spec[:type]
    )

    case task_spec[:type] do
      :code_review ->
        execute_code_review(task_spec, agent_state)

      :quality_analysis ->
        execute_quality_analysis(task_spec, agent_state)

      :security_audit ->
        execute_security_audit(task_spec, agent_state)

      :performance_analysis ->
        execute_performance_analysis(task_spec, agent_state)

      :style_check ->
        execute_style_check(task_spec, agent_state)

      :complexity_analysis ->
        execute_complexity_analysis(task_spec, agent_state)

      :dependency_audit ->
        execute_dependency_audit(task_spec, agent_state)

      :technical_debt_analysis ->
        execute_technical_debt_analysis(task_spec, agent_state)

      _ ->
        {:error, :unsupported_task_type}
    end
  end

  @impl true
  def get_agent_info do
    %{
      name: "Reviewer Agent",
      description: "Specialized in code review, quality analysis, and security auditing",
      version: "1.0.0",
      analysis_capabilities: [
        "Code quality scoring",
        "Security vulnerability detection",
        "Performance bottleneck identification",
        "Best practices verification",
        "Technical debt assessment",
        "Complexity analysis",
        "Style and convention checking"
      ],
      supported_languages: [
        "Elixir",
        "JavaScript",
        "TypeScript",
        "Python",
        "Rust",
        "Go",
        "Java",
        "C#"
      ]
    }
  end

  # Agent-specific implementations

  @impl true
  def init_agent_state(agent_id, context) do
    state = %{
      agent_id: agent_id,
      context: context,
      review_history: [],
      quality_metrics: %{},
      security_patterns: load_security_patterns(),
      performance_patterns: load_performance_patterns(),
      style_guides: load_style_guides(),
      review_templates: load_review_templates()
    }

    {:ok, state}
  end

  # Task execution functions

  defp execute_code_review(task_spec, agent_state) do
    %{
      code: code,
      language: language,
      review_type: review_type,
      context: context
    } = task_spec

    Logger.debug("Conducting code review",
      language: language,
      review_type: review_type,
      code_size: String.length(code)
    )

    # Perform comprehensive code review
    review_results = %{
      quality_score: analyze_code_quality(code, language),
      security_issues: find_security_issues(code, language),
      performance_issues: find_performance_issues(code, language),
      style_issues: find_style_issues(code, language),
      complexity_metrics: calculate_complexity_metrics(code, language),
      best_practices_violations: find_best_practices_violations(code, language),
      suggestions: generate_improvement_suggestions(code, language, context)
    }

    # Generate overall assessment
    overall_score = calculate_overall_score(review_results)
    recommendation = generate_recommendation(overall_score, review_results)

    # Store in review history
    store_review_in_history(agent_state, %{
      code: code,
      language: language,
      review_type: review_type,
      results: review_results,
      overall_score: overall_score,
      timestamp: DateTime.utc_now()
    })

    {:ok,
     %{
       overall_score: overall_score,
       recommendation: recommendation,
       detailed_results: review_results,
       summary: generate_review_summary(review_results),
       action_items: extract_action_items(review_results),
       metadata: %{
         reviewed_at: DateTime.utc_now(),
         review_type: review_type,
         lines_reviewed: count_lines(code),
         issues_found: count_total_issues(review_results)
       }
     }}
  end

  defp execute_quality_analysis(task_spec, agent_state) do
    %{
      code: code,
      language: language,
      quality_criteria: criteria
    } = task_spec

    Logger.debug("Analyzing code quality",
      language: language,
      criteria_count: length(criteria || [])
    )

    # Analyze specific quality criteria
    quality_analysis = %{
      readability: analyze_readability(code, language),
      maintainability: analyze_maintainability(code, language),
      testability: analyze_testability(code, language),
      reusability: analyze_reusability(code, language),
      modularity: analyze_modularity(code, language),
      documentation: analyze_documentation(code, language),
      error_handling: analyze_error_handling(code, language)
    }

    # Filter by requested criteria
    filtered_analysis =
      if criteria do
        Map.take(quality_analysis, criteria)
      else
        quality_analysis
      end

    # Calculate quality score
    quality_score = calculate_quality_score(filtered_analysis)
    quality_grade = assign_quality_grade(quality_score)

    {:ok,
     %{
       quality_score: quality_score,
       quality_grade: quality_grade,
       analysis: filtered_analysis,
       recommendations: generate_quality_recommendations(filtered_analysis),
       benchmarks: compare_with_benchmarks(filtered_analysis, language),
       metadata: %{
         analyzed_at: DateTime.utc_now(),
         criteria_analyzed: Map.keys(filtered_analysis),
         code_metrics: extract_basic_metrics(code)
       }
     }}
  end

  defp execute_security_audit(task_spec, agent_state) do
    %{
      code: code,
      language: language,
      security_level: security_level
    } = task_spec

    Logger.debug("Conducting security audit",
      language: language,
      security_level: security_level
    )

    # Perform security analysis
    security_findings = %{
      vulnerabilities: find_security_vulnerabilities(code, language, security_level),
      sensitive_data_exposure: check_sensitive_data_exposure(code, language),
      injection_risks: check_injection_risks(code, language),
      authentication_issues: check_authentication_issues(code, language),
      authorization_issues: check_authorization_issues(code, language),
      cryptography_issues: check_cryptography_issues(code, language),
      input_validation: check_input_validation(code, language),
      output_encoding: check_output_encoding(code, language)
    }

    # Categorize findings by severity
    categorized_findings = categorize_security_findings(security_findings)

    # Calculate security score
    security_score = calculate_security_score(categorized_findings)
    security_rating = assign_security_rating(security_score)

    {:ok,
     %{
       security_score: security_score,
       security_rating: security_rating,
       findings: categorized_findings,
       remediation_steps: generate_remediation_steps(categorized_findings),
       compliance_status: check_compliance_status(categorized_findings, security_level),
       risk_assessment: assess_security_risks(categorized_findings),
       metadata: %{
         audited_at: DateTime.utc_now(),
         security_level: security_level,
         total_findings: count_security_findings(categorized_findings),
         critical_issues: count_critical_security_issues(categorized_findings)
       }
     }}
  end

  defp execute_performance_analysis(task_spec, agent_state) do
    %{
      code: code,
      language: language,
      performance_targets: targets
    } = task_spec

    Logger.debug("Analyzing performance",
      language: language,
      target_count: length(targets || [])
    )

    # Analyze performance aspects
    performance_analysis = %{
      algorithmic_complexity: analyze_algorithmic_complexity(code, language),
      memory_usage: analyze_memory_usage(code, language),
      io_operations: analyze_io_operations(code, language),
      database_queries: analyze_database_queries(code, language),
      network_calls: analyze_network_calls(code, language),
      concurrency_issues: analyze_concurrency_issues(code, language),
      resource_leaks: check_resource_leaks(code, language),
      bottlenecks: identify_performance_bottlenecks(code, language)
    }

    # Generate performance recommendations
    recommendations = generate_performance_recommendations(performance_analysis, targets)

    # Calculate performance score
    performance_score = calculate_performance_score(performance_analysis)
    performance_grade = assign_performance_grade(performance_score)

    {:ok,
     %{
       performance_score: performance_score,
       performance_grade: performance_grade,
       analysis: performance_analysis,
       recommendations: recommendations,
       optimization_opportunities: identify_optimization_opportunities(performance_analysis),
       estimated_improvements: estimate_performance_improvements(recommendations),
       metadata: %{
         analyzed_at: DateTime.utc_now(),
         targets_checked: targets || [],
         issues_found: count_performance_issues(performance_analysis),
         complexity_rating: get_complexity_rating(performance_analysis)
       }
     }}
  end

  defp execute_style_check(task_spec, agent_state) do
    %{
      code: code,
      language: language,
      style_guide: style_guide
    } = task_spec

    Logger.debug("Checking code style",
      language: language,
      style_guide: style_guide
    )

    # Load appropriate style guide
    guide_rules = get_style_guide_rules(language, style_guide)

    # Check style violations
    style_violations = %{
      naming_conventions: check_naming_conventions(code, language, guide_rules),
      formatting: check_formatting(code, language, guide_rules),
      spacing: check_spacing(code, language, guide_rules),
      indentation: check_indentation(code, language, guide_rules),
      line_length: check_line_length(code, language, guide_rules),
      comments: check_comment_style(code, language, guide_rules),
      imports: check_import_style(code, language, guide_rules),
      structure: check_code_structure(code, language, guide_rules)
    }

    # Calculate style score
    style_score = calculate_style_score(style_violations)
    compliance_percentage = calculate_compliance_percentage(style_violations)

    {:ok,
     %{
       style_score: style_score,
       compliance_percentage: compliance_percentage,
       violations: style_violations,
       auto_fixable: identify_auto_fixable_violations(style_violations),
       style_guide_used: style_guide,
       formatting_suggestions: generate_formatting_suggestions(style_violations),
       metadata: %{
         checked_at: DateTime.utc_now(),
         total_violations: count_style_violations(style_violations),
         severity_breakdown: categorize_style_violations(style_violations)
       }
     }}
  end

  defp execute_complexity_analysis(task_spec, agent_state) do
    %{
      code: code,
      language: language,
      complexity_metrics: requested_metrics
    } = task_spec

    Logger.debug("Analyzing code complexity",
      language: language,
      metrics: requested_metrics || []
    )

    # Calculate various complexity metrics
    complexity_metrics = %{
      cyclomatic_complexity: calculate_cyclomatic_complexity(code, language),
      cognitive_complexity: calculate_cognitive_complexity(code, language),
      halstead_metrics: calculate_halstead_metrics(code, language),
      maintainability_index: calculate_maintainability_index(code, language),
      nesting_depth: calculate_nesting_depth(code, language),
      function_length: calculate_function_lengths(code, language),
      parameter_count: analyze_parameter_counts(code, language),
      coupling_metrics: calculate_coupling_metrics(code, language)
    }

    # Filter by requested metrics
    filtered_metrics =
      if requested_metrics do
        Map.take(complexity_metrics, requested_metrics)
      else
        complexity_metrics
      end

    # Generate complexity assessment
    complexity_assessment = assess_overall_complexity(filtered_metrics)
    refactoring_suggestions = generate_complexity_refactoring_suggestions(filtered_metrics)

    {:ok,
     %{
       complexity_assessment: complexity_assessment,
       metrics: filtered_metrics,
       refactoring_suggestions: refactoring_suggestions,
       complexity_trends: analyze_complexity_trends(filtered_metrics),
       risk_areas: identify_complexity_risk_areas(filtered_metrics),
       simplification_opportunities: identify_simplification_opportunities(filtered_metrics),
       metadata: %{
         analyzed_at: DateTime.utc_now(),
         metrics_calculated: Map.keys(filtered_metrics),
         highest_complexity_functions: find_most_complex_functions(filtered_metrics),
         overall_complexity_rating: get_overall_complexity_rating(complexity_assessment)
       }
     }}
  end

  defp execute_dependency_audit(task_spec, agent_state) do
    %{
      dependencies: dependencies,
      language: language,
      audit_level: audit_level
    } = task_spec

    Logger.debug("Auditing dependencies",
      language: language,
      dependency_count: length(dependencies || []),
      audit_level: audit_level
    )

    # Analyze dependencies
    dependency_analysis = %{
      security_vulnerabilities: check_dependency_vulnerabilities(dependencies, language),
      outdated_packages: check_outdated_dependencies(dependencies, language),
      license_issues: check_license_compatibility(dependencies, language),
      dependency_conflicts: check_dependency_conflicts(dependencies, language),
      unused_dependencies: identify_unused_dependencies(dependencies, language),
      circular_dependencies: check_circular_dependencies(dependencies, language),
      size_analysis: analyze_dependency_sizes(dependencies, language),
      update_recommendations: generate_update_recommendations(dependencies, language)
    }

    # Calculate dependency health score
    health_score = calculate_dependency_health_score(dependency_analysis)
    risk_level = assess_dependency_risk_level(dependency_analysis)

    {:ok,
     %{
       health_score: health_score,
       risk_level: risk_level,
       analysis: dependency_analysis,
       action_plan: generate_dependency_action_plan(dependency_analysis),
       priority_updates: identify_priority_updates(dependency_analysis),
       maintenance_schedule: suggest_maintenance_schedule(dependency_analysis),
       metadata: %{
         audited_at: DateTime.utc_now(),
         total_dependencies: length(dependencies || []),
         vulnerable_dependencies: count_vulnerable_dependencies(dependency_analysis),
         outdated_dependencies: count_outdated_dependencies(dependency_analysis)
       }
     }}
  end

  defp execute_technical_debt_analysis(task_spec, agent_state) do
    %{
      codebase: codebase,
      language: language,
      debt_categories: categories
    } = task_spec

    Logger.debug("Analyzing technical debt",
      language: language,
      categories: categories || []
    )

    # Analyze different types of technical debt
    debt_analysis = %{
      code_duplication: analyze_code_duplication(codebase, language),
      dead_code: identify_dead_code(codebase, language),
      code_smells: detect_code_smells(codebase, language),
      architectural_debt: assess_architectural_debt(codebase, language),
      test_debt: analyze_test_debt(codebase, language),
      documentation_debt: assess_documentation_debt(codebase, language),
      dependency_debt: assess_dependency_debt(codebase, language),
      performance_debt: identify_performance_debt(codebase, language)
    }

    # Filter by requested categories
    filtered_analysis =
      if categories do
        Map.take(debt_analysis, categories)
      else
        debt_analysis
      end

    # Calculate technical debt score
    debt_score = calculate_technical_debt_score(filtered_analysis)
    debt_rating = assign_debt_rating(debt_score)

    # Generate remediation plan
    remediation_plan = generate_debt_remediation_plan(filtered_analysis)

    {:ok,
     %{
       debt_score: debt_score,
       debt_rating: debt_rating,
       analysis: filtered_analysis,
       remediation_plan: remediation_plan,
       cost_estimates: estimate_remediation_costs(remediation_plan),
       priority_matrix: create_debt_priority_matrix(filtered_analysis),
       metadata: %{
         analyzed_at: DateTime.utc_now(),
         categories_analyzed: Map.keys(filtered_analysis),
         total_debt_items: count_debt_items(filtered_analysis),
         estimated_remediation_time: estimate_total_remediation_time(remediation_plan)
       }
     }}
  end

  # Helper functions (stub implementations)

  defp load_security_patterns, do: %{}
  defp load_performance_patterns, do: %{}
  defp load_style_guides, do: %{}
  defp load_review_templates, do: %{}

  defp analyze_code_quality(_code, _language), do: 85
  defp find_security_issues(_code, _language), do: []
  defp find_performance_issues(_code, _language), do: []
  defp find_style_issues(_code, _language), do: []
  defp calculate_complexity_metrics(_code, _language), do: %{cyclomatic: 5, cognitive: 3}
  defp find_best_practices_violations(_code, _language), do: []
  defp generate_improvement_suggestions(_code, _language, _context), do: ["Add more comments"]

  defp calculate_overall_score(_results), do: 82
  defp generate_recommendation(_score, _results), do: "Code quality is good with minor improvements needed"
  defp store_review_in_history(_state, _entry), do: :ok
  defp generate_review_summary(_results), do: "Overall positive review with 3 minor issues"
  defp extract_action_items(_results), do: ["Fix naming convention", "Add error handling"]
  defp count_lines(code), do: String.split(code, "\n") |> length()
  defp count_total_issues(_results), do: 3

  # Additional stub implementations for all other helper functions...
  defp analyze_readability(_code, _lang), do: %{score: 80}
  defp analyze_maintainability(_code, _lang), do: %{score: 75}
  defp analyze_testability(_code, _lang), do: %{score: 70}
  defp analyze_reusability(_code, _lang), do: %{score: 85}
  defp analyze_modularity(_code, _lang), do: %{score: 90}
  defp analyze_documentation(_code, _lang), do: %{score: 60}
  defp analyze_error_handling(_code, _lang), do: %{score: 80}
  defp calculate_quality_score(_analysis), do: 78
  defp assign_quality_grade(score) when score >= 90, do: "A"
  defp assign_quality_grade(score) when score >= 80, do: "B"
  defp assign_quality_grade(score) when score >= 70, do: "C"
  defp assign_quality_grade(score) when score >= 60, do: "D"
  defp assign_quality_grade(_score), do: "F"
  defp generate_quality_recommendations(_analysis), do: ["Improve documentation", "Add more tests"]
  defp compare_with_benchmarks(_analysis, _lang), do: %{industry_average: 75}
  defp extract_basic_metrics(code), do: %{lines: count_lines(code), characters: String.length(code)}

  # More stub implementations for brevity...
  defp find_security_vulnerabilities(_code, _lang, _level), do: []
  defp check_sensitive_data_exposure(_code, _lang), do: []
  defp check_injection_risks(_code, _lang), do: []
  defp check_authentication_issues(_code, _lang), do: []
  defp check_authorization_issues(_code, _lang), do: []
  defp check_cryptography_issues(_code, _lang), do: []
  defp check_input_validation(_code, _lang), do: []
  defp check_output_encoding(_code, _lang), do: []
  defp categorize_security_findings(findings), do: findings
  defp calculate_security_score(_findings), do: 95
  defp assign_security_rating(score) when score >= 95, do: "Excellent"
  defp assign_security_rating(score) when score >= 85, do: "Good"
  defp assign_security_rating(score) when score >= 75, do: "Fair"
  defp assign_security_rating(_score), do: "Poor"
  defp generate_remediation_steps(_findings), do: ["Update dependencies", "Add input validation"]
  defp check_compliance_status(_findings, _level), do: %{compliant: true}
  defp assess_security_risks(_findings), do: %{overall_risk: :low}
  defp count_security_findings(_findings), do: 0
  defp count_critical_security_issues(_findings), do: 0

  # Continue with more stub implementations...
  defp analyze_algorithmic_complexity(_code, _lang), do: %{average: "O(n)"}
  defp analyze_memory_usage(_code, _lang), do: %{estimated_mb: 10}
  defp analyze_io_operations(_code, _lang), do: %{operations: 5}
  defp analyze_database_queries(_code, _lang), do: %{queries: 3, n_plus_one: 0}
  defp analyze_network_calls(_code, _lang), do: %{calls: 2}
  defp analyze_concurrency_issues(_code, _lang), do: %{race_conditions: 0}
  defp check_resource_leaks(_code, _lang), do: %{leaks: 0}
  defp identify_performance_bottlenecks(_code, _lang), do: []
  defp generate_performance_recommendations(_analysis, _targets), do: ["Use caching", "Optimize queries"]
  defp calculate_performance_score(_analysis), do: 88
  defp assign_performance_grade(score) when score >= 90, do: "Excellent"
  defp assign_performance_grade(score) when score >= 80, do: "Good"
  defp assign_performance_grade(_score), do: "Needs Improvement"
  defp identify_optimization_opportunities(_analysis), do: ["Implement caching"]
  defp estimate_performance_improvements(_recommendations), do: %{estimated_speedup: "2x"}
  defp count_performance_issues(_analysis), do: 2
  defp get_complexity_rating(_analysis), do: :moderate

  # Add remaining stub implementations for all other helper functions
  defp get_style_guide_rules(_lang, _guide), do: %{}
  defp check_naming_conventions(_code, _lang, _rules), do: []
  defp check_formatting(_code, _lang, _rules), do: []
  defp check_spacing(_code, _lang, _rules), do: []
  defp check_indentation(_code, _lang, _rules), do: []
  defp check_line_length(_code, _lang, _rules), do: []
  defp check_comment_style(_code, _lang, _rules), do: []
  defp check_import_style(_code, _lang, _rules), do: []
  defp check_code_structure(_code, _lang, _rules), do: []
  defp calculate_style_score(_violations), do: 92
  defp calculate_compliance_percentage(_violations), do: 95
  defp identify_auto_fixable_violations(_violations), do: []
  defp generate_formatting_suggestions(_violations), do: []
  defp count_style_violations(_violations), do: 3
  defp categorize_style_violations(_violations), do: %{minor: 3, major: 0}

  defp calculate_cyclomatic_complexity(_code, _lang), do: 5
  defp calculate_cognitive_complexity(_code, _lang), do: 3
  defp calculate_halstead_metrics(_code, _lang), do: %{difficulty: 10}
  defp calculate_maintainability_index(_code, _lang), do: 85
  defp calculate_nesting_depth(_code, _lang), do: 3
  defp calculate_function_lengths(_code, _lang), do: %{average: 15, max: 30}
  defp analyze_parameter_counts(_code, _lang), do: %{average: 3, max: 5}
  defp calculate_coupling_metrics(_code, _lang), do: %{afferent: 2, efferent: 3}
  defp assess_overall_complexity(_metrics), do: %{rating: :moderate, score: 70}
  defp generate_complexity_refactoring_suggestions(_metrics), do: ["Extract method", "Reduce nesting"]
  defp analyze_complexity_trends(_metrics), do: %{trend: :stable}
  defp identify_complexity_risk_areas(_metrics), do: ["Function xyz is too complex"]
  defp identify_simplification_opportunities(_metrics), do: ["Use guard clauses"]
  defp find_most_complex_functions(_metrics), do: ["function_a", "function_b"]
  defp get_overall_complexity_rating(_assessment), do: :moderate

  # More stubs for dependency and technical debt analysis
  defp check_dependency_vulnerabilities(_deps, _lang), do: []
  defp check_outdated_dependencies(_deps, _lang), do: []
  defp check_license_compatibility(_deps, _lang), do: []
  defp check_dependency_conflicts(_deps, _lang), do: []
  defp identify_unused_dependencies(_deps, _lang), do: []
  defp check_circular_dependencies(_deps, _lang), do: []
  defp analyze_dependency_sizes(_deps, _lang), do: %{total_mb: 50}
  defp generate_update_recommendations(_deps, _lang), do: []
  defp calculate_dependency_health_score(_analysis), do: 90
  defp assess_dependency_risk_level(_analysis), do: :low
  defp generate_dependency_action_plan(_analysis), do: []
  defp identify_priority_updates(_analysis), do: []
  defp suggest_maintenance_schedule(_analysis), do: %{frequency: :monthly}
  defp count_vulnerable_dependencies(_analysis), do: 0
  defp count_outdated_dependencies(_analysis), do: 2

  defp analyze_code_duplication(_codebase, _lang), do: %{percentage: 5}
  defp identify_dead_code(_codebase, _lang), do: []
  defp detect_code_smells(_codebase, _lang), do: []
  defp assess_architectural_debt(_codebase, _lang), do: %{score: 80}
  defp analyze_test_debt(_codebase, _lang), do: %{coverage: 85}
  defp assess_documentation_debt(_codebase, _lang), do: %{completeness: 70}
  defp assess_dependency_debt(_codebase, _lang), do: %{outdated_count: 3}
  defp identify_performance_debt(_codebase, _lang), do: []
  defp calculate_technical_debt_score(_analysis), do: 75
  defp assign_debt_rating(score) when score >= 80, do: "Low"
  defp assign_debt_rating(score) when score >= 60, do: "Medium"
  defp assign_debt_rating(_score), do: "High"
  defp generate_debt_remediation_plan(_analysis), do: []
  defp estimate_remediation_costs(_plan), do: %{hours: 40, cost: "$4000"}
  defp create_debt_priority_matrix(_analysis), do: %{}
  defp count_debt_items(_analysis), do: 10
  defp estimate_total_remediation_time(_plan), do: "2 weeks"
end
