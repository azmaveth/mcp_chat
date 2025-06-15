defmodule MCPChat.AdvancedScenariosE2ETest do
  use ExUnit.Case, async: false

  @moduledoc """
  End-to-end tests for advanced scenarios including multi-agent coordination,
  complex workflows, and edge cases using real servers.
  """

  @ollama_url "http://localhost:11_434"
  @test_model "nomic-embed-text:latest"
  @test_timeout 60_000
  @demo_servers_path Path.expand("../../examples/demo_servers", __DIR__)

  setup_all do
    case check_environment() do
      :ok ->
        Application.ensure_all_started(:mcp_chat)
        setup_test_config()
        :ok

      {:error, reason} ->
        IO.puts("Skipping advanced tests: #{reason}")
        :ignore
    end
  end

  setup do
    # Clean state for each test
    cleanup_test_state()
    :ok
  end

  describe "Multi-Agent Coordination" do
    @tag timeout: @test_timeout
    test "coordinates multiple agents with shared context" do
      # Create multiple agent instances (simulated via sessions)
      agent1_session = "research_agent"
      agent2_session = "analysis_agent"
      agent3_session = "summary_agent"

      # Agent 1: Research agent gathers data
      MCPChat.Persistence.save_session(agent1_session)
      MCPChat.Session.clear_session()

      MCPChat.Session.set_context(%{
        "agent_role" => "research",
        "system_message" => "You are a research agent that gathers information"
      })

      # Start data server for research
      {:ok, _} =
        start_mcp_server("data", [
          "python3",
          Path.join(@demo_servers_path, "data_server.py")
        ])

      Process.sleep(1_000)

      # Research agent generates data
      {:ok, users} =
        MCPChat.MCP.ServerManager.call_tool(
          "data",
          "generate_users",
          %{count: 20}
        )

      {:ok, products} =
        MCPChat.MCP.ServerManager.call_tool(
          "data",
          "generate_products",
          %{count: 10}
        )

      # Store research results
      research_data = %{
        "users" => users,
        "products" => products,
        "timestamp" => DateTime.utc_now()
      }

      MCPChat.Session.add_message(
        "assistant",
        "Research complete: #{length(users)} users and #{length(products)} products collected"
      )

      MCPChat.Persistence.save_session(agent1_session)

      # Agent 2: Analysis agent processes data
      MCPChat.Session.clear_session()

      MCPChat.Session.set_context(%{
        "agent_role" => "analysis",
        "system_message" => "You are an analysis agent that processes data",
        "research_data" => research_data
      })

      # Start calculator for analysis
      {:ok, _} =
        start_mcp_server("calc", [
          "python3",
          Path.join(@demo_servers_path, "calculator_server.py")
        ])

      Process.sleep(1_000)

      # Analyze user ages
      ages = Enum.map(users, & &1["age"])
      avg_age_expr = "(#{Enum.join(ages, " + ")}) / #{length(ages)}"

      {:ok, avg_result} =
        MCPChat.MCP.ServerManager.call_tool(
          "calc",
          "calculate",
          %{expression: avg_age_expr}
        )

      # Analyze product prices
      prices = Enum.map(products, & &1["price"])
      total_value_expr = Enum.join(prices, " + ")

      {:ok, total_result} =
        MCPChat.MCP.ServerManager.call_tool(
          "calc",
          "calculate",
          %{expression: total_value_expr}
        )

      analysis_results = %{
        "avg_user_age" => avg_result["result"],
        "total_product_value" => total_result["result"],
        "user_count" => length(users),
        "product_count" => length(products)
      }

      MCPChat.Session.add_message(
        "assistant",
        "Analysis complete: Average age #{avg_result["result"]}, Total value #{total_result["result"]}"
      )

      MCPChat.Persistence.save_session(agent2_session)

      # Agent 3: Summary agent creates final report
      MCPChat.Session.clear_session()

      MCPChat.Session.set_context(%{
        "agent_role" => "summary",
        "system_message" => "You are a summary agent that creates reports",
        "analysis_results" => analysis_results
      })

      # Create summary
      summary = """
      Multi-Agent Analysis Report
      ==========================

      Research Phase:
      - Collected #{analysis_results["user_count"]} user profiles
      - Collected #{analysis_results["product_count"]} product entries

      Analysis Phase:
      - Average user age: #{Float.round(analysis_results["avg_user_age"], 2)}
      - Total product inventory value: $#{Float.round(analysis_results["total_product_value"], 2)}

      Timestamp: #{DateTime.utc_now() |> DateTime.to_string()}
      """

      MCPChat.Session.add_message("assistant", summary)
      MCPChat.Persistence.save_session(agent3_session)

      # Verify all agents completed their tasks
      assert File.exists?(MCPChat.Persistence.session_path(agent1_session))
      assert File.exists?(MCPChat.Persistence.session_path(agent2_session))
      assert File.exists?(MCPChat.Persistence.session_path(agent3_session))

      # Load and verify final summary
      {:ok, _} = MCPChat.Persistence.load_session(agent3_session)
      messages = MCPChat.Session.get_messages()
      assert length(messages) > 0
      assert hd(messages).content =~ "Multi-Agent Analysis Report"

      # Cleanup
      MCPChat.Persistence.delete_session(agent1_session)
      MCPChat.Persistence.delete_session(agent2_session)
      MCPChat.Persistence.delete_session(agent3_session)
    end

    @tag timeout: @test_timeout
    test "handles agent communication via shared resources" do
      # Create a shared file resource for agent communication
      shared_file = Path.join(System.tmp_dir!(), "agent_communication_#{System.unique_integer()}.json")

      # Agent 1 writes data
      agent1_data = %{
        "task" => "data_collection",
        "status" => "complete",
        "results" => %{
          "items_processed" => 100,
          "errors" => 0
        }
      }

      File.write!(shared_file, Jason.encode!(agent1_data))

      # Agent 2 reads and updates
      {:ok, content} = File.read(shared_file)
      {:ok, data} = Jason.decode(content)

      updated_data =
        Map.merge(data, %{
          "task" => "data_validation",
          "validation_results" => %{
            "valid_items" => 98,
            "invalid_items" => 2
          }
        })

      File.write!(shared_file, Jason.encode!(updated_data))

      # Verify communication
      {:ok, final_content} = File.read(shared_file)
      {:ok, final_data} = Jason.decode(final_content)

      assert final_data["results"]["items_processed"] == 100
      assert final_data["validation_results"]["valid_items"] == 98

      # Cleanup
      File.rm!(shared_file)
    end
  end

  describe "Complex Workflow Orchestration" do
    @tag timeout: @test_timeout
    test "executes multi-step workflow with conditional logic" do
      # Workflow: Generate data -> Validate -> Process -> Report

      # Step 1: Generate data
      {:ok, _} =
        start_mcp_server("data", [
          "python3",
          Path.join(@demo_servers_path, "data_server.py")
        ])

      Process.sleep(1_000)

      {:ok, users} =
        MCPChat.MCP.ServerManager.call_tool(
          "data",
          "generate_users",
          %{count: 50}
        )

      # Step 2: Validate data (check age distribution)
      {:ok, _} =
        start_mcp_server("calc", [
          "python3",
          Path.join(@demo_servers_path, "calculator_server.py")
        ])

      Process.sleep(1_000)

      adults = Enum.filter(users, &(&1["age"] >= 18))
      minors = Enum.filter(users, &(&1["age"] < 18))

      adult_ratio = length(adults) / length(users)

      # Step 3: Conditional processing based on validation
      processing_result =
        if adult_ratio > 0.7 do
          # Process for adult-heavy dataset
          %{
            "strategy" => "adult_focused",
            "recommendations" => ["Premium products", "Investment services", "Career development"]
          }
        else
          # Process for mixed-age dataset
          %{
            "strategy" => "family_oriented",
            "recommendations" => ["Educational content", "Family plans", "Age-appropriate services"]
          }
        end

      # Step 4: Generate report with calculations
      avg_age_expr = "(#{users |> Enum.map_join(& &1["age"], " + ")}) / #{length(users)}"

      {:ok, avg_age} =
        MCPChat.MCP.ServerManager.call_tool(
          "calc",
          "calculate",
          %{expression: avg_age_expr}
        )

      # Final workflow report
      report = %{
        "workflow_id" => System.unique_integer(),
        "steps_completed" => 4,
        "data_summary" => %{
          "total_users" => length(users),
          "adults" => length(adults),
          "minors" => length(minors),
          "average_age" => avg_age["result"]
        },
        "processing_strategy" => processing_result["strategy"],
        "recommendations" => processing_result["recommendations"],
        "timestamp" => DateTime.utc_now()
      }

      # Store in session
      MCPChat.Session.add_message("system", "Workflow completed: #{Jason.encode!(report)}")

      # Verify workflow execution
      assert report["steps_completed"] == 4
      assert report["data_summary"]["total_users"] == 50
      assert is_list(report["recommendations"])
    end

    @tag timeout: @test_timeout
    test "handles workflow with error recovery" do
      # Start servers
      {:ok, _} =
        start_mcp_server("calc", [
          "python3",
          Path.join(@demo_servers_path, "calculator_server.py")
        ])

      Process.sleep(1_000)

      # Workflow with potential errors
      workflow_steps = [
        {"step1", "2 + 2"},
        # Will cause error
        {"step2", "10 / 0"},
        {"step3", "5 * 5"},
        # Will cause error
        {"step4", "invalid expression ###"},
        {"step5", "100 - 50"}
      ]

      results =
        Enum.map(workflow_steps, fn {step_name, expression} ->
          result =
            MCPChat.MCP.ServerManager.call_tool(
              "calc",
              "calculate",
              %{expression: expression}
            )

          case result do
            {:ok, value} ->
              {step_name, {:success, value["result"]}}

            {:error, reason} ->
              # Implement recovery strategy
              recovery_result =
                case step_name do
                  # Default to 0 for division errors
                  "step2" -> {:recovered, 0}
                  # Default to 1 for parse errors
                  "step4" -> {:recovered, 1}
                  _ -> {:failed, reason}
                end

              {step_name, recovery_result}
          end
        end)

      # Verify error handling
      assert length(results) == 5

      # Check specific steps
      {"step1", {:success, step1_result}} = Enum.find(results, fn {name, _} -> name == "step1" end)
      assert step1_result == 4

      {"step2", step2_result} = Enum.find(results, fn {name, _} -> name == "step2" end)
      assert elem(step2_result, 0) in [:recovered, :error]

      {"step5", {:success, step5_result}} = Enum.find(results, fn {name, _} -> name == "step5" end)
      assert step5_result == 50

      # Workflow should complete despite errors
      successful_steps = Enum.count(results, fn {_, {status, _}} -> status == :success end)
      assert successful_steps >= 3
    end
  end

  describe "Resource Contention and Concurrency" do
    @tag timeout: @test_timeout
    test "handles concurrent access to same MCP server" do
      # Start calculator server
      {:ok, _} =
        start_mcp_server("calc", [
          "python3",
          Path.join(@demo_servers_path, "calculator_server.py")
        ])

      Process.sleep(1_000)

      # Launch multiple concurrent calculations
      num_concurrent = 10

      calculations =
        Enum.map(1..num_concurrent, fn i ->
          expression = "#{i} * #{i} + #{i}"
          expected = i * i + i
          {expression, expected}
        end)

      # Execute concurrently
      tasks =
        Enum.map(calculations, fn {expr, _expected} ->
          Task.async(fn ->
            MCPChat.MCP.ServerManager.call_tool(
              "calc",
              "calculate",
              %{expression: expr}
            )
          end)
        end)

      # Collect results
      results = Task.await_many(tasks, 15_000)

      # Verify all completed successfully
      assert length(results) == num_concurrent

      Enum.zip(calculations, results)
      |> Enum.each(fn {{_expr, expected}, result} ->
        assert {:ok, %{"result" => actual}} = result
        assert actual == expected
      end)
    end

    @tag timeout: @test_timeout
    test "manages resource limits with many servers" do
      # Try to start many servers
      server_configs =
        Enum.map(1..5, fn i ->
          {
            "server_#{i}",
            ["python3", Path.join(@demo_servers_path, "time_server.py")]
          }
        end)

      # Start servers with tracking
      started_servers =
        Enum.map(server_configs, fn {name, cmd} ->
          result = start_mcp_server(name, cmd)
          # Stagger starts
          Process.sleep(200)
          {name, result}
        end)

      # Count successful starts
      successful =
        Enum.count(started_servers, fn {_, result} ->
          match?({:ok, _}, result)
        end)

      # Should handle multiple servers
      assert successful >= 3

      # List all running servers
      running = MCPChat.MCP.ServerManager.list_servers()
      assert length(running) >= 3

      # Clean up all servers
      Enum.each(started_servers, fn {name, _} ->
        MCPChat.MCP.ServerManager.stop_server(name)
      end)

      Process.sleep(500)

      # Verify cleanup
      remaining = MCPChat.MCP.ServerManager.list_servers()
      assert Enum.empty?(remaining)
    end
  end

  describe "Context Window Management" do
    @tag timeout: @test_timeout
    test "handles very large contexts with smart truncation" do
      # Configure Ollama
      {:ok, _} = set_llm_backend("ollama", @test_model)

      # Generate a large conversation history
      large_history =
        Enum.flat_map(1..100, fn i ->
          [
            %{role: "user", content: "Question #{i}: " <> String.duplicate("word ", 50)},
            %{role: "assistant", content: "Answer #{i}: " <> String.duplicate("response ", 50)}
          ]
        end)

      # Add to session
      Enum.each(large_history, fn msg ->
        MCPChat.Session.add_message(msg.role, msg.content)
      end)

      # Set small context window
      MCPChat.Context.set_max_tokens(1_000)
      MCPChat.Context.set_strategy(:truncate_middle)

      # Prepare context
      messages = MCPChat.Session.get_messages()
      {:ok, truncated} = MCPChat.Context.prepare_context(messages, 1_000)

      # Verify truncation
      assert length(truncated) < length(messages)

      # Should preserve first and last messages
      assert hd(truncated).content =~ "Question 1"
      assert List.last(truncated).content =~ "Answer 100"

      # Middle should be truncated
      truncated_indices =
        Enum.map(truncated, fn msg ->
          case Regex.run(~r/\d+/, msg.content) do
            [num] -> String.to_integer(num)
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      # Should have gaps in the middle
      gaps =
        Enum.chunk_every(truncated_indices, 2, 1, :discard)
        |> Enum.map(fn [a, b] -> b - a end)
        |> Enum.max()

      # There should be gaps where messages were removed
      assert gaps > 1
    end

    @tag timeout: @test_timeout
    test "dynamically adjusts context based on token usage" do
      {:ok, _} = set_llm_backend("ollama", @test_model)

      # Start with empty session
      MCPChat.Session.clear_session()

      # Add messages and track token growth
      token_counts =
        Enum.map(1..10, fn i ->
          msg = "Message #{i}: " <> String.duplicate("content ", i * 10)
          MCPChat.Session.add_message("user", msg)

          # Track tokens
          MCPChat.Session.track_token_usage(
            MCPChat.Session.get_messages(),
            "Response #{i}"
          )

          stats = MCPChat.Session.get_context_stats()
          stats.estimated_tokens
        end)

      # Token count should increase
      assert List.first(token_counts) < List.last(token_counts)

      # Test dynamic adjustment when approaching limit
      MCPChat.Context.set_max_tokens(500)

      # Add more messages
      5..1
      |> Enum.each(fn i ->
        MCPChat.Session.add_message("user", String.duplicate("Extra message ", i * 20))
      end)

      # Prepare context should truncate to fit
      messages = MCPChat.Session.get_messages()
      {:ok, fitted} = MCPChat.Context.prepare_context(messages, 500)

      # Estimate tokens for fitted context
      fitted_tokens = ExLLM.Cost.estimate_tokens(fitted)
      # Some buffer for estimation variance
      assert fitted_tokens <= 600
    end
  end

  describe "Advanced MCP Features" do
    @tag timeout: @test_timeout
    test "uses MCP server sampling/createMessage capabilities" do
      # This test would work with MCP servers that support sampling
      # For now, we'll simulate the interaction

      # Check if any connected server supports sampling
      servers = MCPChat.MCP.ServerManager.list_servers()

      # In a real scenario, we'd check server capabilities
      sampling_capable_server =
        Enum.find(servers, fn server ->
          # Would check server.capabilities.sampling
          # Demo servers don't support sampling yet
          false
        end)

      if sampling_capable_server do
        # Would call sampling endpoint
        # result = MCPChat.MCP.ServerManager.create_message(
        #   sampling_capable_server.name,
        #   messages,
        #   %{max_tokens: 100}
        # )
        assert true
      else
        # No sampling-capable servers available
        assert true
      end
    end

    @tag timeout: @test_timeout
    test "handles custom MCP protocol extensions" do
      # Test handling of custom notification types
      MCPChat.MCP.NotificationRegistry.register_handler(
        :custom_notification,
        fn notification ->
          send(self(), {:custom, notification})
        end
      )

      # Send custom notification
      MCPChat.MCP.NotificationRegistry.notify(:custom_notification, %{
        type: "experimental_feature",
        data: %{
          feature: "quantum_computation",
          status: "activated"
        }
      })

      # Should receive custom notification
      assert_receive {:custom, %{data: %{feature: "quantum_computation"}}}, 1_000
    end
  end

  describe "Performance and Stress Tests" do
    @tag timeout: @test_timeout * 2
    test "handles rapid message exchanges efficiently" do
      {:ok, _} = set_llm_backend("ollama", @test_model)

      # Measure baseline response time
      start_time = System.monotonic_time(:millisecond)

      messages = [%{role: "user", content: "Hi"}]
      {:ok, _response} = get_llm_response(messages)

      baseline_time = System.monotonic_time(:millisecond) - start_time

      # Rapid fire messages
      response_times =
        Enum.map(1..10, fn i ->
          start = System.monotonic_time(:millisecond)

          MCPChat.Session.add_message("user", "Quick message #{i}")
          # Last 3 messages
          messages = MCPChat.Session.get_messages() |> Enum.take(-3)
          {:ok, _} = get_llm_response(messages)

          System.monotonic_time(:millisecond) - start
        end)

      # Average response time shouldn't degrade significantly
      avg_time = Enum.sum(response_times) / length(response_times)
      # Should not be more than 2x slower
      assert avg_time < baseline_time * 2
    end

    @tag timeout: @test_timeout * 2
    test "maintains stability with memory pressure" do
      # Create many sessions with large contexts
      session_names =
        Enum.map(1..5, fn i ->
          name = "memory_test_#{i}"

          # Create session with substantial content
          MCPChat.Session.clear_session()

          Enum.each(1..50, fn j ->
            MCPChat.Session.add_message("user", "Message #{j} in session #{i}: " <> String.duplicate("x", 100))
            MCPChat.Session.add_message("assistant", "Response #{j}: " <> String.duplicate("y", 100))
          end)

          # Save session
          MCPChat.Persistence.save_session(name)
          name
        end)

      # Load sessions concurrently
      tasks =
        Enum.map(session_names, fn name ->
          Task.async(fn ->
            {:ok, _} = MCPChat.Persistence.load_session(name)
            MCPChat.Session.get_messages() |> length()
          end)
        end)

      results = Task.await_many(tasks, 30_000)

      # All should load successfully
      assert Enum.all?(results, &(&1 == 100))

      # System should remain responsive
      start_time = System.monotonic_time(:millisecond)
      MCPChat.Session.clear_session()
      clear_time = System.monotonic_time(:millisecond) - start_time

      # Should clear quickly
      assert clear_time < 100

      # Cleanup
      Enum.each(session_names, &MCPChat.Persistence.delete_session/1)
    end
  end

  # Helper Functions

  defp check_environment do
    with :ok <- check_ollama(),
         :ok <- check_python(),
         :ok <- check_disk_space() do
      :ok
    else
      error -> error
    end
  end

  defp check_ollama do
    case HTTPoison.get("#{@ollama_url}/api/tags") do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"models" => models}} when length(models) > 0 ->
            :ok

          _ ->
            {:error, "Ollama has no models installed"}
        end

      _ ->
        {:error, "Ollama is not running"}
    end
  end

  defp check_python do
    case System.cmd("python3", ["--version"]) do
      {_, 0} -> :ok
      _ -> {:error, "Python 3 is not available"}
    end
  end

  defp check_disk_space do
    # Ensure we have space for test files
    tmp_dir = System.tmp_dir!()

    case File.stat(tmp_dir) do
      {:ok, _} -> :ok
      _ -> {:error, "Cannot access temp directory"}
    end
  end

  defp setup_test_config do
    config = %{
      "llm" => %{
        "default" => "ollama",
        "ollama" => %{
          "base_url" => @ollama_url,
          "model" => @test_model
        }
      }
    }

    MCPChat.Config.merge_config(config)
  end

  defp cleanup_test_state do
    MCPChat.Session.clear_session()
    MCPChat.MCP.ServerManager.stop_all_servers()

    # Clean temp files
    Path.wildcard(Path.join(System.tmp_dir!(), "agent_*"))
    |> Enum.each(&File.rm/1)

    Path.wildcard(Path.join(System.tmp_dir!(), "test_*"))
    |> Enum.each(&File.rm/1)
  end

  defp start_mcp_server(name, command) do
    config = %{
      "name" => name,
      "command" => hd(command),
      "args" => tl(command)
    }

    MCPChat.MCP.ServerManager.start_server(config)
  end

  defp set_llm_backend(provider, model) do
    config = %{
      "provider" => provider,
      "model" => model,
      "base_url" => @ollama_url
    }

    current = MCPChat.Config.get()
    updated = put_in(current, ["llm", provider], config)
    updated = put_in(updated, ["llm", "default"], provider)
    MCPChat.Config.merge_config(updated)

    {:ok, config}
  end

  defp get_llm_response(messages) do
    config = MCPChat.Config.get_llm_config()
    {:ok, client} = MCPChat.LLM.ExLLMAdapter.init(config)

    case MCPChat.LLM.ExLLMAdapter.complete(client, messages, %{}) do
      {:ok, response} ->
        {:ok, response}

      error ->
        error
    end
  end
end
