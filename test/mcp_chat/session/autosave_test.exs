defmodule MCPChat.Session.AutosaveTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias MCPChat.Session.Autosave
  alias MCPChat.{Session, Persistence}

  @test_session %{
    id: "test_session_#{System.unique_integer([:positive])}",
    messages: [
      %{role: "user", content: "Hello"},
      %{role: "assistant", content: "Hi there!"}
    ],
    context: %{
      files: %{},
      tokens: 100
    },
    metadata: %{
      created_at: DateTime.utc_now(),
      backend: "test"
    }
  }

  setup do
    # Mock Session
    :meck.new(MCPChat.Session, [:non_strict])
    :meck.expect(MCPChat.Session, :get_current_session, fn -> @test_session end)

    # Mock Persistence
    :meck.new(MCPChat.Persistence, [:non_strict])

    :meck.expect(MCPChat.Persistence, :save_session, fn _session, _name, _opts ->
      {:ok, "/tmp/test_session.json"}
    end)

    :meck.expect(MCPChat.Persistence, :get_sessions_dir, fn -> "/tmp/sessions" end)

    # Start autosave with test config
    {:ok, pid} =
      Autosave.start_link(
        # 100ms for testing
        interval: 100,
        # 50ms for testing
        debounce: 50,
        # Start disabled
        enabled: false
      )

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
      :meck.unload(MCPChat.Session)
      :meck.unload(MCPChat.Persistence)
    end)

    {:ok, pid: pid}
  end

  describe "autosave lifecycle" do
    test "starts in disabled state", %{pid: _pid} do
      stats = Autosave.get_stats()
      assert stats.enabled == false
      assert stats.save_count == 0
      assert stats.failure_count == 0
    end

    test "can be enabled and disabled", %{pid: _pid} do
      # Enable autosave
      assert :ok = Autosave.set_enabled(true)

      stats = Autosave.get_stats()
      assert stats.enabled == true

      # Should have scheduled next save
      assert stats.next_save_in != nil

      # Disable autosave
      assert :ok = Autosave.set_enabled(false)

      stats = Autosave.get_stats()
      assert stats.enabled == false
      assert stats.next_save_in == nil
    end

    test "performs automatic saves when enabled", %{pid: _pid} do
      # Track save calls
      test_pid = self()

      :meck.expect(MCPChat.Persistence, :save_session, fn session, name, _opts ->
        send(test_pid, {:save_called, session, name})
        {:ok, "/tmp/#{name}.json"}
      end)

      # Enable autosave
      Autosave.set_enabled(true)

      # Wait for automatic save
      assert_receive {:save_called, session, name}, 200
      assert session == @test_session
      assert String.starts_with?(name, "autosave_")

      # Check stats
      stats = Autosave.get_stats()
      assert stats.save_count == 1
      assert stats.failure_count == 0
      assert stats.last_save_time != nil
    end
  end

  describe "manual save triggers" do
    test "trigger_save debounces multiple requests", %{pid: _pid} do
      save_count = :meck.num_calls(MCPChat.Persistence, :save_session, :_)

      Autosave.set_enabled(true)

      # Trigger multiple saves quickly
      Autosave.trigger_save()
      Autosave.trigger_save()
      Autosave.trigger_save()

      # Wait for debounce period
      Process.sleep(100)

      # Should only save once due to debouncing
      new_save_count = :meck.num_calls(MCPChat.Persistence, :save_session, :_)
      assert new_save_count - save_count == 1
    end

    test "force_save bypasses debouncing", %{pid: _pid} do
      Autosave.set_enabled(true)

      # Force save should work immediately
      assert {:ok, _} = Autosave.force_save()

      stats = Autosave.get_stats()
      assert stats.save_count == 1
    end
  end

  describe "change detection" do
    test "skips save when session hasn't changed", %{pid: _pid} do
      Autosave.set_enabled(true)

      # First save
      assert {:ok, _} = Autosave.force_save()
      initial_count = Autosave.get_stats().save_count

      # Second save with same session
      assert {:ok, :no_changes} = Autosave.force_save()

      # Save count shouldn't increase
      assert Autosave.get_stats().save_count == initial_count
    end

    test "saves when session changes", %{pid: _pid} do
      Autosave.set_enabled(true)

      # First save
      assert {:ok, _} = Autosave.force_save()
      initial_count = Autosave.get_stats().save_count

      # Change the session
      new_session =
        Map.put(@test_session, :messages, [
          %{role: "user", content: "Hello"},
          %{role: "assistant", content: "Hi there!"},
          %{role: "user", content: "New message"}
        ])

      :meck.expect(MCPChat.Session, :get_current_session, fn -> new_session end)

      # Second save should detect change
      assert {:ok, save_info} = Autosave.force_save()
      assert save_info != :no_changes

      # Save count should increase
      assert Autosave.get_stats().save_count == initial_count + 1
    end
  end

  describe "error handling" do
    test "handles save failures gracefully", %{pid: _pid} do
      # Mock save failure
      :meck.expect(MCPChat.Persistence, :save_session, fn _session, _name, _opts ->
        {:error, :write_failed}
      end)

      Autosave.set_enabled(true)

      # Try to save
      assert {:error, :write_failed} = Autosave.force_save()

      stats = Autosave.get_stats()
      assert stats.failure_count == 1
      assert stats.save_count == 0
    end

    test "disables autosave after max failures", %{pid: _pid} do
      # Mock persistent failures
      :meck.expect(MCPChat.Persistence, :save_session, fn _session, _name, _opts ->
        {:error, :write_failed}
      end)

      # Configure with low max_retries
      Autosave.configure(%{max_retries: 2})
      Autosave.set_enabled(true)

      # Force failures
      Autosave.force_save()
      assert Autosave.get_stats().failure_count == 1
      assert Autosave.get_stats().enabled == true

      # Second failure should disable
      assert {:error, :max_failures} = Autosave.force_save()

      stats = Autosave.get_stats()
      assert stats.failure_count == 2
      assert stats.enabled == false
    end

    test "resets failure count on success", %{pid: _pid} do
      Autosave.set_enabled(true)

      # First fail
      :meck.expect(MCPChat.Persistence, :save_session, fn _session, _name, _opts ->
        {:error, :write_failed}
      end)

      Autosave.force_save()
      assert Autosave.get_stats().failure_count == 1

      # Then succeed
      :meck.expect(MCPChat.Persistence, :save_session, fn _session, _name, _opts ->
        {:ok, "/tmp/test.json"}
      end)

      Autosave.force_save()
      assert Autosave.get_stats().failure_count == 0
    end
  end

  describe "configuration" do
    test "can update configuration", %{pid: _pid} do
      initial_stats = Autosave.get_stats()
      assert initial_stats.config.interval == 100

      # Update config
      Autosave.configure(%{interval: 200, session_name_prefix: "custom"})

      new_stats = Autosave.get_stats()
      assert new_stats.config.interval == 200
      assert new_stats.config.session_name_prefix == "custom"
    end

    test "reschedules timer when interval changes", %{pid: _pid} do
      Autosave.set_enabled(true)

      # Get initial next save time
      initial_next_save = Autosave.get_stats().next_save_in

      # Change interval
      Autosave.configure(%{interval: 500})

      # Next save time should be different
      new_next_save = Autosave.get_stats().next_save_in
      assert new_next_save != initial_next_save
    end
  end

  describe "compression" do
    test "compresses large sessions", %{pid: _pid} do
      # Create a large session
      large_messages =
        for i <- 1..1_000 do
          %{role: "user", content: "Message #{i} with some content to make it larger"}
        end

      large_session = Map.put(@test_session, :messages, large_messages)
      :meck.expect(MCPChat.Session, :get_current_session, fn -> large_session end)

      # Track compression option
      test_pid = self()

      :meck.expect(MCPChat.Persistence, :save_session, fn _session, _name, opts ->
        send(test_pid, {:save_opts, opts})
        {:ok, "/tmp/large_session.json"}
      end)

      Autosave.set_enabled(true)
      Autosave.force_save()

      # Should have compress option
      assert_receive {:save_opts, opts}
      assert opts[:compress] == true
    end
  end

  describe "cleanup" do
    test "cleans up old autosaves", %{pid: _pid} do
      # Mock file operations
      :meck.new(File, [:unstick, :passthrough])

      old_files = [
        "autosave_1000.json",
        "autosave_2000.json",
        "autosave_3000.json",
        "autosave_4000.json",
        "autosave_5000.json",
        # Should be deleted
        "autosave_6000.json",
        # Should be deleted
        "autosave_7000.json"
      ]

      :meck.expect(File, :ls, fn _dir -> {:ok, old_files} end)

      :meck.expect(File, :stat!, fn path ->
        # Extract timestamp from filename for mtime
        case Regex.run(~r/autosave_(\d+)\.json/, path) do
          [_, timestamp] ->
            time = String.to_integer(timestamp)
            %File.Stat{mtime: time}

          _ ->
            %File.Stat{mtime: 0}
        end
      end)

      deleted_files = []
      test_pid = self()

      :meck.expect(File, :rm, fn path ->
        send(test_pid, {:file_deleted, path})
        :ok
      end)

      Autosave.set_enabled(true)
      Autosave.force_save()

      # Wait for cleanup to run
      Process.sleep(100)

      # Should have deleted 2 oldest files
      assert_receive {:file_deleted, path1}
      assert_receive {:file_deleted, path2}

      assert String.contains?(path1, "autosave_1000.json") or String.contains?(path1, "autosave_2000.json")
      assert String.contains?(path2, "autosave_1000.json") or String.contains?(path2, "autosave_2000.json")

      :meck.unload(File)
    end
  end
end
