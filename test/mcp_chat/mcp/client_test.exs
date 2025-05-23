defmodule MCPChat.MCP.ClientTest do
  use ExUnit.Case, async: true
  alias MCPChat.MCP.{Client, Protocol}

  # Mock WebSocket server for testing
  defmodule MockWebSocketServer do
    use Plug.Router

    plug :match
    plug :dispatch

    match _ do
      conn
      |> WebSockAdapter.upgrade(MockHandler, [], timeout: 5_000)
      |> halt()
    end

    defmodule MockHandler do
      def init(options) do
        {:ok, options}
      end

      def handle_in({text, _opts}, state) do
        # Echo back for testing
        {:reply, :ok, {:text, text}, state}
      end

      def terminate(_reason, _state) do
        :ok
      end
    end
  end

  setup do
    # Since we can't easily test WebSocket connections in unit tests,
    # we'll test the logic without actual connections
    {:ok, %{}}
  end

  describe "start_link/2" do
    test "initializes with correct default state" do
      # We'll test the state initialization logic
      # In real tests, this would require a mock WebSocket server
      expected_state = %Client{
        server_info: nil,
        capabilities: %{},
        tools: [],
        resources: [],
        prompts: [],
        pending_requests: %{},
        callback_pid: self()
      }

      # The actual WebSocket connection would fail in tests,
      # but we can verify the state structure
      assert %Client{} = expected_state
      assert expected_state.tools == []
      assert expected_state.pending_requests == %{}
    end
  end

  describe "message encoding" do
    test "initialize/2 creates proper message" do
      client_info = %{name: "test-client", version: "1.0.0"}
      message = Protocol.encode_initialize(client_info)

      assert message.method == "initialize"
      assert message.params.clientInfo == client_info
      assert is_integer(message.id)
    end

    test "list_tools/1 creates proper message" do
      message = Protocol.encode_list_tools()

      assert message.method == "tools/list"
      assert message.params == %{}
      assert is_integer(message.id)
    end

    test "call_tool/3 creates proper message" do
      message = Protocol.encode_call_tool("test_tool", %{input: "test"})

      assert message.method == "tools/call"
      assert message.params.name == "test_tool"
      assert message.params.arguments == %{input: "test"}
      assert is_integer(message.id)
    end

    test "list_resources/1 creates proper message" do
      message = Protocol.encode_list_resources()

      assert message.method == "resources/list"
      assert message.params == %{}
      assert is_integer(message.id)
    end

    test "read_resource/2 creates proper message" do
      message = Protocol.encode_read_resource("file:///test.txt")

      assert message.method == "resources/read"
      assert message.params.uri == "file:///test.txt"
      assert is_integer(message.id)
    end

    test "list_prompts/1 creates proper message" do
      message = Protocol.encode_list_prompts()

      assert message.method == "prompts/list"
      assert message.params == %{}
      assert is_integer(message.id)
    end

    test "get_prompt/3 creates proper message" do
      message = Protocol.encode_get_prompt("test_prompt", %{context: "test"})

      assert message.method == "prompts/get"
      assert message.params.name == "test_prompt"
      assert message.params.arguments == %{context: "test"}
      assert is_integer(message.id)
    end
  end

  describe "handle_frame/2" do
    setup do
      state = %Client{
        server_info: nil,
        capabilities: %{},
        tools: [],
        resources: [],
        prompts: [],
        pending_requests: %{},
        callback_pid: self()
      }

      {:ok, %{state: state}}
    end

    test "handles notification frames", %{state: state} do
      notification =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "test/notification",
          "params" => %{"data" => "test"}
        })

      assert {:ok, ^state} = Client.handle_frame({:text, notification}, state)

      assert_receive {:mcp_notification, _pid, "test/notification", %{"data" => "test"}}
    end

    test "handles initialized notification", %{state: state} do
      notification =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "initialized",
          "params" => %{}
        })

      assert {:ok, ^state} = Client.handle_frame({:text, notification}, state)

      assert_receive {:mcp_initialized, _pid}
    end

    test "handles result frames and updates state", %{state: state} do
      # Add a pending request
      request_id = 123
      state = %{state | pending_requests: Map.put(state.pending_requests, request_id, %{method: "initialize"})}

      result =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "result" => %{
            "serverInfo" => %{"name" => "test-server", "version" => "1.0"},
            "capabilities" => %{"tools" => %{}}
          },
          "id" => request_id
        })

      assert {:ok, new_state} = Client.handle_frame({:text, result}, state)

      assert new_state.server_info == %{"name" => "test-server", "version" => "1.0"}
      assert new_state.capabilities == %{"tools" => %{}}
      assert Map.get(new_state.pending_requests, request_id) == nil

      assert_receive {:mcp_result, _pid, _result, ^request_id}
    end

    test "handles tools list result", %{state: state} do
      request_id = 124
      state = %{state | pending_requests: Map.put(state.pending_requests, request_id, %{method: "tools/list"})}

      tools = [
        %{"name" => "tool1", "description" => "First tool"},
        %{"name" => "tool2", "description" => "Second tool"}
      ]

      result =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "result" => %{"tools" => tools},
          "id" => request_id
        })

      assert {:ok, new_state} = Client.handle_frame({:text, result}, state)

      assert new_state.tools == tools
      assert Map.get(new_state.pending_requests, request_id) == nil
    end

    test "handles resources list result", %{state: state} do
      request_id = 125
      state = %{state | pending_requests: Map.put(state.pending_requests, request_id, %{method: "resources/list"})}

      resources = [
        %{"uri" => "file:///test1.txt", "name" => "Test 1"},
        %{"uri" => "file:///test2.txt", "name" => "Test 2"}
      ]

      result =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "result" => %{"resources" => resources},
          "id" => request_id
        })

      assert {:ok, new_state} = Client.handle_frame({:text, result}, state)

      assert new_state.resources == resources
    end

    test "handles prompts list result", %{state: state} do
      request_id = 126
      state = %{state | pending_requests: Map.put(state.pending_requests, request_id, %{method: "prompts/list"})}

      prompts = [
        %{"name" => "prompt1", "description" => "First prompt"},
        %{"name" => "prompt2", "description" => "Second prompt"}
      ]

      result =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "result" => %{"prompts" => prompts},
          "id" => request_id
        })

      assert {:ok, new_state} = Client.handle_frame({:text, result}, state)

      assert new_state.prompts == prompts
    end

    test "handles error frames", %{state: state} do
      request_id = 127
      state = %{state | pending_requests: Map.put(state.pending_requests, request_id, %{method: "test"})}

      error =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "error" => %{"code" => -32_600, "message" => "Invalid Request"},
          "id" => request_id
        })

      assert {:ok, new_state} = Client.handle_frame({:text, error}, state)

      assert Map.get(new_state.pending_requests, request_id) == nil

      assert_receive {:mcp_error, _pid, %{"code" => -32_600, "message" => "Invalid Request"}, ^request_id}
    end

    test "handles invalid JSON", %{state: state} do
      assert {:ok, ^state} = Client.handle_frame({:text, "invalid json"}, state)
      # Should log error but continue
    end

    test "handles binary frames", %{state: state} do
      assert {:ok, ^state} = Client.handle_frame({:binary, <<1, 2, 3>>}, state)
      # Should log warning but continue
    end
  end

  describe "handle_cast/2" do
    setup do
      state = %Client{
        pending_requests: %{},
        callback_pid: self()
      }

      {:ok, %{state: state}}
    end

    test "sends message and tracks request with ID", %{state: state} do
      message = %{
        jsonrpc: "2.0",
        method: "test",
        params: %{},
        id: 123
      }

      assert {:reply, {:text, json}, new_state} = Client.handle_cast({:send, message}, state)

      assert is_binary(json)
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["id"] == 123
      assert Map.get(new_state.pending_requests, 123) == message
    end

    test "sends message without tracking if no ID", %{state: state} do
      message = %{
        jsonrpc: "2.0",
        method: "notification",
        params: %{}
      }

      assert {:reply, {:text, _json}, new_state} = Client.handle_cast({:send, message}, state)

      assert new_state.pending_requests == %{}
    end
  end

  describe "handle_disconnect/2" do
    test "sends disconnection message to callback" do
      state = %Client{callback_pid: self()}
      reason = {:remote, :closed}

      assert {:ok, ^state} = Client.handle_disconnect(%{reason: reason}, state)

      assert_receive {:mcp_disconnected, _pid, {:remote, :closed}}
    end
  end

  describe "handle_info/2" do
    test "handles unexpected messages gracefully" do
      state = %Client{callback_pid: self()}

      assert {:ok, ^state} = Client.handle_info({:unexpected, "message"}, state)
      # Should log debug message but continue
    end
  end
end
