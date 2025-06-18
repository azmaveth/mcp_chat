defmodule MCPChat.Security.RevocationCacheTest do
  @moduledoc """
  Unit tests for the RevocationCache module.
  """

  use ExUnit.Case, async: false

  alias MCPChat.Security.RevocationCache

  setup do
    # Start fresh RevocationCache for each test
    start_supervised!(RevocationCache)

    # Clear any existing revocations
    RevocationCache.clear_all()

    {:ok, %{}}
  end

  describe "revoke/2" do
    test "adds token to revocation list" do
      jti = "test_token_#{System.unique_integer()}"

      # Revoke token
      assert :ok == RevocationCache.revoke(jti)

      # Check if revoked
      assert RevocationCache.is_revoked?(jti) == true
    end

    test "supports permanent revocation" do
      jti = "permanent_token_#{System.unique_integer()}"

      # Revoke permanently
      assert :ok == RevocationCache.revoke(jti, :permanent)

      # Should stay revoked
      assert RevocationCache.is_revoked?(jti) == true

      # Check stats show permanent revocation
      {:ok, stats} = RevocationCache.get_stats()
      assert stats.permanent_revocations >= 1
    end

    test "supports temporary revocation with expiry" do
      jti = "temp_token_#{System.unique_integer()}"
      # 2 seconds
      expires_at = System.system_time(:second) + 2

      # Revoke temporarily
      assert :ok == RevocationCache.revoke(jti, expires_at)

      # Should be revoked now
      assert RevocationCache.is_revoked?(jti) == true

      # Wait for expiry
      Process.sleep(2100)

      # Should no longer be revoked
      assert RevocationCache.is_revoked?(jti) == false
    end
  end

  describe "is_revoked?/1" do
    test "returns false for non-revoked tokens" do
      jti = "clean_token_#{System.unique_integer()}"
      assert RevocationCache.is_revoked?(jti) == false
    end

    test "handles concurrent checks efficiently" do
      jti = "concurrent_token_#{System.unique_integer()}"
      RevocationCache.revoke(jti)

      # Spawn multiple concurrent checks
      tasks =
        for _ <- 1..100 do
          Task.async(fn ->
            RevocationCache.is_revoked?(jti)
          end)
        end

      # All should return true
      results = Task.await_many(tasks)
      assert Enum.all?(results, &(&1 == true))
    end
  end

  describe "revoke_batch/1" do
    test "revokes multiple tokens efficiently" do
      # Generate JTIs
      jtis = for i <- 1..50, do: "batch_token_#{i}_#{System.unique_integer()}"

      # Batch revoke
      assert :ok == RevocationCache.revoke_batch(jtis)

      # All should be revoked
      for jti <- jtis do
        assert RevocationCache.is_revoked?(jti) == true
      end

      # Stats should reflect batch
      {:ok, stats} = RevocationCache.get_stats()
      assert stats.total_revocations >= 50
    end

    test "handles mixed format batch revocations" do
      now = System.system_time(:second)

      # Mix of formats
      revocations = [
        "simple_jti_1",
        {"jti_with_expiry", now + 3600},
        "simple_jti_2",
        {"permanent_jti", :permanent}
      ]

      assert :ok == RevocationCache.revoke_batch(revocations)

      # All should be revoked
      assert RevocationCache.is_revoked?("simple_jti_1") == true
      assert RevocationCache.is_revoked?("jti_with_expiry") == true
      assert RevocationCache.is_revoked?("simple_jti_2") == true
      assert RevocationCache.is_revoked?("permanent_jti") == true
    end
  end

  describe "get_stats/0" do
    test "returns accurate statistics" do
      # Add some revocations
      RevocationCache.revoke("perm_1", :permanent)
      RevocationCache.revoke("perm_2", :permanent)

      now = System.system_time(:second)
      RevocationCache.revoke("temp_1", now + 3600)
      RevocationCache.revoke("temp_2", now + 7200)

      # Already expired
      RevocationCache.revoke("expired_1", now - 1)

      # Get stats
      {:ok, stats} = RevocationCache.get_stats()

      # Not counting expired
      assert stats.total_revocations >= 4
      assert stats.permanent_revocations >= 2
      assert stats.temporary_revocations >= 2
      assert is_atom(stats.node)
      assert is_list(stats.connected_nodes)
    end
  end

  describe "clear_all/0" do
    test "removes all revocations" do
      # Add some revocations
      for i <- 1..10 do
        RevocationCache.revoke("clear_test_#{i}")
      end

      # Verify they exist
      {:ok, stats_before} = RevocationCache.get_stats()
      assert stats_before.total_revocations >= 10

      # Clear all
      assert :ok == RevocationCache.clear_all()

      # Verify cleared
      {:ok, stats_after} = RevocationCache.get_stats()
      assert stats_after.total_revocations == 0

      # Tokens should no longer be revoked
      assert RevocationCache.is_revoked?("clear_test_1") == false
    end
  end

  describe "distributed behavior" do
    test "handles revocation broadcasts" do
      jti = "broadcast_token_#{System.unique_integer()}"

      # Simulate broadcast from another node
      Phoenix.PubSub.broadcast(
        MCPChat.PubSub,
        "security:revocations",
        {:revocation_broadcast, jti, :permanent, :fake_node@host}
      )

      # Allow propagation
      Process.sleep(50)

      # Should be revoked locally
      assert RevocationCache.is_revoked?(jti) == true
    end

    test "broadcasts local revocations" do
      jti = "local_broadcast_#{System.unique_integer()}"

      # Subscribe to revocation topic
      Phoenix.PubSub.subscribe(MCPChat.PubSub, "security:revocations")

      # Revoke locally
      RevocationCache.revoke(jti)

      # Should receive broadcast
      assert_receive {:revocation_broadcast, ^jti, _, node}, 1000
      assert node == node()
    end

    test "handles clear broadcasts" do
      # Add some revocations
      RevocationCache.revoke("dist_clear_1")
      RevocationCache.revoke("dist_clear_2")

      # Simulate clear from another node
      Phoenix.PubSub.broadcast(
        MCPChat.PubSub,
        "security:revocations",
        {:revocation_cleared, :remote_node@host}
      )

      # Allow propagation
      Process.sleep(50)

      # Should be cleared locally
      {:ok, stats} = RevocationCache.get_stats()
      assert stats.total_revocations == 0
    end
  end

  describe "cleanup behavior" do
    test "automatically cleans up expired revocations" do
      now = System.system_time(:second)

      # Add mix of revocations
      RevocationCache.revoke("cleanup_perm", :permanent)
      RevocationCache.revoke("cleanup_future", now + 3600)
      RevocationCache.revoke("cleanup_expired_1", now - 1)
      RevocationCache.revoke("cleanup_expired_2", now - 100)

      # Trigger cleanup
      send(Process.whereis(RevocationCache), :cleanup)
      Process.sleep(100)

      # Check what remains
      assert RevocationCache.is_revoked?("cleanup_perm") == true
      assert RevocationCache.is_revoked?("cleanup_future") == true
      assert RevocationCache.is_revoked?("cleanup_expired_1") == false
      assert RevocationCache.is_revoked?("cleanup_expired_2") == false
    end
  end

  describe "performance characteristics" do
    test "handles large revocation lists efficiently" do
      # Add many revocations
      jtis = for i <- 1..1000, do: "perf_test_#{i}"
      RevocationCache.revoke_batch(jtis)

      # Measure lookup time
      sample_jti = "perf_test_500"

      {time, true} =
        :timer.tc(fn ->
          RevocationCache.is_revoked?(sample_jti)
        end)

      # Should be very fast (under 1ms)
      assert time < 1000, "Lookup took #{time}μs, expected < 1000μs"

      # Non-existent lookup should also be fast
      {time2, false} =
        :timer.tc(fn ->
          RevocationCache.is_revoked?("non_existent_token")
        end)

      assert time2 < 1000, "Negative lookup took #{time2}μs, expected < 1000μs"
    end
  end
end
