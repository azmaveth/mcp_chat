defmodule MCPChat.BasicIntegrationTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  @moduledoc """
  Basic integration tests for MCP Chat application.
  Tests core functionality with minimal setup.
  """

  describe "MCP Protocol integration" do
    test "protocol encoding and response parsing work together" do
      # Test request encoding
      request =
        MCPChat.MCP.Protocol.encode_initialize(%{
          name: "test-client",
          version: "1.0.0"
        })

      assert request.method == "initialize"
      assert request.params.clientInfo.name == "test-client"
      assert is_integer(request.id)

      # Test response parsing - updated to match actual format
      response = %{
        "jsonrpc" => "2.0",
        "id" => request.id,
        "result" => %{
          "protocolVersion" => "2_024-11-05",
          "serverInfo" => %{"name" => "test-server", "version" => "1.0.0"}
        }
      }

      {tag, parsed, _id} = MCPChat.MCP.Protocol.parse_response(response)
      assert tag == :result
      assert parsed["protocolVersion"] == "2_024-11-05"
    end

    test "protocol handles different message types" do
      # Test tool list encoding
      tool_request = MCPChat.MCP.Protocol.encode_list_tools()
      assert tool_request.method == "tools/list"

      # Test resource list encoding
      resource_request = MCPChat.MCP.Protocol.encode_list_resources()
      assert resource_request.method == "resources/list"

      # Test prompt list encoding
      prompt_request = MCPChat.MCP.Protocol.encode_list_prompts()
      assert prompt_request.method == "prompts/list"
    end
  end

  describe "MCP Server Handler integration" do
    test "handler initialization flow" do
      initial_state = %{transport: :stdio, initialized: false}

      # Initialize
      {:ok, result, new_state} =
        MCPChat.MCPServer.Handler.handle_request(
          "initialize",
          %{"clientInfo" => %{"name" => "test-client", "version" => "1.0.0"}},
          initial_state
        )

      assert result.protocolVersion == "2_024-11-05"
      assert result.serverInfo.name == "mcp_chat"
      assert new_state == :initialized
    end

    test "handler handles tool listing" do
      state = :initialized

      {:ok, result, ^state} =
        MCPChat.MCPServer.Handler.handle_request(
          "tools/list",
          %{},
          state
        )

      assert is_list(result.tools)
      assert length(result.tools) > 0

      # Check specific tools exist
      tool_names = Enum.map(result.tools, & &1.name)
      assert "chat" in tool_names
      assert "new_session" in tool_names
      assert "get_history" in tool_names
      assert "clear_history" in tool_names
    end

    test "handler handles resource listing" do
      state = :initialized

      {:ok, result, ^state} =
        MCPChat.MCPServer.Handler.handle_request(
          "resources/list",
          %{},
          state
        )

      assert is_list(result.resources)

      # Check specific resources exist
      resource_names = Enum.map(result.resources, & &1.name)
      assert "Chat History" in resource_names
      assert "Session Info" in resource_names
    end

    test "handler handles prompt listing" do
      state = :initialized

      {:ok, result, ^state} =
        MCPChat.MCPServer.Handler.handle_request(
          "prompts/list",
          %{},
          state
        )

      assert is_list(result.prompts)

      # Check specific prompts exist
      prompt_names = Enum.map(result.prompts, & &1.name)
      assert "code_review" in prompt_names
      assert "explain" in prompt_names
    end

    test "handler error handling" do
      state = :initialized

      # Unknown method
      {:error, error, ^state} =
        MCPChat.MCPServer.Handler.handle_request(
          "unknown/method",
          %{},
          state
        )

      assert error.code == -32_601
      assert error.message =~ "Method not found"

      # Invalid resource
      {:error, error, ^state} =
        MCPChat.MCPServer.Handler.handle_request(
          "resources/read",
          %{"uri" => "invalid://uri"},
          state
        )

      assert error.code == -32_602
      assert error.message =~ "Unknown resource"
    end
  end

  describe "Persistence integration" do
    test "session save and load cycle" do
      # Create a test session with proper structure
      test_session = %{
        id: "test_#{System.unique_integer([:positive])}",
        messages: [
          %{role: :user, content: "Test message", timestamp: DateTime.utc_now()},
          %{role: :assistant, content: "Test response", timestamp: DateTime.utc_now()}
        ],
        context_strategy: :truncate_old,
        context: %{"system_message" => "Test system"},
        system_message: "Test system",
        token_usage: %{
          total_input: 10,
          total_output: 20
        },
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        llm_backend: "test"
      }

      # Save session with a name
      result = MCPChat.Persistence.save_session(test_session, "integration_test")
      assert {:ok, path} = result
      assert File.exists?(path)

      # Load session by name
      {:ok, loaded_session} = MCPChat.Persistence.load_session("integration_test")
      assert length(loaded_session.messages) == 2
      # The system message is stored in the context
      assert Map.get(loaded_session.context, "system_message") == "Test system"
      assert loaded_session.token_usage["total_input"] == 10

      # Clean up
      File.rm(path)
    end

    test "export functionality" do
      test_session = %{
        id: "test_export_#{System.unique_integer([:positive])}",
        messages: [
          %{role: "user", content: "What is Elixir?", timestamp: DateTime.utc_now()},
          %{role: "assistant", content: "Elixir is great!", timestamp: DateTime.utc_now()}
        ],
        system_message: "Be helpful",
        context: %{},
        token_usage: %{total_input: 5, total_output: 10},
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        llm_backend: "test"
      }

      # Export as JSON
      json_path = Path.join(System.tmp_dir!(), "test_export.json")
      {:ok, _} = MCPChat.Persistence.export_session(test_session, :json, json_path)
      assert File.exists?(json_path)

      # Verify JSON content
      {:ok, content} = File.read(json_path)
      {:ok, data} = Jason.decode(content)
      assert length(data["messages"]) == 2

      # Export as Markdown
      md_path = Path.join(System.tmp_dir!(), "test_export.md")
      {:ok, _} = MCPChat.Persistence.export_session(test_session, :markdown, md_path)
      assert File.exists?(md_path)

      # Verify Markdown content
      md_content = File.read!(md_path)
      assert md_content =~ "# Chat Session Export"
      assert md_content =~ "What is Elixir?"
      assert md_content =~ "Elixir is great!"

      # Clean up
      File.rm(json_path)
      File.rm(md_path)
    end
  end

  describe "Context estimation" do
    test "token estimation for messages" do
      messages = [
        %{role: "system", content: "You are a helpful assistant"},
        %{role: "user", content: "Hello, how are you?"},
        %{role: "assistant", content: "I'm doing well, thank you!"}
      ]

      tokens = MCPChat.Context.estimate_tokens(messages)
      assert tokens > 0
      # These short messages should be under 100 tokens
      assert tokens < 100
    end
  end

  describe "Cost calculation" do
    test "cost calculation for session" do
      # Create a test session with Anthropic backend
      session = %{
        llm_backend: "anthropic",
        model: "claude-3-sonnet-20240229",
        messages: [],
        context: %{model: "claude-3-sonnet-20240229"}
      }

      token_usage = %{
        input_tokens: 100,
        output_tokens: 200
      }

      cost_info = MCPChat.Cost.calculate_session_cost(session, token_usage)
      assert cost_info.input_cost > 0
      assert cost_info.output_cost > 0
      assert cost_info.total_cost == cost_info.input_cost + cost_info.output_cost
      assert cost_info.backend == "anthropic"
    end
  end
end
