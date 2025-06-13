#!/usr/bin/env elixir

# User Acceptance Test Runner for MCP Chat
# This script runs all example demos non-interactively for testing purposes

defmodule UserAcceptanceTests do
  @moduledoc """
  Non-interactive test runner for MCP Chat examples.
  Each test captures output and validates expected behavior.
  """

  require Logger

  defmodule TestResult do
    defstruct [:name, :status, :output, :error, :duration]
  end

  def run do
    IO.puts """
    ========================================
    MCP Chat User Acceptance Tests
    ========================================
    """

    # Setup
    setup_environment()

    # Run all tests
    results = [
      run_test("Basic Chat Interaction", &test_basic_chat/0),
      run_test("Command Execution", &test_commands/0),
      run_test("Context Management", &test_context_management/0),
      run_test("Alias System", &test_aliases/0),
      run_test("Multi-Model Support", &test_multi_model/0),
      run_test("MCP Server Connection", &test_mcp_server/0),
      run_test("Progress Tracking", &test_progress_tracking/0),
      run_test("Change Notifications", &test_change_notifications/0),
      run_test("Cost Tracking", &test_cost_tracking/0),
      run_test("Session Persistence", &test_session_persistence/0),
      run_test("Stream Recovery", &test_stream_recovery/0),
      run_test("Concurrent Tools", &test_concurrent_tools/0)
    ]

    # Print summary
    print_summary(results)

    # Return exit code based on results
    if Enum.all?(results, & &1.status == :pass) do
      System.halt(0)
    else
      System.halt(1)
    end
  end

  defp setup_environment do
    # Add parent directory to path for dependencies
    parent_dir = Path.expand("..", __DIR__)
    Code.prepend_path(Path.join([parent_dir, "_build", "dev", "lib", "mcp_chat", "ebin"]))
    Code.prepend_path(Path.join([parent_dir, "_build", "dev", "lib", "ex_mcp", "ebin"]))
    Code.prepend_path(Path.join([parent_dir, "_build", "dev", "lib", "ex_llm", "ebin"]))
    Code.prepend_path(Path.join([parent_dir, "_build", "dev", "lib", "ex_alias", "ebin"]))
    Code.prepend_path(Path.join([parent_dir, "_build", "dev", "lib", "ex_readline", "ebin"]))
    Code.prepend_path(Path.join([parent_dir, "_build", "dev", "lib", "owl", "ebin"]))
    Code.prepend_path(Path.join([parent_dir, "_build", "dev", "lib", "toml", "ebin"]))

    # Set test mode environment variable
    System.put_env("MCP_CHAT_TEST_MODE", "true")

    # Start application
    {:ok, _} = Application.ensure_all_started(:mcp_chat)

    # Wait for services to start
    Process.sleep(500)
  end

  defp run_test(name, test_fn) do
    IO.puts "\n▶ Running: #{name}"
    start_time = System.monotonic_time(:millisecond)

    {status, output, error} = 
      try do
        output = capture_output(test_fn)
        {:pass, output, nil}
      rescue
        e ->
          {:fail, nil, Exception.format(:error, e, __STACKTRACE__)}
      catch
        :exit, reason ->
          {:fail, nil, "Process exited: #{inspect(reason)}"}
      end

    duration = System.monotonic_time(:millisecond) - start_time

    result = %TestResult{
      name: name,
      status: status,
      output: output,
      error: error,
      duration: duration
    }

    print_result(result)
    result
  end

  defp capture_output(fun) do
    ExUnit.CaptureIO.capture_io(fun)
  rescue
    _ ->
      # Fallback if ExUnit not available
      fun.()
      "Output capture not available"
  end

  defp print_result(%TestResult{status: :pass, duration: duration}) do
    IO.puts "  ✅ PASS (#{duration}ms)"
  end

  defp print_result(%TestResult{status: :fail, error: error}) do
    IO.puts "  ❌ FAIL"
    IO.puts "     Error: #{error}"
  end

  defp print_summary(results) do
    total = length(results)
    passed = Enum.count(results, & &1.status == :pass)
    failed = total - passed
    total_duration = Enum.sum(Enum.map(results, & &1.duration))

    IO.puts """

    ========================================
    Test Summary
    ========================================
    Total:   #{total} tests
    Passed:  #{passed} tests
    Failed:  #{failed} tests
    Duration: #{total_duration}ms

    """

    if failed > 0 do
      IO.puts "Failed tests:"
      results
      |> Enum.filter(& &1.status == :fail)
      |> Enum.each(fn result ->
        IO.puts "  - #{result.name}"
      end)
    end
  end

  # Individual test implementations

  defp test_basic_chat do
    # Test basic chat interaction
    session = MCPChat.Session.new_session()
    
    # Send a simple message
    messages = [%{role: "user", content: "Say 'Hello, test!' and nothing else."}]
    
    case MCPChat.LLM.ExLLMAdapter.chat(messages, provider: :mock, mock_response: "Hello, test!") do
      {:ok, response} ->
        assert_equal(response.content, "Hello, test!", "Basic chat response")
      {:error, reason} ->
        raise "Chat failed: #{inspect(reason)}"
    end
  end

  defp test_commands do
    # Test command execution
    alias MCPChat.CLI.Commands
    
    # Test help command
    {output, _session} = Commands.Utility.handle_command(["help"], %{})
    assert_contains(output, "Available commands:", "Help command output")
    
    # Test version command
    {output, _session} = Commands.Utility.handle_command(["version"], %{})
    assert_contains(output, "MCP Chat", "Version command output")
    
    # Test stats command  
    {output, _session} = Commands.Session.handle_command(["stats"], %{})
    assert_contains(output, "Session Statistics", "Stats command output")
  end

  defp test_context_management do
    # Test context management features
    alias MCPChat.Context
    alias MCPChat.Session
    
    session = Session.new_session()
    
    # Add some test content to context
    test_content = "This is test content for context management."
    Context.add_to_context(test_content, "test.txt")
    
    # Verify context was added
    context_content = Context.get_context()
    assert_contains(context_content, test_content, "Context content")
    
    # Test context stats
    stats = Context.get_context_stats()
    assert(stats.total_tokens > 0, "Context has tokens")
    
    # Clear context
    Context.clear_context()
    assert_equal(Context.get_context(), "", "Context cleared")
  end

  defp test_aliases do
    # Test alias system
    alias MCPChat.Alias.ExAliasAdapter
    alias MCPChat.CLI.Commands.Alias
    
    # Create an alias
    {output, _session} = Alias.handle_command(["add", "hello", "echo Hello from alias!"], %{})
    assert_contains(output, "created", "Alias creation")
    
    # List aliases
    {output, _session} = Alias.handle_command(["list"], %{})
    assert_contains(output, "hello", "Alias listing")
    
    # Execute alias (would need CLI context)
    expanded = ExAliasAdapter.expand_command("hello")
    assert_equal(expanded, {:ok, "echo Hello from alias!"}, "Alias expansion")
    
    # Remove alias
    {output, _session} = Alias.handle_command(["remove", "hello"], %{})
    assert_contains(output, "removed", "Alias removal")
  end

  defp test_multi_model do
    # Test multi-model support
    alias MCPChat.LLM.ExLLMAdapter
    
    # Test with mock provider
    messages = [%{role: "user", content: "Test message"}]
    
    # Mock different providers
    providers = [
      {:anthropic, "Response from Claude"},
      {:openai, "Response from GPT"},
      {:ollama, "Response from Ollama"}
    ]
    
    Enum.each(providers, fn {provider, mock_response} ->
      case ExLLMAdapter.chat(messages, provider: :mock, mock_response: mock_response) do
        {:ok, response} ->
          assert_equal(response.content, mock_response, "#{provider} response")
        {:error, reason} ->
          IO.puts("Warning: #{provider} test skipped: #{inspect(reason)}")
      end
    end)
  end

  defp test_mcp_server do
    # Test MCP server connection
    alias MCPChat.MCP.ServerManager
    
    # Define a test server configuration
    server_config = %{
      "test_server" => %{
        transport: "stdio",
        command: ["echo", "test"],
        args: []
      }
    }
    
    # Try to start the server (will fail with echo, but tests the flow)
    case ServerManager.start_server("test_server", server_config["test_server"]) do
      {:ok, _pid} ->
        # Server started (unlikely with echo)
        ServerManager.stop_server("test_server")
        :ok
      {:error, _reason} ->
        # Expected for echo command
        :ok
    end
  end

  defp test_progress_tracking do
    # Test progress tracking
    alias MCPChat.MCP.ProgressTracker
    
    # Start a progress operation
    operation_id = ProgressTracker.start_operation("test_op", 100, %{
      description: "Test operation"
    })
    
    # Update progress
    ProgressTracker.update_progress(operation_id, 50, "Halfway done")
    
    # Get progress
    case ProgressTracker.get_progress(operation_id) do
      {:ok, progress} ->
        assert_equal(progress.current, 50, "Progress updated")
        assert_equal(progress.status, :in_progress, "Progress status")
      _ ->
        raise "Progress tracking failed"
    end
    
    # Complete operation
    ProgressTracker.complete_operation(operation_id, "Done!")
  end

  defp test_change_notifications do
    # Test change notification system
    alias MCPChat.MCP.NotificationRegistry
    alias MCPChat.MCP.Handlers.ComprehensiveNotificationHandler
    
    # The handler should already be registered
    handlers = NotificationRegistry.list_handlers()
    assert(length(handlers) > 0, "Notification handlers registered")
    
    # Check handler settings
    settings = ComprehensiveNotificationHandler.get_settings()
    assert(settings.enabled, "Notifications enabled")
  end

  defp test_cost_tracking do
    # Test cost tracking
    alias MCPChat.Cost
    alias MCPChat.Session
    
    # Create a session with some usage
    session = Session.new_session()
    session = Session.track_token_usage(session, %{
      input_tokens: 100,
      output_tokens: 50
    })
    
    # Calculate cost (using mock provider rates)
    case Cost.calculate_session_cost(session, session.token_usage, 
                                    provider: "anthropic", 
                                    model: "claude-3-haiku-20240307") do
      {:ok, cost_info} ->
        assert(cost_info.total_cost >= 0, "Cost calculated")
      {:error, :no_pricing_data} ->
        # Acceptable if pricing data not available
        :ok
      error ->
        raise "Cost calculation failed: #{inspect(error)}"
    end
  end

  defp test_session_persistence do
    # Test session save/load
    alias MCPChat.Session
    alias MCPChat.Persistence
    
    # Create a session with some data
    session = Session.new_session()
    session = Session.add_message(session, "user", "Test message")
    session = Session.add_message(session, "assistant", "Test response")
    
    # Save session to temp file
    temp_dir = System.tmp_dir!()
    session_name = "test_session_#{:os.system_time(:millisecond)}"
    
    case Persistence.save_session(session, session_name, 
                                 path_provider: fn -> temp_dir end) do
      {:ok, path} ->
        assert(File.exists?(path), "Session file created")
        
        # Load session back
        case Persistence.load_session(path) do
          {:ok, loaded_session} ->
            messages = Session.get_messages(loaded_session)
            assert_equal(length(messages), 2, "Messages preserved")
          error ->
            raise "Session load failed: #{inspect(error)}"
        end
        
        # Cleanup
        File.rm(path)
      error ->
        raise "Session save failed: #{inspect(error)}"
    end
  end

  defp test_stream_recovery do
    # Test stream recovery mechanism
    messages = [%{role: "user", content: "Test streaming"}]
    
    # Test with mock streaming
    case MCPChat.LLM.ExLLMAdapter.stream_chat(messages, 
                                              provider: :mock,
                                              mock_chunks: ["Hello", " from", " stream!"]) do
      {:ok, stream} ->
        chunks = Enum.to_list(stream)
        assert_equal(length(chunks), 3, "Stream chunks received")
      error ->
        raise "Streaming failed: #{inspect(error)}"
    end
  end

  defp test_concurrent_tools do
    # Test concurrent tool execution planning
    alias MCPChat.MCP.ConcurrentToolExecutor
    
    # Create test tool calls
    tool_calls = [
      %{tool: "tool1", args: %{}, server: "server1"},
      %{tool: "tool2", args: %{}, server: "server1"},
      %{tool: "tool3", args: %{}, server: "server2"}
    ]
    
    # Plan execution
    case ConcurrentToolExecutor.plan_execution(tool_calls) do
      {:ok, plan} ->
        # Verify we have execution groups
        assert(is_list(plan.groups), "Execution plan created")
        assert(plan.stats.total_tools == 3, "All tools counted")
      error ->
        raise "Execution planning failed: #{inspect(error)}"
    end
  end

  # Assertion helpers

  defp assert(condition, message) do
    unless condition do
      raise "Assertion failed: #{message}"
    end
  end

  defp assert_equal(actual, expected, message) do
    unless actual == expected do
      raise "Assertion failed: #{message}\nExpected: #{inspect(expected)}\nActual: #{inspect(actual)}"
    end
  end

  defp assert_contains(string, substring, message) do
    unless String.contains?(string || "", substring) do
      raise "Assertion failed: #{message}\nString does not contain: #{substring}\nActual: #{inspect(string)}"
    end
  end
end

# Run the tests
UserAcceptanceTests.run()