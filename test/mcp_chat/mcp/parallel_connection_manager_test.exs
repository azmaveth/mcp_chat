defmodule MCPChat.MCP.ParallelConnectionManagerTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias MCPChat.MCP.ParallelConnectionManager
  alias MCPChat.MCP.ParallelConnectionManager.ConnectionResult

  alias MCPChat.MCP.LazyServerManager
  alias MCPChat.MCP.ParallelConnectionManagerTest
  alias ServerManager.Core

  describe "connect_servers_parallel/2" do
    test "connects multiple servers successfully" do
      servers = [
        {"server1", %{command: ["echo", "server1"]}},
        {"server2", %{command: ["echo", "server2"]}},
        {"server3", %{command: ["echo", "server3"]}}
      ]

      # Mock ServerManager.Core.start_server to return success
      :meck.new(Core, [:non_strict])
      :meck.expect(Core, :start_server, fn _name, _config -> {:ok, self()} end)

      # Mock GenServer.call to simulate successful connection
      :meck.new(GenServer, [:unstick, :passthrough])
      :meck.expect(GenServer, :call, fn _pid, :get_info, _timeout -> {:ok, %{status: :connected}} end)

      try do
        assert {:ok, results} =
                 ParallelConnectionManager.connect_servers_parallel(servers,
                   max_concurrency: 2,
                   connection_timeout: 1_000
                 )

        assert length(results) == 3

        # All results should be successful
        Enum.each(results, fn result ->
          assert %ConnectionResult{} = result
          assert result.status == :connected
          assert is_binary(result.server_name)
          assert is_integer(result.duration_ms)
          assert result.duration_ms >= 0
        end)

        # Server names should match input
        server_names = Enum.map(results, & &1.server_name)
        assert "server1" in server_names
        assert "server2" in server_names
        assert "server3" in server_names
      after
        :meck.unload(Core)
        :meck.unload(GenServer)
      end
    end

    test "handles server connection failures gracefully" do
      servers = [
        {"good_server", %{command: ["echo", "good"]}},
        {"bad_server", %{command: ["false"]}},
        {"another_good", %{command: ["echo", "another"]}}
      ]

      # Mock with mixed success/failure
      :meck.new(Core, [:non_strict])

      :meck.expect(Core, :start_server, fn
        "bad_server", _config -> {:error, :connection_failed}
        _name, _config -> {:ok, self()}
      end)

      :meck.new(GenServer, [:unstick, :passthrough])
      :meck.expect(GenServer, :call, fn _pid, :get_info, _timeout -> {:ok, %{status: :connected}} end)

      try do
        assert {:ok, results} =
                 ParallelConnectionManager.connect_servers_parallel(servers,
                   max_concurrency: 3
                 )

        assert length(results) == 3

        # Check results by server name
        results_by_name = Enum.group_by(results, & &1.server_name)

        good_result = results_by_name["good_server"] |> List.first()
        assert good_result.status == :connected

        bad_result = results_by_name["bad_server"] |> List.first()
        assert bad_result.status == :failed
        assert bad_result.error == :connection_failed

        another_result = results_by_name["another_good"] |> List.first()
        assert another_result.status == :connected
      after
        :meck.unload(Core)
        :meck.unload(GenServer)
      end
    end

    test "respects concurrency limits" do
      servers = [
        {"server1", %{command: ["sleep", "0.1"]}},
        {"server2", %{command: ["sleep", "0.1"]}},
        {"server3", %{command: ["sleep", "0.1"]}},
        {"server4", %{command: ["sleep", "0.1"]}}
      ]

      # Track concurrent connections
      test_pid = self()
      concurrent_count = :ets.new(:concurrent_test, [:public])
      :ets.insert(concurrent_count, {:count, 0})
      :ets.insert(concurrent_count, {:max_seen, 0})

      :meck.new(Core, [:non_strict])

      :meck.expect(Core, :start_server, fn _name, _config ->
        # Increment counter
        current = :ets.update_counter(concurrent_count, :count, 1)
        max_seen = :ets.lookup_element(concurrent_count, :max_seen, 2)

        if current > max_seen do
          :ets.insert(concurrent_count, {:max_seen, current})
        end

        # Simulate work
        Process.sleep(50)

        # Decrement counter
        :ets.update_counter(concurrent_count, :count, -1)

        {:ok, self()}
      end)

      :meck.new(GenServer, [:unstick, :passthrough])
      :meck.expect(GenServer, :call, fn _pid, :get_info, _timeout -> {:ok, %{status: :connected}} end)

      try do
        assert {:ok, results} =
                 ParallelConnectionManager.connect_servers_parallel(servers,
                   max_concurrency: 2,
                   connection_timeout: 5_000
                 )

        assert length(results) == 4

        # Check that concurrency limit was respected
        max_concurrent = :ets.lookup_element(concurrent_count, :max_seen, 2)
        assert max_concurrent <= 2
      after
        :ets.delete(concurrent_count)
        :meck.unload(Core)
        :meck.unload(GenServer)
      end
    end

    test "provides progress callbacks" do
      servers = [
        {"server1", %{command: ["echo", "1"]}},
        {"server2", %{command: ["echo", "2"]}}
      ]

      progress_updates = []

      progress_callback = fn update ->
        send(self(), {:progress, update})
      end

      :meck.new(Core, [:non_strict])
      :meck.expect(Core, :start_server, fn _name, _config -> {:ok, self()} end)

      :meck.new(GenServer, [:unstick, :passthrough])
      :meck.expect(GenServer, :call, fn _pid, :get_info, _timeout -> {:ok, %{status: :connected}} end)

      try do
        assert {:ok, _results} =
                 ParallelConnectionManager.connect_servers_parallel(servers,
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
        :meck.unload(Core)
        :meck.unload(GenServer)
      end
    end

    test "handles configuration from MCPChat.Config" do
      # Mock config to return specific parallel settings
      :meck.new(MCPChat.Config, [:non_strict])

      :meck.expect(MCPChat.Config, :get, fn [:startup, :parallel] ->
        %{
          max_concurrency: 8,
          connection_timeout: 15_000,
          show_progress: true
        }
      end)

      servers = [{"test_server", %{command: ["echo", "test"]}}]

      :meck.new(Core, [:non_strict])
      :meck.expect(Core, :start_server, fn _name, _config -> {:ok, self()} end)

      :meck.new(GenServer, [:unstick, :passthrough])
      :meck.expect(GenServer, :call, fn _pid, :get_info, _timeout -> {:ok, %{status: :connected}} end)

      try do
        # Should use config values since no opts override
        assert {:ok, _results} = ParallelConnectionManager.connect_servers_parallel(servers)

        # Verify config was called
        assert :meck.called(MCPChat.Config, :get, [[:startup, :parallel]])
      after
        :meck.unload(MCPChat.Config)
        :meck.unload(Core)
        :meck.unload(GenServer)
      end
    end
  end

  describe "connect_with_mode/3" do
    test "handles eager mode with parallel connections" do
      servers = [{"server1", %{command: ["echo", "1"]}}]

      :meck.new(Core, [:non_strict])
      :meck.expect(Core, :start_server, fn _name, _config -> {:ok, self()} end)

      :meck.new(GenServer, [:unstick, :passthrough])
      :meck.expect(GenServer, :call, fn _pid, :get_info, _timeout -> {:ok, %{status: :connected}} end)

      try do
        assert {:ok, results} = ParallelConnectionManager.connect_with_mode(servers, :eager)
        assert length(results) == 1
      after
        :meck.unload(Core)
        :meck.unload(GenServer)
      end
    end

    test "handles background mode with async connections" do
      servers = [{"server1", %{command: ["echo", "1"]}}]

      assert {:ok, results} = ParallelConnectionManager.connect_with_mode(servers, :background)

      # Background mode returns empty results immediately
      assert results == []

      # Give background task time to start
      Process.sleep(50)
    end

    test "handles lazy mode preparation" do
      servers = [{"server1", %{command: ["echo", "1"]}}]

      :meck.new(LazyServerManager, [:non_strict])

      :meck.expect(LazyServerManager, :prepare_parallel_connections, fn _servers, _opts ->
        {:ok, :prepared}
      end)

      try do
        assert {:ok, results} = ParallelConnectionManager.connect_with_mode(servers, :lazy)
        assert results == []
      after
        :meck.unload(LazyServerManager)
      end
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
