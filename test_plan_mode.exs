#!/usr/bin/env elixir

# Test Plan Mode functionality
# Run with: elixir test_plan_mode.exs

defmodule TestPlanMode do
  alias MCPChat.PlanMode.{Plan, Step, Parser}
  alias MCPChat.PlanMode.SimpleRenderer, as: Renderer
  
  def run do
    IO.puts """
    
    ==========================================
    🎯 Testing Plan Mode
    ==========================================
    """
    
    # Test 1: Parse a refactor request
    IO.puts "\n1️⃣ Testing plan parsing for refactor request...\n"
    
    request = "refactor the User module to be more modular"
    
    case Parser.parse(request) do
      {:ok, plan} ->
        IO.puts "✅ Successfully parsed plan!"
        IO.puts "\n" <> Renderer.render(plan)
        
      {:error, reason} ->
        IO.puts "❌ Failed to parse: #{inspect(reason)}"
    end
    
    # Test 2: Create a manual plan
    IO.puts "\n\n2️⃣ Testing manual plan creation...\n"
    
    manual_plan = 
      Plan.new("Manual test plan for file operations")
      |> Plan.add_step(
        Step.new_tool(
          "Read configuration file",
          "filesystem",
          "read_file",
          %{"path" => "config/dev.exs"}
        )
      )
      |> Plan.add_step(
        Step.new_command(
          "Create backup",
          "cp",
          ["config/dev.exs", "config/dev.exs.backup"],
          prerequisites: ["step_1"],
          rollback_info: %{
            type: :delete_file,
            path: "config/dev.exs.backup"
          }
        )
      )
      |> Plan.add_step(
        Step.new_message(
          "Analyze configuration",
          "Analyze the configuration and suggest improvements",
          prerequisites: ["step_1"]
        )
      )
      |> Plan.update_status(:pending_approval)
    
    IO.puts Renderer.render(manual_plan)
    
    # Test 3: Show approval options
    IO.puts "\n\n3️⃣ Approval options:\n"
    IO.puts Renderer.render_approval_options()
    
    # Test 4: Test different risk levels
    IO.puts "\n\n4️⃣ Testing risk level rendering...\n"
    
    risky_plan = 
      Plan.new("Dangerous operations demo")
      |> Plan.add_step(
        Step.new_command(
          "Delete temporary files",
          "rm",
          ["-rf", "/tmp/test_*"],
          rollback_info: nil
        )
      )
      |> Plan.update_status(:pending_approval)
    
    IO.puts Renderer.render(risky_plan, verbose: true)
    
    # Test 5: Show step execution progress
    IO.puts "\n\n5️⃣ Testing execution progress rendering...\n"
    
    executing_step = %{
      Step.new_tool("Processing data", "analyzer", "analyze", %{})
      | status: :executing
    }
    
    completed_step = %{
      Step.new_tool("Data processed", "analyzer", "analyze", %{})
      | status: :completed
    }
    
    failed_step = %{
      Step.new_tool("Failed operation", "analyzer", "analyze", %{})
      | status: :failed
    }
    
    IO.puts Renderer.render_progress(executing_step, "Analyzing code structure...")
    IO.puts Renderer.render_progress(completed_step, "Analysis complete")
    IO.puts Renderer.render_progress(failed_step, "Analysis failed: timeout")
    
    IO.puts "\n✨ Plan Mode test complete!"
  end
end

# Ensure required modules are available
Code.require_file("lib/mcp_chat/plan_mode/plan.ex")
Code.require_file("lib/mcp_chat/plan_mode/step.ex")
Code.require_file("lib/mcp_chat/plan_mode/parser.ex")
Code.require_file("lib/mcp_chat/plan_mode/simple_renderer.ex")

# Mock the Colors module if not available
unless Code.ensure_loaded?(MCPChat.CLI.Colors) do
  defmodule MCPChat.CLI.Colors do
    def green(text), do: "\e[32m#{text}\e[0m"
    def red(text), do: "\e[31m#{text}\e[0m"
    def yellow(text), do: "\e[33m#{text}\e[0m"
    def blue(text), do: "\e[34m#{text}\e[0m"
    def cyan(text), do: "\e[36m#{text}\e[0m"
    def magenta(text), do: "\e[35m#{text}\e[0m"
    def bright(text), do: "\e[1m#{text}\e[0m"
    def dim(text), do: "\e[2m#{text}\e[0m"
  end
end

TestPlanMode.run()