defmodule MCPChat.PersistenceTest do
  use ExUnit.Case
  alias MCPChat.{Persistence, Session}

  @test_session %Session{
    id: "test123",
    llm_backend: "anthropic",
    messages: [
      %{role: "user", content: "Hello", timestamp: DateTime.utc_now()},
      %{role: "assistant", content: "Hi there!", timestamp: DateTime.utc_now()}
    ],
    context: %{model: "claude-3-haiku-20_240_307"},
    created_at: DateTime.utc_now(),
    updated_at: DateTime.utc_now(),
    token_usage: %{input_tokens: 10, output_tokens: 5}
  }

  setup do
    # Clean up test sessions
    on_exit(fn ->
      case Persistence.list_sessions() do
        {:ok, sessions} ->
          Enum.each(sessions, fn session ->
            Persistence.delete_session(session.filename)
          end)

        _ ->
          :ok
      end
    end)

    :ok
  end

  describe "save_session/2" do
    test "saves session with auto-generated name" do
      assert {:ok, path} = Persistence.save_session(@test_session)
      assert File.exists?(path)

      # Verify filename format
      assert String.contains?(path, "session_test123_")
      assert String.ends_with?(path, ".json")
    end

    test "saves session with custom name" do
      assert {:ok, path} = Persistence.save_session(@test_session, "my-test")
      assert File.exists?(path)

      # Verify filename includes custom name
      assert String.contains?(path, "my-test_test123")
    end

    test "sanitizes custom name" do
      assert {:ok, path} = Persistence.save_session(@test_session, "my/bad:name*")
      assert File.exists?(path)

      # Bad characters should be replaced with underscores
      assert String.contains?(path, "my_bad_name_")
    end
  end

  describe "load_session/1" do
    test "loads session by filename" do
      {:ok, path} = Persistence.save_session(@test_session, "load-test")
      filename = Path.basename(path)

      assert {:ok, loaded} = Persistence.load_session(filename)
      assert loaded.id == @test_session.id
      assert loaded.llm_backend == @test_session.llm_backend
      assert length(loaded.messages) == 2
    end

    test "loads session by partial name" do
      {:ok, _path} = Persistence.save_session(@test_session, "unique-name")

      assert {:ok, loaded} = Persistence.load_session("unique-name")
      assert loaded.id == @test_session.id
    end

    test "loads session by index" do
      {:ok, _} = Persistence.save_session(@test_session, "first")
      {:ok, _} = Persistence.save_session(@test_session, "second")

      assert {:ok, loaded} = Persistence.load_session(1)
      assert loaded.id == @test_session.id
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = Persistence.load_session("nonexistent")
    end
  end

  describe "list_sessions/0" do
    test "returns empty list when no sessions" do
      assert {:ok, []} = Persistence.list_sessions()
    end

    test "returns session metadata" do
      {:ok, _} = Persistence.save_session(@test_session, "list-test")

      assert {:ok, [session]} = Persistence.list_sessions()

      assert session.id == @test_session.id
      assert session.llm_backend == @test_session.llm_backend
      assert session.message_count == 2
      assert session.size > 0
      assert session.relative_time =~ ~r/just now|seconds? ago/
    end

    test "sorts sessions by updated_at descending" do
      # Save sessions with slight delays
      {:ok, _} = Persistence.save_session(@test_session, "old")
      Process.sleep(1_000)

      new_session = %{@test_session | id: "newer", updated_at: DateTime.utc_now()}
      {:ok, _} = Persistence.save_session(new_session, "new")

      assert {:ok, sessions} = Persistence.list_sessions()
      assert length(sessions) == 2

      # Newer session should be first
      assert hd(sessions).id == "newer"
    end
  end

  describe "delete_session/1" do
    test "deletes existing session" do
      {:ok, path} = Persistence.save_session(@test_session, "delete-test")
      filename = Path.basename(path)

      assert :ok = Persistence.delete_session(filename)
      assert not File.exists?(path)
    end

    test "handles non-existent session gracefully" do
      assert {:error, :enoent} = Persistence.delete_session("nonexistent.json")
    end
  end

  describe "export_session/3" do
    test "exports session as JSON" do
      path = "test_export.json"

      assert {:ok, ^path} = Persistence.export_session(@test_session, :json, path)
      assert File.exists?(path)

      # Verify JSON content
      {:ok, content} = File.read(path)
      {:ok, data} = Jason.decode(content)

      assert data["id"] == @test_session.id
      assert length(data["messages"]) == 2

      # Clean up
      File.rm!(path)
    end

    test "exports session as markdown" do
      path = "test_export.md"

      assert {:ok, ^path} = Persistence.export_session(@test_session, :markdown, path)
      assert File.exists?(path)

      # Verify markdown content
      {:ok, content} = File.read(path)

      assert String.contains?(content, "# Chat Session Export")
      assert String.contains?(content, @test_session.id)
      assert String.contains?(content, "## User")
      assert String.contains?(content, "## Assistant")
      assert String.contains?(content, "Hello")
      assert String.contains?(content, "Hi there!")

      # Clean up
      File.rm!(path)
    end

    test "returns error for unsupported format" do
      assert {:error, :unsupported_format} =
               Persistence.export_session(@test_session, :xml, "test.xml")
    end
  end
end
