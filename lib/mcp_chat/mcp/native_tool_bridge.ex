defmodule MCPChat.MCP.NativeToolBridge do
  @moduledoc """
  Bridge module that exposes native BEAM services as MCP tools for LLM function calling.

  This module transforms native ExMCP.Native services into standard MCP tool definitions
  that can be discovered and used by LLMs through function calling.
  """

  require Logger

  @doc """
  Get all native tools formatted as MCP tool definitions for LLM function calling.
  """
  def get_native_tools do
    case ExMCP.Native.service_available?(:filesystem_server) do
      true ->
        get_filesystem_tools()

      false ->
        Logger.debug("Native filesystem server not available")
        []
    end
  end

  @doc """
  Execute a native tool by name with given arguments.
  """
  def execute_native_tool(tool_name, arguments) do
    case tool_name do
      name
      when name in ["fs_ls", "fs_cat", "fs_write", "fs_edit", "fs_grep", "fs_find", "fs_mkdir", "fs_rm", "fs_stat"] ->
        execute_filesystem_tool(String.trim_leading(name, "fs_"), arguments)

      _ ->
        {:error, "Unknown native tool: #{tool_name}"}
    end
  end

  # Private functions

  defp get_filesystem_tools do
    if ExMCP.Native.service_available?(:filesystem_server) do
      case ExMCP.Native.call(:filesystem_server, "list_tools", %{}) do
        {:ok, %{"tools" => tools}} ->
          Enum.map(tools, &transform_filesystem_tool/1)

        error ->
          Logger.warning("Failed to get filesystem tools: #{inspect(error)}")
          []
      end
    else
      []
    end
  end

  defp transform_filesystem_tool(%{"name" => name} = tool) do
    %{
      "name" => "fs_#{name}",
      "description" => enhance_tool_description(tool["description"], name),
      "inputSchema" => transform_input_schema(tool["inputSchema"]),
      "server" => :native_filesystem,
      "category" => "filesystem",
      "performance" => "ultra_fast"
    }
  end

  defp enhance_tool_description(description, name) do
    prefix =
      case name do
        "ls" -> "[NATIVE FILESYSTEM] List directory contents - "
        "cat" -> "[NATIVE FILESYSTEM] Read file contents - "
        "write" -> "[NATIVE FILESYSTEM] Write to file - "
        "edit" -> "[NATIVE FILESYSTEM] Edit file with line operations - "
        "grep" -> "[NATIVE FILESYSTEM] Search file contents - "
        "find" -> "[NATIVE FILESYSTEM] Find files and directories - "
        "mkdir" -> "[NATIVE FILESYSTEM] Create directories - "
        "rm" -> "[NATIVE FILESYSTEM] Remove files/directories - "
        "stat" -> "[NATIVE FILESYSTEM] Get file information - "
        _ -> "[NATIVE FILESYSTEM] "
      end

    "#{prefix}#{description} (Ultra-fast native BEAM execution ~15μs)"
  end

  defp transform_input_schema(schema) do
    # Ensure the schema is properly formatted for LLM function calling
    schema
    |> Map.put("type", "object")
    |> ensure_required_field()
  end

  defp ensure_required_field(schema) do
    if Map.has_key?(schema, "required") do
      schema
    else
      # Infer required fields from properties
      required =
        case Map.get(schema, "properties") do
          properties when is_map(properties) ->
            properties
            |> Enum.filter(fn {_key, value} ->
              is_map(value) and not Map.get(value, "optional", false)
            end)
            |> Enum.map(fn {key, _value} -> key end)

          _ ->
            []
        end

      Map.put(schema, "required", required)
    end
  end

  defp execute_filesystem_tool(tool_name, arguments) do
    case ExMCP.Native.call(:filesystem_server, "tools/call", %{
           "name" => tool_name,
           "arguments" => arguments
         }) do
      {:ok, %{"content" => content} = response} ->
        # Transform the response for LLM consumption
        transformed_content = transform_content_for_llm(content, tool_name)
        {:ok, Map.put(response, "content", transformed_content)}

      {:ok, %{"content" => content, "isError" => true} = response} ->
        # Handle error responses
        error_content = transform_error_for_llm(content)
        {:error, Map.put(response, "content", error_content)}

      {:error, {:service_not_found, :filesystem_server}} ->
        {:error, "Native filesystem server is not available"}

      {:error, reason} ->
        {:error, "Filesystem operation failed: #{inspect(reason)}"}

      other ->
        {:error, "Unexpected response from filesystem server: #{inspect(other)}"}
    end
  end

  defp transform_content_for_llm(content, tool_name) when is_list(content) do
    # Extract text from MCP content format and format for LLM
    text_content =
      content
      |> Enum.map(fn
        %{"type" => "text", "text" => text} -> text
        other -> inspect(other)
      end)
      |> Enum.join("\n")

    # Add context about the operation
    operation_context =
      case tool_name do
        "ls" -> "Directory listing result"
        "cat" -> "File contents"
        "write" -> "File write operation result"
        "edit" -> "File edit operation result"
        "grep" -> "Search results"
        "find" -> "File search results"
        "mkdir" -> "Directory creation result"
        "rm" -> "File removal result"
        "stat" -> "File information"
        _ -> "Filesystem operation result"
      end

    "#{operation_context}:\n#{text_content}"
  end

  defp transform_content_for_llm(content, _tool_name) do
    # Handle non-list content
    inspect(content)
  end

  defp transform_error_for_llm(content) when is_list(content) do
    content
    |> Enum.map(fn
      %{"type" => "text", "text" => text} -> text
      other -> inspect(other)
    end)
    |> Enum.join("\n")
  end

  defp transform_error_for_llm(content) do
    inspect(content)
  end
end
