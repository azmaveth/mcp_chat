defmodule MCPChat.Tools.NativeFilesystemTool do
  @moduledoc """
  MCP tool that provides filesystem operations using the native BEAM filesystem server.

  This tool demonstrates the benefits of ExMCP.Native by providing ultra-fast
  filesystem operations with zero serialization overhead.

  ## Performance Benefits

  - **Ultra-low latency**: ~15μs for local calls vs ~1-5ms for external servers
  - **Zero serialization**: Direct process communication with no JSON overhead  
  - **Resource sharing**: Can access and modify files directly within the BEAM
  - **Fault tolerance**: Leverages OTP supervision and process isolation

  ## Available Operations

  All filesystem operations are available through the `/fs` command:

  - `/fs ls <path>` - List directory contents
  - `/fs cat <path>` - Read file contents  
  - `/fs write <path> <content>` - Write to file
  - `/fs edit <path> <operation>` - Edit file with line operations
  - `/fs grep <pattern> <path>` - Search file contents
  - `/fs find <path> <pattern>` - Find files by pattern
  - `/fs mkdir <path>` - Create directories
  - `/fs rm <path>` - Remove files/directories
  - `/fs stat <path>` - Get file information
  """

  alias MCPChat.CLI.Renderer

  @doc """
  Execute a filesystem operation using the native BEAM server.
  """
  def execute(operation, args) do
    case ExMCP.Native.call(:filesystem_server, "tools/call", %{
           "name" => operation,
           "arguments" => args
         }) do
      {:ok, %{"content" => content}} ->
        display_results(content)

      {:ok, %{"content" => content, "isError" => true}} ->
        display_error_results(content)

      {:error, reason} ->
        Renderer.show_error("Native filesystem server error: #{inspect(reason)}")

      other ->
        Renderer.show_error("Unexpected response from filesystem server: #{inspect(other)}")
    end
  end

  @doc """
  Get available filesystem tools from the native server.
  """
  def list_tools do
    case ExMCP.Native.call(:filesystem_server, "list_tools", %{}) do
      {:ok, %{"tools" => tools}} ->
        tools

      {:error, reason} ->
        Renderer.show_error("Failed to list filesystem tools: #{inspect(reason)}")
        []

      other ->
        Renderer.show_error("Unexpected response when listing tools: #{inspect(other)}")
        []
    end
  end

  @doc """
  Show help for filesystem operations.
  """
  def show_help do
    tools = list_tools()

    if Enum.empty?(tools) do
      Renderer.show_error("Filesystem server not available")
    else
      Renderer.show_text("# Native BEAM Filesystem Tools\n")
      Renderer.show_success("✓ Ultra-fast filesystem operations with zero serialization overhead")
      Renderer.show_text("\n## Available Operations:\n")

      Enum.each(tools, fn tool ->
        name = tool["name"]
        description = tool["description"]
        schema = tool["inputSchema"]

        Renderer.show_text("### `/fs #{name}`")
        Renderer.show_text("#{description}\n")

        if schema["properties"] do
          Renderer.show_text("**Parameters:**")

          Enum.each(schema["properties"], fn {param, config} ->
            required = if param in Map.get(schema, "required", []), do: " (required)", else: ""
            param_description = Map.get(config, "description", "No description")
            Renderer.show_text("- `#{param}`: #{param_description}#{required}")
          end)
        end

        show_usage_examples(name)
        Renderer.show_text("")
      end)

      Renderer.show_info("💡 Native BEAM benefits: ~15μs latency vs ~1-5ms for external servers")
    end
  end

  @doc """
  Handle filesystem command with argument parsing.
  """
  def handle_command(args) when is_list(args) and length(args) >= 1 do
    [operation | rest_args] = args

    case operation do
      "help" ->
        show_help()

      "ls" ->
        handle_ls_command(rest_args)

      "cat" ->
        handle_cat_command(rest_args)

      "write" ->
        handle_write_command(rest_args)

      "edit" ->
        handle_edit_command(rest_args)

      "grep" ->
        handle_grep_command(rest_args)

      "find" ->
        handle_find_command(rest_args)

      "mkdir" ->
        handle_mkdir_command(rest_args)

      "rm" ->
        handle_rm_command(rest_args)

      "stat" ->
        handle_stat_command(rest_args)

      _ ->
        Renderer.show_error("Unknown filesystem operation: #{operation}")
        Renderer.show_text("Use `/fs help` to see available operations")
    end
  end

  def handle_command(_) do
    Renderer.show_error("Usage: /fs <operation> [args...]")
    Renderer.show_text("Use `/fs help` to see available operations")
  end

  # Command handlers

  defp handle_ls_command([path | options]) do
    args = %{"path" => path}

    # Parse options
    args =
      Enum.reduce(options, args, fn
        "--hidden", acc -> Map.put(acc, "show_hidden", true)
        "-a", acc -> Map.put(acc, "show_hidden", true)
        "--no-details", acc -> Map.put(acc, "details", false)
        "-1", acc -> Map.put(acc, "details", false)
        _, acc -> acc
      end)

    execute("ls", args)
  end

  defp handle_ls_command([]) do
    execute("ls", %{"path" => "."})
  end

  defp handle_cat_command([path | options]) do
    args = %{"path" => path}

    # Parse options like --lines=10 or --offset=5
    args =
      Enum.reduce(options, args, fn option, acc ->
        cond do
          String.starts_with?(option, "--lines=") ->
            lines = option |> String.replace("--lines=", "") |> String.to_integer()
            Map.put(acc, "lines", lines)

          String.starts_with?(option, "--offset=") ->
            offset = option |> String.replace("--offset=", "") |> String.to_integer()
            Map.put(acc, "offset", offset)

          true ->
            acc
        end
      end)

    execute("cat", args)
  end

  defp handle_cat_command([]) do
    Renderer.show_error("Usage: /fs cat <path> [--lines=N] [--offset=N]")
  end

  defp handle_write_command([path, content | options]) do
    args = %{"path" => path, "content" => content}

    # Parse options
    args =
      Enum.reduce(options, args, fn
        "--append", acc -> Map.put(acc, "append", true)
        "-a", acc -> Map.put(acc, "append", true)
        "--no-backup", acc -> Map.put(acc, "backup", false)
        _, acc -> acc
      end)

    execute("write", args)
  end

  defp handle_write_command(_) do
    Renderer.show_error("Usage: /fs write <path> <content> [--append] [--no-backup]")
  end

  defp handle_grep_command([pattern, path | options]) do
    args = %{"pattern" => pattern, "path" => path}

    # Parse options
    args =
      Enum.reduce(options, args, fn
        "--recursive", acc ->
          Map.put(acc, "recursive", true)

        "-r", acc ->
          Map.put(acc, "recursive", true)

        "--ignore-case", acc ->
          Map.put(acc, "ignore_case", true)

        "-i", acc ->
          Map.put(acc, "ignore_case", true)

        "--no-line-numbers", acc ->
          Map.put(acc, "line_numbers", false)

        option, acc ->
          if String.starts_with?(option, "--context=") do
            context = option |> String.replace("--context=", "") |> String.to_integer()
            Map.put(acc, "context", context)
          else
            acc
          end
      end)

    execute("grep", args)
  end

  defp handle_grep_command(_) do
    Renderer.show_error("Usage: /fs grep <pattern> <path> [--recursive] [--ignore-case] [--context=N]")
  end

  defp handle_find_command([path | options]) do
    args = %{"path" => path}

    # Parse options
    args =
      Enum.reduce(options, args, fn
        option, acc ->
          cond do
            String.starts_with?(option, "--name=") ->
              name = String.replace(option, "--name=", "")
              Map.put(acc, "name", name)

            String.starts_with?(option, "--type=") ->
              type = String.replace(option, "--type=", "")
              Map.put(acc, "type", type)

            String.starts_with?(option, "--max-depth=") ->
              depth = option |> String.replace("--max-depth=", "") |> String.to_integer()
              Map.put(acc, "max_depth", depth)

            true ->
              acc
          end
      end)

    execute("find", args)
  end

  defp handle_find_command([]) do
    Renderer.show_error("Usage: /fs find <path> [--name=pattern] [--type=file|directory] [--max-depth=N]")
  end

  defp handle_mkdir_command([path | _options]) do
    args = %{"path" => path}
    execute("mkdir", args)
  end

  defp handle_mkdir_command([]) do
    Renderer.show_error("Usage: /fs mkdir <path>")
  end

  defp handle_rm_command([path | options]) do
    args = %{"path" => path}

    # Parse options
    args =
      Enum.reduce(options, args, fn
        "--recursive", acc -> Map.put(acc, "recursive", true)
        "-r", acc -> Map.put(acc, "recursive", true)
        "--force", acc -> Map.put(acc, "force", true)
        "-f", acc -> Map.put(acc, "force", true)
        _, acc -> acc
      end)

    execute("rm", args)
  end

  defp handle_rm_command([]) do
    Renderer.show_error("Usage: /fs rm <path> [--recursive] [--force]")
  end

  defp handle_stat_command([path]) do
    args = %{"path" => path}
    execute("stat", args)
  end

  defp handle_stat_command(_) do
    Renderer.show_error("Usage: /fs stat <path>")
  end

  defp handle_edit_command([path, operation | rest]) do
    args = %{"path" => path, "operation" => operation}

    case operation do
      "replace" ->
        case rest do
          [line_num, content] ->
            args =
              Map.merge(args, %{
                "line_number" => String.to_integer(line_num),
                "content" => content
              })

            execute("edit", args)

          _ ->
            Renderer.show_error("Usage: /fs edit <path> replace <line_number> <content>")
        end

      "insert" ->
        case rest do
          [line_num, content] ->
            args =
              Map.merge(args, %{
                "line_number" => String.to_integer(line_num),
                "content" => content
              })

            execute("edit", args)

          _ ->
            Renderer.show_error("Usage: /fs edit <path> insert <line_number> <content>")
        end

      "delete" ->
        case rest do
          [line_num] ->
            args = Map.put(args, "line_number", String.to_integer(line_num))
            execute("edit", args)

          _ ->
            Renderer.show_error("Usage: /fs edit <path> delete <line_number>")
        end

      "substitute" ->
        case rest do
          [pattern, replacement] ->
            args =
              Map.merge(args, %{
                "pattern" => pattern,
                "replacement" => replacement
              })

            execute("edit", args)

          [line_num, pattern, replacement] ->
            args =
              Map.merge(args, %{
                "line_number" => String.to_integer(line_num),
                "pattern" => pattern,
                "replacement" => replacement
              })

            execute("edit", args)

          _ ->
            Renderer.show_error("Usage: /fs edit <path> substitute [line_number] <pattern> <replacement>")
        end

      _ ->
        Renderer.show_error("Unknown edit operation: #{operation}")
        Renderer.show_text("Available operations: replace, insert, delete, substitute")
    end
  end

  defp handle_edit_command(_) do
    Renderer.show_error("Usage: /fs edit <path> <operation> [args...]")
    Renderer.show_text("Available operations: replace, insert, delete, substitute")
  end

  # Result display functions

  defp display_results(content) when is_list(content) do
    Enum.each(content, fn item ->
      case item do
        %{"type" => "text", "text" => text} ->
          Renderer.show_text(text)

        other ->
          Renderer.show_text(inspect(other))
      end
    end)
  end

  defp display_error_results(content) when is_list(content) do
    Enum.each(content, fn item ->
      case item do
        %{"type" => "text", "text" => text} ->
          Renderer.show_error(text)

        other ->
          Renderer.show_error(inspect(other))
      end
    end)
  end

  defp show_usage_examples(tool_name) do
    examples =
      case tool_name do
        "ls" ->
          [
            "/fs ls .",
            "/fs ls /Users/username --hidden",
            "/fs ls ~/Documents --no-details"
          ]

        "cat" ->
          [
            "/fs cat README.md",
            "/fs cat large_file.txt --lines=50",
            "/fs cat file.txt --offset=10 --lines=20"
          ]

        "write" ->
          [
            "/fs write hello.txt \"Hello, world!\"",
            "/fs write log.txt \"New entry\" --append",
            "/fs write config.json '{\"setting\": true}' --no-backup"
          ]

        "grep" ->
          [
            "/fs grep \"error\" app.log",
            "/fs grep \"TODO\" . --recursive",
            "/fs grep \"function\" file.js --ignore-case --context=3"
          ]

        "find" ->
          [
            "/fs find . --name=\"*.ex\"",
            "/fs find /Users --type=directory --max-depth=2",
            "/fs find ~/Documents --name=\"*test*\""
          ]

        "edit" ->
          [
            "/fs edit file.txt replace 5 \"New line content\"",
            "/fs edit file.txt insert 10 \"Inserted line\"",
            "/fs edit file.txt delete 3",
            "/fs edit file.txt substitute \"old\" \"new\"",
            "/fs edit file.txt substitute 5 \"pattern\" \"replacement\""
          ]

        _ ->
          []
      end

    unless Enum.empty?(examples) do
      Renderer.show_text("\n**Examples:**")

      Enum.each(examples, fn example ->
        Renderer.show_text("```\n#{example}\n```")
      end)
    end
  end
end
