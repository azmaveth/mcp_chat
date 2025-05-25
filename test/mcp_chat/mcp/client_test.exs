defmodule MCPChat.MCP.ClientTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Tests for MCP client functionality.

  Note: The original MCPChat.MCP.Client has been replaced by ExMCP.Client
  through the MCPChat.MCP.ExMCPAdapter. These tests have been updated
  to reflect the new architecture.
  """

  # Since we're now using ExMCP through an adapter, most of the original
  # client tests are no longer applicable. The adapter tests are in
  # integration/mcp_client_integration_test.exs

  describe "MCP client adapter existence" do
    test "ExMCPAdapter module is available" do
      assert Code.ensure_loaded?(MCPChat.MCP.ExMCPAdapter)
    end

    test "adapter implements required callbacks" do
      # Check that the adapter provides the expected interface
      callbacks = MCPChat.MCP.ExMCPAdapter.__info__(:functions)

      assert {:start_link, 1} in callbacks
      assert {:get_status, 1} in callbacks
      assert {:get_tools, 1} in callbacks
      assert {:get_resources, 1} in callbacks
      assert {:get_prompts, 1} in callbacks
    end
  end
end
