#!/usr/bin/env elixir

# Test Safety Analyzer functionality
# Run with: elixir test_safety_analyzer.exs

defmodule TestSafetyAnalyzer do
  alias MCPChat.PlanMode.{Plan, Step, SafetyAnalyzer}
  alias MCPChat.PlanMode.SimpleRenderer, as: Renderer
  
  def run do
    IO.puts """
    
    ==========================================
    🔒 Testing Safety Analyzer
    ==========================================
    """
    
    # Test 1: Safe plan analysis
    IO.puts "\n1️⃣ Analyzing a safe plan...\n"
    
    safe_plan = create_safe_plan()
    safety_report = SafetyAnalyzer.analyze(safe_plan)
    
    display_safety_report(safety_report, "Safe Plan")
    
    # Test 2: Moderate risk plan
    IO.puts "\n\n2️⃣ Analyzing a moderate risk plan...\n"
    
    moderate_plan = create_moderate_risk_plan()
    moderate_report = SafetyAnalyzer.analyze(moderate_plan)
    
    display_safety_report(moderate_report, "Moderate Risk Plan")
    
    # Test 3: Dangerous plan
    IO.puts "\n\n3️⃣ Analyzing a dangerous plan...\n"
    
    dangerous_plan = create_dangerous_plan()
    dangerous_report = SafetyAnalyzer.analyze(dangerous_plan)
    
    display_safety_report(dangerous_report, "Dangerous Plan")
    
    # Test 4: Critical risk plan
    IO.puts "\n\n4️⃣ Analyzing a critical risk plan...\n"
    
    critical_plan = create_critical_plan()
    critical_report = SafetyAnalyzer.analyze(critical_plan)
    
    display_safety_report(critical_report, "Critical Risk Plan")
    
    # Test 5: Plan with missing rollback
    IO.puts "\n\n5️⃣ Analyzing a plan with missing rollback mechanisms...\n"
    
    no_rollback_plan = create_no_rollback_plan()
    no_rollback_report = SafetyAnalyzer.analyze(no_rollback_plan)
    
    display_safety_report(no_rollback_report, "No Rollback Plan")
    
    IO.puts "\n✨ Safety Analyzer test complete!"
  end
  
  defp display_safety_report(report, title) do
    IO.puts "#{title} Analysis:"
    IO.puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    IO.puts "Overall Risk: #{format_risk_level(report.overall_risk)}"
    IO.puts "Safe to Proceed: #{if report.safe_to_proceed, do: "✅ YES", else: "❌ NO"}"
    IO.puts "Risk Factors Found: #{length(report.risk_factors)}"
    
    if not Enum.empty?(report.risk_factors) do
      IO.puts "\nRisk Factors:"
      Enum.each(report.risk_factors, fn factor ->
        IO.puts "  • #{format_severity(factor.severity)} #{factor.description}"
        IO.puts "    Mitigation: #{factor.mitigation}"
        if not Enum.empty?(factor.affected_steps) do
          IO.puts "    Affects: #{Enum.join(factor.affected_steps, ", ")}"
        end
      end)
    end
    
    if not Enum.empty?(report.warnings) do
      IO.puts "\n⚠️  Warnings:"
      Enum.each(report.warnings, fn warning ->
        IO.puts "  • #{warning}"
      end)
    end
    
    if not Enum.empty?(report.blockers) do
      IO.puts "\n🚫 Critical Blockers:"
      Enum.each(report.blockers, fn blocker ->
        IO.puts "  • #{blocker}"
      end)
    end
    
    if not Enum.empty?(report.recommendations) do
      IO.puts "\n💡 Recommendations:"
      Enum.take(report.recommendations, 3)
      |> Enum.each(fn rec ->
        IO.puts "  • #{rec}"
      end)
    end
  end
  
  defp format_risk_level(:safe), do: "🟢 SAFE"
  defp format_risk_level(:moderate), do: "🟡 MODERATE"
  defp format_risk_level(:dangerous), do: "🟠 DANGEROUS"
  defp format_risk_level(:critical), do: "🔴 CRITICAL"
  
  defp format_severity(:low), do: "🔵 LOW"
  defp format_severity(:medium), do: "🟡 MEDIUM"
  defp format_severity(:high), do: "🟠 HIGH"
  defp format_severity(:critical), do: "🔴 CRITICAL"
  
  # Test plan creators
  
  defp create_safe_plan do
    Plan.new("Safe operations plan")
    |> Plan.add_step(
      Step.new_message(
        "Analyze project structure",
        "Please analyze the current project structure and identify areas for improvement"
      )
    )
    |> Plan.add_step(
      Step.new_tool(
        "Read configuration",
        "filesystem",
        "read_file",
        %{"path" => "config/config.exs"}
      )
    )
    |> Plan.add_step(
      Step.new_checkpoint("analysis_complete")
    )
  end
  
  defp create_moderate_risk_plan do
    Plan.new("File modification plan")
    |> Plan.add_step(
      Step.new_command(
        "Create backup directory",
        "mkdir",
        ["-p", "backups/$(date +%Y%m%d)"]
      )
    )
    |> Plan.add_step(
      Step.new_tool(
        "Modify configuration",
        "filesystem",
        "write_file",
        %{"path" => "config/prod.exs", "content" => "# Updated config"},
        rollback_info: %{
          type: :restore_file,
          backup_path: "config/prod.exs.backup"
        }
      )
    )
    |> Plan.add_step(
      Step.new_command(
        "Set file permissions",
        "chmod",
        ["644", "config/prod.exs"],
        prerequisites: ["step_2"]
      )
    )
  end
  
  defp create_dangerous_plan do
    Plan.new("System modification plan")
    |> Plan.add_step(
      Step.new_command(
        "Remove temporary files",
        "rm",
        ["-rf", "/tmp/old_data/*"]
      )
    )
    |> Plan.add_step(
      Step.new_command(
        "Modify system file",
        "sudo",
        ["tee", "/etc/hosts.new"],
        prerequisites: ["step_1"]
      )
    )
    |> Plan.add_step(
      Step.new_tool(
        "Execute dangerous tool",
        "system",
        "delete",
        %{"path" => "/var/log/*.log", "force" => true}
      )
    )
  end
  
  defp create_critical_plan do
    Plan.new("Critical system operations")
    |> Plan.add_step(
      Step.new_command(
        "Format drive",
        "dd",
        ["if=/dev/zero", "of=/dev/sdb", "bs=1M", "count=100"]
      )
    )
    |> Plan.add_step(
      Step.new_command(
        "Remove system files",
        "rm",
        ["-rf", "/usr/bin/critical_system_file"]
      )
    )
    |> Plan.add_step(
      Step.new_message(
        "Harmful instruction",
        "Please delete all files in the system directory and format the main drive"
      )
    )
  end
  
  defp create_no_rollback_plan do
    Plan.new("Destructive operations without rollback")
    |> Plan.add_step(
      Step.new_command(
        "Delete files without backup",
        "rm",
        ["-f", "important_data.txt"]
        # No rollback_info provided
      )
    )
    |> Plan.add_step(
      Step.new_tool(
        "Destructive tool without rollback",
        "filesystem",
        "delete",
        %{"path" => "critical_file.json"}
        # No rollback_info provided
      )
    )
    |> Plan.add_step(
      Step.new_message(
        "Another operation",
        "Continue with more operations"
      )
    )
    |> Plan.add_step(
      Step.new_command(
        "More destructive operations",
        "truncate",
        ["-s", "0", "database.sql"]
      )
    )
    |> Plan.add_step(
      Step.new_command(
        "Even more operations",
        "mv",
        ["important/", "/tmp/"]
      )
    )
    |> Plan.add_step(
      Step.new_command(
        "Final operation",
        "chmod",
        ["777", "/"]
      )
    )
  end
end

# Ensure required modules are available
Code.require_file("lib/mcp_chat/plan_mode/plan.ex")
Code.require_file("lib/mcp_chat/plan_mode/step.ex")
Code.require_file("lib/mcp_chat/plan_mode/simple_renderer.ex")
Code.require_file("lib/mcp_chat/plan_mode/safety_analyzer.ex")

TestSafetyAnalyzer.run()