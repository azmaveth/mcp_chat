defmodule MCPChat.SessionTest do
  use ExUnit.Case
  alias MCPChat.Session

  setup do
    # Start Config GenServer first
    case Process.whereis(MCPChat.Config) do
      nil -> {:ok, _} = MCPChat.Config.start_link()
      _pid -> :ok
    end

    # Start the Session GenServer if not already started
    case Process.whereis(Session) do
      nil ->
        {:ok, _} = Session.start_link()

      pid ->
        # Clear any existing session
        Session.clear_session()
        {:ok, pid}
    end

    :ok
  end

  describe "new_session/1" do
    test "creates a new session with default backend" do
      {:ok, session} = Session.new_session()

      assert session.id != nil
      # 16 bytes hex encoded
      assert String.length(session.id) == 32
      assert session.messages == []
      assert session.context == %{}
      assert session.created_at != nil
      assert session.updated_at != nil
      assert session.token_usage == %{input_tokens: 0, output_tokens: 0}
    end

    test "creates a new session with specified backend" do
      {:ok, session} = Session.new_session("openai")

      assert session.llm_backend == "openai"
    end
  end

  describe "add_message/2" do
    test "adds a message to the current session" do
      :ok = Session.add_message("user", "Hello, world!")

      messages = Session.get_messages()
      assert length(messages) == 1

      [message] = messages
      assert message.role == "user"
      assert message.content == "Hello, world!"
      assert message.timestamp != nil
    end

    test "maintains message order" do
      :ok = Session.add_message("user", "First message")
      :ok = Session.add_message("assistant", "First response")
      :ok = Session.add_message("user", "Second message")

      messages = Session.get_messages()
      assert length(messages) == 3

      assert Enum.at(messages, 0).content == "First message"
      assert Enum.at(messages, 1).content == "First response"
      assert Enum.at(messages, 2).content == "Second message"
    end
  end

  describe "get_messages/1" do
    test "returns all messages when no limit specified" do
      for i <- 1..5 do
        Session.add_message("user", "Message #{i}")
      end

      messages = Session.get_messages()
      assert length(messages) == 5
    end

    test "returns limited messages when limit specified" do
      for i <- 1..10 do
        Session.add_message("user", "Message #{i}")
      end

      messages = Session.get_messages(3)
      assert length(messages) == 3
      assert hd(messages).content == "Message 1"
    end
  end

  describe "clear_session/0" do
    test "clears all messages from the session" do
      Session.add_message("user", "Test message")
      assert length(Session.get_messages()) == 1

      Session.clear_session()
      # Give async cast time to process
      Process.sleep(10)

      assert Session.get_messages() == []
    end

    test "preserves session ID when clearing" do
      session = Session.get_current_session()
      original_id = session.id

      Session.clear_session()
      Process.sleep(10)

      cleared_session = Session.get_current_session()
      assert cleared_session.id == original_id
    end
  end

  describe "set_context/1 and update_context_config/1" do
    test "sets context for the session" do
      context = %{system_prompt: "You are helpful", max_tokens: 2_048}
      Session.set_context(context)
      Process.sleep(10)

      session = Session.get_current_session()
      assert session.context == context
    end

    test "updates context configuration" do
      Session.set_context(%{system_prompt: "Initial prompt"})
      Process.sleep(10)

      Session.update_context_config(%{max_tokens: 4_096})
      Process.sleep(10)

      session = Session.get_current_session()
      assert session.context.system_prompt == "Initial prompt"
      assert session.context.max_tokens == 4_096
    end
  end

  describe "get_messages_for_llm/1" do
    test "prepares messages for LLM with context" do
      Session.set_context(%{system_prompt: "Be helpful", max_tokens: 1_000})
      Process.sleep(10)

      Session.add_message("user", "Hello")
      Session.add_message("assistant", "Hi there")

      messages = Session.get_messages_for_llm()

      # Should include system prompt
      assert length(messages) >= 2
      assert hd(messages).role == "system"
      assert hd(messages).content == "Be helpful"
    end

    test "applies context options" do
      for i <- 1..50 do
        Session.add_message("user", "Message #{i}")
      end

      messages = Session.get_messages_for_llm(max_tokens: 500)

      # Should have truncated messages
      assert length(messages) < 50
    end
  end

  describe "get_context_stats/0" do
    test "returns context statistics" do
      Session.set_context(%{max_tokens: 1_000})
      Process.sleep(10)

      Session.add_message("user", "Hello")
      Session.add_message("assistant", "Hi there!")

      stats = Session.get_context_stats()

      assert stats.message_count == 2
      assert stats.estimated_tokens > 0
      assert stats.max_tokens == 1_000
      assert stats.tokens_remaining < 1_000
    end
  end

  describe "track_token_usage/2" do
    test "tracks token usage for messages" do
      input_messages = [%{role: "user", content: "Hello"}]
      response_content = "Hi there! How can I help you today?"

      Session.track_token_usage(input_messages, response_content)
      Process.sleep(10)

      session = Session.get_current_session()
      assert session.token_usage.input_tokens > 0
      assert session.token_usage.output_tokens > 0
    end

    test "accumulates token usage" do
      Session.track_token_usage([%{content: "First"}], "Response 1")
      Process.sleep(10)

      first_usage = Session.get_current_session().token_usage

      Session.track_token_usage([%{content: "Second"}], "Response 2")
      Process.sleep(10)

      second_usage = Session.get_current_session().token_usage

      assert second_usage.input_tokens > first_usage.input_tokens
      assert second_usage.output_tokens > first_usage.output_tokens
    end
  end

  describe "get_session_cost/0" do
    test "calculates session cost" do
      # Set a backend with known pricing
      {:ok, _} = Session.new_session("anthropic")

      # Track some token usage
      Session.track_token_usage(
        [%{content: "Test message"}],
        "Test response"
      )

      Process.sleep(10)

      cost_info = Session.get_session_cost()

      assert cost_info.total_cost >= 0
      assert cost_info.input_cost >= 0
      assert cost_info.output_cost >= 0
      assert cost_info.model != nil
    end
  end

  describe "save_session/1 and load_session/1" do
    @tag :tmp_dir
    test "saves and loads session", %{tmp_dir: _} do
      # Add some messages
      Session.add_message("user", "Test message")
      Session.add_message("assistant", "Test response")

      # Save session
      {:ok, path} = Session.save_session("test_session")
      assert path =~ "test_session"

      # Create a new session
      Session.new_session()

      # Load the saved session
      {:ok, _loaded_session} = Session.load_session("test_session")

      messages = Session.get_messages()
      assert length(messages) == 2
      assert hd(messages).content == "Test message"
    end
  end

  describe "export_session/2" do
    test "exports session in JSON format" do
      Session.add_message("user", "Export test")

      {:ok, path} = Session.export_session(:json)
      assert path =~ ".json"

      # Clean up
      File.rm(path)
    end

    test "exports session in Markdown format" do
      Session.add_message("user", "Export test")

      {:ok, path} = Session.export_session(:markdown, "test_export.md")
      assert path == "test_export.md"

      # Clean up
      File.rm(path)
    end
  end

  describe "restore_session/1" do
    test "restores a session object" do
      # Create a session with some data
      original_session = %Session{
        id: "test123",
        messages: [%{role: "user", content: "Restored"}],
        context: %{max_tokens: 2_048},
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        token_usage: %{input_tokens: 10, output_tokens: 20}
      }

      :ok = Session.restore_session(original_session)

      current = Session.get_current_session()
      assert current.id == "test123"
      assert length(current.messages) == 1
      assert current.context.max_tokens == 2_048
    end
  end
end
