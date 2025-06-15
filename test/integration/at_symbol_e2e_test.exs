defmodule MCPChat.AtSymbolE2ETest do
  use ExUnit.Case, async: false

  @moduledoc """
  End-to-end tests for @ symbol context inclusion feature.
  Tests file, URL, and MCP resource/tool/prompt inclusion.
  """

  alias AtSymbolResolver
  alias MCPChat.Session
  alias ServerManager

  @test_timeout 30_000
  @demo_servers_path Path.expand("../support", __DIR__)

  setup_all do
    # Start the application
    Application.ensure_all_started(:mcp_chat)

    :ok
  end

  setup do
    # Clear session before each test
    Session.clear_session()

    # Reset MCP server connections by stopping any running servers
    case ServerManager.list_servers() do
      servers when is_list(servers) ->
        Enum.each(servers, fn server ->
          case server do
            %{name: name} -> ServerManager.stop_server(name)
            _ -> :ok
          end
        end)

      _ ->
        :ok
    end

    # Create test files
    create_test_files()

    on_exit(fn ->
      clean_test_files()
    end)

    :ok
  end

  describe "File @ symbol resolution" do
    test "resolves single file reference" do
      message = "Please analyze @file:test_file1.txt"

      result = AtSymbolResolver.resolve_all(message)

      assert result.resolved_text == "Please analyze Test content 1"
      assert length(result.results) == 1
      assert result.errors == []
      assert result.total_tokens > 0
    end

    test "resolves multiple file references" do
      message = "Compare @file:test_file1.txt with @file:test_file2.txt"

      result = AtSymbolResolver.resolve_all(message)

      assert result.resolved_text == "Compare Test content 1 with Test content 2"
      assert length(result.results) == 2
      assert result.errors == []
    end

    test "handles missing file gracefully" do
      message = "Read @file:nonexistent.txt please"

      result = AtSymbolResolver.resolve_all(message)

      assert result.resolved_text =~ "[ERROR:"
      assert result.resolved_text =~ "File not found"
      assert length(result.errors) == 1
    end

    test "uses short form @f:" do
      message = "Check @f:test_file1.txt"

      result = AtSymbolResolver.resolve_all(message)

      assert result.resolved_text == "Check Test content 1"
    end
  end

  describe "URL @ symbol resolution" do
    @tag :external_network
    test "resolves URL reference" do
      # Using httpbin for reliable test endpoint
      message = "Fetch @url:https://httpbin.org/json"

      result = AtSymbolResolver.resolve_all(message)

      # Should contain JSON response
      assert result.resolved_text =~ "slideshow"
      assert length(result.results) == 1
      assert result.errors == []
    end

    test "handles invalid URL gracefully" do
      message = "Get @url:not-a-valid-url"

      result = AtSymbolResolver.resolve_all(message)

      assert result.resolved_text =~ "[ERROR:"
      assert length(result.errors) == 1
    end
  end

  describe "MCP @ symbol resolution" do
    test "handles missing MCP server gracefully" do
      message = "Get @resource:nonexistent-resource"

      result = AtSymbolResolver.resolve_all(message)

      assert result.resolved_text =~ "[ERROR:"
      assert result.resolved_text =~ "No MCP servers available"
      assert length(result.errors) == 1
    end

    test "handles missing MCP tool gracefully" do
      message = "Execute @tool:nonexistent-tool"

      result = AtSymbolResolver.resolve_all(message)

      assert result.resolved_text =~ "[ERROR:"
      assert result.resolved_text =~ "Tool not found"
      assert length(result.errors) == 1
    end

    test "handles missing MCP prompt gracefully" do
      message = "Use @prompt:nonexistent-prompt"

      result = AtSymbolResolver.resolve_all(message)

      assert result.resolved_text =~ "[ERROR:"
      assert result.resolved_text =~ "No MCP servers available"
      assert length(result.errors) == 1
    end
  end

  describe "Mixed @ symbol resolution" do
    test "resolves multiple file types in one message" do
      message = "Based on @file:test_file1.txt and @file:test_file2.txt"

      result = AtSymbolResolver.resolve_all(message)

      # Should contain both file contents
      assert result.resolved_text == "Based on Test content 1 and Test content 2"
      assert length(result.results) == 2
      assert result.errors == []
    end

    test "handles mixed success and failure" do
      message = "Read @file:test_file1.txt and @file:nonexistent.txt"

      result = AtSymbolResolver.resolve_all(message)

      # Should contain successful file and error for missing file
      assert result.resolved_text =~ "Test content 1"
      assert result.resolved_text =~ "[ERROR:"
      assert result.resolved_text =~ "File not found"
      assert length(result.results) == 2
      assert length(result.errors) == 1
    end
  end

  describe "Integration with chat session" do
    test "@ symbols are resolved before sending to LLM" do
      # Add message with @ symbol
      Session.add_message("user", "Analyze @file:test_file1.txt")

      # Get messages - @ symbols should be resolved
      messages = Session.get_messages()
      user_message = List.last(messages)

      # The session should store the original message
      assert user_message.content == "Analyze @file:test_file1.txt"

      # When preparing for LLM, it should be resolved
      # This would happen in the chat flow, but we can test the resolver directly
      result = AtSymbolResolver.resolve_all(user_message.content)
      assert result.resolved_text == "Analyze Test content 1"
    end
  end

  # Helper functions

  defp create_test_files do
    File.write!("test_file1.txt", "Test content 1")
    File.write!("test_file2.txt", "Test content 2")
  end

  defp clean_test_files do
    File.rm("test_file1.txt")
    File.rm("test_file2.txt")
  rescue
    _ -> :ok
  end
end
