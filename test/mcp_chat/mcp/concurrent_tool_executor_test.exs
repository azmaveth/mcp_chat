defmodule MCPChat.MCP.ConcurrentToolExecutorTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias MCPChat.MCP.ConcurrentToolExecutor
  alias MCPChat.MCP.ConcurrentToolExecutor.ExecutionResult

  describe "execute_concurrent/2" do
    test "executes multiple tools concurrently" do
      tool_calls = [
        {"server1", "read_file", %{"path" => "/tmp/file1"}},
        {"server2", "get_data", %{"id" => "123"}},
        {"server1", "list_dir", %{"path" => "/tmp"}}
      ]

      # Mock ServerManager.call_tool to return success
      :meck.new(MCPChat.MCP.ServerManager, [:non_strict])

      :meck.expect(MCPChat.MCP.ServerManager, :call_tool, fn _server, _tool, _args ->
        # Simulate work
        Process.sleep(10)
        {:ok, %{"result" => "success"}}
      end)

      # Mock ProgressTracker
      :meck.new(MCPChat.MCP.ProgressTracker, [:non_strict])

      :meck.expect(MCPChat.MCP.ProgressTracker, :start_operation, fn _name, _params ->
        {:ok, "progress_token_#{:rand.uniform(1_000)}"}
      end)

      :meck.expect(MCPChat.MCP.ProgressTracker, :complete_operation, fn _token -> :ok end)
      :meck.expect(MCPChat.MCP.ProgressTracker, :fail_operation, fn _token, _reason -> :ok end)

      try do
        assert {:ok, results} =
                 ConcurrentToolExecutor.execute_concurrent(tool_calls,
                   max_concurrency: 2,
                   timeout: 5_000
                 )

        assert length(results) == 3

        # All results should be successful
        Enum.each(results, fn result ->
          assert %ExecutionResult{} = result
          assert result.status == :success
          assert is_binary(result.server_name)
          assert is_binary(result.tool_name)
          assert is_integer(result.duration_ms)
          assert result.duration_ms >= 0
        end)

        # Should have called all tools
        assert :meck.num_calls(MCPChat.MCP.ServerManager, :call_tool, :_) == 3
      after
        :meck.unload(MCPChat.MCP.ServerManager)
        :meck.unload(MCPChat.MCP.ProgressTracker)
      end
    end

    test "handles tool execution failures gracefully" do
      tool_calls = [
        {"server1", "good_tool", %{}},
        {"server1", "bad_tool", %{}},
        {"server2", "another_good", %{}}
      ]

      # Mock with mixed success/failure
      :meck.new(MCPChat.MCP.ServerManager, [:non_strict])

      :meck.expect(MCPChat.MCP.ServerManager, :call_tool, fn
        _server, "bad_tool", _args -> {:error, :tool_failed}
        _server, _tool, _args -> {:ok, %{"result" => "success"}}
      end)

      :meck.new(MCPChat.MCP.ProgressTracker, [:non_strict])
      :meck.expect(MCPChat.MCP.ProgressTracker, :start_operation, fn _name, _params -> {:ok, "progress_token"} end)
      :meck.expect(MCPChat.MCP.ProgressTracker, :complete_operation, fn _token -> :ok end)
      :meck.expect(MCPChat.MCP.ProgressTracker, :fail_operation, fn _token, _reason -> :ok end)

      try do
        assert {:ok, results} = ConcurrentToolExecutor.execute_concurrent(tool_calls)

        assert length(results) == 3

        # Check results by tool name
        results_by_tool = Enum.group_by(results, & &1.tool_name)

        good_result = results_by_tool["good_tool"] |> List.first()
        assert good_result.status == :success

        bad_result = results_by_tool["bad_tool"] |> List.first()
        assert bad_result.status == :failed
        assert bad_result.error == :tool_failed

        another_result = results_by_tool["another_good"] |> List.first()
        assert another_result.status == :success
      after
        :meck.unload(MCPChat.MCP.ServerManager)
        :meck.unload(MCPChat.MCP.ProgressTracker)
      end
    end

    test "respects same_server_sequential option" do
      tool_calls = [
        {"server1", "tool1", %{}},
        {"server1", "tool2", %{}},
        {"server2", "tool3", %{}},
        {"server2", "tool4", %{}}
      ]

      # Track execution order with timestamps
      test_pid = self()
      execution_order = :ets.new(:execution_order, [:public, :ordered_set])

      :meck.new(MCPChat.MCP.ServerManager, [:non_strict])

      :meck.expect(MCPChat.MCP.ServerManager, :call_tool, fn server, tool, _args ->
        timestamp = System.monotonic_time(:microsecond)
        :ets.insert(execution_order, {timestamp, {server, tool}})
        # Ensure measurable time difference
        Process.sleep(20)
        {:ok, %{"result" => "success"}}
      end)

      :meck.new(MCPChat.MCP.ProgressTracker, [:non_strict])
      :meck.expect(MCPChat.MCP.ProgressTracker, :start_operation, fn _, _ -> {:ok, "token"} end)
      :meck.expect(MCPChat.MCP.ProgressTracker, :complete_operation, fn _ -> :ok end)
      :meck.expect(MCPChat.MCP.ProgressTracker, :fail_operation, fn _, _ -> :ok end)

      try do
        assert {:ok, _results} =
                 ConcurrentToolExecutor.execute_concurrent(tool_calls,
                   same_server_sequential: true,
                   max_concurrency: 4
                 )

        # Check execution order - tools from same server should be sequential within their group
        order = :ets.tab2list(execution_order) |> Enum.map(fn {_ts, {server, tool}} -> {server, tool} end)

        # Find server1 tools and their order
        server1_tools =
          order
          |> Enum.with_index()
          |> Enum.filter(fn {{server, _tool}, _index} -> server == "server1" end)
          |> Enum.map(fn {{_server, tool}, index} -> {tool, index} end)

        # Find server2 tools and their order
        server2_tools =
          order
          |> Enum.with_index()
          |> Enum.filter(fn {{server, _tool}, _index} -> server == "server2" end)
          |> Enum.map(fn {{_server, tool}, index} -> {tool, index} end)

        # Within each server, tools should be in the right order (tool1 before tool2, tool3 before tool4)
        case server1_tools do
          [{"tool1", pos1}, {"tool2", pos2}] -> assert pos1 < pos2, "tool1 should execute before tool2"
          [{"tool2", pos1}, {"tool1", pos2}] -> assert pos1 > pos2, "tool1 should execute before tool2"
          _ -> flunk("Expected exactly 2 server1 tools")
        end

        case server2_tools do
          [{"tool3", pos3}, {"tool4", pos4}] -> assert pos3 < pos4, "tool3 should execute before tool4"
          [{"tool4", pos3}, {"tool3", pos4}] -> assert pos3 > pos4, "tool3 should execute before tool4"
          _ -> flunk("Expected exactly 2 server2 tools")
        end
      after
        :ets.delete(execution_order)
        :meck.unload(MCPChat.MCP.ServerManager)
        :meck.unload(MCPChat.MCP.ProgressTracker)
      end
    end

    test "provides progress callbacks" do
      tool_calls = [
        {"server1", "tool1", %{}},
        {"server2", "tool2", %{}}
      ]

      progress_updates = []

      progress_callback = fn update ->
        send(self(), {:progress, update})
      end

      :meck.new(MCPChat.MCP.ServerManager, [:non_strict])

      :meck.expect(MCPChat.MCP.ServerManager, :call_tool, fn _server, _tool, _args ->
        {:ok, %{"result" => "success"}}
      end)

      :meck.new(MCPChat.MCP.ProgressTracker, [:non_strict])
      :meck.expect(MCPChat.MCP.ProgressTracker, :start_operation, fn _, _ -> {:ok, "token"} end)
      :meck.expect(MCPChat.MCP.ProgressTracker, :complete_operation, fn _ -> :ok end)
      :meck.expect(MCPChat.MCP.ProgressTracker, :fail_operation, fn _, _ -> :ok end)

      try do
        assert {:ok, _results} =
                 ConcurrentToolExecutor.execute_concurrent(tool_calls,
                   progress_callback: progress_callback
                 )

        # Collect progress messages
        progress_messages = collect_progress_messages([])

        # Should have at least starting and completed phases
        phases = Enum.map(progress_messages, & &1.phase)
        assert :starting in phases
        assert :completed in phases

        # Starting phase should have correct totals
        starting_msg = Enum.find(progress_messages, &(&1.phase == :starting))
        assert starting_msg.total == 2
        assert starting_msg.completed == 0

        # Completed phase should have results
        completed_msg = Enum.find(progress_messages, &(&1.phase == :completed))
        assert completed_msg.total == 2
        assert completed_msg.completed + completed_msg.failed == 2
      after
        :meck.unload(MCPChat.MCP.ServerManager)
        :meck.unload(MCPChat.MCP.ProgressTracker)
      end
    end
  end

  describe "tool_safe_for_concurrency?/2" do
    test "identifies unsafe tools correctly" do
      # Known unsafe tools
      refute ConcurrentToolExecutor.tool_safe_for_concurrency?("write_file")
      refute ConcurrentToolExecutor.tool_safe_for_concurrency?("delete_file")
      refute ConcurrentToolExecutor.tool_safe_for_concurrency?("create_directory")
      refute ConcurrentToolExecutor.tool_safe_for_concurrency?("set_config")

      # Tools with unsafe keywords
      refute ConcurrentToolExecutor.tool_safe_for_concurrency?("update_database")
      refute ConcurrentToolExecutor.tool_safe_for_concurrency?("create_user")
      refute ConcurrentToolExecutor.tool_safe_for_concurrency?("modify_settings")

      # Safe tools
      assert ConcurrentToolExecutor.tool_safe_for_concurrency?("read_file")
      assert ConcurrentToolExecutor.tool_safe_for_concurrency?("get_weather")
      assert ConcurrentToolExecutor.tool_safe_for_concurrency?("search_database")
      assert ConcurrentToolExecutor.tool_safe_for_concurrency?("list_files")
    end

    test "respects safety_checks option" do
      # With safety checks disabled, all tools are considered safe
      assert ConcurrentToolExecutor.tool_safe_for_concurrency?("delete_file", safety_checks: false)
      assert ConcurrentToolExecutor.tool_safe_for_concurrency?("write_file", safety_checks: false)

      # With safety checks enabled (default), unsafe tools are caught
      refute ConcurrentToolExecutor.tool_safe_for_concurrency?("delete_file", safety_checks: true)
      refute ConcurrentToolExecutor.tool_safe_for_concurrency?("write_file", safety_checks: true)
    end
  end

  describe "execute_single/4" do
    test "executes a single tool" do
      :meck.new(MCPChat.MCP.ServerManager, [:non_strict])

      :meck.expect(MCPChat.MCP.ServerManager, :call_tool, fn _server, _tool, _args ->
        {:ok, %{"result" => "single_success"}}
      end)

      :meck.new(MCPChat.MCP.ProgressTracker, [:non_strict])
      :meck.expect(MCPChat.MCP.ProgressTracker, :start_operation, fn _, _ -> {:ok, "token"} end)
      :meck.expect(MCPChat.MCP.ProgressTracker, :complete_operation, fn _ -> :ok end)
      :meck.expect(MCPChat.MCP.ProgressTracker, :fail_operation, fn _, _ -> :ok end)

      try do
        assert {:ok, results} =
                 ConcurrentToolExecutor.execute_single(
                   "test_server",
                   "test_tool",
                   %{"param" => "value"}
                 )

        assert length(results) == 1
        result = List.first(results)
        assert result.status == :success
        assert result.server_name == "test_server"
        assert result.tool_name == "test_tool"
      after
        :meck.unload(MCPChat.MCP.ServerManager)
        :meck.unload(MCPChat.MCP.ProgressTracker)
      end
    end
  end

  describe "get_execution_stats/0" do
    test "returns basic statistics" do
      stats = ConcurrentToolExecutor.get_execution_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :total_executions)
      assert Map.has_key?(stats, :concurrent_executions)
      assert Map.has_key?(stats, :average_duration)
      assert Map.has_key?(stats, :success_rate)
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
