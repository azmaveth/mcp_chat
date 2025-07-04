defmodule MCPChat.PersistenceTest do
  use ExUnit.Case, async: true
  alias MCPChat.Persistence
  alias MCPChat.Types.Session

  @test_session %Session{
    id: "test123",
    llm_backend: "anthropic",
    messages: [
      %{role: "user", content: "Hello", timestamp: DateTime.utc_now()},
      %{role: "assistant", content: "Hi there!", timestamp: DateTime.utc_now()}
    ],
    context: %{model: "claude-3-haiku-20240307"},
    created_at: DateTime.utc_now(),
    updated_at: DateTime.utc_now(),
    token_usage: %{input_tokens: 10, output_tokens: 5}
  }

  setup do
    # Create a temporary directory for test sessions
    temp_dir = Path.join([System.tmp_dir!(), "mcp_chat_test_#{:rand.uniform(1_000_000)}"])
    sessions_dir = Path.join(temp_dir, "sessions")

    # Start a Static path provider with the temp directory
    {:ok, path_provider} =
      MCPChat.PathProvider.Static.start_link(%{
        config_dir: temp_dir,
        sessions_dir: sessions_dir
      })

    # Clean up on exit
    on_exit(fn ->
      # Stop the path provider
      if Process.alive?(path_provider) do
        Agent.stop(path_provider)
      end

      # Remove the temp directory
      File.rm_rf!(temp_dir)
    end)

    {:ok, path_provider: path_provider}
  end

  describe "save_session/2" do
    test "saves session with auto-generated name", %{path_provider: path_provider} do
      assert {:ok, path} = Persistence.save_session(@test_session, nil, path_provider: path_provider)
      assert File.exists?(path)

      # Verify filename format
      assert String.contains?(path, "session_test123_")
      assert String.ends_with?(path, ".json")
    end

    test "saves session with custom name", %{path_provider: path_provider} do
      assert {:ok, path} = Persistence.save_session(@test_session, "my-test", path_provider: path_provider)
      assert File.exists?(path)

      # Verify filename includes custom name
      assert String.contains?(path, "my-test_test123")
    end

    test "sanitizes custom name", %{path_provider: path_provider} do
      assert {:ok, path} = Persistence.save_session(@test_session, "my/bad:name*", path_provider: path_provider)
      assert File.exists?(path)

      # Bad characters should be replaced with underscores
      assert String.contains?(path, "my_bad_name_")
    end
  end

  describe "load_session/1" do
    test "loads session by filename", %{path_provider: path_provider} do
      {:ok, path} = Persistence.save_session(@test_session, "load-test", path_provider: path_provider)
      filename = Path.basename(path)

      assert {:ok, loaded} = Persistence.load_session(filename, path_provider: path_provider)
      assert loaded.id == @test_session.id
      assert loaded.llm_backend == @test_session.llm_backend
      assert length(loaded.messages) == 2
    end

    test "loads session by partial name", %{path_provider: path_provider} do
      {:ok, _path} = Persistence.save_session(@test_session, "unique-name", path_provider: path_provider)

      assert {:ok, loaded} = Persistence.load_session("unique-name", path_provider: path_provider)
      assert loaded.id == @test_session.id
    end

    test "loads session by index", %{path_provider: path_provider} do
      {:ok, _} = Persistence.save_session(@test_session, "first", path_provider: path_provider)
      {:ok, _} = Persistence.save_session(@test_session, "second", path_provider: path_provider)

      assert {:ok, loaded} = Persistence.load_session(1, path_provider: path_provider)
      # Just verify we loaded a session
      assert loaded.id != nil
      assert loaded.messages != nil
    end

    test "returns error for non-existent session", %{path_provider: path_provider} do
      assert {:error, :not_found} = Persistence.load_session("nonexistent", path_provider: path_provider)
    end
  end

  describe "list_sessions/0" do
    test "returns list of sessions", %{path_provider: path_provider} do
      # Should be empty initially since we're using a temp directory
      assert {:ok, []} = Persistence.list_sessions(path_provider: path_provider)
    end

    test "returns session metadata", %{path_provider: path_provider} do
      {:ok, _} = Persistence.save_session(@test_session, "list-test", path_provider: path_provider)

      assert {:ok, [session]} = Persistence.list_sessions(path_provider: path_provider)

      assert session.id == @test_session.id
      assert session.llm_backend == @test_session.llm_backend
      assert session.message_count == 2
      assert session.size > 0
      assert session.relative_time =~ ~r/just now|seconds? ago/
    end

    test "sorts sessions by updated_at descending", %{path_provider: path_provider} do
      # Save sessions with slight delays
      {:ok, _} = Persistence.save_session(@test_session, "old", path_provider: path_provider)
      Process.sleep(1_000)

      new_session = %{@test_session | id: "newer", updated_at: DateTime.utc_now()}
      {:ok, _} = Persistence.save_session(new_session, "new", path_provider: path_provider)

      assert {:ok, sessions} = Persistence.list_sessions(path_provider: path_provider)
      assert length(sessions) == 2

      # Newer session should be first
      assert hd(sessions).id == "newer"
    end
  end

  describe "delete_session/1" do
    test "deletes existing session", %{path_provider: path_provider} do
      {:ok, path} = Persistence.save_session(@test_session, "delete-test", path_provider: path_provider)
      filename = Path.basename(path)

      assert :ok = Persistence.delete_session(filename, path_provider: path_provider)
      assert not File.exists?(path)
    end

    test "handles non-existent session gracefully", %{path_provider: path_provider} do
      assert {:error, :enoent} = Persistence.delete_session("nonexistent.json", path_provider: path_provider)
    end
  end

  describe "export_session/3" do
    test "exports session as JSON", %{path_provider: path_provider} do
      # Use temp directory for export
      temp_dir = MCPChat.PathProvider.Static.config_dir(path_provider)
      File.mkdir_p!(temp_dir)
      path = Path.join(temp_dir, "test_export.json")

      assert {:ok, ^path} = Persistence.export_session(@test_session, :json, path)
      assert File.exists?(path)

      # Verify JSON content
      {:ok, content} = File.read(path)
      {:ok, data} = Jason.decode(content)

      assert data["id"] == @test_session.id
      assert length(data["messages"]) == 2
    end

    test "exports session as markdown", %{path_provider: path_provider} do
      # Use temp directory for export
      temp_dir = MCPChat.PathProvider.Static.config_dir(path_provider)
      File.mkdir_p!(temp_dir)
      path = Path.join(temp_dir, "test_export.md")

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
    end

    test "returns error for unsupported format" do
      assert {:error, :unsupported_format} =
               Persistence.export_session(@test_session, :xml, "test.xml")
    end
  end
end
