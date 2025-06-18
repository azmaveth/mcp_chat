defmodule MCPChat.Agents.DocumenterAgent do
  @moduledoc """
  Specialized agent for documentation generation and maintenance.

  This agent handles:
  - API documentation generation
  - Code comment and docstring creation
  - README and guide generation
  - Documentation quality assessment
  - Knowledge base management
  - User manual creation
  """

  use MCPChat.Agents.BaseAgent,
    agent_type: :documenter,
    capabilities: [:documentation_writing, :code_analysis, :content_generation, :technical_writing]

  # Required BaseAgent callbacks

  @impl true
  def get_capabilities do
    [
      :documentation_writing,
      :code_analysis,
      :content_generation,
      :technical_writing,
      :api_documentation,
      :user_guides,
      :tutorial_creation,
      :readme_generation,
      :docstring_generation,
      :knowledge_extraction,
      :documentation_quality_assessment,
      :markdown_generation,
      :diagram_creation
    ]
  end

  @impl true
  def can_handle_task?(task_spec) do
    case task_spec[:type] do
      :generate_documentation ->
        true

      :api_documentation ->
        true

      :readme_generation ->
        true

      :user_guide_creation ->
        true

      :tutorial_creation ->
        true

      :docstring_generation ->
        true

      :documentation_quality_check ->
        true

      :knowledge_extraction ->
        true

      _ ->
        # Check if required capabilities match
        required_caps = task_spec[:required_capabilities] || []
        Enum.any?(required_caps, &(&1 in get_capabilities()))
    end
  end

  @impl true
  def execute_task(task_spec, agent_state) do
    Logger.info("Documenter agent executing task",
      agent_id: agent_state[:agent_id],
      task_type: task_spec[:type]
    )

    case task_spec[:type] do
      :generate_documentation ->
        execute_documentation_generation(task_spec, agent_state)

      :api_documentation ->
        execute_api_documentation(task_spec, agent_state)

      :readme_generation ->
        execute_readme_generation(task_spec, agent_state)

      :user_guide_creation ->
        execute_user_guide_creation(task_spec, agent_state)

      :tutorial_creation ->
        execute_tutorial_creation(task_spec, agent_state)

      :docstring_generation ->
        execute_docstring_generation(task_spec, agent_state)

      :documentation_quality_check ->
        execute_documentation_quality_check(task_spec, agent_state)

      :knowledge_extraction ->
        execute_knowledge_extraction(task_spec, agent_state)

      _ ->
        {:error, :unsupported_task_type}
    end
  end

  @impl true
  def get_agent_info do
    %{
      name: "Documenter Agent",
      description: "Specialized in creating and maintaining technical documentation",
      version: "1.0.0",
      documentation_types: [
        "API documentation",
        "User guides and manuals",
        "Technical tutorials",
        "Code documentation",
        "README files",
        "Architecture documentation"
      ],
      supported_formats: [
        "Markdown",
        "HTML",
        "LaTeX",
        "reStructuredText",
        "AsciiDoc"
      ],
      features: [
        "Automatic API documentation generation",
        "Code analysis for documentation gaps",
        "Interactive tutorial creation",
        "Multi-format output support",
        "Documentation quality assessment",
        "Knowledge extraction from code"
      ]
    }
  end

  # Agent-specific implementations

  @impl true
  def init_agent_state(agent_id, context) do
    state = %{
      agent_id: agent_id,
      context: context,
      documentation_templates: load_documentation_templates(),
      style_guides: load_style_guides(),
      documentation_history: [],
      knowledge_base: %{},
      generation_settings: %{
        default_format: :markdown,
        include_examples: true,
        include_diagrams: true,
        verbosity_level: :detailed
      }
    }

    {:ok, state}
  end

  # Task execution functions

  defp execute_documentation_generation(task_spec, agent_state) do
    %{
      source: source,
      documentation_type: doc_type,
      target_audience: audience,
      format: format
    } = task_spec

    Logger.debug("Generating documentation",
      doc_type: doc_type,
      format: format,
      audience: audience
    )

    case analyze_source_for_documentation(source, doc_type) do
      {:ok, analyzed_content} ->
        case generate_documentation_content(analyzed_content, doc_type, audience, format) do
          {:ok, documentation} ->
            # Apply formatting and styling
            formatted_docs = apply_documentation_formatting(documentation, format, agent_state)

            # Store in history
            store_documentation_in_history(agent_state, %{
              type: doc_type,
              source: source,
              audience: audience,
              format: format,
              documentation: formatted_docs,
              timestamp: DateTime.utc_now()
            })

            {:ok,
             %{
               documentation: formatted_docs,
               metadata: %{
                 doc_type: doc_type,
                 format: format,
                 audience: audience,
                 word_count: count_words(formatted_docs),
                 sections: extract_sections(formatted_docs),
                 generated_at: DateTime.utc_now()
               }
             }}

          {:error, reason} ->
            {:error, {:documentation_generation_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:source_analysis_failed, reason}}
    end
  end

  defp execute_api_documentation(task_spec, agent_state) do
    %{
      api_specification: api_spec,
      language: language,
      include_examples: include_examples,
      output_format: format
    } = task_spec

    Logger.debug("Generating API documentation",
      language: language,
      format: format,
      include_examples: include_examples
    )

    # Parse API specification
    case parse_api_specification(api_spec, language) do
      {:ok, parsed_api} ->
        # Generate documentation sections
        documentation_sections = %{
          overview: generate_api_overview(parsed_api),
          endpoints: generate_endpoint_documentation(parsed_api, include_examples),
          authentication: generate_authentication_docs(parsed_api),
          error_handling: generate_error_handling_docs(parsed_api),
          examples: if(include_examples, do: generate_api_examples(parsed_api), else: nil),
          sdk_references: generate_sdk_references(parsed_api, language)
        }

        # Combine into final documentation
        final_documentation = combine_api_documentation_sections(documentation_sections, format)

        {:ok,
         %{
           api_documentation: final_documentation,
           sections: Map.keys(documentation_sections),
           metadata: %{
             api_version: parsed_api[:version] || "1.0.0",
             endpoint_count: count_endpoints(parsed_api),
             generated_at: DateTime.utc_now(),
             format: format,
             includes_examples: include_examples
           }
         }}

      {:error, reason} ->
        {:error, {:api_parsing_failed, reason}}
    end
  end

  defp execute_readme_generation(task_spec, agent_state) do
    %{
      project_info: project_info,
      codebase: codebase,
      readme_type: readme_type,
      include_badges: include_badges
    } = task_spec

    Logger.debug("Generating README",
      readme_type: readme_type,
      include_badges: include_badges
    )

    # Analyze project structure
    case analyze_project_structure(codebase, project_info) do
      {:ok, project_analysis} ->
        # Generate README sections
        readme_sections = %{
          title_and_description: generate_title_section(project_info),
          badges: if(include_badges, do: generate_badges(project_info), else: nil),
          installation: generate_installation_section(project_analysis),
          usage: generate_usage_section(project_analysis),
          features: generate_features_section(project_analysis),
          contributing: generate_contributing_section(project_info),
          license: generate_license_section(project_info),
          changelog: generate_changelog_section(project_analysis)
        }

        # Combine sections based on README type
        final_readme = combine_readme_sections(readme_sections, readme_type)

        {:ok,
         %{
           readme_content: final_readme,
           sections_included: filter_included_sections(readme_sections),
           metadata: %{
             readme_type: readme_type,
             project_name: project_info[:name],
             generated_at: DateTime.utc_now(),
             estimated_reading_time: estimate_reading_time(final_readme)
           }
         }}

      {:error, reason} ->
        {:error, {:project_analysis_failed, reason}}
    end
  end

  defp execute_user_guide_creation(task_spec, agent_state) do
    %{
      application_info: app_info,
      user_scenarios: scenarios,
      guide_sections: sections,
      difficulty_level: difficulty
    } = task_spec

    Logger.debug("Creating user guide",
      difficulty: difficulty,
      scenario_count: length(scenarios || []),
      section_count: length(sections || [])
    )

    # Generate user guide content
    guide_content = %{
      introduction: generate_user_guide_introduction(app_info, difficulty),
      getting_started: generate_getting_started_section(app_info, difficulty),
      user_scenarios: generate_scenario_documentation(scenarios, difficulty),
      feature_guides: generate_feature_guides(sections, app_info, difficulty),
      troubleshooting: generate_troubleshooting_section(app_info),
      faq: generate_faq_section(scenarios, app_info),
      glossary: generate_glossary(app_info, scenarios)
    }

    # Combine into cohesive guide
    final_guide = combine_user_guide_sections(guide_content, difficulty)

    {:ok,
     %{
       user_guide: final_guide,
       sections: Map.keys(guide_content),
       metadata: %{
         difficulty_level: difficulty,
         scenario_count: length(scenarios || []),
         estimated_completion_time: estimate_guide_completion_time(final_guide, difficulty),
         generated_at: DateTime.utc_now()
       }
     }}
  end

  defp execute_tutorial_creation(task_spec, agent_state) do
    %{
      topic: topic,
      learning_objectives: objectives,
      skill_level: skill_level,
      tutorial_format: format
    } = task_spec

    Logger.debug("Creating tutorial",
      topic: topic,
      skill_level: skill_level,
      format: format
    )

    # Structure tutorial based on learning objectives
    tutorial_structure = %{
      introduction: generate_tutorial_introduction(topic, objectives, skill_level),
      prerequisites: generate_prerequisites_section(topic, skill_level),
      learning_objectives: format_learning_objectives(objectives),
      step_by_step_guide: generate_step_by_step_guide(topic, objectives, skill_level),
      exercises: generate_tutorial_exercises(topic, objectives, skill_level),
      summary: generate_tutorial_summary(topic, objectives),
      next_steps: generate_next_steps_section(topic, skill_level),
      resources: generate_additional_resources(topic)
    }

    # Format according to specified format
    final_tutorial = format_tutorial(tutorial_structure, format)

    {:ok,
     %{
       tutorial: final_tutorial,
       structure: Map.keys(tutorial_structure),
       metadata: %{
         topic: topic,
         skill_level: skill_level,
         format: format,
         objective_count: length(objectives || []),
         estimated_duration: estimate_tutorial_duration(final_tutorial, skill_level),
         generated_at: DateTime.utc_now()
       }
     }}
  end

  defp execute_docstring_generation(task_spec, agent_state) do
    %{
      code: code,
      language: language,
      docstring_style: style,
      include_examples: include_examples
    } = task_spec

    Logger.debug("Generating docstrings",
      language: language,
      style: style,
      include_examples: include_examples
    )

    # Parse code to identify functions/methods/classes
    case parse_code_for_documentation(code, language) do
      {:ok, code_elements} ->
        # Generate docstrings for each element
        documented_elements =
          code_elements
          |> Enum.map(fn element ->
            docstring = generate_docstring_for_element(element, language, style, include_examples)
            Map.put(element, :docstring, docstring)
          end)

        # Integrate docstrings back into code
        documented_code = integrate_docstrings_into_code(code, documented_elements, language)

        {:ok,
         %{
           documented_code: documented_code,
           elements_documented: length(documented_elements),
           docstring_style: style,
           metadata: %{
             language: language,
             original_lines: count_lines(code),
             documented_lines: count_lines(documented_code),
             documentation_coverage: calculate_documentation_coverage(documented_elements),
             generated_at: DateTime.utc_now()
           }
         }}

      {:error, reason} ->
        {:error, {:code_parsing_failed, reason}}
    end
  end

  defp execute_documentation_quality_check(task_spec, agent_state) do
    %{
      documentation: docs,
      quality_criteria: criteria,
      documentation_type: doc_type
    } = task_spec

    Logger.debug("Checking documentation quality",
      doc_type: doc_type,
      criteria_count: length(criteria || [])
    )

    # Perform quality assessment
    quality_assessment = %{
      completeness: assess_documentation_completeness(docs, doc_type),
      clarity: assess_documentation_clarity(docs),
      accuracy: assess_documentation_accuracy(docs, doc_type),
      consistency: assess_documentation_consistency(docs),
      usefulness: assess_documentation_usefulness(docs, doc_type),
      formatting: assess_documentation_formatting(docs),
      grammar_and_style: assess_grammar_and_style(docs)
    }

    # Filter by requested criteria
    filtered_assessment =
      if criteria do
        Map.take(quality_assessment, criteria)
      else
        quality_assessment
      end

    # Calculate overall quality score
    quality_score = calculate_documentation_quality_score(filtered_assessment)
    quality_grade = assign_documentation_quality_grade(quality_score)

    # Generate improvement recommendations
    improvements = generate_documentation_improvements(filtered_assessment)

    {:ok,
     %{
       quality_score: quality_score,
       quality_grade: quality_grade,
       assessment: filtered_assessment,
       improvements: improvements,
       benchmarks: compare_with_documentation_standards(filtered_assessment, doc_type),
       metadata: %{
         assessed_at: DateTime.utc_now(),
         criteria_assessed: Map.keys(filtered_assessment),
         documentation_length: String.length(docs),
         improvement_count: length(improvements)
       }
     }}
  end

  defp execute_knowledge_extraction(task_spec, agent_state) do
    %{
      source: source,
      extraction_type: extraction_type,
      knowledge_format: format
    } = task_spec

    Logger.debug("Extracting knowledge",
      extraction_type: extraction_type,
      format: format
    )

    # Extract knowledge based on type
    case extraction_type do
      :api_knowledge ->
        extract_api_knowledge(source, format)

      :code_patterns ->
        extract_code_patterns(source, format)

      :business_logic ->
        extract_business_logic(source, format)

      :architectural_knowledge ->
        extract_architectural_knowledge(source, format)

      :domain_knowledge ->
        extract_domain_knowledge(source, format)

      _ ->
        {:error, :unsupported_extraction_type}
    end
  end

  # Helper functions (stub implementations)

  defp load_documentation_templates, do: %{}
  defp load_style_guides, do: %{}
  defp store_documentation_in_history(_state, _entry), do: :ok

  defp analyze_source_for_documentation(_source, _type), do: {:ok, %{}}
  defp generate_documentation_content(_content, _type, _audience, _format), do: {:ok, "Generated documentation"}
  defp apply_documentation_formatting(docs, _format, _state), do: docs
  defp count_words(text), do: String.split(text, ~r/\s+/) |> length()
  defp extract_sections(_docs), do: ["Introduction", "Main Content", "Conclusion"]

  defp parse_api_specification(_spec, _language), do: {:ok, %{endpoints: [], version: "1.0.0"}}
  defp generate_api_overview(_api), do: "API Overview"
  defp generate_endpoint_documentation(_api, _examples), do: "Endpoint Documentation"
  defp generate_authentication_docs(_api), do: "Authentication"
  defp generate_error_handling_docs(_api), do: "Error Handling"
  defp generate_api_examples(_api), do: "Examples"
  defp generate_sdk_references(_api, _lang), do: "SDK References"
  defp combine_api_documentation_sections(sections, _format), do: Enum.join(Map.values(sections), "\n\n")
  defp count_endpoints(api), do: length(api[:endpoints] || [])

  defp analyze_project_structure(_codebase, _info), do: {:ok, %{}}
  defp generate_title_section(info), do: "# #{info[:name] || "Project"}"
  defp generate_badges(_info), do: "[![Build Status](example.svg)]"
  defp generate_installation_section(_analysis), do: "## Installation"
  defp generate_usage_section(_analysis), do: "## Usage"
  defp generate_features_section(_analysis), do: "## Features"
  defp generate_contributing_section(_info), do: "## Contributing"
  defp generate_license_section(info), do: "## License\n\n#{info[:license] || "MIT"}"
  defp generate_changelog_section(_analysis), do: "## Changelog"
  defp combine_readme_sections(sections, _type), do: Enum.join(Map.values(sections), "\n\n")
  defp filter_included_sections(sections), do: Map.keys(sections)
  defp estimate_reading_time(text), do: div(count_words(text), 200)

  defp generate_user_guide_introduction(_app, _difficulty), do: "# User Guide"
  defp generate_getting_started_section(_app, _difficulty), do: "## Getting Started"
  defp generate_scenario_documentation(_scenarios, _difficulty), do: "## Scenarios"
  defp generate_feature_guides(_sections, _app, _difficulty), do: "## Features"
  defp generate_troubleshooting_section(_app), do: "## Troubleshooting"
  defp generate_faq_section(_scenarios, _app), do: "## FAQ"
  defp generate_glossary(_app, _scenarios), do: "## Glossary"
  defp combine_user_guide_sections(content, _difficulty), do: Enum.join(Map.values(content), "\n\n")
  defp estimate_guide_completion_time(guide, _difficulty), do: div(count_words(guide), 150)

  defp generate_tutorial_introduction(_topic, _objectives, _level), do: "# Tutorial Introduction"
  defp generate_prerequisites_section(_topic, _level), do: "## Prerequisites"
  defp format_learning_objectives(objectives), do: "## Learning Objectives\n\n" <> Enum.join(objectives || [], "\n")
  defp generate_step_by_step_guide(_topic, _objectives, _level), do: "## Step-by-Step Guide"
  defp generate_tutorial_exercises(_topic, _objectives, _level), do: "## Exercises"
  defp generate_tutorial_summary(_topic, _objectives), do: "## Summary"
  defp generate_next_steps_section(_topic, _level), do: "## Next Steps"
  defp generate_additional_resources(_topic), do: "## Additional Resources"
  defp format_tutorial(structure, _format), do: Enum.join(Map.values(structure), "\n\n")
  defp estimate_tutorial_duration(tutorial, _level), do: div(count_words(tutorial), 100)

  defp parse_code_for_documentation(_code, _language), do: {:ok, []}
  defp generate_docstring_for_element(_element, _language, _style, _examples), do: "Generated docstring"
  defp integrate_docstrings_into_code(code, _elements, _language), do: code
  defp count_lines(text), do: String.split(text, "\n") |> length()
  defp calculate_documentation_coverage(_elements), do: 85

  defp assess_documentation_completeness(_docs, _type), do: %{score: 85}
  defp assess_documentation_clarity(_docs), do: %{score: 80}
  defp assess_documentation_accuracy(_docs, _type), do: %{score: 90}
  defp assess_documentation_consistency(_docs), do: %{score: 88}
  defp assess_documentation_usefulness(_docs, _type), do: %{score: 82}
  defp assess_documentation_formatting(_docs), do: %{score: 95}
  defp assess_grammar_and_style(_docs), do: %{score: 87}
  defp calculate_documentation_quality_score(_assessment), do: 85
  defp assign_documentation_quality_grade(score) when score >= 90, do: "A"
  defp assign_documentation_quality_grade(score) when score >= 80, do: "B"
  defp assign_documentation_quality_grade(score) when score >= 70, do: "C"
  defp assign_documentation_quality_grade(score) when score >= 60, do: "D"
  defp assign_documentation_quality_grade(_score), do: "F"
  defp generate_documentation_improvements(_assessment), do: ["Add more examples", "Improve clarity"]
  defp compare_with_documentation_standards(_assessment, _type), do: %{industry_standard: 80}

  defp extract_api_knowledge(_source, _format), do: {:ok, %{knowledge: "API knowledge", format: _format}}
  defp extract_code_patterns(_source, _format), do: {:ok, %{knowledge: "Code patterns", format: _format}}
  defp extract_business_logic(_source, _format), do: {:ok, %{knowledge: "Business logic", format: _format}}
  defp extract_architectural_knowledge(_source, _format), do: {:ok, %{knowledge: "Architecture", format: _format}}
  defp extract_domain_knowledge(_source, _format), do: {:ok, %{knowledge: "Domain knowledge", format: _format}}
end
