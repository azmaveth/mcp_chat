defmodule MCPChat.MCPServer.HandlerTest do
  use ExUnit.Case, async: true
  alias MCPChat.MCPServer.Handler

  describe "init/1" do
    test "initializes handler state with transport" do
      assert {:ok, state} = Handler.init(:stdio)
      assert state.transport == :stdio
      assert state.initialized == false
    end

    test "initializes with SSE transport" do
      assert {:ok, state} = Handler.init(:sse)
      assert state.transport == :sse
      assert state.initialized == false
    end
  end

  describe "handle_request initialize" do
    test "returns server info and capabilities" do
      params = %{
        "clientInfo" => %{
          "name" => "test-client",
          "version" => "1.0.0"
        }
      }

      state = %{transport: :stdio, initialized: false}

      assert {:ok, result, :initialized} = Handler.handle_request("initialize", params, state)

      assert result.protocolVersion == "2_024-11-05"
      assert result.serverInfo.name == "mcp_chat"
      assert result.serverInfo.version == "0.1.0"
      assert result.serverInfo.vendor == "mcp_chat"
      assert result.capabilities == %{tools: %{}, resources: %{}, prompts: %{}}
    end
  end

  describe "handle_request tools/list" do
    test "returns available tools" do
      state = %{transport: :stdio, initialized: true}

      assert {:ok, result, ^state} = Handler.handle_request("tools/list", %{}, state)

      assert Map.has_key?(result, :tools)
      tools = result.tools

      # Check we have the expected tools
      tool_names = Enum.map(tools, & &1.name)
      assert "chat" in tool_names
      assert "new_session" in tool_names
      assert "get_history" in tool_names
      assert "clear_history" in tool_names

      # Check chat tool structure
      chat_tool = Enum.find(tools, &(&1.name == "chat"))
      assert chat_tool.description =~ "Send a message"
      assert chat_tool.inputSchema.type == "object"
      assert chat_tool.inputSchema.required == ["message"]
      assert Map.has_key?(chat_tool.inputSchema.properties, :message)
      assert Map.has_key?(chat_tool.inputSchema.properties, :backend)
    end
  end

  describe "handle_request tools/call - structure" do
    test "handles unknown tool" do
      state = %{transport: :stdio, initialized: true}

      params = %{
        "name" => "unknown_tool",
        "arguments" => %{}
      }

      assert {:error, error, ^state} = Handler.handle_request("tools/call", params, state)

      assert error.code == -32_603
      assert error.message =~ "Unknown tool"
    end
  end

  describe "handle_request resources/list" do
    test "returns available resources" do
      state = %{transport: :stdio, initialized: true}

      assert {:ok, result, ^state} = Handler.handle_request("resources/list", %{}, state)

      assert Map.has_key?(result, :resources)
      resources = result.resources

      # Check we have the expected resources
      resource_uris = Enum.map(resources, & &1.uri)
      assert "chat://history" in resource_uris
      assert "chat://session" in resource_uris

      # Check resource structure
      history_resource = Enum.find(resources, &(&1.uri == "chat://history"))
      assert history_resource.name == "Chat History"
      assert history_resource.mimeType == "application/json"
    end
  end

  describe "handle_request resources/read - structure" do
    test "handles invalid resource URI" do
      state = %{transport: :stdio, initialized: true}
      params = %{"uri" => "chat://invalid"}

      assert {:error, error, ^state} = Handler.handle_request("resources/read", params, state)

      assert error.code == -32_602
      assert error.message =~ "Unknown resource"
    end
  end

  describe "handle_request prompts/list" do
    test "returns available prompts" do
      state = %{transport: :stdio, initialized: true}

      assert {:ok, result, ^state} = Handler.handle_request("prompts/list", %{}, state)

      assert Map.has_key?(result, :prompts)
      prompts = result.prompts

      # Check we have the expected prompts
      prompt_names = Enum.map(prompts, & &1.name)
      assert "code_review" in prompt_names
      assert "explain" in prompt_names

      # Check prompt structure
      code_review = Enum.find(prompts, &(&1.name == "code_review"))
      assert code_review.description =~ "Review code"
      assert length(code_review.arguments) == 2

      code_arg = Enum.find(code_review.arguments, &(&1.name == "code"))
      assert code_arg.required == true
    end
  end

  describe "handle_request prompts/get" do
    test "gets code_review prompt" do
      state = %{transport: :stdio, initialized: true}

      params = %{
        "name" => "code_review",
        "arguments" => %{
          "code" => "def hello, do: :world",
          "language" => "elixir"
        }
      }

      assert {:ok, result, ^state} = Handler.handle_request("prompts/get", params, state)

      assert Map.has_key?(result, :messages)
      messages = result.messages

      assert length(messages) == 1
      assert hd(messages).role == "user"
      assert hd(messages).content.text =~ "def hello, do: :world"
      assert hd(messages).content.text =~ "elixir"
    end

    test "gets explain prompt" do
      state = %{transport: :stdio, initialized: true}

      params = %{
        "name" => "explain",
        "arguments" => %{
          "topic" => "recursion",
          "level" => "beginner"
        }
      }

      assert {:ok, result, ^state} = Handler.handle_request("prompts/get", params, state)

      assert Map.has_key?(result, :messages)
      messages = result.messages

      assert length(messages) == 1
      assert hd(messages).role == "user"
      assert hd(messages).content.text =~ "recursion"
      assert hd(messages).content.text =~ "beginner"
    end

    test "handles unknown prompt" do
      state = %{transport: :stdio, initialized: true}

      params = %{
        "name" => "unknown_prompt",
        "arguments" => %{}
      }

      assert {:error, error, ^state} = Handler.handle_request("prompts/get", params, state)

      assert error.code == -32_602
      assert error.message =~ "Unknown prompt"
    end
  end

  describe "handle_request completion/complete" do
    test "returns not implemented error" do
      state = %{transport: :stdio, initialized: true}

      assert {:error, error, ^state} = Handler.handle_request("completion/complete", %{}, state)

      assert error.code == -32_601
      assert error.message =~ "Completion not implemented"
    end
  end

  describe "handle_request unknown method" do
    test "returns method not found error" do
      state = %{transport: :stdio, initialized: true}

      assert {:error, error, ^state} = Handler.handle_request("unknown/method", %{}, state)

      assert error.code == -32_601
      assert error.message == "Method not found: unknown/method"
    end
  end

  describe "handle_notification" do
    test "handles initialized notification" do
      state = %{transport: :stdio, initialized: true}

      assert {:ok, ^state} = Handler.handle_notification("notifications/initialized", %{}, state)
    end

    test "handles other notifications" do
      state = %{transport: :stdio, initialized: true}

      assert {:ok, ^state} = Handler.handle_notification("test/notification", %{}, state)
    end
  end

  # Test helper functions indirectly through their structure
  describe "prompt content structure" do
    test "code_review prompt has correct structure" do
      state = %{transport: :stdio, initialized: true}

      params = %{
        "name" => "code_review",
        "arguments" => %{
          "code" => "test code"
        }
      }

      {:ok, result, _} = Handler.handle_request("prompts/get", params, state)
      message = hd(result.messages)

      assert message.content.type == "text"
      # default language
      assert message.content.text =~ "unknown"
      assert message.content.text =~ "test code"
    end

    test "explain prompt has correct structure" do
      state = %{transport: :stdio, initialized: true}

      params = %{
        "name" => "explain",
        "arguments" => %{
          "topic" => "test topic"
        }
      }

      {:ok, result, _} = Handler.handle_request("prompts/get", params, state)
      message = hd(result.messages)

      assert message.content.type == "text"
      # default level
      assert message.content.text =~ "intermediate"
      assert message.content.text =~ "test topic"
    end
  end
end
