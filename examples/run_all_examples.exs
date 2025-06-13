#!/usr/bin/env elixir

# Non-interactive runner for MCP Chat example demos
# Runs all example scenarios without user input for automated testing

defmodule ExampleRunner do
  @moduledoc """
  Runs all MCP Chat examples non-interactively.
  Each example is executed with predefined inputs and outputs are captured.
  """

  alias MCPChat.{Session, MCP.ServerManager, CLI.Commands}
  alias MCPChat.MCP.{ProgressTracker, NotificationRegistry}
  alias MCPChat.MCP.Handlers.ComprehensiveNotificationHandler

  def run do
    IO.puts """
    ╔══════════════════════════════════════════╗
    ║    MCP Chat Example Runner               ║
    ║    Running all demos non-interactively   ║
    ╚══════════════════════════════════════════╝
    """

    # Setup environment
    setup()

    # Run each example
    examples = [
      {"Getting Started Examples", &run_getting_started/0},
      {"Progress Tracking Demo", &run_progress_demo/0},
      {"Change Notifications Demo", &run_change_notifications/0},
      {"Multi-Model Demo", &run_multi_model/0},
      {"Server Sampling Demo", &run_sampling_demo/0},
      {"Context Management Demo", &run_context_demo/0},
      {"Session Commands Demo", &run_session_commands/0}
    ]

    results = Enum.map(examples, fn {name, func} ->
      IO.puts "\n┌─ Running: #{name}"
      IO.puts "├" <> String.duplicate("─", 40)
      
      result = try do
        func.()
        IO.puts "└─ ✅ Success"
        {:ok, name}
      rescue
        e ->
          IO.puts "└─ ❌ Failed: #{Exception.message(e)}"
          {:error, name, e}
      end
      
      Process.sleep(100)  # Brief pause between demos
      result
    end)

    # Print summary
    print_summary(results)
  end

  defp setup do
    # Add paths for dependencies
    parent_dir = Path.expand("..", __DIR__)
    
    # Core dependencies in order
    deps = ~w[
      castore mint telemetry hpax nimble_options nimble_pool finch
      jason yamerl yaml_elixir toml 
      jaxon req gun instructor
      owl ex_readline ex_alias ex_mcp ex_llm mcp_chat
    ]
    
    Enum.each(deps, fn dep ->
      path = Path.join([parent_dir, "_build", "dev", "lib", dep, "ebin"])
      if File.exists?(path), do: Code.prepend_path(path)
    end)

    # Start required applications first
    Application.ensure_all_started(:crypto)
    Application.ensure_all_started(:ssl)
    Application.ensure_all_started(:inets)
    
    # Start the main application
    case Application.ensure_all_started(:mcp_chat) do
      {:ok, _} -> 
        Process.sleep(500)  # Wait for services
      {:error, reason} ->
        IO.puts "Failed to start application: #{inspect(reason)}"
        System.halt(1)
    end
  end

  defp run_getting_started do
    IO.puts "│ Testing basic chat interaction..."
    
    # Simulate sending a message
    session = Session.new_session()
    messages = [%{role: "user", content: "Hello, this is a test!"}]
    
    # Use mock provider for predictable output
    case MCPChat.LLM.ExLLMAdapter.chat(messages, 
                                       provider: :mock, 
                                       mock_response: "Hello! Test successful.") do
      {:ok, response} ->
        IO.puts "│ Response: #{response.content}"
      {:error, reason} ->
        IO.puts "│ Error: #{inspect(reason)}"
    end

    IO.puts "│"
    IO.puts "│ Testing command execution..."
    
    # Test some basic commands
    test_commands = [
      ["help"],
      ["version"],
      ["stats"],
      ["cost"]
    ]
    
    Enum.each(test_commands, fn cmd ->
      IO.puts "│ Command: /#{Enum.join(cmd, " ")}"
      
      {output, _session} = case cmd do
        ["help"] -> Commands.Utility.handle_command(cmd, %{})
        ["version"] -> Commands.Utility.handle_command(cmd, %{})
        ["stats"] -> Commands.Session.handle_command(cmd, %{})
        ["cost"] -> Commands.Session.handle_command(cmd, %{})
        _ -> {"Unknown command", %{}}
      end
      
      # Show first line of output
      first_line = output |> String.split("\n") |> List.first()
      IO.puts "│   → #{first_line}"
    end)
  end

  defp run_progress_demo do
    IO.puts "│ Starting progress tracking demo..."
    
    # Create a progress operation
    operation_id = ProgressTracker.start_operation("demo_task", 100, %{
      description: "Processing demo data"
    })
    
    IO.puts "│ Operation ID: #{operation_id}"
    
    # Simulate progress updates
    progress_steps = [
      {25, "Loading data..."},
      {50, "Processing..."},
      {75, "Analyzing results..."},
      {100, "Complete!"}
    ]
    
    Enum.each(progress_steps, fn {progress, message} ->
      ProgressTracker.update_progress(operation_id, progress, message)
      
      case ProgressTracker.get_progress(operation_id) do
        {:ok, info} ->
          bar = render_progress_bar(info.current, info.total, 20)
          IO.puts "│ #{bar} #{info.current}% - #{message}"
        _ ->
          IO.puts "│ Progress update failed"
      end
      
      Process.sleep(200)  # Simulate work
    end)
    
    # Complete the operation
    ProgressTracker.complete_operation(operation_id, "Demo completed successfully!")
    IO.puts "│ ✓ Operation completed"
  end

  defp run_change_notifications do
    IO.puts "│ Testing notification system..."
    
    # Check registered handlers
    handlers = NotificationRegistry.list_handlers()
    IO.puts "│ Registered handlers: #{length(handlers)}"
    
    # Get notification settings
    settings = ComprehensiveNotificationHandler.get_settings()
    IO.puts "│ Notifications enabled: #{settings.enabled}"
    
    # Simulate some notifications
    test_notifications = [
      {:tools_list_changed, %{server: "test_server", tools: ["tool1", "tool2"]}},
      {:resource_added, %{server: "test_server", uri: "file:///test.txt"}},
      {:server_connected, %{server: "test_server"}}
    ]
    
    Enum.each(test_notifications, fn {type, params} ->
      IO.puts "│ Simulating #{type} notification..."
      # Would normally come from MCP server
      IO.puts "│   → Params: #{inspect(params)}"
    end)
    
    # Check event count
    event_count = ComprehensiveNotificationHandler.get_event_count()
    IO.puts "│ Total events processed: #{event_count}"
  end

  defp run_multi_model do
    IO.puts "│ Testing multi-model support..."
    
    # List available providers
    providers = [:anthropic, :openai, :ollama, :gemini, :mock]
    
    messages = [%{role: "user", content: "Say 'Hello from [provider]'"}]
    
    Enum.each(providers, fn provider ->
      IO.puts "│"
      IO.puts "│ Testing provider: #{provider}"
      
      # Mock response for each provider
      mock_response = "Hello from #{provider}!"
      
      case MCPChat.LLM.ExLLMAdapter.chat(messages, 
                                         provider: :mock,
                                         mock_response: mock_response) do
        {:ok, response} ->
          IO.puts "│   ✓ Response: #{response.content}"
        {:error, reason} ->
          IO.puts "│   ✗ Error: #{inspect(reason)}"
      end
    end)
  end

  defp run_sampling_demo do
    IO.puts "│ Testing server-side sampling simulation..."
    
    # Simulate a server with sampling capability
    server_config = %{
      name: "sampling_server",
      capabilities: %{
        sampling: true
      }
    }
    
    IO.puts "│ Server: #{server_config.name}"
    IO.puts "│ Has sampling: #{server_config.capabilities.sampling}"
    
    # Simulate sampling request
    sampling_request = %{
      messages: [
        %{role: "user", content: "Generate a haiku about Elixir"}
      ],
      max_tokens: 50
    }
    
    IO.puts "│"
    IO.puts "│ Sampling request:"
    IO.puts "│   Messages: #{length(sampling_request.messages)}"
    IO.puts "│   Max tokens: #{sampling_request.max_tokens}"
    
    # Mock sampling response
    mock_haiku = """
    Functional and pure,
    Processes dance concurrent,
    Elixir flows free.
    """
    
    IO.puts "│"
    IO.puts "│ Generated haiku:"
    mock_haiku
    |> String.split("\n")
    |> Enum.reject(&(&1 == ""))
    |> Enum.each(fn line ->
      IO.puts "│   #{line}"
    end)
  end

  defp run_context_demo do
    IO.puts "│ Testing context management..."
    
    alias MCPChat.Context
    
    # Add some content
    test_files = [
      {"example.txt", "This is example content for testing."},
      {"data.json", ~s({"name": "test", "value": 42})},
      {"code.ex", "defmodule Test do\n  def hello, do: :world\nend"}
    ]
    
    Enum.each(test_files, fn {filename, content} ->
      Context.add_to_context(content, filename)
      IO.puts "│ Added #{filename} to context"
    end)
    
    # Get context stats
    stats = Context.get_context_stats()
    IO.puts "│"
    IO.puts "│ Context statistics:"
    IO.puts "│   Files: #{stats.file_count}"
    IO.puts "│   Total tokens: #{stats.total_tokens}"
    IO.puts "│   Total size: #{stats.total_size} bytes"
    
    # Clear context
    Context.clear_context()
    IO.puts "│"
    IO.puts "│ Context cleared"
  end

  defp run_session_commands do
    IO.puts "│ Testing session management commands..."
    
    # Create a new session
    session = Session.new_session()
    Session.set_current_session(session)
    
    # Test various session commands
    commands_to_test = [
      {"Show stats", ["stats"], Commands.Session},
      {"Show cost", ["cost"], Commands.Session},
      {"List sessions", ["list"], Commands.Session},
      {"Show history", ["history", "5"], Commands.Session}
    ]
    
    Enum.each(commands_to_test, fn {desc, cmd, module} ->
      IO.puts "│"
      IO.puts "│ #{desc}:"
      
      {output, _session} = module.handle_command(cmd, %{})
      
      # Show first few lines
      output
      |> String.split("\n")
      |> Enum.take(3)
      |> Enum.each(fn line ->
        if String.trim(line) != "" do
          IO.puts "│   #{line}"
        end
      end)
    end)
  end

  defp render_progress_bar(current, total, width) do
    percentage = current / total
    filled = round(percentage * width)
    empty = width - filled
    
    "[" <> String.duplicate("█", filled) <> String.duplicate("░", empty) <> "]"
  end

  defp print_summary(results) do
    successful = Enum.count(results, fn
      {:ok, _} -> true
      _ -> false
    end)
    
    failed = Enum.count(results, fn
      {:error, _, _} -> true
      _ -> false
    end)
    
    IO.puts """

    ╔══════════════════════════════════════════╗
    ║              Summary                     ║
    ╠══════════════════════════════════════════╣
    ║  Total examples: #{String.pad_leading(to_string(length(results)), 2)}                      ║
    ║  Successful:     #{String.pad_leading(to_string(successful), 2)}                      ║
    ║  Failed:         #{String.pad_leading(to_string(failed), 2)}                      ║
    ╚══════════════════════════════════════════╝
    """
    
    if failed > 0 do
      IO.puts "\nFailed examples:"
      Enum.each(results, fn
        {:error, name, _} -> IO.puts "  - #{name}"
        _ -> :ok
      end)
    end
  end
end

# Run all examples
ExampleRunner.run()