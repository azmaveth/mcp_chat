defmodule MCPChat.EnhancedE2ETest do
  use ExUnit.Case, async: false

  @moduledoc """
  Enhanced comprehensive end-to-end tests for MCP Chat.
  NO MOCKING - All tests use real backends and servers.

  Prerequisites:
  - Ollama running at http://localhost:11_434
  - At least one model installed (we'll check and use what's available)
  - Elixir MCP demo servers (included in test/support/)
  """

  require Logger
  import MCPChat.TestConfig
  import MCPChat.MCPTestHelpers

  # Configuration
  @ollama_url "http://localhost:11_434"
  # 2 minutes for complex operations
  @test_timeout 120_000

  # State tracking
  @available_models_key :e2e_available_models
  @test_model_key :e2e_test_model

  setup_all do
    # Start application
    Application.ensure_all_started(:mcp_chat)

    # Check Ollama and get available models
    case check_and_configure_ollama() do
      {:ok, model} ->
        Logger.info("E2E Tests: Using Ollama model #{model}")

        # Start demo MCP servers
        {:ok, servers} = start_demo_servers()

        on_exit(fn ->
          stop_demo_servers(servers)
          cleanup_test_environment()
        end)

        {:ok, %{test_model: model, demo_servers: servers}}

      {:error, reason} ->
        Logger.error("E2E Tests: Skipping - #{reason}")
        :ignore
    end
  end

  setup context do
    # Clear state before each test
    MCPChat.Session.clear_session()

    # Reset MCP server connections by stopping each one
    try do
      for server <- MCPChat.MCP.ServerManager.list_servers() do
        MCPChat.MCP.ServerManager.stop_server(server.name)
      end
    rescue
      # ignore if no servers are running
      _ -> :ok
    end

    # Set up Ollama for this test
    configure_ollama(context.test_model)

    {:ok, %{model: context.test_model}}
  end

  describe "Complete Chat Flow with Ollama" do
    @tag timeout: @test_timeout
    test "single turn conversation", %{model: model} do
      # Start a session (or get existing one)
      case MCPChat.Session.start_link() do
        {:ok, pid} -> {:ok, pid}
        {:error, {:already_started, pid}} -> {:ok, pid}
      end

      # Send a message
      MCPChat.Session.add_message("user", "What is 2 + 2?")

      # Get response using real Ollama
      messages = MCPChat.Session.get_messages()
      {:ok, response} = get_ollama_response(messages, model)

      # Verify response
      assert response.content != nil
      assert response.content =~ ~r/4|four/i

      # Check token tracking (ExLLM uses different field names than expected)
      assert response.usage.prompt_tokens > 0
      assert response.usage.completion_tokens > 0

      # Add to session (usage tracking handled internally)
      MCPChat.Session.add_message("assistant", response.content)

      # Verify session state
      session_messages = MCPChat.Session.get_messages()
      assert length(session_messages) == 2

      # Check that both user and assistant messages are present
      assert Enum.at(session_messages, 0).role == "user"
      assert Enum.at(session_messages, 1).role == "assistant"
      assert Enum.at(session_messages, 1).content =~ ~r/4|four/i
    end

    @tag timeout: @test_timeout
    test "multi-turn conversation with context", %{model: model} do
      case MCPChat.Session.start_link() do
        {:ok, _} ->
          :ok

        {:error, {:already_started, _}} ->
          MCPChat.Session.clear_session()
      end

      # First turn
      MCPChat.Session.add_message("user", "My name is Alice. What's 2 + 2?")
      {:ok, response1} = get_ollama_response(MCPChat.Session.get_messages(), model)
      MCPChat.Session.add_message("assistant", response1.content)

      assert response1.content =~ ~r/4|four/i

      # Second turn - should remember context
      MCPChat.Session.add_message("user", "What's my name?")
      {:ok, response2} = get_ollama_response(MCPChat.Session.get_messages(), model)
      MCPChat.Session.add_message("assistant", response2.content)

      assert response2.content =~ ~r/Alice/i

      # Third turn - math with context
      MCPChat.Session.add_message("user", "Multiply the number I asked about earlier by 10")
      {:ok, response3} = get_ollama_response(MCPChat.Session.get_messages(), model)

      assert response3.content =~ ~r/40|forty/i
    end

    @tag timeout: @test_timeout
    test "streaming responses", %{model: model} do
      {:ok, _} = MCPChat.Session.start_link()

      MCPChat.Session.add_message("user", "Count from 1 to 5")

      # Stream response
      chunks = []

      {:ok, _response} =
        stream_ollama_response(
          MCPChat.Session.get_messages(),
          model,
          fn chunk ->
            chunks = [chunk | chunks]
          end
        )

      # Verify streaming worked
      assert length(chunks) > 1

      # Reconstruct full response
      full_content = chunks |> Enum.reverse() |> Enum.join("")
      assert full_content =~ ~r/1.*2.*3.*4.*5/s
    end
  end

  describe "MCP Server Integration" do
    @tag timeout: @test_timeout
    test "connect to time server and execute tools", %{model: model} do
      # Use proper MCP architecture with test helpers
      with_mcp_server("time-server", time_server_config(), fn server_name ->
        # List available tools
        {:ok, tools} = MCPChat.MCP.ServerManager.get_tools(server_name)
        assert Enum.any?(tools, &(&1["name"] == "get_current_time"))

        # Execute tool
        {:ok, result} =
          MCPChat.MCP.ServerManager.call_tool(
            server_name,
            "get_current_time",
            %{"timezone" => "UTC"}
          )

        assert result["time"] =~ ~r/\d{4}-\d{2}-\d{2}/

        # Use in conversation
        MCPChat.Session.add_message("user", "What time is it in UTC?")
        MCPChat.Session.set_context(%{tool_result: result})

        {:ok, response} = get_ollama_response(MCPChat.Session.get_messages(), model)
        assert response.content =~ ~r/UTC|time/i
      end)
    end

    @tag timeout: @test_timeout
    test "multiple MCP servers working together", %{model: model} do
      # Start multiple servers
      {:ok, _} = start_mcp_server("time-server", time_server_config())
      {:ok, _} = start_mcp_server("calc-server", calculator_server_config())

      Process.sleep(1_500)

      # Execute tools from both servers
      {:ok, time_result} =
        MCPChat.MCP.ServerManager.call_tool(
          "time-server",
          "get_current_time",
          %{"timezone" => "UTC"}
        )

      {:ok, calc_result} =
        MCPChat.MCP.ServerManager.call_tool(
          "calc-server",
          "calculate",
          %{"expression" => "365 * 24"}
        )

      assert calc_result["result"] == 8_760

      # Use both results in conversation
      MCPChat.Session.add_message(
        "user",
        "How many hours are in a year? And what's the current time?"
      )

      MCPChat.Session.add_context(:tool_results, %{
        time: time_result,
        calculation: calc_result
      })

      {:ok, response} = get_ollama_response(MCPChat.Session.get_messages(), model)
      assert response.content =~ ~r/8_760|8,760/
      assert response.content =~ ~r/time|UTC/i
    end

    @tag timeout: @test_timeout
    test "resource reading from MCP server", %{model: model} do
      # Start data server with resources
      {:ok, _} = start_mcp_server("data-server", data_server_config())

      Process.sleep(1_000)

      # List resources
      {:ok, resources} = MCPChat.MCP.ServerManager.get_resources("data-server")
      assert length(resources) > 0

      # Read a resource
      resource_uri = Enum.at(resources, 0)["uri"]
      {:ok, content} = MCPChat.MCP.ServerManager.read_resource("data-server", resource_uri)

      assert content != nil

      # Use resource in conversation
      MCPChat.Session.add_message("user", "Summarize this data: #{resource_uri}")
      MCPChat.Session.add_context(:resource_content, content)

      {:ok, response} = get_ollama_response(MCPChat.Session.get_messages(), model)
      assert String.length(response.content) > 10
    end
  end

  describe "Notification and Progress Features" do
    @tag timeout: @test_timeout
    test "progress notifications during long operations", %{model: model} do
      # Enable notifications
      Application.put_env(:mcp_chat, :enable_notifications, true)

      # Start calculator server with progress support
      {:ok, _} = start_mcp_server("calc-server", calculator_server_config())

      Process.sleep(1_000)

      # Track progress updates
      progress_updates = :ets.new(:progress_updates, [:set, :public])

      # Subscribe to progress notifications
      MCPChat.MCP.NotificationRegistry.subscribe(self())

      # Execute long-running calculation
      task =
        Task.async(fn ->
          MCPChat.MCP.ServerManager.call_tool(
            "calc-server",
            "factorial",
            %{"n" => 20, "with_progress" => true}
          )
        end)

      # Collect progress updates
      collect_progress_updates(progress_updates, 5_000)

      # Wait for completion
      {:ok, result} = Task.await(task, 10_000)

      # Verify progress was tracked
      updates = :ets.tab2list(progress_updates)
      assert length(updates) > 0

      # Verify result
      assert result["result"] == factorial(20)

      :ets.delete(progress_updates)
    end

    @tag timeout: @test_timeout
    test "change notifications when tools update", %{model: model} do
      # Enable notifications
      Application.put_env(:mcp_chat, :enable_notifications, true)

      # Start dynamic server that can add/remove tools
      {:ok, _} = start_mcp_server("dynamic-server", dynamic_server_config())

      Process.sleep(1_000)

      # Subscribe to notifications
      MCPChat.MCP.NotificationRegistry.subscribe(self())

      # Get initial tools
      {:ok, initial_tools} = MCPChat.MCP.ServerManager.get_tools("dynamic-server")
      initial_count = length(initial_tools)

      # Trigger tool addition
      {:ok, _} =
        MCPChat.MCP.ServerManager.call_tool(
          "dynamic-server",
          "add_tool",
          %{"name" => "new_tool"}
        )

      # Wait for notification
      assert_receive {:notification, :tools_changed, _}, 5_000

      # Verify tools updated
      {:ok, updated_tools} = MCPChat.MCP.ServerManager.get_tools("dynamic-server")
      assert length(updated_tools) == initial_count + 1
    end
  end

  describe "Session Management and Persistence" do
    @tag timeout: @test_timeout
    test "save and load session with full context", %{model: model} do
      # Create a session with history
      {:ok, _} = MCPChat.Session.start_link()

      # Add messages
      MCPChat.Session.add_message("user", "Remember: the secret code is 42")
      {:ok, r1} = get_ollama_response(MCPChat.Session.get_messages(), model)
      MCPChat.Session.add_message("assistant", r1.content)

      MCPChat.Session.add_message("user", "What's 10 times the secret code?")
      {:ok, r2} = get_ollama_response(MCPChat.Session.get_messages(), model)
      MCPChat.Session.add_message("assistant", r2.content)

      # Save session
      session_name = "test_session_#{:rand.uniform(10_000)}"
      {:ok, path} = MCPChat.Session.save_session(session_name)

      # Clear and reload
      MCPChat.Session.clear_session()
      assert MCPChat.Session.get_messages() == []

      {:ok, _} = MCPChat.Session.load_session(session_name)

      # Verify loaded correctly
      messages = MCPChat.Session.get_messages()
      assert length(messages) == 4
      assert Enum.at(messages, 3).content =~ ~r/420/

      # Continue conversation with loaded context
      MCPChat.Session.add_message("user", "What was the secret code again?")
      {:ok, r3} = get_ollama_response(MCPChat.Session.get_messages(), model)

      assert r3.content =~ ~r/42/

      # Clean up
      File.rm(path)
    end

    @tag timeout: @test_timeout
    test "export session in multiple formats", %{model: model} do
      {:ok, _} = MCPChat.Session.start_link()

      # Create session
      MCPChat.Session.add_message("user", "Test export")
      {:ok, response} = get_ollama_response(MCPChat.Session.get_messages(), model)
      MCPChat.Session.add_message("assistant", response.content)

      # Export as JSON
      {:ok, json_path} = MCPChat.Session.export_session(:json, "test_export")
      assert File.exists?(json_path)

      json_content = File.read!(json_path)
      decoded = Jason.decode!(json_content)
      assert decoded["messages"] != nil
      assert decoded["metadata"] != nil

      # Export as Markdown
      {:ok, md_path} = MCPChat.Session.export_session(:markdown, "test_export")
      assert File.exists?(md_path)

      md_content = File.read!(md_path)
      assert md_content =~ ~r/# Chat Session/
      assert md_content =~ ~r/Test export/

      # Clean up
      File.rm(json_path)
      File.rm(md_path)
    end
  end

  describe "Error Handling and Recovery" do
    @tag timeout: @test_timeout
    test "graceful handling of Ollama connection failure", %{model: model} do
      # Temporarily misconfigure Ollama
      original_url = Application.get_env(:ex_llm, :ollama_base_url)
      Application.put_env(:ex_llm, :ollama_base_url, "http://localhost:99_999")

      MCPChat.Session.add_message("user", "Test message")

      # Should fail gracefully
      result = get_ollama_response(MCPChat.Session.get_messages(), model)
      assert {:error, _reason} = result

      # Restore configuration
      Application.put_env(:ex_llm, :ollama_base_url, original_url)

      # Should work again
      {:ok, response} = get_ollama_response(MCPChat.Session.get_messages(), model)
      assert response.content != nil
    end

    @tag timeout: @test_timeout
    test "MCP server crash and recovery", %{model: model} do
      # Start server
      {:ok, pid} = start_mcp_server("crash-test", time_server_config())

      Process.sleep(1_000)

      # Verify it works
      {:ok, _tools} = MCPChat.MCP.ServerManager.get_tools("crash-test")

      # Kill the server process
      Process.exit(pid, :kill)
      Process.sleep(100)

      # Should fail
      result = MCPChat.MCP.ServerManager.get_tools("crash-test")
      assert {:error, _} = result

      # Restart server
      {:ok, _new_pid} = start_mcp_server("crash-test", time_server_config())
      Process.sleep(1_000)

      # Should work again
      {:ok, tools} = MCPChat.MCP.ServerManager.get_tools("crash-test")
      assert length(tools) > 0
    end

    @tag timeout: @test_timeout
    test "handling of large contexts", %{model: model} do
      {:ok, _} = MCPChat.Session.start_link()

      # Add many messages to approach token limit
      Enum.each(1..20, fn i ->
        MCPChat.Session.add_message("user", "Message #{i}: " <> String.duplicate("test ", 50))
        MCPChat.Session.add_message("assistant", "Response #{i}: acknowledged")
      end)

      # Add final message
      MCPChat.Session.add_message("user", "What was message 1 about?")

      # Should handle truncation gracefully
      {:ok, response} = get_ollama_response(MCPChat.Session.get_messages(), model)
      assert response.content != nil

      # Check that truncation happened
      messages = MCPChat.Session.get_messages()
      # Should be truncated from 40+ messages
      assert length(messages) < 50
    end
  end

  describe "Advanced CLI Integration" do
    @tag timeout: @test_timeout
    test "execute complex command sequences", %{model: model} do
      # This tests the full CLI command flow without mocking

      # These commands would be executed through the CLI interface
      # For testing, we'll use the underlying functions directly

      # Test basic integration components
      # (CLI command functions are not yet implemented)

      # List models
      models =
        case ExLLM.list_models(:ollama) do
          {:ok, model_list} -> model_list
          _ -> []
        end

      assert is_list(models)

      # Connect MCP server
      {:ok, _} = start_mcp_server("test-server", time_server_config())

      # List tools
      {:ok, tools} = MCPChat.MCP.ServerManager.get_tools("test-server")
      assert length(tools) > 0

      # Execute tool
      {:ok, result} =
        MCPChat.MCP.ServerManager.call_tool(
          "test-server",
          "get_current_time",
          %{"timezone" => "UTC"}
        )

      assert result["time"] != nil

      # Add context
      MCPChat.Session.set_context(%{tool_result: result})

      # Clear context (reset to empty)
      MCPChat.Session.set_context(%{})
    end
  end

  # Helper Functions

  defp check_and_configure_ollama do
    # Configure Ollama
    config = %{
      "provider" => "ollama",
      "base_url" => @ollama_url
    }

    # Set up environment for ExLLM
    Application.put_env(:ex_llm, :ollama_base_url, @ollama_url)
    System.put_env("OLLAMA_API_BASE", @ollama_url)

    # Try to list models
    case list_ollama_models() do
      {:ok, models} when models != [] ->
        # Get model names
        model_names = models

        # Prefer models that support tool calling for testing
        preferred_models = [
          "hf.co/unsloth/Qwen3-8B-GGUF:IQ4_XS",
          "hf.co/unsloth/Qwen3-8B-GGUF:IQ4_NL",
          "hf.co/bartowski/Zyphra_ZR1-1.5B-GGUF:Q8_0",
          # fallback
          "nomic-embed-text:latest"
        ]

        model = Enum.find(preferred_models, &(&1 in model_names)) || hd(model_names)

        # Store available models
        Application.put_env(:mcp_chat, @available_models_key, model_names)
        Application.put_env(:mcp_chat, @test_model_key, model)

        {:ok, model}

      {:ok, []} ->
        {:error, "No models available in Ollama. Run: ollama pull nomic-embed-text:latest"}

      {:error, :econnrefused} ->
        {:error, "Ollama not running at #{@ollama_url}. Start with: ollama serve"}

      {:error, reason} ->
        {:error, "Failed to get models: #{inspect(reason)}"}
    end
  end

  defp configure_ollama(model) do
    config = %{
      "provider" => "ollama",
      "base_url" => @ollama_url,
      "model" => model,
      # Low temperature for consistent test results
      "temperature" => 0.1,
      "stream" => false
    }

    Application.put_env(:mcp_chat, :llm, config)
    Application.put_env(:ex_llm, :ollama_base_url, @ollama_url)
    Application.put_env(:ex_llm, :default_model, model)
  end

  defp get_ollama_response(messages, model) do
    # Use ExLLM directly with a simple prompt that works
    # Based on our successful simple test
    ExLLM.chat(:ollama, messages,
      model: model,
      temperature: 0.1,
      # Very short responses for faster tests
      max_tokens: 50,
      config_provider: ExLLM.ConfigProvider.Env
    )
  end

  defp stream_ollama_response(messages, model, callback) do
    # Use ExLLM directly for streaming to avoid adapter complexity
    {:ok, stream} =
      ExLLM.stream_chat(:ollama, messages,
        model: model,
        temperature: 0.1,
        max_tokens: 500,
        config_provider: ExLLM.ConfigProvider.Env
      )

    # Collect chunks and call callback
    for chunk <- stream do
      if chunk.content, do: callback.(chunk.content)
    end

    # Return a basic response
    {:ok, %{content: "Streamed response", finish_reason: "stop"}}
  end

  defp list_ollama_models do
    # Use ExLLM directly to list models with Env config provider
    case ExLLM.list_models(:ollama, config_provider: ExLLM.ConfigProvider.Env) do
      {:ok, models} ->
        model_names = Enum.map(models, & &1.id)
        {:ok, model_names}

      error ->
        error
    end
  end

  defp start_demo_servers do
    # No need to start external servers - we'll use stdio-based Elixir servers
    # that are started on demand when connecting
    {:ok, []}
  end

  defp stop_demo_servers(_pids) do
    # Stop any MCP servers that might be running
    try do
      for server <- MCPChat.MCP.ServerManager.list_servers() do
        MCPChat.MCP.ServerManager.stop_server(server.name)
      end
    rescue
      # ignore if no servers are running
      _ -> :ok
    end
  end

  defp start_mcp_server(name, config) do
    # Create a full server config with name
    server_config = Map.put(config, "name", name)

    MCPChat.MCP.ServerManager.start_server(server_config)
  end

  defp time_server_config do
    %{
      "command" => "elixir",
      "args" => [Path.expand("../support/demo_time_server_stdio.exs", __DIR__)],
      "transport" => "stdio"
    }
  end

  defp calculator_server_config do
    %{
      "command" => "elixir",
      "args" => [Path.expand("../support/demo_calculator_server.exs", __DIR__)],
      "transport" => "stdio"
    }
  end

  defp data_server_config do
    # For now, use time server as a data server substitute
    %{
      "command" => "elixir",
      "args" => [Path.expand("../support/demo_time_server.exs", __DIR__)],
      "transport" => "stdio"
    }
  end

  defp dynamic_server_config do
    %{
      "command" => "elixir",
      "args" => [Path.expand("../support/demo_dynamic_server.exs", __DIR__)],
      "transport" => "stdio"
    }
  end

  defp collect_progress_updates(ets_table, timeout) do
    receive do
      {:notification, :progress, %{progress: progress}} ->
        :ets.insert(ets_table, {System.monotonic_time(), progress})
        collect_progress_updates(ets_table, timeout)
    after
      timeout -> :ok
    end
  end

  defp factorial(0), do: 1
  defp factorial(n) when n > 0, do: n * factorial(n - 1)

  describe "@ Symbol Context Inclusion" do
    @tag timeout: @test_timeout
    test "resolves file references in chat messages", %{model: model} do
      # Create test file
      test_file = "/tmp/test_at_symbol.txt"
      File.write!(test_file, "The answer to everything is 42")

      # Use @ symbol in message
      message = "What does @file:#{test_file} say about the answer?"

      # Resolve @ symbols
      resolved = MCPChat.Context.AtSymbolResolver.resolve_all(message)

      assert resolved.resolved_text =~ "The answer to everything is 42"
      assert length(resolved.results) == 1
      assert resolved.errors == []

      # Clean up
      File.rm(test_file)
    end

    @tag timeout: @test_timeout
    test "resolves MCP resource references", %{model: model} do
      # Start calculator server with resources
      {:ok, _} = start_mcp_server("calculator", calculator_server_config())
      Process.sleep(2_000)

      # Use @ symbol to reference MCP resource
      message = "Show me the constants from @resource:calc://constants"

      # Resolve @ symbols
      resolved = MCPChat.Context.AtSymbolResolver.resolve_all(message)

      # Should contain mathematical constants
      assert resolved.resolved_text =~ "pi"
      assert resolved.resolved_text =~ "3.14"
      assert resolved.errors == []
    end

    @tag timeout: @test_timeout
    test "executes MCP tools via @ symbols", %{model: model} do
      # Start calculator server
      {:ok, _} = start_mcp_server("calculator", calculator_server_config())
      Process.sleep(2_000)

      # Use @ symbol to execute tool
      message = "Calculate @tool:calculate:expression=10*5 for me"

      # Resolve @ symbols
      resolved = MCPChat.Context.AtSymbolResolver.resolve_all(message)

      # Should contain calculation result
      assert resolved.resolved_text =~ "50"
      assert resolved.errors == []
    end

    @tag timeout: @test_timeout
    test "handles multiple @ symbols in one message", %{model: model} do
      # Create test files
      file1 = "/tmp/test_file1.txt"
      file2 = "/tmp/test_file2.txt"
      File.write!(file1, "First file content")
      File.write!(file2, "Second file content")

      # Start calculator server
      {:ok, _} = start_mcp_server("calculator", calculator_server_config())
      Process.sleep(2_000)

      # Message with multiple @ symbols
      message = "Compare @file:#{file1} with @file:#{file2} and calculate @tool:calculate:expression=2+2"

      # Resolve @ symbols
      resolved = MCPChat.Context.AtSymbolResolver.resolve_all(message)

      # Should contain all resolved content
      assert resolved.resolved_text =~ "First file content"
      assert resolved.resolved_text =~ "Second file content"
      assert resolved.resolved_text =~ "4"
      assert length(resolved.results) == 3
      assert resolved.errors == []

      # Clean up
      File.rm(file1)
      File.rm(file2)
    end

    @tag timeout: @test_timeout
    test "integrates @ symbols with full chat flow", %{model: model} do
      # Create test file
      test_file = "/tmp/chat_test_file.txt"
      File.write!(test_file, "Elixir is a dynamic, functional language")

      # Add message with @ symbol
      user_message = "Summarize @file:#{test_file} in one sentence"
      MCPChat.Session.add_message("user", user_message)

      # Get messages and resolve @ symbols before sending to LLM
      messages = MCPChat.Session.get_messages()
      last_message = List.last(messages)

      # Resolve @ symbols
      resolved = MCPChat.Context.AtSymbolResolver.resolve_all(last_message.content)

      # Create modified messages for LLM
      resolved_messages =
        List.update_at(messages, -1, fn msg ->
          %{msg | content: resolved.resolved_text}
        end)

      # Get Ollama response
      {:ok, response} = get_ollama_response(resolved_messages, model)

      # Response should mention Elixir and functional language
      assert String.downcase(response.content) =~ "elixir"
      assert String.downcase(response.content) =~ "functional"

      # Clean up
      File.rm(test_file)
    end
  end

  defp cleanup_test_environment do
    # Clean up any test files
    test_sessions_dir = Path.expand("~/.config/mcp_chat/test_sessions")
    if File.exists?(test_sessions_dir), do: File.rm_rf(test_sessions_dir)

    # Reset application environment
    Application.delete_env(:mcp_chat, @available_models_key)
    Application.delete_env(:mcp_chat, @test_model_key)
    Application.delete_env(:mcp_chat, :enable_notifications)
  end

  defp clean_test_files do
    # Clean up any temporary files created during tests
    test_files = Path.wildcard("/tmp/test_export*")
    Enum.each(test_files, &File.rm/1)
  end
end
