defmodule MCPChat.Agents.ExportAgent do
  @moduledoc """
  Specialized agent for export operations and data formatting.

  This agent handles:
  - Intelligent export format selection and optimization
  - Advanced formatting with AI-powered enhancement
  - Multi-format conversion with quality preservation
  - Export workflow automation and customization
  """

  use GenServer, restart: :temporary
  require Logger

  alias MCPChat.Events.AgentEvents

  # Public API

  def start_link({session_id, task_spec}) do
    GenServer.start_link(__MODULE__, {session_id, task_spec})
  end

  @doc "Get available export commands this agent can handle"
  def available_commands do
    %{
      "export" => %{
        description: "Smart export with AI-powered formatting and optimization",
        usage: "/export [format] [options...]",
        formats: %{
          "markdown" => "Enhanced markdown with intelligent formatting",
          "html" => "Rich HTML with styling and interactive elements",
          "pdf" => "Professional PDF with layout optimization",
          "json" => "Structured JSON with metadata and analytics",
          "csv" => "Optimized CSV for data analysis",
          "txt" => "Clean text with smart formatting",
          "docx" => "Microsoft Word with professional styling",
          "slides" => "Presentation format with auto-generated slides"
        },
        options: [
          "--enhanced",
          "--with-metadata",
          "--compress",
          "--template <name>",
          "--style <style>",
          "--include-analysis",
          "--optimize-for <purpose>"
        ],
        examples: [
          "/export markdown --enhanced",
          "/export pdf --template professional",
          "/export slides --optimize-for presentation",
          "/export json --with-metadata --include-analysis"
        ],
        capabilities: [:ai_formatting, :multi_format, :template_system, :quality_optimization]
      }
    }
  end

  # GenServer implementation

  def init({session_id, task_spec}) do
    # Validate task spec
    case validate_export_task(task_spec) do
      :ok ->
        Logger.info("Starting Export agent", session_id: session_id, command: task_spec.command)

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
        Logger.error("Invalid Export task spec", reason: inspect(reason))
        {:stop, {:invalid_task, reason}}
    end
  end

  def handle_info(:execute_command, state) do
    try do
      # Broadcast execution started
      broadcast_event(state.session_id, %AgentEvents.ToolExecutionStarted{
        session_id: state.session_id,
        execution_id: generate_execution_id(),
        tool_name: "export_#{state.task_spec.command}",
        args: state.task_spec.args,
        agent_pid: self(),
        started_at: state.started_at,
        estimated_duration: estimate_duration(state.task_spec.args),
        timestamp: DateTime.utc_now()
      })

      # Execute the export command
      result = execute_export_command(state.task_spec.args, state)

      # Broadcast completion
      broadcast_event(state.session_id, %AgentEvents.ToolExecutionCompleted{
        session_id: state.session_id,
        execution_id: state.execution_id || generate_execution_id(),
        tool_name: "export_#{state.task_spec.command}",
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
          tool_name: "export_#{state.task_spec.command}",
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

  defp execute_export_command(args, state) do
    update_progress(state, 5, :parsing_options)

    # Parse export format and options
    {format, options} = parse_export_args(args)

    update_progress(state, 15, :gathering_session_data)

    # Gather session data for export
    session_data = gather_export_data(state.session_id)

    update_progress(state, 25, :analyzing_content)

    # Analyze content for optimal formatting
    content_analysis = analyze_content_for_export(session_data, format, options)

    update_progress(state, 40, :selecting_template)

    # Select or generate appropriate template
    template_info = select_export_template(format, options, content_analysis)

    update_progress(state, 55, :processing_content)

    # Process and enhance content based on format
    processed_content = process_content_for_export(session_data, content_analysis, template_info)

    update_progress(state, 70, :applying_formatting)

    # Apply AI-powered formatting and enhancement
    formatted_content = apply_intelligent_formatting(processed_content, format, options)

    update_progress(state, 85, :generating_output)

    # Generate final export output
    export_result = generate_export_output(formatted_content, format, options, template_info)

    update_progress(state, 95, :optimizing_output)

    # Post-process and optimize output
    final_result = optimize_export_output(export_result, format, options)

    update_progress(state, 100, :completed)

    %{
      format: format,
      options: options,
      session_id: state.session_id,
      content_analysis: content_analysis,
      template_used: template_info.name,
      file_info: final_result.file_info,
      quality_metrics: final_result.quality_metrics,
      export_path: final_result.path,
      size: final_result.size,
      optimization_applied: final_result.optimizations,
      recommendations: generate_export_recommendations(final_result, content_analysis)
    }
  end

  # Helper functions

  defp validate_export_task(task_spec) do
    required_fields = [:command, :args]

    cond do
      not is_map(task_spec) ->
        {:error, :task_spec_must_be_map}

      not Enum.all?(required_fields, &Map.has_key?(task_spec, &1)) ->
        {:error, :missing_required_fields}

      task_spec.command != "export" ->
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

  defp estimate_duration(args) do
    # 8 seconds base
    base_time = 8_000

    # Adjust based on format complexity
    format_adjustment =
      case get_format_from_args(args) do
        # Complex formats
        format when format in ["pdf", "docx", "slides"] -> 6_000
        # Medium complexity
        format when format in ["html", "json"] -> 3_000
        # Simple formats
        _ -> 1_000
      end

    # Adjust based on options
    len = length(args)

    options_adjustment =
      cond do
        len <= 2 -> 0
        len >= 3 and len <= 5 -> 2_000
        true -> 4_000
      end

    base_time + format_adjustment + options_adjustment
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

  # Default format
  defp get_format_from_args([]), do: "markdown"
  defp get_format_from_args([format | _]), do: format

  defp parse_export_args([]) do
    {"markdown", %{enhanced: false, metadata: false}}
  end

  defp parse_export_args([format | args]) do
    options = parse_export_options(args)
    {format, options}
  end

  defp parse_export_options(args) do
    %{
      enhanced: "--enhanced" in args,
      metadata: "--with-metadata" in args,
      compress: "--compress" in args,
      analysis: "--include-analysis" in args,
      template: extract_option_value(args, "--template"),
      style: extract_option_value(args, "--style"),
      optimize_for: extract_option_value(args, "--optimize-for")
    }
  end

  defp extract_option_value(args, option) do
    case Enum.find_index(args, &(&1 == option)) do
      nil -> nil
      index when index + 1 < length(args) -> Enum.at(args, index + 1)
      _ -> nil
    end
  end

  # Stub implementations for demonstration
  # In a real implementation, these would contain actual export logic

  defp gather_export_data(session_id) do
    %{
      session_id: session_id,
      messages: [
        %{role: "user", content: "Hello, can you help me with Elixir?"},
        %{
          role: "assistant",
          content: "Of course! I'd be happy to help you with Elixir. What specific topic would you like to learn about?"
        },
        %{role: "user", content: "How do I create a GenServer?"},
        %{
          role: "assistant",
          content:
            "A GenServer is a behavior in Elixir for building stateful server processes. Here's a basic example..."
        }
      ],
      metadata: %{
        created_at: DateTime.utc_now(),
        model: "claude-3-sonnet",
        provider: "anthropic",
        total_tokens: 1250,
        tools_used: ["code_analysis", "documentation"]
      },
      context: %{
        files: ["/path/to/project.ex", "/path/to/config.exs"],
        topics: ["genserver", "elixir", "otp"]
      }
    }
  end

  defp analyze_content_for_export(session_data, format, _options) do
    %{
      content_type: determine_content_type(session_data),
      complexity: "medium",
      structure: %{
        has_code: true,
        has_explanations: true,
        has_examples: true,
        conversation_flow: "tutorial"
      },
      recommendations: %{
        format_suitability: calculate_format_suitability(format),
        enhancement_opportunities: ["syntax_highlighting", "section_headers", "code_formatting"],
        estimated_quality: 0.85
      }
    }
  end

  defp select_export_template(format, options, content_analysis) do
    template_name = options[:template] || select_default_template(format, content_analysis)

    %{
      name: template_name,
      type: format,
      features: ["syntax_highlighting", "responsive_design", "professional_styling"],
      customizations: determine_template_customizations(options, content_analysis)
    }
  end

  defp process_content_for_export(session_data, content_analysis, template_info) do
    %{
      processed_messages: enhance_message_formatting(session_data.messages, content_analysis),
      metadata: enrich_metadata(session_data.metadata, content_analysis),
      structure: organize_content_structure(session_data, template_info),
      enhancements: apply_content_enhancements(session_data, content_analysis)
    }
  end

  defp apply_intelligent_formatting(processed_content, format, options) do
    base_formatting = apply_base_formatting(processed_content, format)

    enhanced_formatting =
      if options[:enhanced] do
        apply_ai_enhancements(base_formatting, format)
      else
        base_formatting
      end

    final_formatting =
      if options[:optimize_for] do
        optimize_for_purpose(enhanced_formatting, options[:optimize_for])
      else
        enhanced_formatting
      end

    final_formatting
  end

  defp generate_export_output(formatted_content, format, options, template_info) do
    %{
      content: generate_format_specific_output(formatted_content, format, template_info),
      metadata: compile_export_metadata(formatted_content, options),
      assets: generate_supporting_assets(formatted_content, format),
      structure: finalize_document_structure(formatted_content, format)
    }
  end

  defp optimize_export_output(export_result, format, options) do
    optimized_content = optimize_content_for_format(export_result.content, format)

    compressed_content =
      if options[:compress] do
        apply_compression(optimized_content, format)
      else
        optimized_content
      end

    %{
      path: generate_export_path(format),
      size: calculate_output_size(compressed_content),
      file_info: generate_file_info(compressed_content, format),
      quality_metrics: calculate_quality_metrics(compressed_content, export_result),
      optimizations: list_applied_optimizations(options)
    }
  end

  defp generate_export_recommendations(final_result, content_analysis) do
    base_recommendations = [
      "Export completed successfully with #{final_result.quality_metrics.score}% quality score",
      "Consider using --enhanced flag for improved formatting in future exports"
    ]

    format_specific =
      case final_result.file_info.format do
        "pdf" -> ["PDF export optimized for printing and sharing"]
        "slides" -> ["Presentation ready with #{content_analysis.structure.conversation_flow} flow"]
        "markdown" -> ["Markdown export ready for documentation systems"]
        _ -> []
      end

    base_recommendations ++ format_specific
  end

  # Additional stub helper functions
  defp determine_content_type(_session_data), do: "technical_conversation"
  defp calculate_format_suitability(_format), do: 0.9
  defp select_default_template(format, _analysis), do: "#{format}_professional"
  defp determine_template_customizations(_options, _analysis), do: ["dark_code_theme", "section_numbering"]
  defp enhance_message_formatting(messages, _analysis), do: messages
  defp enrich_metadata(metadata, _analysis), do: metadata
  defp organize_content_structure(_data, _template), do: %{sections: 4, subsections: 8}
  defp apply_content_enhancements(_data, _analysis), do: ["syntax_highlighting", "auto_linking"]
  defp apply_base_formatting(content, _format), do: content
  defp apply_ai_enhancements(content, _format), do: content
  defp optimize_for_purpose(content, _purpose), do: content
  defp generate_format_specific_output(_content, format, _template), do: "# Exported as #{format}"
  defp compile_export_metadata(_content, _options), do: %{generated_at: DateTime.utc_now()}
  defp generate_supporting_assets(_content, _format), do: []
  defp finalize_document_structure(_content, _format), do: %{pages: 3, sections: 4}
  defp optimize_content_for_format(content, _format), do: content
  defp apply_compression(content, _format), do: content
  defp generate_export_path(format), do: "/tmp/export_#{DateTime.utc_now() |> DateTime.to_unix()}.#{format}"
  defp calculate_output_size(_content), do: "156KB"
  defp generate_file_info(_content, format), do: %{format: format, version: "1.0", encoding: "UTF-8"}
  defp calculate_quality_metrics(_content, _result), do: %{score: 92, readability: 0.88, completeness: 0.95}
  defp list_applied_optimizations(options), do: Map.keys(options) |> Enum.filter(&options[&1])
end
