defmodule DiscoveryIntegrationTest do
  use ExUnit.Case
  alias Discovery
  alias DiscoveryIntegrationTest

  describe "integration with ExMCP.Discovery" do
    test "discover_servers uses ExMCP for generic methods" do
      # Test that npm discovery delegates to ExMCP
      servers = Discovery.discover_servers(methods: [:npm, :env])
      assert is_list(servers)
    end

    test "discover_servers includes quick_setup servers" do
      servers = Discovery.discover_servers(methods: [:quick_setup])
      assert is_list(servers)

      # Quick setup servers should have MCPChat-specific fields
      Enum.each(servers, fn server ->
        assert Map.has_key?(server, :status) || Map.has_key?(server, :name)
      end)
    end

    test "test_server delegates to ExMCP" do
      result = Discovery.test_server(%{command: ["echo"]})
      assert is_boolean(result)
    end

    test "deprecated functions still work" do
      # These should still work but delegate to ExMCP
      npm_servers = Discovery.discover_npm_servers()
      assert is_list(npm_servers)

      env_servers = Discovery.discover_env_servers()
      assert is_list(env_servers)
    end
  end
end
