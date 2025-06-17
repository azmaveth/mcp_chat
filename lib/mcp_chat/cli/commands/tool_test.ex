defmodule MCPChat.CLI.Commands.ToolTest do
  @moduledoc """
  CLI commands for testing MCP tool integration with LLMs.

  Provides commands to test that the native filesystem server and other MCP tools
  are properly exposed to LLMs for function calling.
  """

  alias MCPChat.CLI.Renderer
  alias MCPChat.LLM.ToolBridge
  alias MCPChat.MCP.NativeToolBridge

  @doc """
  Handle tool testing commands.
  """
  def handle_command("tooltest", args) do
    case args do
      ["list"] ->
        list_available_tools()

      ["native"] ->
        test_native_tools()

      ["bridge"] ->
        test_tool_bridge()

      ["llm"] ->
        test_llm_integration()

      _ ->
        show_help()
    end

    :ok
  end

  def handle_command(unknown_command, _args) do
    {:error, "Unknown tool test command: #{unknown_command}"}
  end

  @doc """
  List available commands.
  """
  def commands do
    %{
      "tooltest" => "Test MCP tool integration with LLMs"
    }
  end

  @doc """
  Show help for tool test commands.
  """
  def show_help do
    Renderer.show_text("# MCP Tool Testing Commands\\n")
    Renderer.show_text("Commands for testing MCP tool integration:")
    Renderer.show_text("")
    Renderer.show_text("## Available Commands:")
    Renderer.show_text("/tooltest list    - List all available MCP tools")
    Renderer.show_text("/tooltest native  - Test native filesystem tools")
    Renderer.show_text("/tooltest bridge  - Test the tool bridge functionality")
    Renderer.show_text("/tooltest llm     - Test LLM tool integration")
    Renderer.show_text("")
    Renderer.show_text("## Purpose:")
    Renderer.show_text("These commands help verify that MCP tools are properly")
    Renderer.show_text("exposed to LLMs for function calling during conversations.")
  end

  # Private functions

  defp list_available_tools do
    Renderer.show_text("# Available MCP Tools for LLM Function Calling\\n")

    case ToolBridge.get_available_functions() do
      tools when is_list(tools) and length(tools) > 0 ->
        Renderer.show_success("✓ Found #{length(tools)} tools available for LLMs")
        Renderer.show_text("")

        # Group tools by source
        native_tools =
          Enum.filter(tools, fn tool ->
            get_in(tool, ["metadata", "server"]) == :native_filesystem
          end)

        mcp_tools =
          Enum.filter(tools, fn tool ->
            get_in(tool, ["metadata", "category"]) == "mcp_server"
          end)

        if length(native_tools) > 0 do
          Renderer.show_text("## Native BEAM Filesystem Tools (Ultra-Fast ~15μs):")
          Enum.each(native_tools, &display_tool_info/1)
          Renderer.show_text("")
        end

        if length(mcp_tools) > 0 do
          Renderer.show_text("## External MCP Server Tools:")
          Enum.each(mcp_tools, &display_tool_info/1)
          Renderer.show_text("")
        end

        Renderer.show_info("💡 These tools are automatically available to LLMs during conversations")

      [] ->
        Renderer.show_warning("⚠ No MCP tools are currently available")
        Renderer.show_text("Check that MCP servers are connected and the native filesystem server is running")

      _ ->
        Renderer.show_error("✗ Failed to retrieve available tools")
    end
  end

  defp test_native_tools do
    Renderer.show_text("# Testing Native BEAM Filesystem Tools\\n")

    case NativeToolBridge.get_native_tools() do
      tools when is_list(tools) and length(tools) > 0 ->
        Renderer.show_success("✓ Native filesystem server is available")
        Renderer.show_text("Found #{length(tools)} native tools")
        Renderer.show_text("")

        # Test a simple operation
        Renderer.show_text("Testing native tool execution...")
        test_args = %{"path" => System.tmp_dir!()}

        case NativeToolBridge.execute_native_tool("fs_ls", test_args) do
          {:ok, result} ->
            Renderer.show_success("✓ Native tool execution successful")
            Renderer.show_text("Sample result: #{String.slice(inspect(result), 0, 100)}...")

          {:error, reason} ->
            Renderer.show_error("✗ Native tool execution failed: #{reason}")
        end

      [] ->
        Renderer.show_warning("⚠ Native filesystem server is not available")
        Renderer.show_text("The server may be starting up or disabled")

      other ->
        Renderer.show_error("✗ Unexpected response: #{inspect(other)}")
    end
  end

  defp test_tool_bridge do
    Renderer.show_text("# Testing Tool Bridge Functionality\\n")

    # Test tool discovery
    Renderer.show_text("1. Testing tool discovery...")

    case ToolBridge.get_available_functions() do
      tools when is_list(tools) ->
        Renderer.show_success("✓ Tool bridge discovery working (#{length(tools)} tools)")

        # Test a specific tool if available
        case Enum.find(tools, fn tool ->
               String.starts_with?(get_in(tool, ["function", "name"]) || "", "fs_")
             end) do
          %{"function" => %{"name" => tool_name}} ->
            Renderer.show_text("\\n2. Testing tool execution...")
            test_args = %{"path" => System.tmp_dir!()}

            case ToolBridge.execute_function(tool_name, test_args) do
              {:ok, result} ->
                Renderer.show_success("✓ Tool bridge execution working")
                Renderer.show_text("Result: #{String.slice(result, 0, 100)}...")

              {:error, reason} ->
                Renderer.show_error("✗ Tool bridge execution failed: #{reason}")
            end

          nil ->
            Renderer.show_text("\\n2. No filesystem tools available for testing")
        end

      other ->
        Renderer.show_error("✗ Tool bridge discovery failed: #{inspect(other)}")
    end
  end

  defp test_llm_integration do
    Renderer.show_text("# Testing LLM Tool Integration\\n")

    # Test that tools are properly formatted for LLM function calling
    case ToolBridge.get_available_functions() do
      tools when is_list(tools) and length(tools) > 0 ->
        Renderer.show_success("✓ Tools available for LLM integration")

        # Validate tool format
        valid_tools = Enum.filter(tools, &valid_llm_tool?/1)
        invalid_tools = length(tools) - length(valid_tools)

        if invalid_tools == 0 do
          Renderer.show_success("✓ All tools properly formatted for LLM function calling")
        else
          Renderer.show_warning("⚠ #{invalid_tools} tools have formatting issues")
        end

        # Show sample tool definition
        if sample_tool = Enum.at(tools, 0) do
          Renderer.show_text("\\n## Sample Tool Definition for LLM:")
          Renderer.show_text("```json")
          Renderer.show_text(Jason.encode!(sample_tool, pretty: true))
          Renderer.show_text("```")
        end

        Renderer.show_text("")
        Renderer.show_info("💡 To test in conversation:")
        Renderer.show_text("   Start a chat and ask the LLM to use filesystem tools")
        Renderer.show_text("   Example: 'Please list the files in /tmp using the filesystem tools'")

      [] ->
        Renderer.show_warning("⚠ No tools available for LLM integration")

      other ->
        Renderer.show_error("✗ Failed to get tools: #{inspect(other)}")
    end
  end

  defp display_tool_info(%{"function" => %{"name" => name, "description" => description}} = tool) do
    performance = get_in(tool, ["metadata", "performance"])
    server = get_in(tool, ["metadata", "server"])

    performance_indicator =
      case performance do
        "ultra_fast" -> " ⚡"
        _ -> ""
      end

    Renderer.show_text("  • **#{name}**#{performance_indicator} - #{description}")
    if server, do: Renderer.show_text("    Server: #{server}")
  end

  defp display_tool_info(tool) do
    Renderer.show_text("  • #{inspect(tool)}")
  end

  defp valid_llm_tool?(%{"type" => "function", "function" => function}) when is_map(function) do
    Map.has_key?(function, "name") and Map.has_key?(function, "description")
  end

  defp valid_llm_tool?(_), do: false
end
