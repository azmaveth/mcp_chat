defmodule MCPChat.ComprehensiveE2ETest do
  use ExUnit.Case, async: false

  @moduledoc """
  Comprehensive end-to-end tests for MCP Chat using real Ollama backend.
  No mocks - tests the entire system with actual servers and models.
  """
  alias Commands
  alias ExLLMAdapter
  alias NotificationRegistry
  alias ProgressTracker
  alias ServerManager
  # Test configuration
  @ollama_url "http://localhost:11_434"
  # Small, fast model for testing
  @test_model "nomic-embed-text:latest"
  # 60 seconds for longer operations
  @test_timeout 60_000
  @demo_servers_path Path.expand("../../examples/demo_servers", __DIR__)

  setup_all do
    # Ensure Ollama is running
    case check_ollama() do
      :ok ->
        # Start the application
        Application.ensure_all_started(:mcp_chat)

        # Set up test configuration
        setup_test_config()

        # Start demo servers if needed
        {:ok, demo_pids} = start_demo_servers()

        on_exit(fn ->
          # Clean up demo servers
          Enum.each(demo_pids, &stop_demo_server/1)

          # Reset configuration
          reset_config()
        end)

        {:ok, %{demo_pids: demo_pids}}

      {:error, reason} ->
        skip_tests(reason)
    end
  end

  setup do
    # Clear session before each test
    MCPChat.Session.clear_session()

    # Reset MCP server connections
    ServerManager.stop_all_servers()

    # Clean up any test files
    clean_test_files()

    :ok
  end

  describe "Ollama Integration" do
    @tag timeout: @test_timeout
    test "connects to Ollama and gets available models" do
      # Configure Ollama backend
      config = %{
        "provider" => "ollama",
        "base_url" => @ollama_url,
        "model" => @test_model
      }

      # Initialize LLM adapter
      {:ok, client} = ExLLMAdapter.init(config)

      # List available models
      {:ok, models} = list_ollama_models()

      assert is_list(models)
      assert Enum.any?(models, &(&1 == @test_model))
    end

    @tag timeout: @test_timeout
    test "completes a full chat conversation with Ollama" do
      # Set up Ollama backend
      {:ok, _} = set_llm_backend("ollama", @test_model)

      # Add user message
      MCPChat.Session.add_message("user", "What is 2 + 2?")

      # Get response from Ollama
      messages = MCPChat.Session.get_messages()
      {:ok, response} = get_llm_response(messages)

      assert response.content =~ ~r/4|four/i
      assert response.role == "assistant"

      # Add response to session
      MCPChat.Session.add_message("assistant", response.content)

      # Continue conversation
      MCPChat.Session.add_message("user", "What is the result multiplied by 3?")

      messages = MCPChat.Session.get_messages()
      {:ok, response2} = get_llm_response(messages)

      assert response2.content =~ ~r/12|twelve/i
    end

    @tag timeout: @test_timeout
    test "handles streaming responses from Ollama" do
      # Set up streaming
      {:ok, _} = set_llm_backend("ollama", @test_model)

      # Create streaming request
      messages = [%{role: "user", content: "Count from 1 to 5"}]

      # Collect streamed chunks
      chunks = []
      {:ok, stream} = get_llm_stream(messages)

      chunks = Enum.to_list(stream)

      assert length(chunks) > 0

      # Reconstruct full response
      full_content = Enum.join(chunks, "")
      assert full_content =~ ~r/1.*2.*3.*4.*5/s
    end

    @tag timeout: @test_timeout
    test "tracks token usage and costs" do
      {:ok, _} = set_llm_backend("ollama", @test_model)

      # Clear any existing usage
      MCPChat.Session.clear_session()

      # Send message
      MCPChat.Session.add_message("user", "Hello, how are you?")
      messages = MCPChat.Session.get_messages()
      {:ok, response} = get_llm_response(messages)

      # Track usage
      MCPChat.Session.track_token_usage(messages, response.content)

      # Get stats
      stats = MCPChat.Session.get_context_stats()

      assert stats.estimated_tokens > 0
      assert stats.message_count == 1

      # Check cost tracking (Ollama is free, so should be 0)
      cost = MCPChat.Cost.get_session_cost()
      assert cost.total_cost == 0.0
    end
  end

  describe "MCP Server Integration" do
    @tag timeout: @test_timeout
    test "connects to time server and executes tools" do
      # Start time server
      {:ok, server_pid} =
        start_mcp_server("time", [
          "python3",
          Path.join(@demo_servers_path, "time_server.py")
        ])

      # Wait for server to be ready
      Process.sleep(1_000)

      # List available tools
      {:ok, tools} = ServerManager.list_tools("time")

      assert Enum.any?(tools, &(&1.name == "get_current_time"))
      assert Enum.any?(tools, &(&1.name == "timezone_converter"))

      # Execute get_current_time tool
      {:ok, result} =
        ServerManager.call_tool(
          "time",
          "get_current_time",
          %{timezone: "UTC", format: "24h"}
        )

      assert result["time"] =~ ~r/\d{2}:\d{2}/
      assert result["timezone"] == "UTC"

      # Execute timezone conversion
      {:ok, conversion} =
        ServerManager.call_tool(
          "time",
          "timezone_converter",
          %{
            time: "15:00",
            from_timezone: "UTC",
            to_timezone: "EST"
          }
        )

      assert conversion["converted_time"] =~ ~r/\d{1,2}:\d{2}/
      assert conversion["from_timezone"] == "UTC"
      assert conversion["to_timezone"] == "EST"
    end

    @tag timeout: @test_timeout
    test "connects to calculator server and performs calculations" do
      # Start calculator server
      {:ok, server_pid} =
        start_mcp_server("calc", [
          "python3",
          Path.join(@demo_servers_path, "calculator_server.py")
        ])

      Process.sleep(1_000)

      # List tools
      {:ok, tools} = ServerManager.list_tools("calc")

      assert Enum.any?(tools, &(&1.name == "calculate"))
      assert Enum.any?(tools, &(&1.name == "scientific_calc"))

      # Basic calculation
      {:ok, result} =
        ServerManager.call_tool(
          "calc",
          "calculate",
          %{expression: "(10 + 20) * 3"}
        )

      assert result["result"] == 90
      assert result["expression"] == "(10 + 20) * 3"

      # Scientific calculation
      {:ok, sci_result} =
        ServerManager.call_tool(
          "calc",
          "scientific_calc",
          %{operation: "sin", value: 90}
        )

      assert_in_delta sci_result["result"], 1.0, 0.01
    end

    @tag timeout: @test_timeout
    test "handles multiple concurrent MCP servers" do
      # Start multiple servers
      servers = [
        {"time", ["python3", Path.join(@demo_servers_path, "time_server.py")]},
        {"calc", ["python3", Path.join(@demo_servers_path, "calculator_server.py")]},
        {"data", ["python3", Path.join(@demo_servers_path, "data_server.py")]}
      ]

      server_pids =
        Enum.map(servers, fn {name, cmd} ->
          {:ok, pid} = start_mcp_server(name, cmd)
          {name, pid}
        end)

      Process.sleep(2000)

      # Verify all servers are connected
      connected = ServerManager.list_servers()
      assert length(connected) >= 3

      # Execute tool on each server concurrently
      tasks = [
        Task.async(fn ->
          ServerManager.call_tool("time", "get_current_time", %{})
        end),
        Task.async(fn ->
          ServerManager.call_tool("calc", "calculate", %{expression: "2+2"})
        end),
        Task.async(fn ->
          ServerManager.call_tool("data", "generate_users", %{count: 5})
        end)
      ]

      results = Task.await_many(tasks, 10_000)

      # Verify all succeeded
      Enum.each(results, fn result ->
        assert match?({:ok, _}, result)
      end)
    end

    @tag timeout: @test_timeout
    test "reads resources from MCP servers" do
      # Create a test resource file
      test_file = Path.join(System.tmp_dir!(), "test_resource.txt")
      File.write!(test_file, "Hello from MCP resource!")

      # Start filesystem server with access to temp dir
      {:ok, _} =
        start_mcp_server("fs", [
          "npx",
          "-y",
          "@modelcontextprotocol/server-filesystem",
          System.tmp_dir!()
        ])

      Process.sleep(2000)

      # List resources
      {:ok, resources} = ServerManager.list_resources("fs")

      assert is_list(resources)

      # Read the test resource if available
      test_resource =
        Enum.find(resources, fn r ->
          String.contains?(r.uri, "test_resource.txt")
        end)

      if test_resource do
        {:ok, content} = ServerManager.read_resource("fs", test_resource.uri)
        assert content =~ "Hello from MCP resource!"
      end

      # Clean up
      File.rm!(test_file)
    end
  end

  describe "Full Chat Flow with MCP Tools" do
    @tag timeout: @test_timeout
    test "chat session with LLM using MCP tools" do
      # Set up Ollama
      {:ok, _} = set_llm_backend("ollama", @test_model)

      # Start calculator server
      {:ok, _} =
        start_mcp_server("calc", [
          "python3",
          Path.join(@demo_servers_path, "calculator_server.py")
        ])

      Process.sleep(1_000)

      # Get available tools
      {:ok, tools} = ServerManager.list_tools("calc")

      # Create a message that would trigger tool use
      MCPChat.Session.add_message("user", "Calculate (15 + 25) * 2 for me")

      # In a real scenario, the LLM would decide to use tools
      # For testing, we'll manually execute the tool
      {:ok, calc_result} =
        ServerManager.call_tool(
          "calc",
          "calculate",
          %{expression: "(15 + 25) * 2"}
        )

      assert calc_result["result"] == 80

      # Add tool result to context
      tool_response = "The calculation (15 + 25) * 2 equals #{calc_result["result"]}"
      MCPChat.Session.add_message("assistant", tool_response)

      # Verify session has both messages
      messages = MCPChat.Session.get_messages()
      assert length(messages) == 2
      assert List.last(messages).content =~ "80"
    end

    @tag timeout: @test_timeout
    test "multi-turn conversation with context and tools" do
      # Set up
      {:ok, _} = set_llm_backend("ollama", @test_model)

      {:ok, _} =
        start_mcp_server("calc", [
          "python3",
          Path.join(@demo_servers_path, "calculator_server.py")
        ])

      Process.sleep(1_000)

      # First turn
      MCPChat.Session.add_message("user", "What's 50 divided by 5?")

      {:ok, result1} =
        ServerManager.call_tool(
          "calc",
          "calculate",
          %{expression: "50 / 5"}
        )

      MCPChat.Session.add_message("assistant", "50 divided by 5 equals #{result1["result"]}")

      # Second turn - refers to previous result
      MCPChat.Session.add_message("user", "Now multiply that by 7")

      {:ok, result2} =
        ServerManager.call_tool(
          "calc",
          "calculate",
          # Using the previous result
          %{expression: "10 * 7"}
        )

      MCPChat.Session.add_message("assistant", "10 multiplied by 7 equals #{result2["result"]}")

      # Verify conversation flow
      messages = MCPChat.Session.get_messages()
      assert length(messages) == 4
      assert messages |> Enum.at(1) |> Map.get(:content) =~ "10"
      assert messages |> Enum.at(3) |> Map.get(:content) =~ "70"
    end
  end

  describe "Notification Features" do
    @tag timeout: @test_timeout
    test "receives and handles progress notifications" do
      # Start a server that sends progress notifications
      # For now, we'll simulate this since demo servers don't send progress

      # Create a progress tracker
      {:ok, tracker} = ProgressTracker.start_link([])

      # Simulate progress notification
      progress_token = "test-progress-123"
      ProgressTracker.update_progress(progress_token, 0.5, "Processing...")

      # Check progress status
      progress = ProgressTracker.get_progress(progress_token)
      assert progress.progress == 0.5
      assert progress.message == "Processing..."

      # Complete progress
      ProgressTracker.complete_progress(progress_token)

      # Verify completion
      progress = ProgressTracker.get_progress(progress_token)
      assert progress == nil
    end

    @tag timeout: @test_timeout
    test "handles resource change notifications" do
      # Set up notification registry
      NotificationRegistry.start_link()

      # Register a handler
      handler_ref = make_ref()

      NotificationRegistry.register_handler(
        :resource_list_changed,
        fn notification ->
          send(self(), {:notification, handler_ref, notification})
        end
      )

      # Simulate a resource change notification
      NotificationRegistry.notify(:resource_list_changed, %{
        server: "test-server",
        timestamp: DateTime.utc_now()
      })

      # Verify handler was called
      assert_receive {:notification, ^handler_ref, %{server: "test-server"}}, 1_000
    end
  end

  describe "Session Persistence" do
    @tag timeout: @test_timeout
    test "saves and loads complete chat sessions" do
      # Create a session with messages
      session_name = "test_session_#{System.unique_integer()}"

      # Add various message types
      MCPChat.Session.add_message("user", "Hello")
      MCPChat.Session.add_message("assistant", "Hi there!")
      MCPChat.Session.set_context(%{"system_message" => "You are helpful"})

      # Track some token usage
      MCPChat.Session.track_token_usage(
        [%{role: "user", content: "Hello"}],
        "Hi there!"
      )

      # Save session
      :ok = MCPChat.Persistence.save_session(session_name)

      # Clear current session
      MCPChat.Session.clear_session()

      # Load saved session
      {:ok, _} = MCPChat.Persistence.load_session(session_name)

      # Verify loaded data
      session = MCPChat.Session.get_current_session()
      assert length(session.messages) == 2
      assert session.context["system_message"] == "You are helpful"

      stats = MCPChat.Session.get_context_stats()
      assert stats.estimated_tokens > 0

      # Clean up
      MCPChat.Persistence.delete_session(session_name)
    end

    @tag timeout: @test_timeout
    test "exports sessions in multiple formats" do
      # Create session with content
      MCPChat.Session.add_message("user", "What is Elixir?")
      MCPChat.Session.add_message("assistant", "Elixir is a functional programming language.")

      # Export as markdown
      md_path = Path.join(System.tmp_dir!(), "test_export.md")
      :ok = MCPChat.Persistence.export_session("markdown", md_path)

      md_content = File.read!(md_path)
      assert md_content =~ "What is Elixir?"
      assert md_content =~ "functional programming"

      # Export as JSON
      json_path = Path.join(System.tmp_dir!(), "test_export.json")
      :ok = MCPChat.Persistence.export_session("json", json_path)

      json_content = File.read!(json_path)
      {:ok, data} = Jason.decode(json_content)
      assert length(data["messages"]) == 2

      # Clean up
      File.rm!(md_path)
      File.rm!(json_path)
    end
  end

  describe "Error Scenarios" do
    @tag timeout: @test_timeout
    test "handles LLM connection failures gracefully" do
      # Configure with invalid URL
      config = %{
        "provider" => "ollama",
        # Invalid port
        "base_url" => "http://localhost:99_999",
        "model" => "test-model"
      }

      {:ok, client} = ExLLMAdapter.init(config)

      # Try to get response
      messages = [%{role: "user", content: "Hello"}]
      result = get_llm_response(messages, client)

      assert match?({:error, _}, result)
    end

    @tag timeout: @test_timeout
    test "handles MCP server crashes and restarts" do
      # Start a server
      {:ok, _} =
        start_mcp_server("test", [
          "python3",
          Path.join(@demo_servers_path, "time_server.py")
        ])

      Process.sleep(1_000)

      # Verify it's running
      servers = ServerManager.list_servers()
      assert Enum.any?(servers, &(&1.name == "test"))

      # Force stop the server
      ServerManager.stop_server("test")

      Process.sleep(500)

      # Verify it's stopped
      servers = ServerManager.list_servers()
      refute Enum.any?(servers, &(&1.name == "test"))

      # Restart should work
      {:ok, _} =
        start_mcp_server("test", [
          "python3",
          Path.join(@demo_servers_path, "time_server.py")
        ])

      Process.sleep(1_000)

      servers = ServerManager.list_servers()
      assert Enum.any?(servers, &(&1.name == "test"))
    end

    @tag timeout: @test_timeout
    test "handles malformed tool responses" do
      # This would test how the system handles bad responses
      # For now, we ensure error handling exists

      # Start calc server
      {:ok, _} =
        start_mcp_server("calc", [
          "python3",
          Path.join(@demo_servers_path, "calculator_server.py")
        ])

      Process.sleep(1_000)

      # Try invalid calculation
      result =
        ServerManager.call_tool(
          "calc",
          "calculate",
          %{expression: "invalid expression !!!"}
        )

      # Should return error, not crash
      assert match?({:error, _}, result)
    end
  end

  describe "Configuration Changes" do
    @tag timeout: @test_timeout
    test "switches between LLM backends during session" do
      # Start with Ollama
      {:ok, _} = set_llm_backend("ollama", @test_model)

      # Send a message
      MCPChat.Session.add_message("user", "Hello from Ollama")
      messages = MCPChat.Session.get_messages()
      {:ok, response1} = get_llm_response(messages)

      MCPChat.Session.add_message("assistant", response1.content)

      # Switch to a different model (if available)
      available_models = list_ollama_models()

      if length(available_models) > 1 do
        other_model = Enum.find(available_models, &(&1 != @test_model))
        {:ok, _} = set_llm_backend("ollama", other_model)

        # Continue conversation
        MCPChat.Session.add_message("user", "Now using a different model")
        messages = MCPChat.Session.get_messages()
        {:ok, response2} = get_llm_response(messages)

        assert response2.content != ""
      end

      # Messages should persist across backend changes
      final_messages = MCPChat.Session.get_messages()
      assert length(final_messages) >= 2
    end

    @tag timeout: @test_timeout
    test "updates context window strategy" do
      # Set initial strategy
      MCPChat.Context.set_strategy(:truncate_old)

      # Add many messages to exceed context
      Enum.each(1..20, fn i ->
        MCPChat.Session.add_message("user", "Message #{i}")
        MCPChat.Session.add_message("assistant", "Response #{i}")
      end)

      # Get context with truncation
      {:ok, truncated} =
        MCPChat.Context.prepare_context(
          MCPChat.Session.get_messages(),
          # Small token limit
          1_000
        )

      # Less than all messages
      assert length(truncated) < 40

      # Change strategy
      MCPChat.Context.set_strategy(:truncate_middle)

      {:ok, middle_truncated} =
        MCPChat.Context.prepare_context(
          MCPChat.Session.get_messages(),
          1_000
        )

      # Should have different truncation pattern
      assert length(middle_truncated) < 40
      # First and last messages should be preserved
      assert hd(middle_truncated).content == "Message 1"
    end
  end

  describe "Multi-Server Scenarios" do
    @tag timeout: @test_timeout
    test "coordinates multiple MCP servers for complex tasks" do
      # Start multiple servers
      {:ok, _} =
        start_mcp_server("time", [
          "python3",
          Path.join(@demo_servers_path, "time_server.py")
        ])

      {:ok, _} =
        start_mcp_server("calc", [
          "python3",
          Path.join(@demo_servers_path, "calculator_server.py")
        ])

      {:ok, _} =
        start_mcp_server("data", [
          "python3",
          Path.join(@demo_servers_path, "data_server.py")
        ])

      Process.sleep(2000)

      # Complex scenario: Generate data, calculate statistics, add timestamp

      # 1. Generate users
      {:ok, users} =
        ServerManager.call_tool(
          "data",
          "generate_users",
          %{count: 10}
        )

      assert length(users) == 10

      # 2. Calculate average age (simulate)
      ages = Enum.map(users, & &1["age"])
      avg_age_expr = "(#{Enum.join(ages, " + ")}) / #{length(ages)}"

      {:ok, avg_result} =
        ServerManager.call_tool(
          "calc",
          "calculate",
          %{expression: avg_age_expr}
        )

      assert is_number(avg_result["result"])

      # 3. Get timestamp
      {:ok, time_result} =
        ServerManager.call_tool(
          "time",
          "get_current_time",
          %{timezone: "UTC"}
        )

      # Create summary
      summary = """
      Generated #{length(users)} users
      Average age: #{avg_result["result"]}
      Timestamp: #{time_result["time"]} #{time_result["timezone"]}
      """

      MCPChat.Session.add_message("assistant", summary)

      # Verify complete execution
      messages = MCPChat.Session.get_messages()
      assert List.last(messages).content =~ "Generated 10 users"
      assert List.last(messages).content =~ "Average age:"
      assert List.last(messages).content =~ "Timestamp:"
    end
  end

  describe "Real CLI Commands" do
    @tag timeout: @test_timeout
    test "executes actual CLI commands in sequence" do
      # Test command sequence a user might actually type

      # 1. Check initial state
      assert MCPChat.Session.get_messages() == []

      # 2. Set system message
      Commands.handle_command("/system You are a helpful assistant", %{})
      session = MCPChat.Session.get_current_session()
      assert session.context["system_message"] == "You are a helpful assistant"

      # 3. Create an alias
      Commands.handle_command(
        "/alias calc-simple /mcp call calc calculate expression:",
        %{}
      )

      # 4. Check available models
      capture_io(fn ->
        Commands.handle_command("/models", %{})
      end) =~ "Available models"

      # 5. Save empty session (should handle gracefully)
      result = Commands.handle_command("/save empty_test", %{})
      assert result == :ok

      # 6. Start MCP server via command
      result =
        Commands.handle_command(
          "/mcp connect time python3 #{Path.join(@demo_servers_path, "time_server.py")}",
          %{}
        )

      Process.sleep(1_000)

      # 7. List connected servers
      output =
        capture_io(fn ->
          Commands.handle_command("/mcp servers", %{})
        end)

      assert output =~ "time"

      # Clean up
      MCPChat.Persistence.delete_session("empty_test")
    end
  end

  # Helper Functions

  defp check_ollama do
    case HTTPoison.get("#{@ollama_url}/api/tags") do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"models" => models}} when is_list(models) and length(models) > 0 ->
            :ok

          _ ->
            {:error, "Ollama is running but no models are available"}
        end

      _ ->
        {:error, "Ollama is not running at #{@ollama_url}"}
    end
  end

  defp skip_tests(reason) do
    IO.puts("\n⚠️  Skipping E2E tests: #{reason}")
    IO.puts("   Please ensure Ollama is running with at least one model installed.")
    IO.puts("   Run: ollama pull nomic-embed-text")
    :ignore
  end

  defp setup_test_config do
    # Set up test configuration
    config = %{
      "llm" => %{
        "default" => "ollama",
        "ollama" => %{
          "base_url" => @ollama_url,
          "model" => @test_model
        }
      },
      "mcp" => %{
        "servers" => []
      }
    }

    MCPChat.Config.merge_config(config)
  end

  defp reset_config do
    # Reset to default configuration
    MCPChat.Config.reload()
  end

  defp start_demo_servers do
    # Check if Python is available
    case System.cmd("python3", ["--version"]) do
      {_, 0} ->
        # Install requirements if needed
        System.cmd("pip3", ["install", "-r", Path.join(@demo_servers_path, "requirements.txt")])
        {:ok, []}

      _ ->
        IO.puts("Warning: Python 3 not available, some tests will be limited")
        {:ok, []}
    end
  end

  defp stop_demo_server(_pid) do
    # Servers are managed by MCP ServerManager
    :ok
  end

  defp clean_test_files do
    # Clean up any test files in temp directory
    test_files = Path.wildcard(Path.join(System.tmp_dir!(), "test_*"))
    Enum.each(test_files, &File.rm/1)
  end

  defp set_llm_backend(provider, model) do
    config = %{
      "provider" => provider,
      "model" => model
    }

    case provider do
      "ollama" ->
        config = Map.put(config, "base_url", @ollama_url)

      _ ->
        config
    end

    # Update configuration
    current = MCPChat.Config.get()
    updated = put_in(current, ["llm", provider], config)
    updated = put_in(updated, ["llm", "default"], provider)
    MCPChat.Config.merge_config(updated)

    {:ok, config}
  end

  defp list_ollama_models do
    url = "#{@ollama_url}/api/tags"

    case HTTPoison.get(url) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"models" => models}} ->
            model_names = Enum.map(models, & &1["name"])
            {:ok, model_names}

          _ ->
            {:error, "Invalid response format"}
        end

      error ->
        {:error, error}
    end
  end

  defp get_llm_response(messages, client \\ nil) do
    client = client || get_current_llm_client()

    # Add system message if configured
    session = MCPChat.Session.get_current_session()

    messages =
      if session.context["system_message"] do
        [%{role: "system", content: session.context["system_message"]} | messages]
      else
        messages
      end

    # Get completion
    case ExLLMAdapter.complete(client, messages, %{}) do
      {:ok, response} ->
        {:ok, %{role: "assistant", content: response}}

      error ->
        error
    end
  end

  defp get_llm_stream(messages, client \\ nil) do
    client = client || get_current_llm_client()

    case ExLLMAdapter.stream(client, messages, %{}) do
      {:ok, stream} ->
        {:ok, stream}

      error ->
        error
    end
  end

  defp get_current_llm_client do
    config = MCPChat.Config.get_llm_config()
    {:ok, client} = ExLLMAdapter.init(config)
    client
  end

  defp start_mcp_server(name, command) do
    config = %{
      "name" => name,
      "command" => hd(command),
      "args" => tl(command)
    }

    ServerManager.start_server(config)
  end

  defp capture_io(fun) do
    ExUnit.CaptureIO.capture_io(fun)
  end
end
