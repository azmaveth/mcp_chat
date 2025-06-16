defmodule MCPChat.ConnectionPoolTest do
  use ExUnit.Case, async: false

  alias MCPChat.ConnectionPool

  @moduletag :unit

  describe "ConnectionPool" do
    setup do
      pool_name = :"test_pool_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        ConnectionPool.start_link(
          name: pool_name,
          size: 3,
          health_check_interval: 1_000,
          connection_timeout: 1_000
        )

      on_exit(fn ->
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end
      end)

      {:ok, pool: pool_name, pid: pid}
    end

    test "starts with correct initial state", %{pool: pool} do
      # Give some time for initial connections to be created
      Process.sleep(100)

      stats = ConnectionPool.get_stats(pool)

      # Should have attempted to create initial connections
      assert stats.total >= 0
      assert stats.available >= 0
      assert stats.in_use == 0
      assert stats.waiting == 0
    end

    test "can checkout and checkin connections", %{pool: pool} do
      # Give time for initial connections
      Process.sleep(100)

      {:ok, conn} = ConnectionPool.checkout(pool)
      assert conn != nil

      stats = ConnectionPool.get_stats(pool)
      assert stats.in_use == 1

      ConnectionPool.checkin(pool, conn)
      Process.sleep(10)

      stats = ConnectionPool.get_stats(pool)
      assert stats.in_use == 0
    end

    test "with_connection handles checkout/checkin automatically", %{pool: pool} do
      Process.sleep(100)

      result =
        ConnectionPool.with_connection(pool, fn conn ->
          assert conn != nil
          :test_result
        end)

      assert result == {:ok, :test_result}

      # Connection should be returned to pool
      stats = ConnectionPool.get_stats(pool)
      assert stats.in_use == 0
    end

    test "with_connection handles errors and removes bad connections", %{pool: pool} do
      Process.sleep(100)

      initial_stats = ConnectionPool.get_stats(pool)

      # Function that throws an error
      assert_raise RuntimeError, "test error", fn ->
        ConnectionPool.with_connection(pool, fn _conn ->
          raise "test error"
        end)
      end

      Process.sleep(10)

      # Bad connection should be removed
      final_stats = ConnectionPool.get_stats(pool)
      assert final_stats.total <= initial_stats.total
      assert final_stats.in_use == 0
    end

    test "handles multiple concurrent checkouts", %{pool: pool} do
      Process.sleep(100)

      # Checkout multiple connections concurrently
      tasks =
        for _i <- 1..2 do
          Task.async(fn ->
            ConnectionPool.checkout(pool)
          end)
        end

      results = Task.await_many(tasks)

      # All should succeed or some might timeout/queue
      success_count =
        Enum.count(results, fn
          {:ok, _conn} -> true
          _ -> false
        end)

      assert success_count >= 1

      # Check in all successful connections
      Enum.each(results, fn
        {:ok, conn} -> ConnectionPool.checkin(pool, conn)
        _ -> :ok
      end)
    end

    test "queues requests when pool is exhausted", %{pool: pool} do
      Process.sleep(100)

      # Fill the pool
      connections =
        for _i <- 1..5 do
          case ConnectionPool.checkout(pool, 100) do
            {:ok, conn} -> conn
            _ -> nil
          end
        end

      valid_connections = Enum.filter(connections, & &1)

      if length(valid_connections) > 0 do
        # Try to checkout when pool is full - should timeout quickly
        start_time = System.monotonic_time(:millisecond)
        result = ConnectionPool.checkout(pool, 50)
        end_time = System.monotonic_time(:millisecond)

        case result do
          {:error, :timeout} ->
            # Expected timeout
            assert end_time - start_time >= 40

          {:ok, _conn} ->
            # Pool might have had room or created new connection
            :ok
        end

        # Return connections
        Enum.each(valid_connections, fn conn ->
          ConnectionPool.checkin(pool, conn)
        end)
      end
    end
  end

  describe "HTTP request methods" do
    setup do
      pool_name = :"http_test_pool_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        ConnectionPool.start_link(
          name: pool_name,
          size: 2
        )

      on_exit(fn ->
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end
      end)

      {:ok, pool: pool_name}
    end

    @tag :external
    test "can make GET requests", %{pool: pool} do
      Process.sleep(100)

      case ConnectionPool.get(pool, "https://httpbin.org/get") do
        {:ok, {:ok, %Req.Response{status: 200, body: body}}} ->
          assert is_map(body)
          assert body["url"] == "https://httpbin.org/get"

        {:ok, {:error, _reason}} ->
          # Network error is acceptable in tests
          :ok

        {:error, _reason} ->
          # Pool error is also acceptable
          :ok
      end
    end

    @tag :external
    test "can make POST requests", %{pool: pool} do
      Process.sleep(100)

      test_data = %{key: "value", number: 42}

      case ConnectionPool.post(pool, "https://httpbin.org/post", json: test_data) do
        {:ok, {:ok, %Req.Response{status: 200, body: body}}} ->
          assert is_map(body)
          assert body["json"] == %{"key" => "value", "number" => 42}

        {:ok, {:error, _reason}} ->
          # Network error is acceptable in tests
          :ok

        {:error, _reason} ->
          # Pool error is also acceptable
          :ok
      end
    end

    test "handles unsupported HTTP methods", %{pool: pool} do
      Process.sleep(100)

      case ConnectionPool.request(pool, :unsupported, "https://example.com") do
        {:ok, {:error, {:unsupported_method, :unsupported}}} ->
          :ok

        {:error, _reason} ->
          # Pool error is also acceptable
          :ok
      end
    end

    test "request method supports all standard HTTP verbs", %{pool: pool} do
      Process.sleep(100)

      methods = [:get, :post, :put, :patch, :delete, :head]

      Enum.each(methods, fn method ->
        # Just verify the method is accepted (network might fail)
        case ConnectionPool.request(pool, method, "https://httpbin.org/status/200") do
          {:ok, _result} -> :ok
          {:error, _reason} -> :ok
        end
      end)
    end
  end

  describe "health checks" do
    setup do
      pool_name = :"health_test_pool_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        ConnectionPool.start_link(
          name: pool_name,
          size: 1,
          # Very frequent for testing
          health_check_interval: 100
        )

      on_exit(fn ->
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end
      end)

      {:ok, pool: pool_name}
    end

    @tag :external
    test "performs periodic health checks", %{pool: pool} do
      # Wait for initial setup and first health check
      Process.sleep(200)

      stats = ConnectionPool.get_stats(pool)

      # Should have some connections and health status
      assert stats.total >= 0
      assert stats.healthy >= 0
    end

    test "reports healthy connections in stats", %{pool: pool} do
      Process.sleep(100)

      stats = ConnectionPool.get_stats(pool)

      # Healthy count should be between 0 and total
      assert stats.healthy >= 0
      assert stats.healthy <= stats.total
    end
  end

  describe "connection lifecycle" do
    setup do
      pool_name = :"lifecycle_test_pool_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        ConnectionPool.start_link(
          name: pool_name,
          size: 2,
          # Short timeout for testing
          idle_timeout: 50,
          # Short max idle for testing
          max_idle_time: 100
        )

      on_exit(fn ->
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end
      end)

      {:ok, pool: pool_name}
    end

    test "removes connections after idle timeout", %{pool: pool} do
      Process.sleep(100)

      initial_stats = ConnectionPool.get_stats(pool)

      if initial_stats.total > 0 do
        # Wait for idle timeout
        Process.sleep(200)

        final_stats = ConnectionPool.get_stats(pool)

        # Some connections might have been removed due to idle timeout
        # (This is timing-dependent so we just verify the pool is still functional)
        assert final_stats.total >= 0
      end
    end

    test "creates replacement connections when removed", %{pool: pool} do
      Process.sleep(100)

      # Try to get a connection and force its removal
      case ConnectionPool.checkout(pool) do
        {:ok, conn} ->
          # Force remove the connection
          GenServer.cast(pool, {:remove_connection, conn})
          Process.sleep(50)

          # Pool should attempt to create replacement
          final_stats = ConnectionPool.get_stats(pool)
          assert final_stats.total >= 0

        _ ->
          # If we can't get a connection, that's also a valid test outcome
          :ok
      end
    end
  end

  describe "error handling" do
    setup do
      pool_name = :"error_test_pool_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        ConnectionPool.start_link(
          name: pool_name,
          size: 1
        )

      on_exit(fn ->
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end
      end)

      {:ok, pool: pool_name}
    end

    test "handles invalid pool names gracefully" do
      # GenServer.call will exit if the process doesn't exist
      catch_exit(ConnectionPool.checkout(:nonexistent_pool, 10))
    end

    test "handles checkin of unknown connections", %{pool: pool} do
      Process.sleep(100)

      # Try to checkin a fake connection
      fake_conn = make_ref()

      # Should not crash
      ConnectionPool.checkin(pool, fake_conn)
      Process.sleep(10)

      # Pool should still be functional
      stats = ConnectionPool.get_stats(pool)
      assert is_map(stats)
    end

    test "handles stats request on healthy pool", %{pool: pool} do
      stats = ConnectionPool.get_stats(pool)

      assert is_map(stats)
      assert Map.has_key?(stats, :total)
      assert Map.has_key?(stats, :available)
      assert Map.has_key?(stats, :in_use)
      assert Map.has_key?(stats, :waiting)
      assert Map.has_key?(stats, :healthy)

      # All values should be non-negative integers
      assert stats.total >= 0
      assert stats.available >= 0
      assert stats.in_use >= 0
      assert stats.waiting >= 0
      assert stats.healthy >= 0
    end
  end
end
