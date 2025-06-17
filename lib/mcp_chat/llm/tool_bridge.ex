defmodule MCPChat.LLM.ToolBridge do
  @moduledoc """
  Bridge module that aggregates and exposes all available MCP tools to LLMs for function calling.

  This module combines:
  - Native BEAM filesystem tools (ultra-fast ~15μs)
  - External MCP server tools (traditional servers)
  - Built-in system tools

  And presents them in a unified interface for LLM function calling.
  """

  require Logger

  alias MCPChat.MCP.{ServerManager, NativeToolBridge}

  @doc """
  Get all available tools formatted for LLM function calling.

  Returns a list of tool definitions in OpenAI function calling format.
  """
  def get_available_functions do
    # Combine all tool sources
    native_tools = get_native_tools()
    mcp_tools = get_mcp_server_tools()

    all_tools = native_tools ++ mcp_tools

    Logger.debug("Discovered #{length(all_tools)} tools for LLM function calling")

    all_tools
  end

  @doc """
  Execute a function call from an LLM.

  Returns {:ok, result} or {:error, reason}.
  """
  def execute_function(function_name, arguments) do
    Logger.debug("Executing LLM function call: #{function_name} with args: #{inspect(arguments)}")

    case parse_function_name(function_name) do
      {:native, tool_name} ->
        execute_native_tool(tool_name, arguments)

      {:mcp_server, server_name, tool_name} ->
        execute_mcp_tool(server_name, tool_name, arguments)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a specific tool is available.
  """
  def tool_available?(function_name) do
    get_available_functions()
    |> Enum.any?(fn tool -> tool["name"] == function_name end)
  end

  @doc """
  Get tool definition by name.
  """
  def get_tool_definition(function_name) do
    get_available_functions()
    |> Enum.find(fn tool -> tool["name"] == function_name end)
  end

  # Private functions

  defp get_native_tools do
    NativeToolBridge.get_native_tools()
    |> Enum.map(&transform_to_function_definition/1)
  end

  defp get_mcp_server_tools do
    case ServerManager.list_all_tools() do
      {:ok, tools} ->
        tools
        |> Enum.map(&transform_mcp_tool_to_function/1)

      {:error, reason} ->
        Logger.warning("Failed to get MCP server tools: #{inspect(reason)}")
        []

      tools when is_list(tools) ->
        tools
        |> Enum.map(&transform_mcp_tool_to_function/1)

      _ ->
        []
    end
  end

  defp transform_to_function_definition(%{"name" => name} = tool) do
    %{
      "type" => "function",
      "function" => %{
        "name" => name,
        "description" => tool["description"],
        "parameters" => tool["inputSchema"] || %{"type" => "object", "properties" => %{}}
      },
      "metadata" => %{
        "server" => tool["server"],
        "category" => Map.get(tool, "category", "general"),
        "performance" => Map.get(tool, "performance", "standard")
      }
    }
  end

  defp transform_mcp_tool_to_function(%{"name" => name} = tool) do
    # Add server prefix to avoid name conflicts
    server_name = Map.get(tool, :server, Map.get(tool, "server", "unknown"))
    prefixed_name = "#{server_name}_#{name}"

    %{
      "type" => "function",
      "function" => %{
        "name" => prefixed_name,
        "description" => enhance_mcp_tool_description(tool["description"], server_name),
        "parameters" => normalize_input_schema(tool["inputSchema"])
      },
      "metadata" => %{
        "server" => server_name,
        "original_name" => name,
        "category" => "mcp_server",
        "performance" => "standard"
      }
    }
  end

  defp enhance_mcp_tool_description(description, server_name) do
    "[MCP:#{server_name}] #{description}"
  end

  defp normalize_input_schema(nil), do: %{"type" => "object", "properties" => %{}}

  defp normalize_input_schema(schema) when is_map(schema) do
    schema
    |> Map.put_new("type", "object")
    |> Map.put_new("properties", %{})
  end

  defp normalize_input_schema(_), do: %{"type" => "object", "properties" => %{}}

  defp parse_function_name(function_name) do
    cond do
      String.starts_with?(function_name, "fs_") ->
        {:native, function_name}

      String.contains?(function_name, "_") ->
        case String.split(function_name, "_", parts: 2) do
          [server_name, tool_name] ->
            {:mcp_server, server_name, tool_name}

          _ ->
            {:error, "Invalid function name format: #{function_name}"}
        end

      true ->
        {:error, "Unknown function name format: #{function_name}"}
    end
  end

  defp execute_native_tool(tool_name, arguments) do
    case NativeToolBridge.execute_native_tool(tool_name, arguments) do
      {:ok, response} ->
        format_success_response(response, tool_name, :native)

      {:error, reason} ->
        format_error_response(reason, tool_name, :native)
    end
  end

  defp execute_mcp_tool(server_name, tool_name, arguments) do
    case ServerManager.call_tool(server_name, tool_name, arguments) do
      {:ok, response} ->
        format_success_response(response, tool_name, {:mcp, server_name})

      {:error, reason} ->
        format_error_response(reason, tool_name, {:mcp, server_name})
    end
  end

  defp format_success_response(response, tool_name, source) do
    # Format the response for LLM consumption
    content =
      case response do
        %{"content" => content} -> content
        content when is_binary(content) -> content
        content -> inspect(content)
      end

    source_info =
      case source do
        :native -> "[NATIVE]"
        {:mcp, server} -> "[MCP:#{server}]"
      end

    {:ok, "#{source_info} #{tool_name} executed successfully:\n#{content}"}
  end

  defp format_error_response(reason, tool_name, source) do
    source_info =
      case source do
        :native -> "[NATIVE]"
        {:mcp, server} -> "[MCP:#{server}]"
      end

    error_msg =
      case reason do
        reason when is_binary(reason) -> reason
        reason -> inspect(reason)
      end

    {:error, "#{source_info} #{tool_name} failed: #{error_msg}"}
  end
end
