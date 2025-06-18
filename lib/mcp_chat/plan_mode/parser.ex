defmodule MCPChat.PlanMode.Parser do
  @moduledoc """
  Parses user intent and generates execution plans.

  The parser analyzes natural language requests and creates structured
  plans with appropriate steps, safety checks, and rollback strategies.
  """

  alias MCPChat.PlanMode.{Plan, Step}
  alias MCPChat.Session

  @doc """
  Parses a user request and generates an execution plan.
  """
  def parse(request, context \\ %{}) do
    with {:ok, intent} <- analyze_intent(request),
         {:ok, steps} <- generate_steps(intent, context),
         {:ok, plan} <- build_plan(request, steps, context) do
      {:ok, plan}
    end
  end

  @doc """
  Analyzes the user's intent from their request.
  """
  def analyze_intent(request) do
    intent =
      cond do
        String.match?(request, ~r/refactor/i) ->
          analyze_refactor_intent(request)

        String.match?(request, ~r/test/i) ->
          analyze_test_intent(request)

        String.match?(request, ~r/debug|fix/i) ->
          analyze_debug_intent(request)

        String.match?(request, ~r/analyze|review/i) ->
          analyze_review_intent(request)

        String.match?(request, ~r/create|generate|make/i) ->
          analyze_create_intent(request)

        String.match?(request, ~r/update|modify|change/i) ->
          analyze_update_intent(request)

        true ->
          {:general, request}
      end

    {:ok, intent}
  end

  @doc """
  Generates steps based on the analyzed intent.
  """
  def generate_steps(intent, context) do
    steps =
      case intent do
        {:refactor, target, approach} ->
          generate_refactor_steps(target, approach, context)

        {:test, target, type} ->
          generate_test_steps(target, type, context)

        {:debug, issue, context_info} ->
          generate_debug_steps(issue, context_info, context)

        {:review, target, focus} ->
          generate_review_steps(target, focus, context)

        {:create, artifact, spec} ->
          generate_create_steps(artifact, spec, context)

        {:update, target, changes} ->
          generate_update_steps(target, changes, context)

        {:general, _request} ->
          generate_general_steps(intent, context)
      end

    {:ok, steps}
  end

  # Intent analyzers

  defp analyze_refactor_intent(request) do
    # Extract what to refactor and how
    target = extract_target(request)
    approach = extract_refactor_approach(request)
    {:refactor, target, approach}
  end

  defp analyze_test_intent(request) do
    # Extract what to test and test type
    target = extract_target(request)
    test_type = extract_test_type(request)
    {:test, target, test_type}
  end

  defp analyze_debug_intent(request) do
    # Extract the issue and any context
    issue = extract_issue(request)
    context_info = extract_debug_context(request)
    {:debug, issue, context_info}
  end

  defp analyze_review_intent(request) do
    # Extract what to review and focus areas
    target = extract_target(request)
    focus = extract_review_focus(request)
    {:review, target, focus}
  end

  defp analyze_create_intent(request) do
    # Extract what to create and specifications
    artifact = extract_artifact_type(request)
    spec = extract_specifications(request)
    {:create, artifact, spec}
  end

  defp analyze_update_intent(request) do
    # Extract what to update and how
    target = extract_target(request)
    changes = extract_changes(request)
    {:update, target, changes}
  end

  # Step generators

  defp generate_refactor_steps(target, approach, _context) do
    [
      # Step 1: Analyze current structure
      Step.new_tool(
        "Analyze current code structure",
        "filesystem",
        "analyze_code",
        %{"path" => target, "analysis_type" => "structure"},
        rollback_info: nil
      ),

      # Step 2: Create backup
      Step.new_command(
        "Create backup of #{target}",
        "cp",
        ["-r", target, "#{target}.backup"],
        rollback_info: %{
          type: :restore_backup,
          backup_path: "#{target}.backup"
        }
      ),

      # Step 3: Checkpoint
      Step.new_checkpoint("pre_refactor", save_state: true),

      # Step 4: Apply refactoring
      Step.new_tool(
        "Apply #{approach} refactoring",
        "refactor",
        "apply_refactoring",
        %{
          "path" => target,
          "type" => approach,
          "preview" => false
        },
        rollback_info: %{
          type: :restore_from_checkpoint,
          checkpoint: "pre_refactor"
        },
        prerequisites: ["step_1", "step_2", "step_3"]
      ),

      # Step 5: Run tests
      Step.new_command(
        "Run tests to verify refactoring",
        "mix",
        ["test"],
        prerequisites: ["step_4"]
      ),

      # Step 6: Clean up backup if successful
      Step.new_conditional(
        "Clean up backup if tests pass",
        "step_5.status == :completed",
        "cleanup_backup",
        nil,
        prerequisites: ["step_5"]
      )
    ]
  end

  defp generate_test_steps(target, test_type, _context) do
    [
      # Step 1: Analyze code to test
      Step.new_tool(
        "Analyze #{target} for test generation",
        "filesystem",
        "read_file",
        %{"path" => target}
      ),

      # Step 2: Generate test plan
      Step.new_message(
        "Generate test plan for #{target}",
        "Based on the code analysis, create a comprehensive test plan for #{test_type} testing of #{target}",
        prerequisites: ["step_1"]
      ),

      # Step 3: Create test file
      Step.new_tool(
        "Create test file",
        "filesystem",
        "write_file",
        %{
          "path" => test_file_path(target),
          "content" => "# Generated by plan execution"
        },
        prerequisites: ["step_2"]
      ),

      # Step 4: Generate tests
      Step.new_message(
        "Generate #{test_type} tests",
        "Generate comprehensive #{test_type} tests for the functions in #{target}",
        prerequisites: ["step_3"]
      ),

      # Step 5: Run generated tests
      Step.new_command(
        "Run the generated tests",
        "mix",
        ["test", test_file_path(target)],
        prerequisites: ["step_4"]
      )
    ]
  end

  defp generate_debug_steps(issue, _context_info, _context) do
    [
      # Step 1: Gather diagnostic information
      Step.new_message(
        "Analyze the issue",
        "Analyze this issue: #{issue}. What diagnostic information do we need?"
      ),

      # Step 2: Search for related code
      Step.new_tool(
        "Search for related code",
        "filesystem",
        "search_code",
        %{"query" => issue, "file_types" => [".ex", ".exs"]}
      ),

      # Step 3: Analyze error patterns
      Step.new_message(
        "Identify potential causes",
        "Based on the search results, what are the potential causes of: #{issue}?",
        prerequisites: ["step_2"]
      ),

      # Step 4: Create diagnostic checkpoint
      Step.new_checkpoint("pre_fix", save_state: true),

      # Step 5: Apply fix
      Step.new_message(
        "Generate and apply fix",
        "Generate a fix for the identified issue",
        prerequisites: ["step_3", "step_4"]
      ),

      # Step 6: Verify fix
      Step.new_command(
        "Run tests to verify fix",
        "mix",
        ["test"],
        prerequisites: ["step_5"]
      )
    ]
  end

  defp generate_review_steps(target, focus, _context) do
    [
      Step.new_tool(
        "Read code to review",
        "filesystem",
        "read_file",
        %{"path" => target}
      ),
      Step.new_message(
        "Perform #{focus || "comprehensive"} code review",
        "Review the code focusing on: #{focus || "quality, bugs, performance, and best practices"}",
        prerequisites: ["step_1"]
      ),
      Step.new_message(
        "Generate improvement suggestions",
        "Based on the review, provide specific improvement suggestions with code examples",
        prerequisites: ["step_2"]
      )
    ]
  end

  defp generate_create_steps(artifact, spec, _context) do
    [
      Step.new_message(
        "Design #{artifact}",
        "Design a #{artifact} with these specifications: #{inspect(spec)}"
      ),
      Step.new_tool(
        "Create #{artifact} file",
        "filesystem",
        "write_file",
        %{
          "path" => artifact_path(artifact),
          "content" => "# Generated #{artifact}"
        },
        prerequisites: ["step_1"]
      ),
      Step.new_message(
        "Implement #{artifact}",
        "Implement the designed #{artifact} following best practices",
        prerequisites: ["step_2"]
      )
    ]
  end

  defp generate_update_steps(target, changes, _context) do
    [
      Step.new_tool(
        "Read current version",
        "filesystem",
        "read_file",
        %{"path" => target}
      ),
      Step.new_command(
        "Create backup",
        "cp",
        [target, "#{target}.backup"],
        rollback_info: %{
          type: :restore_file,
          original_path: target,
          backup_path: "#{target}.backup"
        }
      ),
      Step.new_message(
        "Apply updates",
        "Apply these changes to the code: #{inspect(changes)}",
        prerequisites: ["step_1", "step_2"]
      ),
      Step.new_tool(
        "Write updated version",
        "filesystem",
        "write_file",
        %{"path" => target},
        prerequisites: ["step_3"],
        rollback_info: %{
          type: :restore_from_backup,
          backup_path: "#{target}.backup"
        }
      )
    ]
  end

  defp generate_general_steps({:general, request}, _context) do
    [
      Step.new_message(
        "Analyze request",
        "Analyze this request and break it down into steps: #{request}"
      ),
      Step.new_message(
        "Execute request",
        "Based on the analysis, execute the request",
        prerequisites: ["step_1"]
      )
    ]
  end

  # Helper functions

  defp build_plan(description, steps, context) do
    plan =
      Plan.new(description)
      |> Map.put(:context, context)

    # Add steps with proper IDs
    indexed_steps =
      steps
      |> Enum.with_index(1)
      |> Enum.map(fn {step, idx} ->
        %{step | id: "step_#{idx}"}
      end)

    plan_with_steps =
      Enum.reduce(indexed_steps, plan, fn step, acc ->
        Plan.add_step(acc, step)
      end)

    Plan.validate(plan_with_steps)
  end

  defp extract_target(request) do
    # Simple extraction - in real implementation, use NLP
    cond do
      request =~ ~r/module\s+(\w+)/i ->
        [_, module] = Regex.run(~r/module\s+(\w+)/i, request)
        "lib/#{Macro.underscore(module)}.ex"

      request =~ ~r/file\s+([^\s]+)/i ->
        [_, file] = Regex.run(~r/file\s+([^\s]+)/i, request)
        file

      true ->
        "unknown_target"
    end
  end

  defp extract_refactor_approach(request) do
    cond do
      request =~ ~r/extract/i -> "extract_method"
      request =~ ~r/rename/i -> "rename"
      request =~ ~r/inline/i -> "inline"
      request =~ ~r/modular/i -> "modularize"
      true -> "general_refactor"
    end
  end

  defp extract_test_type(request) do
    cond do
      request =~ ~r/unit/i -> "unit"
      request =~ ~r/integration/i -> "integration"
      request =~ ~r/property/i -> "property"
      true -> "comprehensive"
    end
  end

  defp extract_issue(request) do
    # Extract the core issue description
    String.trim(request)
  end

  defp extract_debug_context(request) do
    %{
      has_error_message: request =~ ~r/error/i,
      has_stack_trace: request =~ ~r/stack|trace/i,
      has_line_number: request =~ ~r/line\s+\d+/i
    }
  end

  defp extract_review_focus(request) do
    focuses = []
    focuses = if request =~ ~r/security/i, do: ["security" | focuses], else: focuses
    focuses = if request =~ ~r/performance/i, do: ["performance" | focuses], else: focuses
    focuses = if request =~ ~r/style|convention/i, do: ["style" | focuses], else: focuses
    focuses = if request =~ ~r/bug/i, do: ["bugs" | focuses], else: focuses

    if Enum.empty?(focuses), do: nil, else: Enum.join(focuses, ", ")
  end

  defp extract_artifact_type(request) do
    cond do
      request =~ ~r/module/i -> "module"
      request =~ ~r/function/i -> "function"
      request =~ ~r/test/i -> "test"
      request =~ ~r/config/i -> "config"
      true -> "file"
    end
  end

  defp extract_specifications(request) do
    %{
      raw_request: request,
      has_requirements: request =~ ~r/must|should|need/i,
      has_examples: request =~ ~r/example|like/i
    }
  end

  defp extract_changes(request) do
    %{
      raw_request: request,
      is_addition: request =~ ~r/add/i,
      is_removal: request =~ ~r/remove|delete/i,
      is_modification: request =~ ~r/change|modify|update/i
    }
  end

  defp test_file_path(target) do
    base = Path.basename(target, ".ex")
    dir = Path.dirname(target)

    test_dir =
      if String.starts_with?(dir, "lib/"),
        do: String.replace(dir, "lib/", "test/"),
        else: "test/#{dir}"

    Path.join(test_dir, "#{base}_test.exs")
  end

  defp artifact_path(artifact_type) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    "generated/#{artifact_type}_#{timestamp}.ex"
  end
end
