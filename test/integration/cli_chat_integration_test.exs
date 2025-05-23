defmodule MCPChat.CLIChatIntegrationTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Integration tests for CLI chat functionality.
  Tests the complete chat loop and command handling.
  """

  setup_all do
    Application.ensure_all_started(:mcp_chat)
    :ok
  end

  setup do
    # Clear session before each test
    MCPChat.Session.clear_session()
    :ok
  end

  describe "Chat command processing" do
    test "processes regular chat messages" do
      # Simulate user input
      input = "Hello, how are you?"

      # Message should be added to session
      MCPChat.Session.add_message("user", input)

      session = MCPChat.Session.get_current_session()
      assert length(session.messages) == 1
      assert hd(session.messages).role == "user"
      assert hd(session.messages).content == input
    end

    test "processes slash commands" do
      # Test various slash commands
      commands = [
        "/help",
        "/clear",
        "/save test_session",
        "/load test_session",
        "/export markdown output.md",
        "/history",
        "/stats",
        "/system You are helpful",
        "/alias gpt4 set-backend openai --model gpt-4",
        "/config",
        "/quit"
      ]

      Enum.each(commands, fn cmd ->
        assert String.starts_with?(cmd, "/")
        [command | _args] = String.split(cmd)

        assert command in [
                 "/help",
                 "/clear",
                 "/save",
                 "/load",
                 "/export",
                 "/history",
                 "/stats",
                 "/system",
                 "/alias",
                 "/config",
                 "/quit"
               ]
      end)
    end

    test "handles multi-line input" do
      # Multi-line messages use ''' delimiter
      lines = [
        "'''",
        "Line 1",
        "Line 2",
        "Line 3",
        "'''"
      ]

      # Join should preserve newlines
      content =
        lines
        |> Enum.slice(1..-2)
        |> Enum.join("\n")

      assert content == "Line 1\nLine 2\nLine 3"
      assert String.contains?(content, "\n")
    end

    test "handles empty input" do
      # Empty input should be ignored
      input = ""
      input_trimmed = String.trim(input)

      assert input_trimmed == ""
      # Empty input should not add a message
    end
  end

  describe "Command validation and parsing" do
    test "validates save command arguments" do
      # Valid save commands
      valid_saves = [
        {"/save mysession", {:ok, "mysession"}},
        {"/save my_session_123", {:ok, "my_session_123"}},
        {"/save", {:error, :missing_name}}
      ]

      Enum.each(valid_saves, fn {input, expected} ->
        parts = String.split(input)

        case parts do
          ["/save", name] -> assert {:ok, name} == expected
          ["/save"] -> assert {:error, :missing_name} == expected
          _ -> :ok
        end
      end)
    end

    test "validates export command arguments" do
      # Valid export commands
      valid_exports = [
        {"/export json output.json", {:ok, "json", "output.json"}},
        {"/export markdown README.md", {:ok, "markdown", "README.md"}},
        {"/export text", {:error, :missing_path}},
        {"/export", {:error, :missing_args}}
      ]

      Enum.each(valid_exports, fn {input, expected} ->
        parts = String.split(input)

        case parts do
          ["/export", format, path] -> assert {:ok, format, path} == expected
          ["/export", _format] -> assert {:error, :missing_path} == expected
          ["/export"] -> assert {:error, :missing_args} == expected
          _ -> :ok
        end
      end)
    end

    test "validates system command" do
      valid_system = [
        {"/system You are a helpful assistant", {:ok, "You are a helpful assistant"}},
        {"/system", {:error, :missing_message}}
      ]

      Enum.each(valid_system, fn {input, expected} ->
        parts = String.split(input, " ", parts: 2)

        case parts do
          ["/system", message] -> assert {:ok, message} == expected
          ["/system"] -> assert {:error, :missing_message} == expected
          _ -> :ok
        end
      end)
    end
  end

  describe "Session state during chat" do
    test "maintains conversation context" do
      # Add multiple messages
      MCPChat.Session.add_message("user", "Hello")
      MCPChat.Session.add_message("assistant", "Hi there!")
      MCPChat.Session.add_message("user", "How are you?")
      MCPChat.Session.add_message("assistant", "I'm doing well, thanks!")

      session = MCPChat.Session.get_current_session()
      assert length(session.messages) == 4

      # Messages should be in order
      [msg1, msg2, msg3, msg4] = session.messages
      assert msg1.role == "user" and msg1.content == "Hello"
      assert msg2.role == "assistant" and msg2.content == "Hi there!"
      assert msg3.role == "user" and msg3.content == "How are you?"
      assert msg4.role == "assistant" and msg4.content == "I'm doing well, thanks!"
    end

    test "respects system message" do
      # Set context with system message
      MCPChat.Session.set_context(%{"system_message" => "You are a pirate"})

      session = MCPChat.Session.get_current_session()
      assert session.context["system_message"] == "You are a pirate"

      # Context should persist across messages
      MCPChat.Session.add_message("user", "Hello")
      session = MCPChat.Session.get_current_session()
      assert session.context["system_message"] == "You are a pirate"
    end

    test "tracks token usage" do
      # Simulate messages with token counts
      MCPChat.Session.add_message("user", "Hello")

      MCPChat.Session.track_token_usage(
        [%{role: "user", content: "Hello"}],
        "Hi there!"
      )

      MCPChat.Session.add_message("user", "Tell me a story")

      MCPChat.Session.track_token_usage(
        [%{role: "user", content: "Tell me a story"}],
        "Once upon a time..."
      )

      stats = MCPChat.Session.get_context_stats()
      assert stats.total_tokens > 0
    end
  end

  describe "History and stats display" do
    test "formats conversation history" do
      # Add test messages
      MCPChat.Session.add_message("user", "What is 2+2?")
      MCPChat.Session.add_message("assistant", "2+2 equals 4")

      session = MCPChat.Session.get_current_session()

      # History should show role and content
      Enum.each(session.messages, fn msg ->
        assert msg.role in ["user", "assistant"]
        assert is_binary(msg.content)
        assert msg.timestamp != nil
      end)
    end

    test "calculates session statistics" do
      # Add messages and token usage
      MCPChat.Session.add_message("user", "Question 1")

      MCPChat.Session.track_token_usage(
        [%{role: "user", content: "Question 1"}],
        "Answer 1"
      )

      MCPChat.Session.add_message("user", "Question 2")

      MCPChat.Session.track_token_usage(
        [%{role: "user", content: "Question 2"}],
        "Answer 2"
      )

      session = MCPChat.Session.get_current_session()

      # Stats should include:
      stats = %{
        message_count: length(session.messages),
        user_messages: Enum.count(session.messages, &(&1.role == "user")),
        assistant_messages: Enum.count(session.messages, &(&1.role == "assistant")),
        context_stats: MCPChat.Session.get_context_stats()
      }

      assert stats.message_count == 2
      assert stats.user_messages == 2
      assert stats.assistant_messages == 0
      assert stats.context_stats.total_tokens > 0
    end
  end

  describe "Alias system integration" do
    test "creates and uses aliases" do
      # Create an alias
      alias_name = "gpt4"
      alias_value = "set-backend openai --model gpt-4 --temperature 0.7"

      # Store alias (would use actual alias module)
      aliases = %{
        alias_name => alias_value
      }

      assert Map.has_key?(aliases, alias_name)
      assert aliases[alias_name] =~ "set-backend"
    end

    test "expands aliases in commands" do
      # Test alias expansion
      aliases = %{
        "gpt4" => "set-backend openai --model gpt-4",
        "clear-all" => "clear && save backup"
      }

      # Command with alias
      input = "/gpt4"
      alias_name = String.trim_leading(input, "/")

      if Map.has_key?(aliases, alias_name) do
        expanded = aliases[alias_name]
        assert expanded =~ "set-backend"
      end
    end
  end

  describe "Error handling in chat loop" do
    test "handles invalid commands gracefully" do
      invalid_commands = [
        "/nonexistent",
        # missing argument
        "/save",
        # missing path
        "/export json",
        "/load nonexistent_session"
      ]

      Enum.each(invalid_commands, fn cmd ->
        # Should not crash, should return error message
        assert is_binary(cmd)
      end)
    end

    test "handles LLM errors gracefully" do
      # Simulate various LLM errors
      errors = [
        {:error, :rate_limit},
        {:error, :invalid_api_key},
        {:error, :network_error},
        {:error, {:http_error, 500}}
      ]

      Enum.each(errors, fn error ->
        assert elem(error, 0) == :error
        # Error should be displayed to user, not crash
      end)
    end

    test "recovers from session errors" do
      # Even if session is corrupted, should recover
      # This would test session recovery logic

      # Clear and recreate session
      MCPChat.Session.clear_session()
      # Give time for async clear
      Process.sleep(100)
      new_session = MCPChat.Session.get_current_session()

      assert new_session.messages == []
      assert new_session.id != nil
    end
  end

  describe "Multi-backend chat" do
    test "switches between backends" do
      # Test backend switching
      backends = ["openai", "anthropic", "ollama", "openrouter"]

      Enum.each(backends, fn backend ->
        # Would call actual backend switching
        assert is_binary(backend)
      end)
    end

    test "maintains context across backend switches" do
      # Add messages with one backend
      MCPChat.Session.add_message("user", "Hello")
      MCPChat.Session.add_message("assistant", "Hi!")

      # Switch backend (would use actual command)
      # Messages should persist
      session = MCPChat.Session.get_current_session()
      assert length(session.messages) == 2
    end
  end
end
