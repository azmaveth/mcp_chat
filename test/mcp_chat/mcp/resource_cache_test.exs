defmodule MCPChat.MCP.ResourceCacheTest do
  use ExUnit.Case
  alias MCPChat.MCP.ResourceCache

  @cache_dir Path.join(System.tmp_dir!(), "mcp_chat_test_cache_#{:os.getpid()}")

  alias MCPChat.MCP.ResourceCacheTest

  setup do
    # Ensure clean cache directory
    File.rm_rf!(@cache_dir)
    File.mkdir_p!(@cache_dir)

    # Start cache with test configuration
    {:ok, cache} =
      ResourceCache.start_link(
        name: :test_cache,
        cache_dir: @cache_dir,
        # 1MB
        max_size: 1_024 * 1_024,
        ttl: 60,
        cleanup_interval: 300
      )

    on_exit(fn ->
      GenServer.stop(cache)
      File.rm_rf!(@cache_dir)
    end)

    {:ok, cache: cache}
  end

  describe "get_resource/3" do
    test "caches and retrieves resources", %{cache: cache} do
      server = "test_server"
      uri = "test://resource"
      content = "test content"

      # First call should miss cache
      result1 =
        ResourceCache.get_resource(cache, server, uri, fn ->
          {:ok, content}
        end)

      assert {:ok, ^content} = result1

      # Second call should hit cache
      result2 =
        ResourceCache.get_resource(cache, server, uri, fn ->
          {:ok, "different content"}
        end)

      assert {:ok, ^content} = result2
    end

    test "handles fetch errors", %{cache: cache} do
      server = "test_server"
      uri = "test://error"

      result =
        ResourceCache.get_resource(cache, server, uri, fn ->
          {:error, "fetch failed"}
        end)

      assert {:error, "fetch failed"} = result
    end

    test "respects TTL", %{cache: cache} do
      # Start new cache with short TTL
      GenServer.stop(cache)

      {:ok, cache} =
        ResourceCache.start_link(
          name: :test_cache_ttl,
          cache_dir: @cache_dir,
          # Immediate expiration
          ttl: 0
        )

      server = "test_server"
      uri = "test://ttl"

      # First call
      ResourceCache.get_resource(cache, server, uri, fn ->
        {:ok, "content1"}
      end)

      # Second call should fetch again due to expiration
      result =
        ResourceCache.get_resource(cache, server, uri, fn ->
          {:ok, "content2"}
        end)

      assert {:ok, "content2"} = result

      GenServer.stop(cache)
    end
  end

  describe "invalidate_resource/3" do
    test "removes resource from cache", %{cache: cache} do
      server = "test_server"
      uri = "test://invalidate"
      content = "test content"

      # Cache the resource
      ResourceCache.get_resource(cache, server, uri, fn ->
        {:ok, content}
      end)

      # Invalidate it
      :ok = ResourceCache.invalidate_resource(cache, server, uri)

      # Next call should fetch fresh
      result =
        ResourceCache.get_resource(cache, server, uri, fn ->
          {:ok, "fresh content"}
        end)

      assert {:ok, "fresh content"} = result
    end
  end

  describe "clear_cache/1" do
    test "removes all cached resources", %{cache: cache} do
      # Cache multiple resources
      ResourceCache.get_resource(cache, "server1", "uri1", fn -> {:ok, "content1"} end)
      ResourceCache.get_resource(cache, "server2", "uri2", fn -> {:ok, "content2"} end)

      # Clear cache
      :ok = ResourceCache.clear_cache(cache)

      # Both should fetch fresh
      result1 = ResourceCache.get_resource(cache, "server1", "uri1", fn -> {:ok, "fresh1"} end)
      result2 = ResourceCache.get_resource(cache, "server2", "uri2", fn -> {:ok, "fresh2"} end)

      assert {:ok, "fresh1"} = result1
      assert {:ok, "fresh2"} = result2
    end
  end

  describe "get_stats/1" do
    test "returns cache statistics", %{cache: cache} do
      # Make some cache operations
      ResourceCache.get_resource(cache, "server", "uri1", fn -> {:ok, "content1"} end)
      # Hit
      ResourceCache.get_resource(cache, "server", "uri1", fn -> {:ok, "ignored"} end)
      # Miss
      ResourceCache.get_resource(cache, "server", "uri2", fn -> {:ok, "content2"} end)

      stats = ResourceCache.get_stats(cache)

      assert stats.total_entries == 2
      assert stats.cache_hits == 1
      assert stats.cache_misses == 2
      assert stats.hit_rate == 33.33
      assert stats.total_size > 0
      assert is_integer(stats.avg_response_time)
    end
  end

  describe "size limits" do
    test "enforces max size with LRU eviction", %{cache: _cache} do
      # Start cache with very small size limit
      {:ok, small_cache} =
        ResourceCache.start_link(
          name: :small_cache,
          cache_dir: @cache_dir,
          # 100 bytes
          max_size: 100
        )

      # Add resources that exceed the limit
      ResourceCache.get_resource(small_cache, "server", "uri1", fn ->
        {:ok, String.duplicate("a", 60)}
      end)

      ResourceCache.get_resource(small_cache, "server", "uri2", fn ->
        {:ok, String.duplicate("b", 60)}
      end)

      # First resource should be evicted
      result1 =
        ResourceCache.get_resource(small_cache, "server", "uri1", fn ->
          {:ok, "fresh1"}
        end)

      # Second should still be cached
      result2 =
        ResourceCache.get_resource(small_cache, "server", "uri2", fn ->
          {:ok, "ignored"}
        end)

      assert {:ok, "fresh1"} = result1
      assert {:ok, content} = result2
      assert String.starts_with?(content, "bbb")

      GenServer.stop(small_cache)
    end
  end

  describe "handle_resource_updated/2" do
    test "invalidates resource on update notification", %{cache: cache} do
      server = "test_server"
      uri = "test://updated"

      # Cache a resource
      ResourceCache.get_resource(cache, server, uri, fn -> {:ok, "old content"} end)

      # Simulate resource update notification
      notification = %{
        "method" => "notifications/resources/updated",
        "params" => %{"uri" => uri}
      }

      send(cache, {:notification, server, notification})
      # Allow message to be processed
      Process.sleep(50)

      # Should fetch fresh content
      result = ResourceCache.get_resource(cache, server, uri, fn -> {:ok, "new content"} end)
      assert {:ok, "new content"} = result
    end
  end

  describe "get_cached_resources/1" do
    test "returns list of cached resources", %{cache: cache} do
      # Cache some resources
      ResourceCache.get_resource(cache, "server1", "uri1", fn -> {:ok, "content1"} end)
      ResourceCache.get_resource(cache, "server2", "uri2", fn -> {:ok, "content2"} end)

      resources = ResourceCache.get_cached_resources(cache)

      assert length(resources) == 2
      assert Enum.any?(resources, fn r -> r.server == "server1" and r.uri == "uri1" end)
      assert Enum.any?(resources, fn r -> r.server == "server2" and r.uri == "uri2" end)
    end
  end
end
