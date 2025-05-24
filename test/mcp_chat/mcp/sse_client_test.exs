defmodule MCPChat.MCP.SSEClientTest do
  use ExUnit.Case
  alias MCPChat.MCP.SSEClient

  describe "SSEClient GenServer" do
    test "starts with proper configuration" do
      opts = [
        name: "test-server",
        base_url: "http://localhost:3_000"
      ]

      {:ok, pid} = SSEClient.start_link(opts)
      assert Process.alive?(pid)

      # Clean up
      GenServer.stop(pid)
    end
  end

  describe "Client API" do
    setup do
      opts = [
        name: "test-server",
        base_url: "http://localhost:3_000"
      ]

      {:ok, pid} = SSEClient.start_link(opts)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      {:ok, pid: pid}
    end

    @tag :skip
    test "initialize/1 requires actual server connection", %{pid: pid} do
      # This would require an actual SSE server running
      # In a real test, you'd mock the HTTP requests
      {:error, _} = SSEClient.initialize(pid)
    end

    @tag :skip
    test "list_tools/1 requires initialized connection", %{pid: pid} do
      # This would require an initialized connection
      {:error, _} = SSEClient.list_tools(pid)
    end

    @tag :skip
    test "list_resources/1 requires initialized connection", %{pid: pid} do
      # This would require an initialized connection
      {:error, _} = SSEClient.list_resources(pid)
    end
  end

  describe "SSEClient structure" do
    test "has expected fields" do
      client = %SSEClient{}

      assert Map.has_key?(client, :name)
      assert Map.has_key?(client, :base_url)
      assert Map.has_key?(client, :sse_url)
      assert Map.has_key?(client, :message_url)
      assert Map.has_key?(client, :capabilities)
      assert Map.has_key?(client, :server_info)
      assert Map.has_key?(client, :sse_pid)
      assert Map.has_key?(client, :pending_requests)
      assert Map.has_key?(client, :request_id)
    end
  end
end
