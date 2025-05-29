defmodule MCPChat.AtSymbolE2ETest do
  use ExUnit.Case, async: false

  @moduledoc """
  End-to-end tests for @ symbol context inclusion feature.
  Tests file, URL, and MCP resource/tool/prompt inclusion.
  """

  alias MCPChat.Context.AtSymbolResolver
  alias MCPChat.Session
  alias MCPChat.MCP.ServerManager

  @test_timeout 30_000
  @demo_servers_path Path.expand("../../examples/demo_servers", __DIR__)

  setup_all do
    # Start the application
    Application.ensure_all_started(:mcp_chat)

    # Start demo calculator server for MCP tests
    {:ok, calc_pid} = start_calculator_server()

    on_exit(fn ->
      stop_server(calc_pid)
    end)

    {:ok, %{calc_pid: calc_pid}}
  end

  setup do
    # Clear session before each test
    Session.clear_session()

    # Reset MCP server connections
    ServerManager.stop_all_servers()

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
    @tag timeout: @test_timeout
    test "resolves MCP resource reference" do
      # Connect to calculator server
      config = %{
        "name" => "calculator",
        "command" => ["elixir", Path.join(@demo_servers_path, "demo_calculator_server.exs")]
      }

      {:ok, _} = ServerManager.start_server(config)
      # Wait for server to initialize
      Process.sleep(2000)

      message = "Show me @resource:calc://constants"

      result = AtSymbolResolver.resolve_all(message)

      # Should contain mathematical constants
      assert result.resolved_text =~ "pi"
      assert result.resolved_text =~ "3.14"
      assert result.errors == []
    end

    @tag timeout: @test_timeout
    test "executes MCP tool via @ symbol" do
      # Connect to calculator server
      config = %{
        "name" => "calculator",
        "command" => ["elixir", Path.join(@demo_servers_path, "demo_calculator_server.exs")]
      }

      {:ok, _} = ServerManager.start_server(config)
      # Wait for server to initialize
      Process.sleep(2000)

      message = "Calculate @tool:calculate:expression=2+2"

      result = AtSymbolResolver.resolve_all(message)

      # Should contain calculation result
      assert result.resolved_text =~ "4"
      assert result.errors == []
    end

    test "handles missing MCP server gracefully" do
      message = "Get @resource:nonexistent-resource"

      result = AtSymbolResolver.resolve_all(message)

      assert result.resolved_text =~ "[ERROR:"
      assert result.resolved_text =~ "No MCP server found"
      assert length(result.errors) == 1
    end
  end

  describe "Mixed @ symbol resolution" do
    @tag timeout: @test_timeout
    test "resolves multiple types in one message" do
      # Set up calculator server
      config = %{
        "name" => "calculator",
        "command" => ["elixir", Path.join(@demo_servers_path, "demo_calculator_server.exs")]
      }

      {:ok, _} = ServerManager.start_server(config)
      Process.sleep(2000)

      message = "Based on @file:test_file1.txt and @resource:calc://constants, calculate @tool:calculate:expression=3*3"

      result = AtSymbolResolver.resolve_all(message)

      # Should contain all resolved content
      # File content
      assert result.resolved_text =~ "Test content 1"
      # Resource content
      assert result.resolved_text =~ "pi"
      # Tool result
      assert result.resolved_text =~ "9"
      assert length(result.results) == 3
      assert result.errors == []
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

  defp start_calculator_server() do
    port =
      Port.open(
        {:spawn_executable, System.find_executable("elixir")},
        [:binary, :use_stdio, :stderr_to_stdout, args: [Path.join(@demo_servers_path, "demo_calculator_server.exs")]]
      )

    # Wait for server to start
    Process.sleep(1_000)

    {:ok, port}
  end

  defp stop_server(port) when is_port(port) do
    Port.close(port)
  rescue
    _ -> :ok
  end

  defp create_test_files() do
    File.write!("test_file1.txt", "Test content 1")
    File.write!("test_file2.txt", "Test content 2")
  end

  defp clean_test_files() do
    File.rm("test_file1.txt")
    File.rm("test_file2.txt")
  rescue
    _ -> :ok
  end
end
