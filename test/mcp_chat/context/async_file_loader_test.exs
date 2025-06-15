defmodule AsyncFileLoaderTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias AsyncFileLoader

  @test_file_content "This is a test file for async loading.\nIt has multiple lines.\n"
  @large_file_content String.duplicate("This is a large file content.\n", 1_000)

  alias AsyncFileLoaderTest
  alias ProgressTracker

  setup do
    # Create temporary test files
    test_dir = System.tmp_dir!()

    test_file = Path.join(test_dir, "test_file.txt")
    large_file = Path.join(test_dir, "large_file.txt")
    missing_file = Path.join(test_dir, "missing_file.txt")

    File.write!(test_file, @test_file_content)
    File.write!(large_file, @large_file_content)

    on_exit(fn ->
      File.rm(test_file)
      File.rm(large_file)
      File.rm(missing_file)
    end)

    %{
      test_file: test_file,
      large_file: large_file,
      missing_file: missing_file,
      test_dir: test_dir
    }
  end

  describe "load_file_async/2" do
    test "loads a single file successfully", %{test_file: test_file} do
      # Mock Session to avoid dependency
      :meck.new(MCPChat.Session, [:non_strict])

      :meck.expect(MCPChat.Session, :get_current_session, fn ->
        %{context: %{files: %{}}}
      end)

      :meck.expect(MCPChat.Session, :update_session, fn _ -> :ok end)

      # Mock ProgressTracker
      :meck.new(ProgressTracker, [:non_strict])
      :meck.expect(ProgressTracker, :start_operation, fn _name, _params -> "progress_token" end)
      :meck.expect(ProgressTracker, :complete_operation, fn _token -> :ok end)
      :meck.expect(ProgressTracker, :fail_operation, fn _token, _reason -> :ok end)

      try do
        # Test with callback
        results = []
        test_pid = self()

        callback = fn result ->
          send(test_pid, {:callback_result, result})
        end

        assert {:ok, operation_id} =
                 AsyncFileLoader.load_file_async(test_file,
                   callback: callback
                 )

        assert is_binary(operation_id)

        # Wait for callback
        receive do
          {:callback_result, {:ok, [result]}} ->
            assert result.status == :success
            assert result.result.name == "test_file.txt"
            assert result.result.content == @test_file_content
            assert result.result.size == byte_size(@test_file_content)
            assert is_integer(result.result.load_duration_ms)
            assert %DateTime{} = result.result.loaded_at
        after
          5_000 -> flunk("Callback not received within timeout")
        end
      after
        :meck.unload(MCPChat.Session)
        :meck.unload(ProgressTracker)
      end
    end

    test "handles missing files gracefully", %{missing_file: missing_file} do
      :meck.new(ProgressTracker, [:non_strict])
      :meck.expect(ProgressTracker, :start_operation, fn _, _ -> "token" end)
      :meck.expect(ProgressTracker, :complete_operation, fn _ -> :ok end)
      :meck.expect(ProgressTracker, :fail_operation, fn _, _ -> :ok end)

      try do
        test_pid = self()

        callback = fn result ->
          send(test_pid, {:callback_result, result})
        end

        assert {:ok, _operation_id} =
                 AsyncFileLoader.load_file_async(missing_file,
                   callback: callback
                 )

        # Wait for callback with error
        receive do
          {:callback_result, {:partial, %{failed: [result]}}} ->
            assert result.status == :failed
            assert result.error == :file_not_found
        after
          5_000 -> flunk("Error callback not received")
        end
      after
        :meck.unload(ProgressTracker)
      end
    end

    test "validates file size limits", %{large_file: large_file} do
      :meck.new(ProgressTracker, [:non_strict])
      :meck.expect(ProgressTracker, :start_operation, fn _, _ -> "token" end)
      :meck.expect(ProgressTracker, :complete_operation, fn _ -> :ok end)
      :meck.expect(ProgressTracker, :fail_operation, fn _, _ -> :ok end)

      try do
        # Set a very small max file size to trigger the limit
        test_pid = self()

        callback = fn result ->
          send(test_pid, {:callback_result, result})
        end

        assert {:ok, _operation_id} =
                 AsyncFileLoader.load_file_async(large_file,
                   # 100 bytes limit
                   max_file_size: 100,
                   callback: callback
                 )

        # Should fail due to size limit
        receive do
          {:callback_result, {:partial, %{failed: [result]}}} ->
            assert result.status == :failed
            assert result.error == :file_too_large
        after
          5_000 -> flunk("Size limit error not received")
        end
      after
        :meck.unload(ProgressTracker)
      end
    end
  end

  describe "load_files_async/2" do
    test "loads multiple files concurrently", %{test_file: test_file, test_dir: test_dir} do
      # Create additional test files
      test_file2 = Path.join(test_dir, "test_file2.txt")
      test_file3 = Path.join(test_dir, "test_file3.txt")

      File.write!(test_file2, "Content of file 2")
      File.write!(test_file3, "Content of file 3")

      :meck.new(ProgressTracker, [:non_strict])
      :meck.expect(ProgressTracker, :start_operation, fn _, _ -> "token" end)
      :meck.expect(ProgressTracker, :complete_operation, fn _ -> :ok end)
      :meck.expect(ProgressTracker, :fail_operation, fn _, _ -> :ok end)

      try do
        files = [test_file, test_file2, test_file3]

        progress_updates = []
        test_pid = self()

        progress_callback = fn update ->
          send(test_pid, {:progress, update})
        end

        callback = fn result ->
          send(test_pid, {:callback_result, result})
        end

        assert {:ok, operation_id} =
                 AsyncFileLoader.load_files_async(files,
                   max_concurrency: 2,
                   callback: callback,
                   progress_callback: progress_callback
                 )

        # Collect progress updates
        progress_messages = collect_progress_messages([])

        # Should have starting and completed phases
        phases = Enum.map(progress_messages, & &1.phase)
        assert :starting in phases
        assert :completed in phases

        # Wait for completion callback
        receive do
          {:callback_result, {:ok, results}} ->
            assert length(results) == 3

            # All should be successful
            Enum.each(results, fn result ->
              assert result.status == :success
              assert is_binary(result.result.content)
              assert is_binary(result.result.name)
            end)

            # Check that we got all expected files
            loaded_names = Enum.map(results, & &1.result.name) |> Enum.sort()
            expected_names = ["test_file.txt", "test_file2.txt", "test_file3.txt"]
            assert loaded_names == expected_names
        after
          10_000 -> flunk("Completion callback not received")
        end

        # Cleanup
        File.rm(test_file2)
        File.rm(test_file3)
      after
        :meck.unload(ProgressTracker)
      end
    end

    test "handles mixed success and failure", %{test_file: test_file, missing_file: missing_file} do
      :meck.new(ProgressTracker, [:non_strict])
      :meck.expect(ProgressTracker, :start_operation, fn _, _ -> "token" end)
      :meck.expect(ProgressTracker, :complete_operation, fn _ -> :ok end)
      :meck.expect(ProgressTracker, :fail_operation, fn _, _ -> :ok end)

      try do
        files = [test_file, missing_file]

        test_pid = self()

        callback = fn result ->
          send(test_pid, {:callback_result, result})
        end

        assert {:ok, _operation_id} =
                 AsyncFileLoader.load_files_async(files,
                   callback: callback
                 )

        # Wait for completion - should be partial success
        receive do
          {:callback_result, {:partial, %{successful: successful, failed: failed}}} ->
            # Should have one success and one failure
            assert length(successful) == 1
            assert length(failed) == 1

            # Check successful result
            success_result = List.first(successful)
            assert success_result.result.name == "test_file.txt"

            # Check failed result
            failed_result = List.first(failed)
            assert failed_result.error == :file_not_found
        after
          5_000 -> flunk("Partial result callback not received")
        end
      after
        :meck.unload(ProgressTracker)
      end
    end
  end

  describe "add_to_context_async/2" do
    test "adds loaded file to session context", %{test_file: test_file} do
      # Mock Session and track calls
      session_updates = []
      test_pid = self()

      :meck.new(MCPChat.Session, [:non_strict])

      :meck.expect(MCPChat.Session, :get_current_session, fn ->
        %{context: %{files: %{}}}
      end)

      :meck.expect(MCPChat.Session, :update_session, fn update ->
        send(test_pid, {:session_update, update})
        :ok
      end)

      :meck.new(ProgressTracker, [:non_strict])
      :meck.expect(ProgressTracker, :start_operation, fn _, _ -> "token" end)
      :meck.expect(ProgressTracker, :complete_operation, fn _ -> :ok end)
      :meck.expect(ProgressTracker, :fail_operation, fn _, _ -> :ok end)

      try do
        success_callback = fn result ->
          send(test_pid, {:success_callback, result})
        end

        assert {:ok, _operation_id} =
                 AsyncFileLoader.add_to_context_async(test_file,
                   success_callback: success_callback
                 )

        # Wait for session to be updated
        receive do
          {:session_update, %{context: updated_context}} ->
            assert Map.has_key?(updated_context, :files)
            files = updated_context.files
            assert Map.has_key?(files, "test_file.txt")

            file_info = files["test_file.txt"]
            assert file_info.content == @test_file_content
            assert file_info.name == "test_file.txt"
            assert file_info.size == byte_size(@test_file_content)
        after
          5_000 -> flunk("Session update not received")
        end

        # Wait for success callback
        receive do
          {:success_callback, result} ->
            assert result.status == :success
        after
          1_000 -> flunk("Success callback not received")
        end
      after
        :meck.unload(MCPChat.Session)
        :meck.unload(ProgressTracker)
      end
    end
  end

  describe "validate_file_for_context/2" do
    test "validates existing readable file", %{test_file: test_file} do
      assert :ok = AsyncFileLoader.validate_file_for_context(test_file)
    end

    test "rejects missing file", %{missing_file: missing_file} do
      assert {:error, :file_not_found} = AsyncFileLoader.validate_file_for_context(missing_file)
    end

    test "rejects file larger than limit", %{large_file: large_file} do
      assert {:error, :file_too_large} =
               AsyncFileLoader.validate_file_for_context(
                 large_file,
                 max_file_size: 100
               )
    end
  end

  # Helper function to collect progress messages
  defp collect_progress_messages(acc) do
    receive do
      {:progress, update} -> collect_progress_messages([update | acc])
    after
      100 -> Enum.reverse(acc)
    end
  end
end
