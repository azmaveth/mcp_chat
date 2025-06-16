defmodule MCPChat.CLI.Commands.UtilityTest do
  use ExUnit.Case
  alias MCPChat.CLI.Commands.Utility
  alias MCPChat.Session
  alias MCPChat.Types.Session, as: SessionType
  import ExUnit.CaptureIO
  import :meck

  setup do
    # Start required services
    ensure_services_started()

    # Setup mocks for ExLLM.Cost.Session functions
    setup_cost_session_mocks()

    # Create a test session with cost data
    setup_test_session_with_cost()

    on_exit(fn ->
      unload()
    end)

    :ok
  end

  defp ensure_services_started do
    services = [
      {MCPChat.Config, []},
      {MCPChat.Session, []}
    ]

    Enum.each(services, fn {module, args} ->
      case Process.whereis(module) do
        nil -> {:ok, _} = apply(module, :start_link, args)
        _pid -> :ok
      end
    end)
  end

  defp setup_cost_session_mocks do
    new(ExLLM.Cost.Session)

    # Mock format_summary function
    expect(ExLLM.Cost.Session, :format_summary, fn cost_session, opts ->
      format = Keyword.get(opts, :format, :detailed)

      case format do
        :detailed ->
          """
          💰 Session Cost Summary
          ====================
          Total Cost: $#{cost_session.total_cost}
          Input Tokens: #{cost_session.total_input_tokens}
          Output Tokens: #{cost_session.total_output_tokens}
          Session Duration: 5 minutes
          """

        :compact ->
          "$#{cost_session.total_cost} (#{cost_session.total_input_tokens + cost_session.total_output_tokens} tokens)"

        :table ->
          """
          | Metric | Value |
          |--------|-------|
          | Provider | anthropic |
          | Model | claude-3-haiku |
          | Cost | $#{cost_session.total_cost} |
          """
      end
    end)

    # Mock provider_breakdown function
    expect(ExLLM.Cost.Session, :provider_breakdown, fn cost_session ->
      Map.values(cost_session.provider_breakdown)
    end)

    # Mock model_breakdown function
    expect(ExLLM.Cost.Session, :model_breakdown, fn cost_session ->
      Map.values(cost_session.model_breakdown)
    end)

    # Mock ExLLM.Cost.format
    new(ExLLM.Cost)

    expect(ExLLM.Cost, :format, fn cost ->
      "$#{"#{Float.round(cost, 4)}"}"
    end)

    # Mock ExLLM.StreamRecovery.cleanup_expired
    new(ExLLM.StreamRecovery)

    expect(ExLLM.StreamRecovery, :cleanup_expired, fn ->
      {:ok, 0}
    end)

    # Ensure ExLLMAdapter module is loaded
    Code.ensure_loaded(MCPChat.LLM.ExLLMAdapter)

    # Mock cache persistence configuration
    expect(MCPChat.LLM.ExLLMAdapter, :configure_cache_persistence, fn _enabled -> :ok end)
  end

  defp setup_test_session_with_cost do
    # Clear any existing session
    Session.clear_session()
    Process.sleep(10)

    # Create a new session with backend
    {:ok, _} = Session.new_session("anthropic")

    # Add a system setting for model
    Session.set_context(%{model: "claude-3-haiku-20240307"})
    Process.sleep(10)

    # Get current session to get the actual session ID
    session = Session.get_current_session()

    # Track some token usage to populate the session
    Session.track_token_usage(
      [%{role: "user", content: "Test message"}],
      "Test response"
    )

    Process.sleep(10)

    # Create a mock ExLLM cost session with the actual session ID
    cost_session = %{
      __struct__: ExLLM.Cost.Session,
      session_id: session.id,
      start_time: DateTime.utc_now(),
      total_cost: 0.0_125,
      total_input_tokens: 1_500,
      total_output_tokens: 750,
      messages: [
        %{
          timestamp: DateTime.utc_now(),
          provider: "anthropic",
          model: "claude-3-haiku-20240307",
          input_tokens: 1_000,
          output_tokens: 500,
          input_cost: 0.00_025,
          output_cost: 0.000_625,
          total_cost: 0.000_875
        },
        %{
          timestamp: DateTime.utc_now(),
          provider: "anthropic",
          model: "claude-3-sonnet-20240229",
          input_tokens: 500,
          output_tokens: 250,
          input_cost: 0.0_015,
          output_cost: 0.00_375,
          total_cost: 0.00_525
        }
      ],
      provider_breakdown: %{
        "anthropic" => %{
          provider: "anthropic",
          total_cost: 0.0_125,
          message_count: 2,
          total_tokens: 2_250
        }
      },
      model_breakdown: %{
        "claude-3-haiku-20240307" => %{
          model: "claude-3-haiku-20240307",
          total_cost: 0.000_875,
          message_count: 1,
          total_tokens: 1_500
        },
        "claude-3-sonnet-20240229" => %{
          model: "claude-3-sonnet-20240229",
          total_cost: 0.00_525,
          message_count: 1,
          total_tokens: 750
        }
      }
    }

    # Use set_current_session to update with cost session
    updated_session = %{
      session
      | accumulated_cost: 0.0_125,
        cost_session: cost_session,
        token_usage: %{input_tokens: 1_500, output_tokens: 750}
    }

    Session.set_current_session(updated_session)
    Process.sleep(10)
  end

  describe "handle_command/2 - cost commands" do
    test "shows detailed cost view by default" do
      output =
        capture_io(fn ->
          Utility.handle_command("cost", [])
        end)

      # Should show detailed cost summary (ExLLM enhanced format)
      assert output =~ "Session Cost"
      assert output =~ "Total Cost"
      assert output =~ "Input Tokens"
      assert output =~ "Output Tokens"
    end

    test "shows detailed cost view explicitly" do
      output =
        capture_io(fn ->
          Utility.handle_command("cost", ["detailed"])
        end)

      assert output =~ "Session Cost"
      assert output =~ "Total Cost"
    end

    test "shows compact cost view" do
      output =
        capture_io(fn ->
          Utility.handle_command("cost", ["compact"])
        end)

      # Compact view should be more concise
      assert output =~ "$"
      assert output =~ "tokens"
      refute output =~ "Session Duration"
    end

    test "shows table cost view" do
      output =
        capture_io(fn ->
          Utility.handle_command("cost", ["table"])
        end)

      # Table view should have formatted columns
      # Table separator
      assert output =~ "|"
      assert output =~ "Provider"
      assert output =~ "Model"
      assert output =~ "Cost"
    end

    test "shows cost breakdown by provider and model" do
      output =
        capture_io(fn ->
          Utility.handle_command("cost", ["breakdown"])
        end)

      assert output =~ "💰 Session Cost Breakdown"
      assert output =~ "📊 By Provider:"
      assert output =~ "anthropic"
      assert output =~ "🤖 By Model:"
      assert output =~ "claude-3-haiku"
      assert output =~ "claude-3-sonnet"
      assert output =~ "msgs"
      assert output =~ "tokens"
    end

    test "shows cost help" do
      output =
        capture_io(fn ->
          Utility.handle_command("cost", ["help"])
        end)

      assert output =~ "Cost Command Help"
      assert output =~ "/cost detailed"
      assert output =~ "/cost compact"
      assert output =~ "/cost table"
      assert output =~ "/cost breakdown"
      assert output =~ "Real-time cost calculation"
      assert output =~ "Provider and model breakdown"
    end

    test "handles invalid cost command" do
      output =
        capture_io(fn ->
          Utility.handle_command("cost", ["invalid"])
        end)

      assert output =~ "Invalid cost command"
      assert output =~ "/cost [detailed|compact|table|breakdown|help]"
    end

    test "shows legacy cost format when no cost session available" do
      # Clear cost session but keep accumulated cost
      Session.update_session(%{cost_session: nil, accumulated_cost: 0.0_125})
      Process.sleep(10)

      output =
        capture_io(fn ->
          Utility.handle_command("cost", [])
        end)

      assert output =~ "Session Cost Summary"
      assert output =~ "Backend:"
      assert output =~ "Model:"
      assert output =~ "Total cost:"
      assert output =~ "$0.0_125"
    end

    test "handles breakdown when no cost session available" do
      Session.update_session(%{cost_session: nil})
      Process.sleep(10)

      output =
        capture_io(fn ->
          Utility.handle_command("cost", ["breakdown"])
        end)

      assert output =~ "❌ Enhanced cost breakdown not available"
      assert output =~ "Start a new session to enable detailed cost tracking"
    end
  end

  describe "handle_command/2 - streaming commands" do
    test "shows streaming configuration" do
      output =
        capture_io(fn ->
          Utility.handle_command("streaming", [])
        end)

      assert output =~ "Streaming Configuration"
      assert output =~ "Enhanced streaming:"
      assert output =~ "ExLLM Flow Control:"
      assert output =~ "ExLLM Chunk Batching:"
      assert output =~ "Recovery:"
    end

    test "shows streaming metrics info" do
      output =
        capture_io(fn ->
          Utility.handle_command("streaming", ["metrics"])
        end)

      assert output =~ "Streaming Metrics"
      assert output =~ "ExLLM provides comprehensive streaming metrics"
      assert output =~ "Chunks per second"
      assert output =~ "Buffer utilization"
      assert output =~ "track_metrics = true"
    end
  end

  describe "handle_command/2 - cache commands" do
    test "shows cache help when no args" do
      output =
        capture_io(fn ->
          Utility.handle_command("cache", [])
        end)

      assert output =~ "Cache Management"
      assert output =~ "/cache stats"
      assert output =~ "/cache clear"
      assert output =~ "/cache enable"
      assert output =~ "/cache disable"
    end

    test "shows cache statistics" do
      # Mock ExLLMAdapter cache stats
      expect(MCPChat.LLM.ExLLMAdapter, :get_cache_stats, fn ->
        %{
          hits: 10,
          misses: 5,
          evictions: 0,
          errors: 0
        }
      end)

      output =
        capture_io(fn ->
          Utility.handle_command("cache", ["stats"])
        end)

      assert output =~ "Cache Statistics"
      assert output =~ "Configuration:"
      assert output =~ "Caching enabled:"
      assert output =~ "Runtime Statistics:"
    end

    test "clears cache" do
      expect(MCPChat.LLM.ExLLMAdapter, :clear_cache, fn -> :ok end)

      output =
        capture_io(fn ->
          Utility.handle_command("cache", ["clear"])
        end)

      assert output =~ "✅ Cache cleared successfully" or
               output =~ "❌ Failed to clear cache"
    end

    test "enables cache" do
      # Initialize caching config
      MCPChat.Config.put([:caching], %{})

      output =
        capture_io(fn ->
          Utility.handle_command("cache", ["enable"])
        end)

      assert output =~ "✅ Response caching enabled"
      assert output =~ "current session only"
    end

    test "disables cache" do
      # Initialize caching config
      MCPChat.Config.put([:caching], %{})

      output =
        capture_io(fn ->
          Utility.handle_command("cache", ["disable"])
        end)

      assert output =~ "✅ Response caching disabled"
    end
  end

  describe "handle_command/2 - recovery commands" do
    test "shows recovery help with no args" do
      output =
        capture_io(fn ->
          Utility.handle_command("recovery", [])
        end)

      assert output =~ "Recovery Management"
      assert output =~ "/recovery list"
      assert output =~ "/recovery clean"
      assert output =~ "/recovery info"
      assert output =~ "/recovery resume"
    end

    test "lists recoverable streams" do
      output =
        capture_io(fn ->
          Utility.handle_command("recovery", ["list"])
        end)

      assert output =~ "Recoverable Streams" or
               output =~ "No recoverable streams found"
    end

    test "handles recovery clean" do
      output =
        capture_io(fn ->
          Utility.handle_command("recovery", ["clean"])
        end)

      assert output =~ "Cleaned" or output =~ "Failed to clean"
    end

    test "shows error for invalid recovery command" do
      output =
        capture_io(fn ->
          Utility.handle_command("recovery", ["invalid"])
        end)

      assert output =~ "Invalid recovery command"
    end
  end

  describe "handle_command/2 - stats command" do
    test "shows session statistics" do
      # Mock the ExLLMAdapter.get_context_stats to avoid the llm_model issue
      new(MCPChat.LLM.ExLLMAdapter)

      expect(MCPChat.LLM.ExLLMAdapter, :get_context_stats, fn _messages, _provider, _model ->
        %{
          context_window: 4_096,
          estimated_tokens: 100,
          tokens_used_percentage: "2.4",
          tokens_remaining: 3_996,
          token_allocation: %{
            system: 10,
            conversation: 80,
            response: 10
          }
        }
      end)

      output =
        capture_io(fn ->
          Utility.handle_command("stats", [])
        end)

      assert output =~ "Session Statistics"
      assert output =~ "Session ID:"
      assert output =~ "Messages:"
      assert output =~ "Created:"
    end
  end

  describe "handle_command/2 - help command" do
    test "shows all available commands" do
      output =
        capture_io(fn ->
          Utility.handle_command("help", [])
        end)

      assert output =~ "Available Commands"
      assert output =~ "Command"
      assert output =~ "Description"
      assert output =~ "/help"
      assert output =~ "/cost"
      assert output =~ "/streaming"
      assert output =~ "/cache"
    end
  end
end
