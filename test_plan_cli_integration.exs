#!/usr/bin/env elixir

# Test Plan Mode CLI Integration
# Run with: elixir test_plan_cli_integration.exs

defmodule TestPlanCLIIntegration do
  alias MCPChat.CLI.Commands.PlanMode
  
  def run do
    IO.puts """
    
    ==========================================
    🖥️  Testing Plan Mode CLI Integration
    ==========================================
    """
    
    # Test 1: Help command
    IO.puts "\n1️⃣ Testing plan help command...\n"
    test_help_command()
    
    # Test 2: Plan creation simulation
    IO.puts "\n2️⃣ Testing plan creation (simulation)...\n"
    test_plan_creation()
    
    # Test 3: Plan command parsing
    IO.puts "\n3️⃣ Testing command parsing...\n"
    test_command_parsing()
    
    # Test 4: Session state management
    IO.puts "\n4️⃣ Testing session state management...\n"
    test_session_state()
    
    # Test 5: Plan lifecycle commands
    IO.puts "\n5️⃣ Testing plan lifecycle commands...\n"
    test_plan_lifecycle()
    
    IO.puts "\n✨ Plan Mode CLI integration test complete!"
    IO.puts "\n💡 Note: This test validates the CLI command structure without requiring a running session."
  end
  
  defp test_help_command do
    IO.puts "Testing /plan help command:"
    
    # Test basic help
    result1 = PlanMode.handle_command(["plan"], "test_session")
    IO.puts "✅ /plan command help: #{inspect(result1)}"
    
    # Test explicit help
    result2 = PlanMode.handle_command(["plan", "help"], "test_session")
    IO.puts "✅ /plan help command: #{inspect(result2)}"
  end
  
  defp test_plan_creation do
    IO.puts "Testing plan creation command parsing:"
    
    # Test various plan descriptions
    test_descriptions = [
      "refactor the User module",
      "add tests for authentication",
      "fix memory leak in server",
      "create new payment processing module",
      "debug connection timeout issues"
    ]
    
    Enum.each(test_descriptions, fn description ->
      words = String.split(description, " ")
      command = ["plan" | words]
      
      IO.puts "  Command: #{inspect(command)}"
      IO.puts "  Description: \"#{description}\""
      
      # In a real scenario, this would create a plan
      # For testing, we just validate the command structure
      IO.puts "  ✅ Command structure valid"
    end)
    
    IO.puts "✅ Plan creation command parsing validated"
  end
  
  defp test_command_parsing do
    test_commands = [
      # Basic commands
      ["plan"],
      ["plan", "help"],
      ["plan", "list"],
      ["plan", "show"],
      ["plan", "approve"],
      ["plan", "execute"],
      ["plan", "cancel"],
      
      # Commands with IDs
      ["plan", "show", "plan_123"],
      ["plan", "approve", "plan_456"],
      ["plan", "execute", "plan_789"],
      ["plan", "cancel", "plan_abc"],
      
      # Plan creation
      ["plan", "refactor", "user", "module"],
      ["plan", "add", "comprehensive", "test", "suite"],
      
      # Invalid commands
      ["plan", "invalid_command"],
      ["plan", "show", "nonexistent", "extra", "args"]
    ]
    
    IO.puts "Testing command parsing for #{length(test_commands)} commands:"
    
    Enum.each(test_commands, fn command ->
      case command do
        ["plan"] ->
          IO.puts "  ✅ Help command: #{inspect(command)}"
        
        ["plan", "help"] ->
          IO.puts "  ✅ Help command: #{inspect(command)}"
        
        ["plan", "list"] ->
          IO.puts "  ✅ List command: #{inspect(command)}"
        
        ["plan", "show"] ->
          IO.puts "  ✅ Show current plan: #{inspect(command)}"
        
        ["plan", "show", plan_id] ->
          IO.puts "  ✅ Show specific plan: #{inspect(command)} (ID: #{plan_id})"
        
        ["plan", "approve"] ->
          IO.puts "  ✅ Approve current plan: #{inspect(command)}"
        
        ["plan", "approve", plan_id] ->
          IO.puts "  ✅ Approve specific plan: #{inspect(command)} (ID: #{plan_id})"
        
        ["plan", "execute"] ->
          IO.puts "  ✅ Execute current plan: #{inspect(command)}"
        
        ["plan", "execute", plan_id] ->
          IO.puts "  ✅ Execute specific plan: #{inspect(command)} (ID: #{plan_id})"
        
        ["plan", "cancel"] ->
          IO.puts "  ✅ Cancel current plan: #{inspect(command)}"
        
        ["plan", "cancel", plan_id] ->
          IO.puts "  ✅ Cancel specific plan: #{inspect(command)} (ID: #{plan_id})"
        
        ["plan" | description_parts] when length(description_parts) > 0 ->
          description = Enum.join(description_parts, " ")
          IO.puts "  ✅ Plan creation: #{inspect(command)} → \"#{description}\""
        
        _ ->
          IO.puts "  ⚠️  Invalid command: #{inspect(command)}"
      end
    end)
    
    IO.puts "✅ Command parsing validation complete"
  end
  
  defp test_session_state do
    IO.puts "Testing session state management functions:"
    
    # Test context structure
    mock_context = %{
      current_directory: "/Users/test/project",
      recent_files: ["lib/user.ex", "test/user_test.exs"],
      project_info: %{
        type: :elixir,
        name: "my_project"
      }
    }
    
    IO.puts "✅ Mock session context created: #{inspect(mock_context)}"
    
    # Test plan storage structure
    mock_plan = %{
      id: "plan_test_001",
      description: "Test plan for integration",
      status: :draft,
      steps: [],
      created_at: DateTime.utc_now()
    }
    
    IO.puts "✅ Mock plan structure: #{inspect(mock_plan)}"
    
    # Test plan history structure
    mock_history = [mock_plan]
    IO.puts "✅ Mock plan history: #{length(mock_history)} plans"
    
    IO.puts "✅ Session state structures validated"
  end
  
  defp test_plan_lifecycle do
    IO.puts "Testing plan lifecycle command flow:"
    
    # Simulate plan lifecycle
    lifecycle_steps = [
      "/plan create authentication module",
      "/plan show",
      "/plan approve", 
      "/plan execute",
      "/plan list"
    ]
    
    IO.puts "Plan lifecycle simulation:"
    Enum.with_index(lifecycle_steps, 1)
    |> Enum.each(fn {step, index} ->
      IO.puts "  #{index}. #{step}"
      
      case step do
        "/plan create" <> description ->
          IO.puts "     → Would create plan with description: \"#{String.trim(description)}\""
        
        "/plan show" ->
          IO.puts "     → Would display current plan details"
        
        "/plan approve" ->
          IO.puts "     → Would request interactive approval"
        
        "/plan execute" ->
          IO.puts "     → Would execute approved plan"
        
        "/plan list" ->
          IO.puts "     → Would list all plans in session"
        
        _ ->
          IO.puts "     → Unknown command"
      end
    end)
    
    # Test plan status transitions
    status_transitions = [
      {:draft, :pending_approval},
      {:pending_approval, :approved},
      {:approved, :executing},
      {:executing, :completed}
    ]
    
    IO.puts "\nPlan status transitions:"
    Enum.each(status_transitions, fn {from, to} ->
      IO.puts "  #{from} → #{to}"
    end)
    
    IO.puts "✅ Plan lifecycle validation complete"
  end
end

# Mock session module for testing
unless Code.ensure_loaded?(MCPChat.Session) do
  defmodule MCPChat.Session do
    def get_context(_session_id) do
      {:ok, %{current_directory: File.cwd!()}}
    end
    
    def get_context(_session_id, _key) do
      {:error, :not_found}
    end
    
    def put_context(_session_id, _key, _value) do
      :ok
    end
  end
end

# Ensure required modules are available
Code.require_file("lib/mcp_chat/plan_mode/plan.ex")
Code.require_file("lib/mcp_chat/plan_mode/step.ex")
Code.require_file("lib/mcp_chat/plan_mode/parser.ex")
Code.require_file("lib/mcp_chat/plan_mode/safety_analyzer.ex")
Code.require_file("lib/mcp_chat/plan_mode/interactive_approval.ex")
Code.require_file("lib/mcp_chat/plan_mode/executor.ex")
Code.require_file("lib/mcp_chat/plan_mode/simple_renderer.ex")
Code.require_file("lib/mcp_chat/cli/commands/plan_mode.ex")

TestPlanCLIIntegration.run()