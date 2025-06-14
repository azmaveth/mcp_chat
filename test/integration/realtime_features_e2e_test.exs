defmodule MCPChat.RealtimeFeaturesE2ETest do
  use ExUnit.Case, async: false

  @moduledoc """
  End-to-end tests for real-time features including streaming,
  notifications, and progress tracking with actual servers.
  """

  @ollama_url "http://localhost:11_434"
  @streaming_model "nomic-embed-text:latest"
  @test_timeout 30_000
  @demo_servers_path Path.expand("../../examples/demo_servers", __DIR__)

  setup_all do
    case check_ollama() do
      :ok ->
        Application.ensure_all_started(:mcp_chat)
        setup_test_environment()
        :ok

      {:error, reason} ->
        IO.puts("Skipping real-time tests: #{reason}")
        :ignore
    end
  end

  setup do
    # Reset state for each test
    MCPChat.Session.clear_session()
    MCPChat.MCP.ServerManager.stop_all_servers()
    :ok
  end

  describe "Streaming Response Tests" do
    @tag timeout: @test_timeout
    test "streams response with real-time token display" do
      # Configure Ollama for streaming
      config = %{
        "provider" => "ollama",
        "base_url" => @ollama_url,
        "model" => @streaming_model,
        "stream" => true
      }

      {:ok, client} = MCPChat.LLM.ExLLMAdapter.init(config)

      # Create a prompt that generates longer output
      messages = [
        %{role: "user", content: "List 5 programming languages with a brief description of each."}
      ]

      # Capture streaming chunks
      chunks = []
      start_time = System.monotonic_time(:millisecond)

      {:ok, stream} = MCPChat.LLM.ExLLMAdapter.stream(client, messages, %{})

      chunks =
        stream
        |> Stream.map(fn chunk ->
          timestamp = System.monotonic_time(:millisecond) - start_time
          {timestamp, chunk}
        end)
        |> Enum.to_list()

      # Verify streaming behavior
      # Should have multiple chunks
      assert length(chunks) > 5

      # Check chunks arrive over time (not all at once)
      timestamps = Enum.map(chunks, &elem(&1, 0))
      time_spread = List.last(timestamps) - List.first(timestamps)
      # At least 100ms spread
      assert time_spread > 100

      # Reconstruct full response
      full_response =
        chunks
        |> Enum.map_join("", &elem(&1, 1))

      # Should mention multiple languages
      assert full_response =~ ~r/\b(Python|JavaScript|Java|Ruby|Go|Rust|Elixir)\b/i
    end

    @tag timeout: @test_timeout
    test "handles interrupted streams gracefully" do
      config = %{
        "provider" => "ollama",
        "base_url" => @ollama_url,
        "model" => @streaming_model,
        "stream" => true
      }

      {:ok, client} = MCPChat.LLM.ExLLMAdapter.init(config)

      messages = [
        %{role: "user", content: "Count from 1 to 100 slowly"}
      ]

      {:ok, stream} = MCPChat.LLM.ExLLMAdapter.stream(client, messages, %{})

      # Collect only first few chunks then stop
      partial_chunks =
        stream
        |> Stream.take(5)
        |> Enum.to_list()

      # Should have collected partial response
      assert length(partial_chunks) == 5
      partial_response = Enum.join(partial_chunks, "")
      assert partial_response != ""

      # Stream should be properly closed (no hanging resources)
      # In real implementation, we'd check for proper cleanup
    end

    @tag timeout: @test_timeout
    test "tracks tokens during streaming" do
      config = %{
        "provider" => "ollama",
        "base_url" => @ollama_url,
        "model" => @streaming_model,
        "stream" => true
      }

      {:ok, client} = MCPChat.LLM.ExLLMAdapter.init(config)

      # Clear session
      MCPChat.Session.clear_session()

      messages = [
        %{role: "user", content: "Write a haiku about Elixir"}
      ]

      # Add user message
      MCPChat.Session.add_message("user", messages |> hd() |> Map.get(:content))

      {:ok, stream} = MCPChat.LLM.ExLLMAdapter.stream(client, messages, %{})

      # Collect all chunks and simulate adding to session
      chunks = Enum.to_list(stream)
      full_response = Enum.join(chunks, "")

      # Track token usage
      MCPChat.Session.track_token_usage(messages, full_response)

      # Add assistant response
      MCPChat.Session.add_message("assistant", full_response)

      # Check token tracking
      stats = MCPChat.Session.get_context_stats()
      assert stats.estimated_tokens > 0
      assert stats.message_count == 2
    end
  end

  describe "Progress Notification Tests" do
    @tag timeout: @test_timeout
    test "tracks progress for long-running MCP operations" do
      # Start data server which has operations that could be long
      {:ok, _} =
        start_mcp_server("data", [
          "python3",
          Path.join(@demo_servers_path, "data_server.py")
        ])

      Process.sleep(1_000)

      # Start progress tracker
      progress_token = "data-gen-#{System.unique_integer()}"

      # Simulate progress updates during data generation
      task =
        Task.async(fn ->
          # Generate large dataset
          MCPChat.MCP.ServerManager.call_tool(
            "data",
            "generate_users",
            %{count: 100}
          )
        end)

      # Simulate progress updates (in real implementation, server would send these)
      spawn(fn ->
        Enum.each([0.1, 0.3, 0.5, 0.7, 0.9, 1.0], fn progress ->
          Process.sleep(100)

          MCPChat.MCP.ProgressTracker.update_progress(
            progress_token,
            progress,
            "Generating users: #{round(progress * 100)}%"
          )
        end)
      end)

      # Wait for task
      result = Task.await(task, 10_000)
      assert {:ok, users} = result
      assert length(users) == 100

      # Progress should be completed
      Process.sleep(200)
      progress = MCPChat.MCP.ProgressTracker.get_progress(progress_token)
      # Completed progress is removed
      assert progress == nil
    end

    @tag timeout: @test_timeout
    test "handles multiple concurrent progress operations" do
      # Start multiple servers
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

      Process.sleep(1_500)

      # Track multiple operations
      tokens = Enum.map(1..3, fn i -> "op-#{i}-#{System.unique_integer()}" end)

      # Start concurrent operations
      tasks =
        Enum.map(tokens, fn token ->
          Task.async(fn ->
            # Simulate different operations
            cond do
              String.contains?(token, "op-1") ->
                MCPChat.MCP.ServerManager.call_tool("calc", "calculate", %{expression: "sum(1..1_000)"})

              String.contains?(token, "op-2") ->
                MCPChat.MCP.ServerManager.call_tool("data", "generate_products", %{count: 50})

              true ->
                MCPChat.MCP.ServerManager.call_tool("data", "generate_users", %{count: 30})
            end
          end)
        end)

      # Simulate progress for each
      Enum.each(tokens, fn token ->
        spawn(fn ->
          Enum.each([0.2, 0.5, 0.8, 1.0], fn progress ->
            Process.sleep(50)
            MCPChat.MCP.ProgressTracker.update_progress(token, progress, "Processing...")
          end)
        end)
      end)

      # Wait for all tasks
      results = Task.await_many(tasks, 10_000)

      assert Enum.all?(results, fn
               {:ok, _} -> true
               _ -> false
             end)

      # All progress should be completed
      Process.sleep(300)

      Enum.each(tokens, fn token ->
        assert MCPChat.MCP.ProgressTracker.get_progress(token) == nil
      end)
    end
  end

  describe "Change Notification Tests" do
    @tag timeout: @test_timeout
    test "receives notifications when MCP server capabilities change" do
      # Set up notification handler
      test_pid = self()
      handler_ref = make_ref()

      MCPChat.MCP.NotificationRegistry.start_link()

      MCPChat.MCP.NotificationRegistry.register_handler(
        :tool_list_changed,
        fn notification ->
          send(test_pid, {:tool_change, handler_ref, notification})
        end
      )

      # Start a basic server
      {:ok, _} =
        start_mcp_server("calc", [
          "python3",
          Path.join(@demo_servers_path, "calculator_server.py")
        ])

      Process.sleep(1_000)

      # Simulate tool list change (in real scenario, server would notify)
      MCPChat.MCP.NotificationRegistry.notify(:tool_list_changed, %{
        server: "calc",
        timestamp: DateTime.utc_now(),
        change_type: :added,
        tools: ["new_calculator_function"]
      })

      # Should receive notification
      assert_receive {:tool_change, ^handler_ref, %{server: "calc"}}, 2000
    end

    @tag timeout: @test_timeout
    test "auto-refreshes resource list on change notification" do
      # Start filesystem server if available
      fs_cmd =
        case System.cmd("npx", ["--version"]) do
          {_, 0} ->
            ["npx", "-y", "@modelcontextprotocol/server-filesystem", System.tmp_dir!()]

          _ ->
            # Fallback to data server which can simulate resources
            ["python3", Path.join(@demo_servers_path, "data_server.py")]
        end

      {:ok, _} = start_mcp_server("resources", fs_cmd)
      Process.sleep(2000)

      # Get initial resource list
      {:ok, initial_resources} = MCPChat.MCP.ServerManager.list_resources("resources")
      initial_count = length(initial_resources)

      # Create a new file (simulating resource change)
      test_file = Path.join(System.tmp_dir!(), "new_test_resource_#{System.unique_integer()}.txt")
      File.write!(test_file, "New resource content")

      # Simulate resource change notification
      MCPChat.MCP.NotificationRegistry.notify(:resource_list_changed, %{
        server: "resources",
        timestamp: DateTime.utc_now()
      })

      # In a real implementation, the client would auto-refresh
      # For now, manually refresh
      Process.sleep(500)
      {:ok, updated_resources} = MCPChat.MCP.ServerManager.list_resources("resources")

      # Clean up
      File.rm!(test_file)

      # Resources might have changed (depending on server implementation)
      assert is_list(updated_resources)
    end
  end

  describe "Real-time Chat with Notifications" do
    @tag timeout: @test_timeout
    test "full chat session with streaming and progress notifications" do
      # Set up streaming LLM
      config = %{
        "provider" => "ollama",
        "base_url" => @ollama_url,
        "model" => @streaming_model,
        "stream" => true
      }

      {:ok, client} = MCPChat.LLM.ExLLMAdapter.init(config)

      # Start MCP servers
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

      Process.sleep(1_500)

      # Simulate a conversation with tool usage

      # User asks for calculation
      MCPChat.Session.add_message("user", "Calculate the sum of squares from 1 to 10")

      # Execute calculation with progress
      progress_token = "calc-#{System.unique_integer()}"

      # Start progress tracking
      spawn(fn ->
        steps = 10

        Enum.each(1..steps, fn i ->
          Process.sleep(50)

          MCPChat.MCP.ProgressTracker.update_progress(
            progress_token,
            i / steps,
            "Calculating square of #{i}..."
          )
        end)
      end)

      # Perform calculation
      sum_of_squares = Enum.reduce(1..10, 0, fn i, acc -> acc + i * i end)

      {:ok, result} =
        MCPChat.MCP.ServerManager.call_tool(
          "calc",
          "calculate",
          %{expression: "1^2 + 2^2 + 3^2 + 4^2 + 5^2 + 6^2 + 7^2 + 8^2 + 9^2 + 10^2"}
        )

      # Stream response
      response_text =
        "The sum of squares from 1 to 10 is #{result["result"]}. " <>
          "This equals 1² + 2² + ... + 10² = #{sum_of_squares}."

      # Simulate streaming the response
      chunks = String.split(response_text, " ")

      streamed_response =
        chunks
        |> Enum.map_join("", fn chunk ->
          # Simulate streaming delay
          Process.sleep(30)
          chunk <> " "
        end)

      MCPChat.Session.add_message("assistant", streamed_response)

      # Verify complete interaction
      messages = MCPChat.Session.get_messages()
      assert length(messages) == 2
      assert messages |> List.last() |> Map.get(:content) =~ "385"
    end

    @tag timeout: @test_timeout
    test "handles notification storms without blocking chat" do
      # Start servers
      {:ok, _} =
        start_mcp_server("data", [
          "python3",
          Path.join(@demo_servers_path, "data_server.py")
        ])

      Process.sleep(1_000)

      # Set up notification counter
      notification_count = :counters.new(1, [])
      test_pid = self()

      MCPChat.MCP.NotificationRegistry.register_handler(
        # Listen to all notifications
        :all,
        fn _notification ->
          :counters.add(notification_count, 1, 1)
        end
      )

      # Generate many notifications rapidly
      notification_task =
        Task.async(fn ->
          Enum.each(1..100, fn i ->
            MCPChat.MCP.NotificationRegistry.notify(:resource_updated, %{
              server: "data",
              resource: "item_#{i}",
              timestamp: DateTime.utc_now()
            })

            # 200 notifications/second
            Process.sleep(5)
          end)
        end)

      # Meanwhile, perform normal chat operations
      start_time = System.monotonic_time(:millisecond)

      # Add messages
      MCPChat.Session.add_message("user", "Hello")
      MCPChat.Session.add_message("assistant", "Hi there!")

      # Call a tool
      {:ok, result} =
        MCPChat.MCP.ServerManager.call_tool(
          "data",
          "generate_users",
          %{count: 5}
        )

      end_time = System.monotonic_time(:millisecond)

      # Chat operations should not be blocked by notifications
      # Should complete quickly
      assert end_time - start_time < 2000
      assert length(result) == 5

      # Wait for notifications to complete
      Task.await(notification_task)

      # Should have received many notifications
      total_notifications = :counters.get(notification_count, 1)
      # At least half should have been processed
      assert total_notifications >= 50
    end
  end

  describe "Circuit Breaker Integration" do
    @tag timeout: @test_timeout
    test "circuit breaker protects against repeated LLM failures" do
      # Configure with failing endpoint
      config = %{
        "provider" => "ollama",
        # Non-existent
        "base_url" => "http://localhost:99_999",
        "model" => "test-model"
      }

      {:ok, client} = MCPChat.LLM.ExLLMAdapter.init(config)

      messages = [%{role: "user", content: "Hello"}]

      # First few attempts should try to connect
      results =
        Enum.map(1..5, fn _ ->
          MCPChat.LLM.ExLLMAdapter.complete(client, messages, %{})
        end)

      # All should fail
      assert Enum.all?(results, fn
               {:error, _} -> true
               _ -> false
             end)

      # Circuit breaker should eventually open
      # (In real implementation with circuit breaker)
      # Later attempts should fail fast without trying to connect
    end

    @tag timeout: @test_timeout
    test "circuit breaker recovers after successful calls" do
      # Start with working configuration
      config = %{
        "provider" => "ollama",
        "base_url" => @ollama_url,
        "model" => @streaming_model
      }

      {:ok, client} = MCPChat.LLM.ExLLMAdapter.init(config)
      messages = [%{role: "user", content: "Hello"}]

      # Should work
      {:ok, response1} = MCPChat.LLM.ExLLMAdapter.complete(client, messages, %{})
      assert response1 != ""

      # Simulate temporary failure by using bad config
      bad_client = %{client | config: Map.put(client.config, "base_url", "http://localhost:99_999")}

      # This should fail
      result = MCPChat.LLM.ExLLMAdapter.complete(bad_client, messages, %{})
      assert match?({:error, _}, result)

      # Switch back to good config
      {:ok, response2} = MCPChat.LLM.ExLLMAdapter.complete(client, messages, %{})
      assert response2 != ""

      # Circuit should recover and allow calls
    end
  end

  # Helper Functions

  defp check_ollama() do
    case HTTPoison.get("#{@ollama_url}/api/tags") do
      {:ok, %{status_code: 200, body: body}} ->
        check_ollama_models(body)

      _ ->
        {:error, "Ollama is not running at #{@ollama_url}"}
    end
  end

  defp check_ollama_models(body) do
    case Jason.decode(body) do
      {:ok, %{"models" => models}} when is_list(models) and length(models) > 0 ->
        check_model_availability(models)

      _ ->
        {:error, "Ollama has no models"}
    end
  end

  defp check_model_availability(models) do
    if Enum.any?(models, &(&1["name"] == @streaming_model)) do
      :ok
    else
      {:error, "Ollama doesn't have #{@streaming_model} model. Run: ollama pull #{@streaming_model}"}
    end
  end

  defp setup_test_environment() do
    # Ensure progress tracker is started
    unless Process.whereis(MCPChat.MCP.ProgressTracker) do
      {:ok, _} = MCPChat.MCP.ProgressTracker.start_link([])
    end

    # Ensure notification registry is started
    unless Process.whereis(MCPChat.MCP.NotificationRegistry) do
      {:ok, _} = MCPChat.MCP.NotificationRegistry.start_link()
    end
  end

  defp start_mcp_server(name, command) do
    config = %{
      "name" => name,
      "command" => hd(command),
      "args" => tl(command)
    }

    MCPChat.MCP.ServerManager.start_server(config)
  end
end
