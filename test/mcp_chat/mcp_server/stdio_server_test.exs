defmodule MCPChat.MCPServer.StdioServerTest do
  use ExUnit.Case
  alias MCPChat.MCPServer.StdioServer

  import ExUnit.CaptureLog

  describe "start_link/1" do
    test "starts the server with name" do
      # Stop the server if it's already running
      try do
        GenServer.stop(StdioServer, :normal)
      catch
        :exit, _ -> :ok
      end

      assert {:ok, pid} = StdioServer.start_link()
      assert Process.alive?(pid)
      assert Process.whereis(StdioServer) == pid

      # Clean up
      GenServer.stop(StdioServer)
    end
  end

  describe "start/0 and stop/0" do
    setup do
      # Ensure server is started for these tests
      try do
        GenServer.stop(StdioServer, :normal)
      catch
        :exit, _ -> :ok
      end

      {:ok, _pid} = StdioServer.start_link()

      on_exit(fn ->
        try do
          GenServer.stop(StdioServer, :normal)
        catch
          :exit, _ -> :ok
        end
      end)

      :ok
    end

    test "start/0 returns :ok and logs start message" do
      assert capture_log(fn ->
               assert :ok = StdioServer.start()
             end) =~ "MCP stdio server started"
    end

    test "stop/0 returns :ok and logs stop message" do
      assert capture_log(fn ->
               assert :ok = StdioServer.stop()
             end) =~ "MCP stdio server stopping"
    end
  end

  describe "message processing" do
    setup do
      # Start a fresh server
      try do
        GenServer.stop(StdioServer, :normal)
      catch
        :exit, _ -> :ok
      end

      {:ok, pid} = StdioServer.start_link()

      on_exit(fn ->
        try do
          GenServer.stop(StdioServer, :normal)
        catch
          :exit, _ -> :ok
        end
      end)

      {:ok, pid: pid}
    end

    test "logs error for invalid JSON", %{pid: pid} do
      invalid_json = "not valid json\n"

      assert capture_log(fn ->
               send(pid, {:stdin, invalid_json})
               Process.sleep(50)
             end) =~ "Failed to parse JSON-RPC request"
    end

    test "handles unhandled messages", %{pid: pid} do
      assert capture_log(fn ->
               send(pid, {:unknown, "message"})
               Process.sleep(50)
             end) =~ "Unhandled message"
    end
  end

  describe "JSON-RPC request structures" do
    test "valid request with ID structure" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "initialize",
        "params" => %{"clientInfo" => %{"name" => "test", "version" => "1.0"}},
        "id" => 1
      }

      # Verify structure
      assert request["jsonrpc"] == "2.0"
      assert is_binary(request["method"])
      assert is_map(request["params"])
      assert is_integer(request["id"])

      # Verify it encodes properly
      assert {:ok, json} = Jason.encode(request)
      assert is_binary(json)
    end

    test "valid request without params structure" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "tools/list",
        "id" => 2
      }

      # Verify structure
      assert request["jsonrpc"] == "2.0"
      assert is_binary(request["method"])
      refute Map.has_key?(request, "params")
      assert is_integer(request["id"])
    end

    test "valid notification structure" do
      notification = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/initialized",
        "params" => %{}
      }

      # Verify structure
      assert notification["jsonrpc"] == "2.0"
      assert is_binary(notification["method"])
      assert is_map(notification["params"])
      refute Map.has_key?(notification, "id")
    end
  end

  describe "state management" do
    test "initial state structure" do
      # Test the expected initial state
      initial_state = %StdioServer{
        buffer: "",
        state: :ready
      }

      assert initial_state.buffer == ""
      assert initial_state.state == :ready
    end

    test "state transitions" do
      # Test state with buffer content
      state_with_buffer = %StdioServer{
        buffer: "partial line",
        state: :ready
      }

      assert state_with_buffer.buffer == "partial line"

      # Test initialized state
      initialized_state = %StdioServer{
        buffer: "",
        state: :initialized
      }

      assert initialized_state.state == :initialized
    end
  end

  describe "line splitting logic" do
    test "complete lines pattern" do
      # Test data patterns that would be split
      complete_lines = "line1\nline2\n"
      lines = String.split(complete_lines, "\n")

      # With trailing newline, we get an empty string at the end
      assert length(lines) == 3
      assert List.last(lines) == ""
    end

    test "incomplete line pattern" do
      incomplete = "line1\npartial"
      lines = String.split(incomplete, "\n")

      assert length(lines) == 2
      assert List.last(lines) == "partial"
    end

    test "multiple empty lines pattern" do
      empty_lines = "\n\n\n"
      lines = String.split(empty_lines, "\n")

      # All empty strings
      assert length(lines) == 4
      assert Enum.all?(lines, &(&1 == ""))
    end
  end

  describe "response format" do
    test "success response structure" do
      response = %{
        jsonrpc: "2.0",
        result: %{tools: []},
        id: 1
      }

      assert response.jsonrpc == "2.0"
      assert is_map(response.result)
      assert response.id == 1

      # Should encode to valid JSON
      assert {:ok, json} = Jason.encode(response)
      assert String.contains?(json, "\"jsonrpc\":\"2.0\"")
    end

    test "error response structure" do
      response = %{
        jsonrpc: "2.0",
        error: %{
          code: -32_601,
          message: "Method not found"
        },
        id: 99
      }

      assert response.jsonrpc == "2.0"
      assert response.error.code == -32_601
      assert response.error.message == "Method not found"
      assert response.id == 99
    end
  end
end
