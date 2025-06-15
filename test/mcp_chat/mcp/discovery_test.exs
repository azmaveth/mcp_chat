defmodule DiscoveryTest do
  use ExUnit.Case
  alias Discovery

  alias DiscoveryTest

  describe "discover_servers/1" do
    test "returns discovered servers sorted by name" do
      # This will return an empty list since we don't have any servers configured
      servers = Discovery.discover_servers(methods: [:env])

      assert is_list(servers)
      # Servers should be sorted by name
      assert servers == Enum.sort_by(servers, & &1.name)
    end
  end

  describe "quick_setup_servers/0" do
    test "returns list of quick setup server configurations" do
      servers = Discovery.quick_setup_servers()

      assert is_list(servers)
      assert length(servers) > 0

      # Check structure of server configs
      for server <- servers do
        assert Map.has_key?(server, :name)
        assert Map.has_key?(server, :status)

        case server.status do
          :available ->
            # Available servers should have command or url
            assert Map.has_key?(server, :command) or Map.has_key?(server, :url)
            assert Map.has_key?(server, :source)
            assert server.source == :quick_setup

          :missing_requirements ->
            # Servers with missing requirements should have missing field
            assert Map.has_key?(server, :missing)
            assert is_list(server.missing)
        end
      end

      # Check some known servers exist
      server_names = Enum.map(servers, & &1.name)
      assert "filesystem" in server_names
      assert "github" in server_names
    end
  end
end
