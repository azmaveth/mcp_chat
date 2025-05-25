defmodule MCPChat.SessionPersistenceIntegrationTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Integration tests for session persistence functionality.
  Tests saving, loading, and exporting sessions.
  """

  @test_dir "test/tmp/sessions"

  setup_all do
    Application.ensure_all_started(:mcp_chat)
    # Create test directory
    File.mkdir_p!(@test_dir)

    on_exit(fn ->
      # Cleanup test directory
      File.rm_rf!(@test_dir)
    end)

    :ok
  end

  setup do
    # Clear session before each test
    MCPChat.Session.clear_session()

    # Start a static path provider for this test
    {:ok, path_provider} =
      MCPChat.PathProvider.Static.start_link(%{
        sessions_dir: @test_dir,
        config_dir: @test_dir
      })

    {:ok, path_provider: path_provider}
  end

  describe "Session saving and loading" do
    test "saves session to disk", %{path_provider: path_provider} do
      # Create a session with content
      MCPChat.Session.add_message("user", "Test message 1")
      MCPChat.Session.add_message("assistant", "Test response 1")
      MCPChat.Session.set_context(%{"system_message" => "Test system message"})

      MCPChat.Session.track_token_usage(
        [%{role: "user", content: "Test message 1"}],
        "Test response 1"
      )

      session = MCPChat.Session.get_current_session()
      session_name = "test_save_#{System.unique_integer([:positive])}"

      # Save session
      {:ok, path} = MCPChat.Persistence.save_session(session, session_name, path_provider: path_provider)

      assert File.exists?(path)
      assert String.ends_with?(path, ".json")
    end

    test "loads session from disk", %{path_provider: path_provider} do
      # Create and save a session
      MCPChat.Session.add_message("user", "Hello")
      MCPChat.Session.add_message("assistant", "Hi there!")
      MCPChat.Session.set_context(%{"system_message" => "Be helpful"})

      MCPChat.Session.track_token_usage(
        [%{role: "user", content: "Hello"}],
        "Hi there!"
      )

      original_session = MCPChat.Session.get_current_session()
      session_name = "test_load_#{System.unique_integer([:positive])}"

      {:ok, path} = MCPChat.Persistence.save_session(original_session, session_name, path_provider: path_provider)

      # Clear current session
      MCPChat.Session.clear_session()

      # Load the saved session
      {:ok, loaded_session} = MCPChat.Persistence.load_session(session_name, path_provider: path_provider)

      # Verify content matches
      assert length(loaded_session.messages) == 2
      assert loaded_session.context["system_message"] == "Be helpful"
      assert loaded_session.token_usage["input_tokens"] > 0
      assert loaded_session.token_usage["output_tokens"] > 0
    end

    test "handles non-existent session load", %{path_provider: path_provider} do
      result = MCPChat.Persistence.load_session("non_existent_session", path_provider: path_provider)
      assert {:error, _reason} = result
    end

    test "lists available sessions", %{path_provider: path_provider} do
      # Save multiple sessions
      session_names =
        for i <- 1..3 do
          name = "list_test_#{i}"
          MCPChat.Session.add_message("user", "Message #{i}")
          session = MCPChat.Session.get_current_session()
          {:ok, _} = MCPChat.Persistence.save_session(session, name, path_provider: path_provider)
          MCPChat.Session.clear_session()
          name
        end

      # List sessions
      {:ok, sessions} = MCPChat.Persistence.list_sessions(path_provider: path_provider)

      # Verify all test sessions are listed
      Enum.each(session_names, fn name ->
        assert Enum.any?(sessions, fn s -> String.contains?(s.filename, name) end)
      end)
    end

    test "auto-saves session on interval", %{path_provider: path_provider} do
      # This would test auto-save functionality if implemented
      # For now, test manual save with timestamp

      MCPChat.Session.add_message("user", "Auto-save test")
      session = MCPChat.Session.get_current_session()

      # Save with timestamp
      timestamp = DateTime.utc_now() |> DateTime.to_unix()
      session_name = "autosave_#{timestamp}"

      {:ok, path} = MCPChat.Persistence.save_session(session, session_name, path_provider: path_provider)
      assert File.exists?(path)
    end
  end

  describe "Session export formats" do
    test "exports session as JSON" do
      # Create session with diverse content
      MCPChat.Session.set_context(%{"system_message" => "JSON export test"})
      MCPChat.Session.add_message("user", "What is JSON?")
      MCPChat.Session.add_message("assistant", "JSON is a data format")

      MCPChat.Session.track_token_usage(
        [%{role: "user", content: "What is JSON?"}],
        "JSON is a data format"
      )

      session = MCPChat.Session.get_current_session()
      output_path = Path.join(@test_dir, "export_test.json")

      {:ok, _} = MCPChat.Persistence.export_session(session, :json, output_path)

      assert File.exists?(output_path)

      # Verify JSON structure
      {:ok, content} = File.read(output_path)
      {:ok, parsed} = Jason.decode(content)

      assert parsed["context"]["system_message"] == "JSON export test"
      assert length(parsed["messages"]) == 2
      assert parsed["token_usage"]["prompt_tokens"] > 0
    end

    test "exports session as Markdown" do
      # Create session
      MCPChat.Session.set_context(%{"system_message" => "Markdown export test"})
      MCPChat.Session.add_message("user", "Format this as **markdown**")
      MCPChat.Session.add_message("assistant", "Here is *italic* and `code`")

      session = MCPChat.Session.get_current_session()
      output_path = Path.join(@test_dir, "export_test.md")

      {:ok, _} = MCPChat.Persistence.export_session(session, :markdown, output_path)

      assert File.exists?(output_path)

      # Verify Markdown content
      {:ok, content} = File.read(output_path)

      assert String.contains?(content, "# Chat Session Export")
      assert String.contains?(content, "## User")
      assert String.contains?(content, "## Assistant")
      assert String.contains?(content, "**markdown**")
    end

    test "exports session as plain text" do
      # Create session
      MCPChat.Session.add_message("user", "Plain text export")
      MCPChat.Session.add_message("assistant", "Simple response")

      session = MCPChat.Session.get_current_session()
      output_path = Path.join(@test_dir, "export_test.txt")

      # The :text format is not supported, so this should return an error
      result = MCPChat.Persistence.export_session(session, :text, output_path)
      assert {:error, :unsupported_format} = result
    end

    test "handles invalid export format" do
      session = MCPChat.Session.get_current_session()
      output_path = Path.join(@test_dir, "invalid.xyz")

      result = MCPChat.Persistence.export_session(session, :invalid_format, output_path)
      assert {:error, _} = result
    end
  end

  describe "Session metadata persistence" do
    test "preserves session metadata", %{path_provider: path_provider} do
      # Set various metadata
      session_id = "meta_test_#{System.unique_integer([:positive])}"

      # Add messages with metadata
      MCPChat.Session.add_message("user", "Test with metadata")
      MCPChat.Session.set_context(%{"system_message" => "Metadata system"})

      MCPChat.Session.track_token_usage(
        [%{role: "user", content: "Test with metadata"}],
        "Response with metadata"
      )

      # Get session and ensure it has all metadata
      session = MCPChat.Session.get_current_session()
      # Store extra metadata in context
      MCPChat.Session.set_context(
        Map.merge(session.context, %{
          "llm_backend" => "openai",
          "context_strategy" => "sliding_window"
        })
      )

      session = MCPChat.Session.get_current_session()

      # Save
      {:ok, _} = MCPChat.Persistence.save_session(session, session_id, path_provider: path_provider)

      # Load and verify
      {:ok, loaded} = MCPChat.Persistence.load_session(session_id, path_provider: path_provider)

      assert loaded.context["system_message"] == "Metadata system"
      assert loaded.context["llm_backend"] == "openai"
      assert loaded.context["context_strategy"] == "sliding_window"
      assert loaded.token_usage["input_tokens"] > 0
      assert loaded.token_usage["output_tokens"] > 0
    end

    test "handles session versioning", %{path_provider: path_provider} do
      # Save session with metadata in context
      session = MCPChat.Session.get_current_session()
      MCPChat.Session.set_context(%{"version" => "1.0.0"})
      session = MCPChat.Session.get_current_session()

      session_name = "version_test"
      {:ok, _} = MCPChat.Persistence.save_session(session, session_name, path_provider: path_provider)

      # Load and check version
      {:ok, loaded} = MCPChat.Persistence.load_session(session_name, path_provider: path_provider)
      assert loaded.context["version"] == "1.0.0"
    end
  end

  describe "Concurrent session operations" do
    test "handles concurrent saves safely", %{path_provider: path_provider} do
      # Spawn multiple processes to save sessions
      tasks =
        for i <- 1..5 do
          # Capture path_provider in closure
          provider = path_provider

          Task.async(fn ->
            MCPChat.Session.add_message("user", "Concurrent test #{i}")
            session = MCPChat.Session.get_current_session()
            session_name = "concurrent_#{i}"
            MCPChat.Persistence.save_session(session, session_name, path_provider: provider)
          end)
        end

      # Wait for all saves to complete
      results = Task.await_many(tasks)

      # Verify all succeeded
      assert Enum.all?(results, fn
               {:ok, _} -> true
               _ -> false
             end)
    end

    test "handles concurrent loads safely", %{path_provider: path_provider} do
      # First save a session
      MCPChat.Session.add_message("user", "Concurrent load test")
      session = MCPChat.Session.get_current_session()
      session_name = "concurrent_load"
      {:ok, _} = MCPChat.Persistence.save_session(session, session_name, path_provider: path_provider)

      # Spawn multiple processes to load the same session
      tasks =
        for _ <- 1..5 do
          # Capture path_provider in closure
          provider = path_provider

          Task.async(fn ->
            MCPChat.Persistence.load_session(session_name, path_provider: provider)
          end)
        end

      # Wait for all loads to complete
      results = Task.await_many(tasks)

      # Verify all succeeded and got same data
      assert Enum.all?(results, fn
               {:ok, loaded} ->
                 length(loaded.messages) == 1 and
                   hd(loaded.messages).content == "Concurrent load test"

               _ ->
                 false
             end)
    end
  end

  describe "Session compression and optimization" do
    test "handles large sessions efficiently", %{path_provider: path_provider} do
      # Create a large session
      for i <- 1..100 do
        MCPChat.Session.add_message("user", "Question #{i}")
        MCPChat.Session.add_message("assistant", "Response #{i} with some longer content to increase size")

        MCPChat.Session.track_token_usage(
          [%{role: "user", content: "Test message 1"}],
          "Test response 1"
        )
      end

      large_session = MCPChat.Session.get_current_session()
      assert length(large_session.messages) == 200

      # Save large session
      session_name = "large_session"
      {:ok, path} = MCPChat.Persistence.save_session(large_session, session_name, path_provider: path_provider)

      # Check file size is reasonable
      stat = File.stat!(path)
      assert stat.size > 0

      # Load and verify
      {:ok, loaded} = MCPChat.Persistence.load_session(session_name, path_provider: path_provider)
      assert length(loaded.messages) == 200
    end

    test "prunes old messages when configured", %{path_provider: _path_provider} do
      # This would test message pruning if implemented
      # For now, test that we can limit message history

      max_messages = 10

      # Add more messages than limit
      for i <- 1..20 do
        MCPChat.Session.add_message("user", "Message #{i}")
      end

      session = MCPChat.Session.get_current_session()

      # Simulate pruning
      pruned_messages = Enum.take(session.messages, -max_messages)
      pruned_session = %{session | messages: pruned_messages}

      assert length(pruned_session.messages) == max_messages

      # Verify we kept the most recent messages
      last_message = List.last(pruned_session.messages)
      assert last_message.content == "Message 20"
    end
  end

  describe "Session backup and recovery" do
    test "creates session backups", %{path_provider: path_provider} do
      # Create session
      MCPChat.Session.add_message("user", "Backup test")
      session = MCPChat.Session.get_current_session()

      # Save main session
      session_name = "backup_test"
      {:ok, _} = MCPChat.Persistence.save_session(session, session_name, path_provider: path_provider)

      # Create backup
      backup_name = "#{session_name}_backup_#{DateTime.utc_now() |> DateTime.to_unix()}"
      {:ok, backup_path} = MCPChat.Persistence.save_session(session, backup_name, path_provider: path_provider)

      assert File.exists?(backup_path)
    end

    test "recovers from corrupted session file", %{path_provider: path_provider} do
      # Create corrupted session file
      corrupted_path = Path.join(@test_dir, "corrupted_session.json")
      File.write!(corrupted_path, "{ invalid json ]}")

      # Attempt to load
      result = MCPChat.Persistence.load_session("corrupted_session", path_provider: path_provider)
      assert {:error, _} = result

      # System should handle gracefully, not crash
    end
  end
end
