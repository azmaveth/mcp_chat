defmodule MCPChat.CLI.MCPRefactored do
  @moduledoc """
  Refactored MCP commands that route through the agent architecture.
  Tool executions are handled by agents with real-time progress updates.
  """

  use MCPChat.CLI.Base

  alias MCPChat.Gateway
  alias MCPChat.CLI.EventSubscriber

  @impl true
  def commands do
    %{
      "mcp" => "MCP server management (usage: /mcp <subcommand>)"
    }
  end

  @doc "Returns the list of MCP subcommands for help display"
  def subcommands do
    %{
      "servers" => "List connected MCP servers",
      "connect" => "Connect to an MCP server",
      "disconnect" => "Disconnect from an MCP server",
      "tools" => "List available MCP tools",
      "tool" => "Execute an MCP tool (async with progress)",
      "resources" => "List available MCP resources",
      "resource" => "Read an MCP resource",
      "status" => "Show agent pool and execution status"
    }
  end

  @impl true
  def handle_command("mcp", args) do
    # Get the current session ID from the chat context
    session_id = get_current_session_id()

    case session_id do
      nil ->
        show_error("No active session. Please start a chat first.")
        :ok

      _ ->
        handle_mcp_subcommand(session_id, args)
    end
  end

  defp handle_mcp_subcommand(session_id, []) do
    # Show MCP help
    show_info("MCP (Model Context Protocol) Commands:")
    show_info("")

    subcommands()
    |> Enum.sort_by(fn {cmd, _} -> cmd end)
    |> Enum.each(fn {cmd, desc} ->
      show_info("  #{String.pad_trailing(cmd, 12)} - #{desc}")
    end)

    show_info("")
    show_info("Usage: /mcp <subcommand> [args...]")
    :ok
  end

  defp handle_mcp_subcommand(session_id, ["servers" | _args]) do
    list_servers(session_id)
  end

  defp handle_mcp_subcommand(session_id, ["connect" | args]) do
    connect_server(session_id, args)
  end

  defp handle_mcp_subcommand(session_id, ["disconnect" | args]) do
    disconnect_server(session_id, args)
  end

  defp handle_mcp_subcommand(session_id, ["tools" | args]) do
    list_tools(session_id, args)
  end

  defp handle_mcp_subcommand(session_id, ["tool" | args]) do
    execute_tool(session_id, args)
  end

  defp handle_mcp_subcommand(session_id, ["resources" | _args]) do
    list_resources(session_id)
  end

  defp handle_mcp_subcommand(session_id, ["resource" | args]) do
    read_resource(session_id, args)
  end

  defp handle_mcp_subcommand(session_id, ["status" | _args]) do
    show_execution_status(session_id)
  end

  defp handle_mcp_subcommand(_session_id, [subcmd | _]) do
    show_error("Unknown MCP subcommand: #{subcmd}")
    show_info("Type /mcp for available subcommands")
    :ok
  end

  # Command implementations using Gateway API

  defp list_servers(session_id) do
    case Gateway.list_mcp_tools(session_id, "*") do
      {:ok, servers_info} ->
        display_servers_info(servers_info)

      {:error, reason} ->
        show_error("Failed to list servers: #{inspect(reason)}")
    end

    :ok
  end

  defp connect_server(session_id, args) do
    case args do
      [] ->
        show_error("Usage: /mcp connect <server_name> [options]")

      [server_name | opts] ->
        config = parse_server_config(server_name, opts)

        case Gateway.connect_mcp_server(session_id, config) do
          {:ok, _} ->
            show_success("Connected to server: #{server_name}")

          {:error, reason} ->
            show_error("Failed to connect: #{inspect(reason)}")
        end
    end

    :ok
  end

  defp disconnect_server(session_id, args) do
    case args do
      [] ->
        show_error("Usage: /mcp disconnect <server_name>")

      [server_name | _] ->
        # This would be implemented through Gateway
        show_info("Disconnecting from #{server_name}...")
        # Gateway.disconnect_mcp_server(session_id, server_name)
    end

    :ok
  end

  defp list_tools(session_id, args) do
    server_name =
      case args do
        # List from all servers
        [] -> "*"
        [name | _] -> name
      end

    case Gateway.list_mcp_tools(session_id, server_name) do
      {:ok, tools} ->
        display_tools(tools)

      {:error, reason} ->
        show_error("Failed to list tools: #{inspect(reason)}")
    end

    :ok
  end

  defp execute_tool(session_id, args) do
    case args do
      [] ->
        show_error("Usage: /mcp tool <server> <tool> [args...]")

      [_server] ->
        show_error("Usage: /mcp tool <server> <tool> [args...]")

      [server, tool | tool_args] ->
        # Parse tool arguments
        arguments = parse_tool_arguments(tool_args)

        # Set UI mode to show progress
        EventSubscriber.set_ui_mode(session_id, :interactive)

        show_info("🔧 Executing tool: #{tool} on #{server}")

        # Execute through Gateway - will be routed to appropriate agent
        case Gateway.execute_tool(session_id, tool, arguments, server: server) do
          {:ok, :async, %{execution_id: exec_id}} ->
            show_info("Tool execution started (ID: #{exec_id})")
            show_info("Progress updates will appear below...")

          {:ok, result} ->
            # Synchronous execution completed
            display_tool_result(result)

          {:error, reason} ->
            show_error("Tool execution failed: #{inspect(reason)}")
        end
    end

    :ok
  end

  defp list_resources(session_id) do
    # This would be implemented through Gateway
    show_info("[Resources listing through agents - to be implemented]")
    :ok
  end

  defp read_resource(session_id, args) do
    case args do
      [] ->
        show_error("Usage: /mcp resource <server> <uri>")

      [_server] ->
        show_error("Usage: /mcp resource <server> <uri>")

      [server | uri_parts] ->
        uri = Enum.join(uri_parts, " ")
        show_info("Reading resource: #{uri} from #{server}")
        # Gateway.read_resource(session_id, server, uri)
    end

    :ok
  end

  defp show_execution_status(session_id) do
    # Get agent pool status
    pool_status = Gateway.get_agent_pool_status()

    show_info("Agent Pool Status:")
    show_info("  Active workers: #{pool_status.active_workers}/#{pool_status.max_concurrent}")
    show_info("  Queued tasks: #{pool_status.queue_length}")

    # Get active subagents for this session
    subagents = Gateway.list_session_subagents(session_id)

    if length(subagents) > 0 do
      show_info("\nActive operations:")

      Enum.each(subagents, fn {id, info} ->
        if info.alive do
          type_str = format_agent_type(info.agent_type)
          duration = format_duration_since(info.started_at)
          show_info("  #{type_str} (#{id}): running for #{duration}")
        end
      end)
    else
      show_info("\nNo active operations")
    end

    :ok
  end

  # Helper functions

  defp get_current_session_id do
    # In a real implementation, this would get the session ID from the chat context
    # For now, we'll try to get it from the active sessions
    case Gateway.list_active_sessions() do
      [] -> nil
      [session_id | _] -> session_id
    end
  end

  defp parse_server_config(name, opts) do
    # Parse server configuration from command line options
    %{
      name: name,
      command: parse_command_from_opts(opts),
      env: parse_env_from_opts(opts)
    }
  end

  defp parse_command_from_opts(opts) do
    # Extract command from options
    opts
    |> Enum.take_while(&(not String.starts_with?(&1, "--")))
  end

  defp parse_env_from_opts(opts) do
    # Extract environment variables from --env KEY=VALUE options
    opts
    |> Enum.chunk_while(
      [],
      fn
        "--env", acc -> {:cont, Enum.reverse(acc), ["--env"]}
        arg, ["--env"] -> {:cont, [], {:env, arg}}
        arg, acc -> {:cont, [arg | acc]}
      end,
      fn
        [] -> {:cont, []}
        ["--env"] -> {:cont, []}
        acc -> {:cont, Enum.reverse(acc), []}
      end
    )
    |> Enum.reduce(%{}, fn
      {:env, kv}, env_map ->
        case String.split(kv, "=", parts: 2) do
          [key, value] -> Map.put(env_map, key, value)
          _ -> env_map
        end

      _, env_map ->
        env_map
    end)
  end

  defp parse_tool_arguments([]), do: %{}

  defp parse_tool_arguments([json]) do
    case Jason.decode(json) do
      {:ok, args} when is_map(args) -> args
      _ -> parse_key_value_args([json])
    end
  end

  defp parse_tool_arguments(args) do
    parse_key_value_args(args)
  end

  defp parse_key_value_args(args) do
    args
    |> Enum.map(&String.split(&1, "=", parts: 2))
    |> Enum.filter(&(length(&1) == 2))
    |> Map.new(fn [k, v] -> {k, v} end)
  end

  defp display_servers_info(_servers_info) do
    show_info("[Server listing through agents - to be implemented]")
  end

  defp display_tools(tools) when is_list(tools) do
    if Enum.empty?(tools) do
      show_info("No tools available")
    else
      show_info("Available tools:")

      Enum.each(tools, fn tool ->
        name = Map.get(tool, "name", "unknown")
        desc = Map.get(tool, "description", "")
        show_info("  • #{name} - #{desc}")
      end)
    end
  end

  defp display_tools(_), do: show_info("No tools available")

  defp display_tool_result(%{"content" => content}) when is_list(content) do
    Enum.each(content, &display_content_item/1)
  end

  defp display_tool_result(%{"error" => error}) do
    show_error("Tool error: #{inspect(error)}")
  end

  defp display_tool_result(result) do
    IO.puts(Jason.encode!(result, pretty: true))
  end

  defp display_content_item(%{"type" => "text", "text" => text}) do
    IO.puts(text)
  end

  defp display_content_item(%{"type" => type} = item) do
    IO.puts("Content type: #{type}")
    IO.puts(Jason.encode!(item, pretty: true))
  end

  defp display_content_item(item) do
    IO.puts(inspect(item))
  end

  defp format_agent_type(:tool_executor), do: "Tool execution"
  defp format_agent_type(:export), do: "Export"
  defp format_agent_type(type), do: to_string(type)

  defp format_duration_since(started_at) do
    duration_ms = DateTime.diff(DateTime.utc_now(), started_at, :millisecond)

    cond do
      duration_ms < 1000 -> "#{duration_ms}ms"
      duration_ms < 60_000 -> "#{Float.round(duration_ms / 1000, 1)}s"
      true -> "#{div(duration_ms, 60_000)}m #{rem(div(duration_ms, 1000), 60)}s"
    end
  end
end
