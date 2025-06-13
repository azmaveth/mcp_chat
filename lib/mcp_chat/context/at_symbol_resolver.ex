defmodule MCPChat.Context.AtSymbolResolver do
  @moduledoc """
  Resolves @ symbol references to their actual content.

  Handles fetching content for:
  - @resource: or @r: - MCP resource content
  - @prompt: or @p: - MCP prompt execution results
  - @tool: or @t: - MCP tool execution output
  - @file: or @f: - Local file content
  - @url: or @u: - Web content
  """

  alias MCPChat.Context.AtSymbolParser
  alias MCPChat.MCP.ServerManager
  # alias MCPChat.Session

  require Logger

  @type resolution_result :: %{
          reference: AtSymbolParser.at_reference(),
          content: String.t() | nil,
          error: String.t() | nil,
          metadata: map()
        }

  @type resolution_options :: [
          max_file_size: pos_integer(),
          http_timeout: pos_integer(),
          mcp_timeout: pos_integer(),
          validate_content: boolean()
        ]

  @default_options [
    # 1MB
    max_file_size: 1_024 * 1_024,
    # 10 seconds
    http_timeout: 10_000,
    # 30 seconds
    mcp_timeout: 30_000,
    validate_content: true
  ]

  @doc """
  Resolve all @ references in text to their content.

  Returns a map with:
  - :resolved_text - text with @ references replaced by content
  - :results - list of resolution results
  - :total_tokens - estimated token count for all included content
  """
  @spec resolve_all(String.t(), resolution_options()) :: %{
          resolved_text: String.t(),
          results: [resolution_result()],
          total_tokens: non_neg_integer(),
          errors: [String.t()]
        }
  def resolve_all(text, opts \\ []) do
    opts = Keyword.merge(@default_options, opts)
    references = AtSymbolParser.parse(text)

    Logger.debug("Resolving #{length(references)} @ references")

    # Resolve all references concurrently
    results = resolve_references_parallel(references, opts)

    # Replace references with their content
    resolved_text = replace_with_content(text, results)

    # Calculate total tokens and collect errors
    total_tokens = calculate_total_tokens(results)
    errors = collect_errors(results)

    %{
      resolved_text: resolved_text,
      results: results,
      total_tokens: total_tokens,
      errors: errors
    }
  end

  @doc """
  Resolve a single @ reference to its content.
  """
  @spec resolve_reference(AtSymbolParser.at_reference(), resolution_options()) :: resolution_result()
  def resolve_reference(reference, opts \\ []) do
    opts = Keyword.merge(@default_options, opts)

    Logger.debug("Resolving #{reference.type}:#{reference.identifier}")

    {content, error, metadata} =
      case reference.type do
        :file -> resolve_file(reference.identifier, opts)
        :url -> resolve_url(reference.identifier, opts)
        :resource -> resolve_mcp_resource(reference.identifier, opts)
        :prompt -> resolve_mcp_prompt(reference.identifier, opts)
        :tool -> resolve_mcp_tool(reference.identifier, opts)
        _ -> {nil, "Unknown reference type: #{reference.type}", %{}}
      end

    %{
      reference: reference,
      content: content,
      error: error,
      metadata: metadata
    }
  end

  @doc """
  Get available completions for @ references.
  """
  @spec get_available_completions(AtSymbolParser.reference_type()) :: [String.t()]
  def get_available_completions(type) do
    case type do
      :resource -> get_available_resources()
      :prompt -> get_available_prompts()
      :tool -> get_available_tools()
      # File completions would need filesystem integration
      :file -> []
      # URL completions would need history/bookmarks
      :url -> []
    end
  end

  # Private functions

  defp resolve_references_parallel(references, opts) do
    # Group references by type for more efficient resolution
    references
    |> Task.async_stream(
      fn ref -> resolve_reference(ref, opts) end,
      max_concurrency: 5,
      timeout: Keyword.get(opts, :mcp_timeout, 30_000) + 5_000
    )
    |> Enum.map(fn
      {:ok, result} ->
        result

      {:exit, reason} ->
        %{
          reference: %{type: :unknown, identifier: "unknown", full_match: "", start_pos: 0, end_pos: 0},
          content: nil,
          error: "Resolution timeout: #{inspect(reason)}",
          metadata: %{}
        }
    end)
  end

  defp resolve_file(file_path, opts) do
    max_size = Keyword.get(opts, :max_file_size)
    validate = Keyword.get(opts, :validate_content, true)

    try do
      # Resolve relative paths
      full_path = Path.expand(file_path)

      # Check if file exists and is readable
      case File.stat(full_path) do
        {:ok, %File.Stat{type: :regular, size: size}} when size <= max_size ->
          case File.read(full_path) do
            {:ok, content} ->
              if validate and not valid_text_content?(content) do
                {nil, "File contains binary data or invalid encoding", %{size: size, path: full_path}}
              else
                {content, nil, %{size: size, path: full_path, encoding: "utf-8"}}
              end

            {:error, reason} ->
              {nil, "Failed to read file: #{reason}", %{path: full_path}}
          end

        {:ok, %File.Stat{type: :regular, size: size}} ->
          {nil, "File too large: #{size} bytes (max: #{max_size})", %{size: size, path: full_path}}

        {:ok, %File.Stat{type: type}} ->
          {nil, "Not a regular file: #{type}", %{path: full_path}}

        {:error, :enoent} ->
          {nil, "File not found", %{path: full_path}}

        {:error, reason} ->
          {nil, "File access error: #{reason}", %{path: full_path}}
      end
    rescue
      e in [ArgumentError, File.Error] ->
        {nil, "Invalid file path: #{Exception.message(e)}", %{path: file_path}}
    end
  end

  defp resolve_url(url, opts) do
    timeout = Keyword.get(opts, :http_timeout)

    try do
      # Check if Req is available
      if Code.ensure_loaded?(Req) do
        case Req.get(url, receive_timeout: timeout, connect_options: [timeout: timeout]) do
          {:ok, response} when is_map(response) ->
            status = Map.get(response, :status, 0)
            body = Map.get(response, :body, "")

            if status == 200 do
              content_type = get_content_type(response)

              if String.starts_with?(content_type, "text/") do
                {body, nil, %{url: url, content_type: content_type, status: 200}}
              else
                {nil, "Non-text content type: #{content_type}", %{url: url, content_type: content_type}}
              end
            else
              {nil, "HTTP error: #{status}", %{url: url, status: status}}
            end

          {:error, error} when is_map(error) ->
            reason = Map.get(error, :reason, :unknown)

            if reason == :timeout do
              {nil, "Request timeout", %{url: url, timeout: timeout}}
            else
              {nil, "Request failed: #{inspect(reason)}", %{url: url}}
            end

          {:error, reason} ->
            {nil, "Request failed: #{inspect(reason)}", %{url: url}}
        end
      else
        {nil, "HTTP client not available", %{url: url}}
      end
    rescue
      e ->
        {nil, "URL resolution error: #{Exception.message(e)}", %{url: url}}
    end
  end

  defp resolve_mcp_resource(resource_name, opts) do
    _timeout = Keyword.get(opts, :mcp_timeout)

    case find_resource_server(resource_name) do
      {:ok, server_name} ->
        case ServerManager.read_resource(server_name, resource_name) do
          {:ok, resource} ->
            content = format_resource_content(resource)
            {content, nil, %{server: server_name, resource_name: resource_name, type: "mcp_resource"}}

          {:error, reason} ->
            {nil, "Resource error: #{inspect(reason)}", %{server: server_name, resource_name: resource_name}}
        end

      {:error, reason} ->
        {nil, reason, %{resource_name: resource_name}}
    end
  end

  defp resolve_mcp_prompt(prompt_name, opts) do
    _timeout = Keyword.get(opts, :mcp_timeout)

    case find_prompt_server(prompt_name) do
      {:ok, server_name} ->
        # Get the prompt template with any arguments
        case ServerManager.get_prompt(server_name, prompt_name, %{}) do
          {:ok, prompt} ->
            content = format_prompt_content(prompt)
            {content, nil, %{server: server_name, prompt_name: prompt_name, type: "mcp_prompt"}}

          {:error, reason} ->
            {nil, "Prompt error: #{inspect(reason)}", %{server: server_name, prompt_name: prompt_name}}
        end

      {:error, reason} ->
        {nil, reason, %{prompt_name: prompt_name}}
    end
  end

  defp resolve_mcp_tool(tool_spec, opts) do
    _timeout = Keyword.get(opts, :mcp_timeout)

    # Parse tool spec: tool_name or tool_name:arg1=val1,arg2=val2
    {tool_name, args} = parse_tool_spec(tool_spec)

    case find_tool_server(tool_name) do
      {:ok, server_name} ->
        case ServerManager.call_tool(server_name, tool_name, args) do
          {:ok, result} ->
            content = format_tool_result(result)
            {content, nil, %{server: server_name, tool_name: tool_name, args: args, type: "mcp_tool"}}

          {:error, reason} ->
            {nil, "Tool error: #{inspect(reason)}", %{server: server_name, tool_name: tool_name, args: args}}
        end

      {:error, reason} ->
        {nil, reason, %{tool_name: tool_name}}
    end
  end

  defp replace_with_content(text, results) do
    # Sort by position in reverse order to maintain indices
    results
    |> Enum.sort_by(& &1.reference.start_pos, :desc)
    |> Enum.reduce(text, fn result, acc ->
      ref = result.reference

      replacement =
        case result.content do
          nil -> "[ERROR: #{result.error}]"
          content -> content
        end

      before = String.slice(acc, 0, ref.start_pos)
      after_pos = ref.start_pos + String.length(ref.full_match)
      after_text = String.slice(acc, after_pos..-1//1)

      before <> replacement <> after_text
    end)
  end

  defp calculate_total_tokens(results) do
    # Rough token estimation: 1 token ≈ 4 characters
    results
    |> Enum.reduce(0, fn result, acc ->
      case result.content do
        nil -> acc
        content -> acc + div(String.length(content), 4)
      end
    end)
  end

  defp collect_errors(results) do
    results
    |> Enum.filter(& &1.error)
    |> Enum.map(& &1.error)
  end

  defp valid_text_content?(content) do
    String.valid?(content) and not String.contains?(content, <<0>>)
  end

  defp get_content_type(response) when is_map(response) do
    headers = Map.get(response, :headers, [])

    case List.keyfind(headers, "content-type", 0) do
      {"content-type", content_type} when is_binary(content_type) ->
        String.split(content_type, ";") |> hd()

      {"content-type", [content_type | _]} ->
        String.split(content_type, ";") |> hd()

      _ ->
        "application/octet-stream"
    end
  end

  defp find_resource_server(resource_uri) do
    try do
      # Get all servers and their resources
      all_resources = ServerManager.list_all_resources()

      # Find which server has the requested resource
      resource_found =
        Enum.find(all_resources, fn {_server_name, resources} ->
          Enum.any?(resources, fn resource ->
            case resource do
              %{uri: ^resource_uri} -> true
              %{name: ^resource_uri} -> true
              %{"uri" => ^resource_uri} -> true
              %{"name" => ^resource_uri} -> true
              _ -> false
            end
          end)
        end)

      case resource_found do
        {server_name, _resources} -> {:ok, server_name}
        nil -> {:error, "Resource not found: #{resource_uri}"}
      end
    rescue
      _ -> {:error, "No MCP servers available or not started"}
    end
  end

  defp find_prompt_server(prompt_name) do
    try do
      # Get all servers and their prompts
      all_prompts = ServerManager.list_all_prompts()

      # Find which server has the requested prompt
      prompt_found =
        Enum.find(all_prompts, fn {_server_name, prompts} ->
          Enum.any?(prompts, fn prompt ->
            case prompt do
              %{name: ^prompt_name} -> true
              %{"name" => ^prompt_name} -> true
              _ -> false
            end
          end)
        end)

      case prompt_found do
        {server_name, _prompts} -> {:ok, server_name}
        nil -> {:error, "Prompt not found: #{prompt_name}"}
      end
    rescue
      _ -> {:error, "No MCP servers available or not started"}
    end
  end

  defp find_tool_server(tool_name) do
    try do
      # Get all servers and their tools
      all_tools = ServerManager.list_all_tools()

      # Find which server has the requested tool
      tool_found =
        Enum.find(all_tools, fn {_server_name, tools} ->
          Enum.any?(tools, fn tool ->
            case tool do
              %{name: ^tool_name} -> true
              %{"name" => ^tool_name} -> true
              _ -> false
            end
          end)
        end)

      case tool_found do
        {server_name, _tools} -> {:ok, server_name}
        nil -> {:error, "Tool not found: #{tool_name}"}
      end
    rescue
      _ -> {:error, "No MCP servers available or not started"}
    end
  end

  defp get_available_resources() do
    try do
      ServerManager.list_all_resources()
      |> Enum.flat_map(fn {_server_name, resources} ->
        Enum.map(resources, fn resource ->
          case resource do
            %{name: name} -> name
            %{"name" => name} -> name
            %{uri: uri} -> uri
            %{"uri" => uri} -> uri
            _ -> nil
          end
        end)
      end)
      |> Enum.filter(& &1)
    rescue
      _ -> []
    end
  end

  defp get_available_prompts() do
    try do
      ServerManager.list_all_prompts()
      |> Enum.flat_map(fn {_server_name, prompts} ->
        Enum.map(prompts, fn prompt ->
          case prompt do
            %{name: name} -> name
            %{"name" => name} -> name
            _ -> nil
          end
        end)
      end)
      |> Enum.filter(& &1)
    rescue
      _ -> []
    end
  end

  defp get_available_tools() do
    try do
      ServerManager.list_all_tools()
      |> Enum.flat_map(fn {_server_name, tools} ->
        Enum.map(tools, fn tool ->
          case tool do
            %{name: name} -> name
            %{"name" => name} -> name
            _ -> nil
          end
        end)
      end)
      |> Enum.filter(& &1)
    rescue
      _ -> []
    end
  end

  defp parse_tool_spec(tool_spec) do
    case String.split(tool_spec, ":", parts: 2) do
      [tool_name] -> {tool_name, %{}}
      [tool_name, args_str] -> {tool_name, parse_tool_args(args_str)}
    end
  end

  defp parse_tool_args(args_str) do
    args_str
    |> String.split(",")
    |> Enum.reduce(%{}, fn arg, acc ->
      case String.split(arg, "=", parts: 2) do
        [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
        [key] -> Map.put(acc, String.trim(key), true)
      end
    end)
  end

  defp format_resource_content(resource) do
    # Format MCP resource content appropriately (ExMCP format)
    case resource do
      # ExMCP format - direct text content
      %{text: text} when is_binary(text) ->
        text

      %{"text" => text} when is_binary(text) ->
        text

      # ExMCP format - multiple content items
      %{contents: contents} when is_list(contents) ->
        format_content_list(contents)

      %{"contents" => contents} when is_list(contents) ->
        format_content_list(contents)

      # Legacy format support
      %{"contents" => [%{"text" => text}]} ->
        text

      %{"contents" => contents} when is_list(contents) ->
        contents
        |> Enum.map(fn
          %{"text" => text} -> text
          %{"blob" => _} -> "[Binary content]"
          other -> inspect(other)
        end)
        |> Enum.join("\n")

      %{"text" => text} ->
        text

      other ->
        inspect(other)
    end
  end

  defp format_prompt_content(prompt) do
    # Format MCP prompt content appropriately (ExMCP format)
    case prompt do
      # ExMCP format - list of messages
      messages when is_list(messages) ->
        messages
        |> Enum.map(fn
          %{role: role, content: content} -> format_message_content(role, content)
          %{"role" => role, "content" => content} -> format_message_content(role, content)
          other -> inspect(other)
        end)
        |> Enum.join("\n")

      # Legacy format support
      %{"messages" => messages} when is_list(messages) ->
        messages
        |> Enum.map(fn
          %{"role" => role, "content" => %{"text" => text}} -> "#{role}: #{text}"
          %{"role" => role, "content" => content} when is_binary(content) -> "#{role}: #{content}"
          other -> inspect(other)
        end)
        |> Enum.join("\n")

      %{"content" => content} ->
        content

      other ->
        inspect(other)
    end
  end

  defp format_tool_result(result) do
    # Format MCP tool result appropriately (ExMCP format)
    case result do
      # ExMCP format - list of content items
      content_list when is_list(content_list) ->
        format_content_list(content_list)

      # Legacy format support
      %{"content" => [%{"text" => text}]} ->
        text

      %{"content" => content} when is_list(content) ->
        content
        |> Enum.map(fn
          %{"text" => text} -> text
          %{"blob" => _} -> "[Binary result]"
          other -> inspect(other)
        end)
        |> Enum.join("\n")

      %{"text" => text} ->
        text

      %{"result" => result} ->
        inspect(result)

      other ->
        inspect(other)
    end
  end

  # Helper functions for content formatting

  defp format_content_list(contents) when is_list(contents) do
    contents
    |> Enum.map(fn
      %{type: "text", text: text} -> text
      %{"type" => "text", "text" => text} -> text
      %{type: "blob"} -> "[Binary content]"
      %{"type" => "blob"} -> "[Binary content]"
      %{type: "image"} -> "[Image content]"
      %{"type" => "image"} -> "[Image content]"
      other -> inspect(other)
    end)
    |> Enum.join("\n")
  end

  defp format_message_content(role, content) do
    content_text =
      case content do
        %{type: "text", text: text} -> text
        %{"type" => "text", "text" => text} -> text
        text when is_binary(text) -> text
        other -> inspect(other)
      end

    "#{role}: #{content_text}"
  end
end
