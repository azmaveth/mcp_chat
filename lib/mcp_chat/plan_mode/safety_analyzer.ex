defmodule MCPChat.PlanMode.SafetyAnalyzer do
  @moduledoc """
  Advanced safety analysis for execution plans.

  Provides comprehensive risk assessment, security analysis,
  and safety recommendations for plan execution.
  """

  alias MCPChat.PlanMode.{Plan, Step}
  require Logger

  @type risk_factor :: %{
          type: atom(),
          severity: :low | :medium | :high | :critical,
          description: String.t(),
          mitigation: String.t(),
          affected_steps: [String.t()]
        }

  @type safety_report :: %{
          overall_risk: :safe | :moderate | :dangerous | :critical,
          risk_factors: [risk_factor()],
          recommendations: [String.t()],
          warnings: [String.t()],
          blockers: [String.t()],
          safe_to_proceed: boolean(),
          analysis_timestamp: DateTime.t()
        }

  # Dangerous commands that should be flagged
  @dangerous_commands [
    "rm",
    "del",
    "delete",
    "rmdir",
    "format",
    "fdisk",
    "dd",
    "mkfs",
    "sudo",
    "su",
    "chmod",
    "chown",
    "kill",
    "killall",
    "halt",
    "reboot",
    "shutdown",
    "poweroff",
    "init",
    "systemctl"
  ]

  # Dangerous file patterns
  @dangerous_patterns [
    # System config files
    ~r/\/etc\//,
    # System data
    ~r/\/var\/lib\//,
    # System binaries
    ~r/\/usr\/bin\//,
    # System admin binaries
    ~r/\/usr\/sbin\//,
    # Boot files
    ~r/\/boot\//,
    # System files
    ~r/\/sys\//,
    # Process files
    ~r/\/proc\//,
    # Device files
    ~r/\/dev\//,
    # Wildcard operations
    ~r/\*$/,
    # Directory traversal
    ~r/\.\.\//,
    # Root filesystem operations
    ~r/^\//
  ]

  # High-risk tools
  @dangerous_tools [
    "delete",
    "remove",
    "destroy",
    "wipe",
    "format",
    "truncate",
    "execute",
    "eval",
    "run_command",
    "system_call",
    "shell_exec"
  ]

  @doc """
  Performs comprehensive safety analysis on a plan.
  """
  @spec analyze(Plan.t(), keyword()) :: safety_report()
  def analyze(%Plan{} = plan, opts \\ []) do
    Logger.info("Starting safety analysis", plan_id: plan.id)

    _risk_factors = []

    # Analyze each step
    step_risks =
      plan.steps
      |> Enum.flat_map(&analyze_step(&1, plan, opts))

    # Analyze plan-level risks
    plan_risks = analyze_plan_structure(plan, opts)

    # Analyze step interactions
    interaction_risks = analyze_step_interactions(plan.steps, opts)

    all_risks = step_risks ++ plan_risks ++ interaction_risks

    # Determine overall risk level
    overall_risk = determine_overall_risk(all_risks)

    # Generate recommendations
    recommendations = generate_recommendations(all_risks, plan)

    # Generate warnings and blockers
    warnings = generate_warnings(all_risks)
    blockers = generate_blockers(all_risks)

    report = %{
      overall_risk: overall_risk,
      risk_factors: all_risks,
      recommendations: recommendations,
      warnings: warnings,
      blockers: blockers,
      safe_to_proceed: Enum.empty?(blockers),
      analysis_timestamp: DateTime.utc_now()
    }

    Logger.info("Safety analysis complete",
      plan_id: plan.id,
      overall_risk: overall_risk,
      risk_count: length(all_risks),
      safe_to_proceed: report.safe_to_proceed
    )

    report
  end

  @doc """
  Analyzes a single step for safety risks.
  """
  @spec analyze_step(map(), Plan.t(), keyword()) :: [risk_factor()]
  def analyze_step(step, plan, opts \\ []) do
    case step.type do
      :tool -> analyze_tool_step(step, plan, opts)
      :command -> analyze_command_step(step, plan, opts)
      :message -> analyze_message_step(step, plan, opts)
      :checkpoint -> analyze_checkpoint_step(step, plan, opts)
      :conditional -> analyze_conditional_step(step, plan, opts)
    end
  end

  # Step-specific analyzers

  defp analyze_tool_step(%{action: %{tool_name: tool_name, arguments: args}} = step, _plan, _opts) do
    risks = []

    # Check if tool is in dangerous list
    risks =
      if tool_name in @dangerous_tools do
        [
          create_risk_factor(
            :dangerous_tool,
            :high,
            "Tool '#{tool_name}' can perform destructive operations",
            "Review tool capabilities and add confirmation prompt",
            [step.id]
          )
          | risks
        ]
      else
        risks
      end

    # Check arguments for dangerous patterns
    risks =
      if has_dangerous_arguments?(args) do
        [
          create_risk_factor(
            :dangerous_arguments,
            :medium,
            "Tool arguments contain potentially dangerous values",
            "Review argument values and validate inputs",
            [step.id]
          )
          | risks
        ]
      else
        risks
      end

    # Check for file system operations
    risks =
      if affects_filesystem?(tool_name, args) do
        [
          create_risk_factor(
            :filesystem_modification,
            :medium,
            "Tool modifies filesystem",
            "Ensure proper backup and rollback mechanisms",
            [step.id]
          )
          | risks
        ]
      else
        risks
      end

    risks
  end

  defp analyze_command_step(%{action: %{command: cmd, args: args}} = step, _plan, _opts) do
    risks = []

    # Check if command is dangerous
    risks =
      if cmd in @dangerous_commands do
        severity = if cmd in ["rm", "del", "format", "dd"], do: :critical, else: :high

        [
          create_risk_factor(
            :dangerous_command,
            severity,
            "Command '#{cmd}' can cause system damage or data loss",
            "Use safer alternatives or add explicit confirmations",
            [step.id]
          )
          | risks
        ]
      else
        risks
      end

    # Check for sudo usage
    risks =
      if String.starts_with?(cmd, "sudo") or "sudo" in args do
        [
          create_risk_factor(
            :elevated_privileges,
            :high,
            "Command requires elevated privileges",
            "Minimize privilege requirements and validate necessity",
            [step.id]
          )
          | risks
        ]
      else
        risks
      end

    # Check for dangerous patterns in arguments
    risks =
      args
      |> Enum.reduce(risks, fn arg, acc ->
        if matches_dangerous_pattern?(arg) do
          [
            create_risk_factor(
              :dangerous_file_pattern,
              :high,
              "Command argument '#{arg}' targets sensitive system areas",
              "Use more specific paths and avoid wildcards",
              [step.id]
            )
            | acc
          ]
        else
          acc
        end
      end)

    # Check for wildcard usage
    risks =
      if Enum.any?(args, &String.contains?(&1, "*")) do
        [
          create_risk_factor(
            :wildcard_usage,
            :medium,
            "Command uses wildcards which can affect unintended files",
            "Use explicit file lists instead of wildcards",
            [step.id]
          )
          | risks
        ]
      else
        risks
      end

    risks
  end

  defp analyze_message_step(%{action: %{content: content}} = step, _plan, _opts) do
    risks = []

    # Check for potentially harmful instructions
    risks =
      if contains_harmful_instructions?(content) do
        [
          create_risk_factor(
            :harmful_instructions,
            :medium,
            "Message contains potentially harmful instructions",
            "Review message content for safety",
            [step.id]
          )
          | risks
        ]
      else
        risks
      end

    risks
  end

  defp analyze_checkpoint_step(_step, _plan, _opts) do
    # Checkpoints are generally safe
    []
  end

  defp analyze_conditional_step(%{action: %{condition: condition}} = step, _plan, _opts) do
    risks = []

    # Check for complex conditions that might be error-prone
    risks =
      if is_complex_condition?(condition) do
        [
          create_risk_factor(
            :complex_condition,
            :low,
            "Conditional step uses complex logic that may be error-prone",
            "Simplify condition or add validation",
            [step.id]
          )
          | risks
        ]
      else
        risks
      end

    risks
  end

  defp analyze_plan_structure(%Plan{steps: steps} = _plan, _opts) do
    risks = []

    # Check for missing rollback mechanisms
    destructive_steps = Enum.filter(steps, &is_destructive_step?/1)
    steps_without_rollback = Enum.filter(destructive_steps, &is_nil(&1.rollback_info))

    risks =
      if length(steps_without_rollback) > 0 do
        step_ids = Enum.map(steps_without_rollback, & &1.id)

        [
          create_risk_factor(
            :missing_rollback,
            :high,
            "#{length(steps_without_rollback)} destructive steps lack rollback mechanisms",
            "Add rollback information to destructive operations",
            step_ids
          )
          | risks
        ]
      else
        risks
      end

    # Check for long sequences without checkpoints
    risks =
      if has_long_sequence_without_checkpoints?(steps) do
        [
          create_risk_factor(
            :missing_checkpoints,
            :medium,
            "Plan has long sequences without recovery checkpoints",
            "Add checkpoints every 3-5 destructive operations",
            []
          )
          | risks
        ]
      else
        risks
      end

    # Check overall complexity
    risks =
      if length(steps) > 20 do
        [
          create_risk_factor(
            :high_complexity,
            :medium,
            "Plan is very complex with #{length(steps)} steps",
            "Consider breaking into smaller sub-plans",
            []
          )
          | risks
        ]
      else
        risks
      end

    risks
  end

  defp analyze_step_interactions(steps, _opts) do
    risks = []

    # Check for dependency cycles
    risks =
      if has_dependency_cycles?(steps) do
        [
          create_risk_factor(
            :dependency_cycle,
            :high,
            "Plan contains circular dependencies between steps",
            "Resolve dependency cycles before execution",
            []
          )
          | risks
        ]
      else
        risks
      end

    # Check for conflicting operations
    risks =
      case find_conflicting_operations(steps) do
        [] ->
          risks

        conflicts ->
          Enum.map(conflicts, fn {step1_id, step2_id, conflict_type} ->
            create_risk_factor(
              :conflicting_operations,
              :high,
              "Steps #{step1_id} and #{step2_id} have conflicting operations: #{conflict_type}",
              "Resolve conflicts or add proper sequencing",
              [step1_id, step2_id]
            )
          end) ++ risks
      end

    risks
  end

  # Helper functions

  defp create_risk_factor(type, severity, description, mitigation, affected_steps) do
    %{
      type: type,
      severity: severity,
      description: description,
      mitigation: mitigation,
      affected_steps: affected_steps
    }
  end

  defp determine_overall_risk(risk_factors) do
    max_severity =
      risk_factors
      |> Enum.map(& &1.severity)
      |> Enum.max_by(&severity_to_number/1, fn -> :low end)

    case max_severity do
      :critical -> :critical
      :high -> :dangerous
      :medium -> :moderate
      :low -> :safe
    end
  end

  defp severity_to_number(:critical), do: 4
  defp severity_to_number(:high), do: 3
  defp severity_to_number(:medium), do: 2
  defp severity_to_number(:low), do: 1

  defp generate_recommendations(risk_factors, _plan) do
    base_recommendations = [
      "Review all steps carefully before approval",
      "Ensure you have recent backups of important data",
      "Consider running in a test environment first"
    ]

    specific_recommendations =
      risk_factors
      |> Enum.map(& &1.mitigation)
      |> Enum.uniq()

    base_recommendations ++ specific_recommendations
  end

  defp generate_warnings(risk_factors) do
    risk_factors
    |> Enum.filter(&(&1.severity in [:medium, :high]))
    |> Enum.map(& &1.description)
  end

  defp generate_blockers(risk_factors) do
    risk_factors
    |> Enum.filter(&(&1.severity == :critical))
    |> Enum.map(& &1.description)
  end

  defp has_dangerous_arguments?(args) when is_map(args) do
    args
    |> Map.values()
    |> Enum.any?(fn value ->
      String.contains?(to_string(value), ["../", "/etc/", "/var/", "rm -rf"])
    end)
  rescue
    _ -> false
  end

  defp affects_filesystem?(tool_name, _args) do
    tool_name in ["write_file", "delete_file", "move_file", "copy_file", "create_directory"]
  end

  defp matches_dangerous_pattern?(arg) do
    dangerous_patterns = [
      # System config files
      ~r/\/etc\//,
      # System data
      ~r/\/var\/lib\//,
      # System binaries
      ~r/\/usr\/bin\//,
      # System admin binaries
      ~r/\/usr\/sbin\//,
      # Boot files
      ~r/\/boot\//,
      # System files
      ~r/\/sys\//,
      # Process files
      ~r/\/proc\//,
      # Device files
      ~r/\/dev\//,
      # Wildcard operations
      ~r/\*$/,
      # Directory traversal
      ~r/\.\.\/\//,
      # Root filesystem operations
      ~r/^\//
    ]

    Enum.any?(dangerous_patterns, &Regex.match?(&1, arg))
  end

  defp contains_harmful_instructions?(content) do
    harmful_keywords = ["delete all", "remove everything", "format drive", "rm -rf /"]
    Enum.any?(harmful_keywords, &String.contains?(String.downcase(content), &1))
  end

  defp is_complex_condition?(condition) do
    # Simple heuristic: complex if contains multiple operators or long
    String.length(condition) > 50 or
      Enum.count(String.graphemes(condition), &(&1 in ["&", "|", "!", "(", ")"])) > 3
  end

  defp is_destructive_step?(%{type: :command, action: %{command: cmd}}) do
    cmd in @dangerous_commands
  end

  defp is_destructive_step?(%{type: :tool, action: %{tool_name: tool}}) do
    tool in @dangerous_tools
  end

  defp is_destructive_step?(_), do: false

  defp has_long_sequence_without_checkpoints?(steps) do
    # Check if there are more than 5 destructive steps without a checkpoint
    {_, max_sequence} =
      Enum.reduce(steps, {0, 0}, fn step, {current, max} ->
        case step.type do
          :checkpoint -> {0, max}
          _ when current >= 5 -> {current + 1, max(current + 1, max)}
          _ -> {current + 1, max}
        end
      end)

    max_sequence > 5
  end

  defp has_dependency_cycles?(steps) do
    # Simplified cycle detection - in reality would need proper graph algorithm
    step_deps =
      steps
      |> Enum.map(fn step -> {step.id, step.prerequisites || []} end)
      |> Map.new()

    # Check for immediate cycles (A depends on B, B depends on A)
    Enum.any?(steps, fn step ->
      Enum.any?(step.prerequisites || [], fn dep_id ->
        dep_prereqs = Map.get(step_deps, dep_id, [])
        step.id in dep_prereqs
      end)
    end)
  end

  defp find_conflicting_operations(steps) do
    # Find steps that might conflict (simplified)
    conflicts = []

    # Check for read/write conflicts on same files
    _file_operations =
      steps
      |> Enum.filter(fn step ->
        case step.type do
          :tool -> step.action.tool_name in ["read_file", "write_file"]
          :command -> step.action.command in ["cat", "cp", "mv", "rm"]
          _ -> false
        end
      end)

    # For now, return empty list - real implementation would check file paths
    conflicts
  end
end
