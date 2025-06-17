defmodule MCPChat.Session.ExLLMSessionAdapterTest do
  use ExUnit.Case
  alias MCPChat.Session.ExLLMSessionAdapter, as: Adapter
  alias MCPChat.Types.Session, as: MCPChatSession

  setup do
    # Ensure config is started
    case Process.whereis(MCPChat.Config) do
      nil -> {:ok, _} = MCPChat.Config.start_link()
      _pid -> :ok
    end

    # Create stub module for ExLLM.Cost.Session if it doesn't exist
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

    :ok
  end

  describe "new_session/2" do
    test "creates a new session with default backend" do
      session = Adapter.new_session()

      assert %MCPChatSession{} = session
      assert session.id != nil
      assert String.length(session.id) > 0
      assert session.messages == []
      assert session.context == %{}
      assert session.created_at != nil
      assert session.updated_at != nil
      assert session.token_usage == %{input_tokens: 0, output_tokens: 0}
      assert session.cost_session != nil
      assert %ExLLM.Cost.Session{} = session.cost_session
      assert session.cost_session.session_id == session.id
    end

    test "creates a new session with specified backend" do
      session = Adapter.new_session("openai")

      assert session.llm_backend == "openai"
    end

    test "initializes ExLLM cost session" do
      session = Adapter.new_session("anthropic")

      assert session.cost_session != nil
      assert session.cost_session.session_id == session.id
      assert session.cost_session.total_cost == 0.0
      assert session.cost_session.total_input_tokens == 0
      assert session.cost_session.total_output_tokens == 0
      assert session.cost_session.messages == []
      assert session.cost_session.provider_breakdown == %{}
      assert session.cost_session.model_breakdown == %{}
    end
  end

  describe "track_cost/2" do
    setup do
      session = Adapter.new_session("anthropic")
      {:ok, session: session}
    end

    test "tracks cost from numeric value (legacy support)", %{session: session} do
      updated_session = Adapter.track_cost(session, 0.0_005)

      assert updated_session.accumulated_cost == 0.0_005
      # Cost session should not be updated for legacy numeric costs
      assert updated_session.cost_session == session.cost_session
    end

    test "handles responses without cost data", %{session: session} do
      # Response without cost field should keep existing accumulated cost
      response = %{content: "No cost response"}

      updated_session = Adapter.track_cost(session, response)

      # Should preserve whatever cost was already there (nil or 0.0)
      assert updated_session.accumulated_cost == session.accumulated_cost || updated_session.accumulated_cost == 0.0
    end

    test "accumulates simple numeric costs", %{session: session} do
      session = Adapter.track_cost(session, 0.0_001)
      session = Adapter.track_cost(session, 0.0_002)

      # Use approximate comparison for floating point
      assert_in_delta session.accumulated_cost, 0.0_003, 0.0000001
    end
  end

  describe "add_message/3" do
    test "adds a message to the session" do
      session = Adapter.new_session()
      updated_session = Adapter.add_message(session, "user", "Hello!")

      assert length(updated_session.messages) == 1
      [message] = updated_session.messages
      assert message.role == "user"
      assert message.content == "Hello!"
      assert message.timestamp != nil
    end

    test "preserves message order" do
      session = Adapter.new_session()

      session = Adapter.add_message(session, "user", "First")
      session = Adapter.add_message(session, "assistant", "Second")
      session = Adapter.add_message(session, "user", "Third")

      assert length(session.messages) == 3
      assert Enum.at(session.messages, 0).content == "First"
      assert Enum.at(session.messages, 1).content == "Second"
      assert Enum.at(session.messages, 2).content == "Third"
    end
  end

  describe "set_system_prompt/2" do
    test "sets system prompt as first message" do
      session = Adapter.new_session()
      session = Adapter.add_message(session, "user", "Hello")

      updated_session = Adapter.set_system_prompt(session, "You are helpful")

      assert length(updated_session.messages) == 2
      [system_msg | _] = updated_session.messages
      assert system_msg.role == "system"
      assert system_msg.content == "You are helpful"
    end

    test "replaces existing system prompt" do
      session = Adapter.new_session()
      session = Adapter.set_system_prompt(session, "Old prompt")
      session = Adapter.add_message(session, "user", "Hello")

      updated_session = Adapter.set_system_prompt(session, "New prompt")

      assert length(updated_session.messages) == 2
      [system_msg | _] = updated_session.messages
      assert system_msg.content == "New prompt"
    end
  end

  describe "update_context/2" do
    test "merges context updates" do
      session = Adapter.new_session()
      session = Adapter.set_context(session, %{model: "gpt-4", max_tokens: 1_000})

      updated_session = Adapter.update_context(session, %{max_tokens: 2000, temperature: 0.7})

      assert updated_session.context == %{
               model: "gpt-4",
               max_tokens: 2000,
               temperature: 0.7
             }
    end
  end

  describe "track_token_usage/2" do
    test "tracks token usage with atom keys" do
      session = Adapter.new_session()
      usage = %{input_tokens: 100, output_tokens: 50}

      updated_session = Adapter.track_token_usage(session, usage)

      assert updated_session.token_usage == %{input_tokens: 100, output_tokens: 50}
    end

    test "tracks token usage with string keys (backward compatibility)" do
      session = Adapter.new_session()
      usage = %{"input_tokens" => 200, "output_tokens" => 100}

      updated_session = Adapter.track_token_usage(session, usage)

      assert updated_session.token_usage == %{input_tokens: 200, output_tokens: 100}
    end

    test "handles mixed key types" do
      session = Adapter.new_session()
      usage = %{:input_tokens => 150, "output_tokens" => 75}

      updated_session = Adapter.track_token_usage(session, usage)

      assert updated_session.token_usage == %{input_tokens: 150, output_tokens: 75}
    end
  end

  describe "get_context_stats/1" do
    test "returns context statistics" do
      session = Adapter.new_session()
      session = Adapter.set_context(session, %{max_tokens: 2000})
      session = Adapter.add_message(session, "user", "Hello")
      session = Adapter.add_message(session, "assistant", "Hi there!")

      stats = Adapter.get_context_stats(session)

      assert stats.message_count == 2
      assert stats.estimated_tokens > 0
      assert stats.max_tokens == 2000
      assert stats.tokens_used_percentage > 0
      assert stats.tokens_remaining < 2000
    end
  end

  describe "get_session_cost/2" do
    test "calculates session cost with token usage" do
      session = Adapter.new_session("anthropic")
      session = Adapter.set_context(session, %{model: "claude-3-haiku-20240307"})
      session = Adapter.track_token_usage(session, %{input_tokens: 1_000, output_tokens: 500})

      cost_info = Adapter.get_session_cost(session)

      assert cost_info.backend == "anthropic"
      assert cost_info.model == "claude-3-haiku-20240307"
      assert cost_info.input_tokens == 1_000
      assert cost_info.output_tokens == 500
      assert cost_info.total_cost > 0
    end

    test "returns cost info even with zero token usage" do
      session = Adapter.new_session()

      # When no token usage, it returns a cost info with 0 values
      cost_info = Adapter.get_session_cost(session)

      assert cost_info.total_cost == 0.0
      assert cost_info.input_tokens == 0
      assert cost_info.output_tokens == 0
    end
  end

  describe "serialization" do
    test "converts to JSON and back" do
      session = Adapter.new_session("openai")
      session = Adapter.add_message(session, "user", "Test message")
      session = Adapter.set_context(session, %{model: "gpt-4"})

      {:ok, json} = Adapter.to_json(session)
      assert is_binary(json)

      {:ok, restored_session} = Adapter.from_json(json)

      assert restored_session.id == session.id
      assert restored_session.llm_backend == session.llm_backend
      assert length(restored_session.messages) == 1
      # Context might have string keys after deserialization
      assert restored_session.context == session.context ||
               restored_session.context == %{"model" => "gpt-4"}
    end
  end

  describe "update_session/2" do
    test "updates session fields" do
      session = Adapter.new_session()

      updates = %{
        llm_backend: "gemini",
        context: %{temperature: 0.9},
        metadata: %{custom: "data"}
      }

      updated_session = Adapter.update_session(session, updates)

      assert updated_session.llm_backend == "gemini"
      assert updated_session.context == %{temperature: 0.9}
      assert updated_session.metadata == %{custom: "data"}
      assert updated_session.updated_at != session.updated_at
    end
  end
end
