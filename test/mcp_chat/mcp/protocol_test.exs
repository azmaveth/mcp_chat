defmodule MCPChat.MCP.ProtocolTest do
  use ExUnit.Case, async: true
  alias MCPChat.MCP.Protocol

  describe "encode_initialize/1" do
    test "creates valid initialize message" do
      client_info = %{name: "test-client", version: "1.0.0"}
      message = Protocol.encode_initialize(client_info)

      assert message.jsonrpc == "2.0"
      assert message.method == "initialize"
      assert message.params.protocolVersion == "2_024-11-05"
      assert message.params.clientInfo == client_info
      assert message.params.capabilities == %{roots: %{}, sampling: %{}}
      assert is_integer(message.id)
      assert message.id > 0
    end

    test "generates unique IDs for each message" do
      client_info = %{name: "test-client", version: "1.0.0"}
      msg1 = Protocol.encode_initialize(client_info)
      msg2 = Protocol.encode_initialize(client_info)

      assert msg1.id != msg2.id
      # monotonic
      assert msg1.id < msg2.id
    end
  end

  describe "encode_initialized/0" do
    test "creates valid initialized notification" do
      message = Protocol.encode_initialized()

      assert message.jsonrpc == "2.0"
      assert message.method == "notifications/initialized"
      assert message.params == %{}
      # notifications don't have IDs
      refute Map.has_key?(message, :id)
    end
  end

  describe "encode_list_tools/0" do
    test "creates valid list tools request" do
      message = Protocol.encode_list_tools()

      assert message.jsonrpc == "2.0"
      assert message.method == "tools/list"
      assert message.params == %{}
      assert is_integer(message.id)
    end
  end

  describe "encode_call_tool/2" do
    test "creates valid tool call request with arguments" do
      name = "test_tool"
      arguments = %{input: "test input", count: 42}
      message = Protocol.encode_call_tool(name, arguments)

      assert message.jsonrpc == "2.0"
      assert message.method == "tools/call"
      assert message.params.name == name
      assert message.params.arguments == arguments
      assert is_integer(message.id)
    end

    test "creates valid tool call request with empty arguments" do
      message = Protocol.encode_call_tool("test_tool", %{})

      assert message.params.arguments == %{}
    end
  end

  describe "encode_list_resources/0" do
    test "creates valid list resources request" do
      message = Protocol.encode_list_resources()

      assert message.jsonrpc == "2.0"
      assert message.method == "resources/list"
      assert message.params == %{}
      assert is_integer(message.id)
    end
  end

  describe "encode_read_resource/1" do
    test "creates valid read resource request" do
      uri = "file:///path/to/resource.txt"
      message = Protocol.encode_read_resource(uri)

      assert message.jsonrpc == "2.0"
      assert message.method == "resources/read"
      assert message.params.uri == uri
      assert is_integer(message.id)
    end
  end

  describe "encode_list_prompts/0" do
    test "creates valid list prompts request" do
      message = Protocol.encode_list_prompts()

      assert message.jsonrpc == "2.0"
      assert message.method == "prompts/list"
      assert message.params == %{}
      assert is_integer(message.id)
    end
  end

  describe "encode_get_prompt/2" do
    test "creates valid get prompt request with arguments" do
      name = "test_prompt"
      arguments = %{context: "test context"}
      message = Protocol.encode_get_prompt(name, arguments)

      assert message.jsonrpc == "2.0"
      assert message.method == "prompts/get"
      assert message.params.name == name
      assert message.params.arguments == arguments
      assert is_integer(message.id)
    end

    test "creates valid get prompt request without arguments" do
      name = "test_prompt"
      message = Protocol.encode_get_prompt(name)

      assert message.params.name == name
      assert message.params.arguments == %{}
    end
  end

  describe "encode_complete/2" do
    test "creates valid completion request" do
      ref = "resource-ref-123"
      params = %{argument: %{name: "content", value: "test completion"}}
      message = Protocol.encode_complete(ref, params)

      assert message.jsonrpc == "2.0"
      assert message.method == "completion/complete"
      assert message.params.ref == ref
      assert message.params.argument == params.argument
      assert is_integer(message.id)
    end

    test "merges ref with other params" do
      ref = "test-ref"
      params = %{foo: "bar", baz: 42}
      message = Protocol.encode_complete(ref, params)

      assert message.params == %{ref: ref, foo: "bar", baz: 42}
    end
  end

  describe "parse_response/1" do
    test "parses notification from binary JSON" do
      json = ~s({"jsonrpc":"2.0","method":"test/notification","params":{"data":"test"}})

      assert {:notification, "test/notification", %{"data" => "test"}} =
               Protocol.parse_response(json)
    end

    test "parses notification from map" do
      message = %{
        "jsonrpc" => "2.0",
        "method" => "test/notification",
        "params" => %{"data" => "test"}
      }

      assert {:notification, "test/notification", %{"data" => "test"}} =
               Protocol.parse_response(message)
    end

    test "parses successful result from binary JSON" do
      json = ~s({"jsonrpc":"2.0","result":{"success":true},"id":123})

      assert {:result, %{"success" => true}, 123} = Protocol.parse_response(json)
    end

    test "parses successful result from map" do
      message = %{
        "jsonrpc" => "2.0",
        "result" => %{"success" => true},
        "id" => 123
      }

      assert {:result, %{"success" => true}, 123} = Protocol.parse_response(message)
    end

    test "parses error response from binary JSON" do
      json = ~s({"jsonrpc":"2.0","error":{"code":-32_600,"message":"Invalid Request"},"id":456})

      assert {:error, %{"code" => -32_600, "message" => "Invalid Request"}, 456} =
               Protocol.parse_response(json)
    end

    test "parses error response from map" do
      message = %{
        "jsonrpc" => "2.0",
        "error" => %{"code" => -32_600, "message" => "Invalid Request"},
        "id" => 456
      }

      assert {:error, %{"code" => -32_600, "message" => "Invalid Request"}, 456} =
               Protocol.parse_response(message)
    end

    test "returns error for invalid JSON" do
      assert {:error, %Jason.DecodeError{}} = Protocol.parse_response("invalid json")
    end

    test "returns error for invalid response format" do
      assert {:error, :invalid_response} = Protocol.parse_response(%{})
      assert {:error, :invalid_response} = Protocol.parse_response(%{"jsonrpc" => "1.0"})
      assert {:error, :invalid_response} = Protocol.parse_response(%{"something" => "else"})
    end
  end

  describe "encode_message/1" do
    test "encodes message to JSON string" do
      message = %{jsonrpc: "2.0", method: "test", params: %{}}
      encoded = Protocol.encode_message(message)

      assert is_binary(encoded)
      assert {:ok, decoded} = Jason.decode(encoded)
      assert decoded["jsonrpc"] == "2.0"
      assert decoded["method"] == "test"
    end

    test "handles complex nested structures" do
      message = %{
        jsonrpc: "2.0",
        method: "complex",
        params: %{
          nested: %{
            array: [1, 2, 3],
            string: "test",
            null: nil,
            bool: true
          }
        }
      }

      encoded = Protocol.encode_message(message)
      {:ok, decoded} = Jason.decode(encoded)

      assert decoded["params"]["nested"]["array"] == [1, 2, 3]
      assert decoded["params"]["nested"]["string"] == "test"
      assert decoded["params"]["nested"]["null"] == nil
      assert decoded["params"]["nested"]["bool"] == true
    end
  end

  describe "protocol version" do
    test "uses correct protocol version in all requests" do
      # Check that initialize uses the correct version
      client_info = %{name: "test", version: "1.0"}
      message = Protocol.encode_initialize(client_info)
      assert message.params.protocolVersion == "2_024-11-05"
    end
  end

  describe "message ID generation" do
    test "generates monotonically increasing IDs" do
      # Generate several messages and check IDs are increasing
      messages =
        for _ <- 1..10 do
          Protocol.encode_list_tools()
        end

      ids = Enum.map(messages, & &1.id)
      sorted_ids = Enum.sort(ids)

      assert ids == sorted_ids
      # all unique
      assert length(Enum.uniq(ids)) == length(ids)
    end
  end
end
