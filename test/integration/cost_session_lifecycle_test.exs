defmodule MCPChat.CostSessionLifecycleIntegrationTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Integration tests for cost session lifecycle and persistence.
  Tests the full flow of cost tracking from session creation through persistence.
  """

  @test_dir "test/tmp/cost_sessions"
  alias MCPChat.PathProvider.Static
  alias MCPChat.{Persistence, Session}
  alias MCPChat.Types.Session, as: SessionType

  setup_all do
    Application.ensure_all_started(:mcp_chat)
    # Create test directory
    File.mkdir_p!(@test_dir)

    on_exit(fn ->
      # Cleanup test directory
      File.rm_rf!(@test_dir)
    end)

    # Create stub for ExLLM modules if not available
    ensure_exllm_modules()

    :ok
  end

  setup do
    # Clear session before each test
    Session.clear_session()
    Process.sleep(10)

    # Start a static path provider for this test
    {:ok, path_provider} =
      Static.start_link(%{
        sessions_dir: @test_dir,
        config_dir: @test_dir
      })

    {:ok, path_provider: path_provider}
  end

  describe "Cost session initialization" do
    test "new session includes cost_session field" do
      {:ok, _session} = Session.new_session("anthropic")
      current_session = Session.get_current_session()

      assert current_session.cost_session != nil
      assert current_session.cost_session.session_id == current_session.id
      assert current_session.cost_session.total_cost == 0.0
      assert current_session.cost_session.total_input_tokens == 0
      assert current_session.cost_session.total_output_tokens == 0
    end

    test "cost session persists across session operations" do
      {:ok, _} = Session.new_session("openai")

      # Add messages and track costs
      Session.add_message("user", "Hello, how are you?")
      Session.add_message("assistant", "I'm doing well, thank you!")

      # Simulate cost tracking with a numeric value
      Session.track_cost(0.0_001)
      Process.sleep(10)

      session = Session.get_current_session()
      assert session.accumulated_cost == 0.0_001
      assert session.cost_session != nil
    end
  end

  describe "Cost tracking through conversation flow" do
    test "tracks costs across multiple message exchanges" do
      {:ok, _} = Session.new_session("anthropic")
      Session.set_context(%{model: "claude-3-haiku-20240307"})

      # Simulate multiple exchanges
      exchanges = [
        {0.00_005, 100, 50},
        {0.00_008, 150, 75},
        {0.00_012, 200, 100}
      ]

      # Track costs individually and sum them
      Enum.each(exchanges, fn {cost, _input_tokens, _output_tokens} ->
        Session.add_message("user", "Question")
        Session.add_message("assistant", "Answer")
        Session.track_cost(cost)
        # Give more time for cast to process
        Process.sleep(50)
      end)

      # Let's check the state after each cost tracking step
      # Extra wait to ensure all casts are processed
      Process.sleep(100)

      # Calculate expected total
      expected_total = exchanges |> Enum.map(&elem(&1, 0)) |> Enum.sum()

      session = Session.get_current_session()
      assert_in_delta session.accumulated_cost || 0.0, expected_total, 0.00_001
    end

    test "maintains cost data when updating context" do
      {:ok, _} = Session.new_session("gemini")

      # Track initial cost
      Session.track_cost(0.0_002)
      Process.sleep(10)

      # Update context
      Session.set_context(%{model: "gemini-pro", temperature: 0.7})
      Process.sleep(10)

      # Track more cost
      Session.track_cost(0.0_003)
      Process.sleep(10)

      session = Session.get_current_session()
      assert_in_delta session.accumulated_cost, 0.0_005, 0.00_001
    end
  end

  describe "Cost session persistence" do
    test "saves and loads session with cost data", %{path_provider: path_provider} do
      # Create session with cost data
      {:ok, _} = Session.new_session("anthropic")
      Session.set_context(%{model: "claude-3-sonnet-20240229"})

      # Add messages and costs
      Session.add_message("user", "Explain quantum computing")
      Session.add_message("assistant", "Quantum computing is...")
      Session.track_cost(0.00_125)

      Session.add_message("user", "What are qubits?")
      Session.add_message("assistant", "Qubits are quantum bits...")
      Session.track_cost(0.00_087)

      Process.sleep(10)

      original_session = Session.get_current_session()
      session_name = "cost_test_#{System.unique_integer([:positive])}"

      # Save session
      {:ok, path} = Persistence.save_session(original_session, session_name, path_provider: path_provider)
      assert File.exists?(path)

      # Clear and load
      Session.clear_session()
      Process.sleep(10)

      {:ok, loaded_session} = Persistence.load_session(session_name, path_provider: path_provider)

      # Verify cost data persisted
      assert_in_delta loaded_session.accumulated_cost || 0.0, 0.00_212, 0.00_001
      assert length(loaded_session.messages) == 4
    end

    test "exports session with cost information", %{path_provider: _path_provider} do
      # Create session with costs
      {:ok, _} = Session.new_session("openai")
      Session.set_context(%{model: "gpt-4"})

      Session.add_message("user", "Write a poem")
      Session.add_message("assistant", "Here's a poem for you...")
      Session.track_cost(0.0_045)
      Process.sleep(10)

      session = Session.get_current_session()

      # Export as JSON
      export_path = Path.join(@test_dir, "export_test.json")
      {:ok, _} = Persistence.export_session(session, :json, export_path)

      # Read the exported file
      {:ok, content} = File.read(export_path)

      # Parse and verify
      {:ok, json_data} = Jason.decode(content)
      assert json_data["accumulated_cost"] == 0.0_045
      assert json_data["llm_backend"] == "openai"
      assert json_data["context"]["model"] == "gpt-4"
    end

    test "handles session with no cost data gracefully", %{path_provider: path_provider} do
      # Create session without tracking any costs
      {:ok, _} = Session.new_session()
      Session.add_message("user", "Hello")
      Session.add_message("assistant", "Hi!")

      session = Session.get_current_session()
      session_name = "no_cost_#{System.unique_integer([:positive])}"

      # Save and load
      {:ok, _} = Persistence.save_session(session, session_name, path_provider: path_provider)
      {:ok, loaded_session} = Persistence.load_session(session_name, path_provider: path_provider)

      # Should have nil or 0 cost
      assert loaded_session.accumulated_cost == nil || loaded_session.accumulated_cost == 0.0
    end
  end

  describe "Cost session lifecycle edge cases" do
    test "handles session restoration with cost data" do
      # Create a session struct with cost data
      test_session = %SessionType{
        id: "test-restore-#{System.unique_integer([:positive])}",
        llm_backend: "anthropic",
        messages: [
          %{role: "user", content: "Test", timestamp: DateTime.utc_now()},
          %{role: "assistant", content: "Response", timestamp: DateTime.utc_now()}
        ],
        context: %{model: "claude-3-haiku-20240307"},
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        token_usage: %{input_tokens: 50, output_tokens: 100},
        accumulated_cost: 0.00_075,
        cost_session: nil,
        metadata: %{test: true}
      }

      # Restore session
      :ok = Session.restore_session(test_session)

      restored = Session.get_current_session()
      assert restored.id == test_session.id
      assert restored.accumulated_cost == 0.00_075
      assert length(restored.messages) == 2
    end

    test "maintains cost tracking after clearing messages" do
      {:ok, _} = Session.new_session("gemini")

      # Track some costs
      Session.track_cost(0.001)
      Session.track_cost(0.002)
      Process.sleep(10)

      # Clear messages but not the session
      Session.clear_session()
      Process.sleep(10)

      # Cost should be reset with new session
      session = Session.get_current_session()
      assert session.accumulated_cost == nil || session.accumulated_cost == 0.0
    end

    test "cost accumulation with concurrent updates" do
      {:ok, _} = Session.new_session("openai")

      # Simulate concurrent cost updates
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            cost = i * 0.0_001
            Session.track_cost(cost)
            cost
          end)
        end

      costs = Task.await_many(tasks)
      expected_total = Enum.sum(costs)

      # Allow all casts to process
      Process.sleep(50)

      session = Session.get_current_session()
      assert_in_delta session.accumulated_cost || 0.0, expected_total, 0.00_001
    end
  end

  # Helper to ensure ExLLM modules exist for testing
  defp ensure_exllm_modules do
    unless Code.ensure_loaded?(ExLLM.Cost.Session) do
      defmodule ExLLM.Cost.Session do
        defstruct [
          :session_id,
          :start_time,
          total_cost: 0.0,
          total_input_tokens: 0,
          total_output_tokens: 0,
          messages: [],
          provider_breakdown: %{},
          model_breakdown: %{}
        ]

        def new(session_id) do
          %__MODULE__{
            session_id: session_id,
            start_time: DateTime.utc_now(),
            total_cost: 0.0,
            total_input_tokens: 0,
            total_output_tokens: 0,
            messages: [],
            provider_breakdown: %{},
            model_breakdown: %{}
          }
        end

        def add_response(session, _response) do
          # Simple stub - just return the session unchanged
          session
        end
      end
    end
  end
end
