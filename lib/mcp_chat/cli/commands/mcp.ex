defmodule MCPChat.CLI.Commands.MCP do
  @moduledoc """
  MCP (Model Context Protocol) related CLI commands.

  Handles commands for managing MCP servers and their capabilities:
  - Server discovery and connection
  - Tool execution
  - Resource access
  - Prompt retrieval
  """

  use MCPChat.CLI.Commands.Base

  alias MCPChat.MCP.{ServerManager, Discovery, ServerPersistence}

  @impl true
  def commands() do
    %{
      # Main MCP command with subcommands
      "mcp" => "MCP server management (usage: /mcp <subcommand>)"
    }
  end

  @doc """
  Returns the list of MCP subcommands for help display.
  """
  def subcommands() do
    %{
      "servers" => "List connected MCP servers",
      "saved" => "List saved MCP server connections",
      "discover" => "Discover available MCP servers",
      "connect" => "Connect to an MCP server (usage: connect <name> [--env KEY=VALUE ...])",
      "disconnect" => "Disconnect from an MCP server (usage: disconnect <name>)",
      "tools" => "List available MCP tools",
      "tool" => "Call an MCP tool (usage: tool <server> <tool> [args...])",
      "resources" => "List available MCP resources",
      "resource" => "Read an MCP resource (usage: resource <server> <uri>)",
      "prompts" => "List available MCP prompts",
      "prompt" => "Get an MCP prompt (usage: prompt <server> <name>)",
      # New v0.2.0 features
      "sample" => "Use server-side LLM generation (usage: sample <server> <prompt>)",
      "progress" => "Show active operations with progress",
      "notify" => "Control notification display (usage: notify <on|off|status>)",
      "capabilities" => "Show detailed server capabilities"
    }
  end

  @impl true
  def handle_command("mcp", args), do: handle_mcp_subcommand(args)

  def handle_command(cmd, _args) do
    {:error, "Unknown MCP command: #{cmd}"}
  end

  # Handle MCP subcommands
  defp handle_mcp_subcommand([]) do
    # Show MCP help when no subcommand given
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

  defp handle_mcp_subcommand(["servers" | _args]), do: list_servers()
  defp handle_mcp_subcommand(["saved" | _args]), do: list_saved_servers()
  defp handle_mcp_subcommand(["discover" | _args]), do: discover_servers()
  defp handle_mcp_subcommand(["connect" | args]), do: connect_server_enhanced(args)
  defp handle_mcp_subcommand(["disconnect" | args]), do: disconnect_server(args)
  defp handle_mcp_subcommand(["tools" | _args]), do: list_tools()
  defp handle_mcp_subcommand(["tool" | args]), do: call_tool(args)
  defp handle_mcp_subcommand(["resources" | _args]), do: list_resources()
  defp handle_mcp_subcommand(["resource" | args]), do: read_resource(args)
  defp handle_mcp_subcommand(["prompts" | _args]), do: list_prompts()
  defp handle_mcp_subcommand(["prompt" | args]), do: get_prompt(args)
  # New v0.2.0 commands
  defp handle_mcp_subcommand(["sample" | args]), do: MCPChat.CLI.Commands.MCPExtended.handle_sample(args)
  defp handle_mcp_subcommand(["progress" | args]), do: MCPChat.CLI.Commands.MCPExtended.handle_progress(args)
  defp handle_mcp_subcommand(["notify" | args]), do: MCPChat.CLI.Commands.MCPExtended.handle_notify(args)
  defp handle_mcp_subcommand(["capabilities" | args]), do: MCPChat.CLI.Commands.MCPExtended.handle_capabilities(args)

  defp handle_mcp_subcommand([subcmd | _]) do
    show_error("Unknown MCP subcommand: #{subcmd}")
    show_info("Type /mcp for available subcommands")
    :ok
  end

  # Server management commands

  defp list_servers() do
    servers = ServerManager.list_servers()

    if Enum.empty?(servers) do
      show_info("No MCP servers connected")
      show_info("Use /discover to find available servers")
    else
      show_info("Connected MCP servers:")

      Enum.each(servers, fn %{name: name, status: status} ->
        status_icon = if status == :connected, do: "✓", else: "✗"
        IO.puts("  #{status_icon} #{name}")
      end)
    end

    :ok
  end

  defp list_saved_servers() do
    servers = ServerPersistence.load_all_servers()

    if Enum.empty?(servers) do
      show_info("No saved server connections")
    else
      show_info("Saved MCP servers:")

      Enum.each(servers, fn server ->
        command_str = Enum.join(server.command, " ")
        IO.puts("  • #{server.name}")
        IO.puts("    Command: #{command_str}")

        if server.env && map_size(server.env) > 0 do
          IO.puts("    Environment: #{inspect(server.env)}")
        end
      end)
    end

    :ok
  end

  defp discover_servers() do
    show_info("Discovering MCP servers...")

    quick_servers = Discovery.quick_setup_servers()

    # Group by status
    available = Enum.filter(quick_servers, &(&1[:status] == :available))
    missing_reqs = Enum.filter(quick_servers, &(&1[:status] == :missing_requirements))

    if Enum.any?(available) do
      show_info("\nAvailable servers (ready to connect):")

      Enum.each(available, fn server ->
        IO.puts("  • #{server[:name]} - #{server[:description]}")
        IO.puts("    Connect with: /connect #{server[:name]}")
      end)
    end

    if Enum.any?(missing_reqs) do
      show_info("\nServers requiring configuration:")

      Enum.each(missing_reqs, fn server ->
        IO.puts("  • #{server[:name]} - #{server[:description]}")
        IO.puts("    Missing: #{Enum.join(server[:missing], ", ")}")
      end)
    end

    show_info("\nTo connect to a custom server:")
    show_info("  /connect <command> [args...] --env KEY=VALUE")

    :ok
  end

  defp connect_server_enhanced(args) do
    case args do
      [] ->
        show_error("Usage: /mcp connect <name> or /mcp connect <command> [args...] [--env KEY=VALUE ...]")

      [name] ->
        # Try quick setup server first
        connect_quick_setup_server(name)

      _ ->
        # Use the existing connect_custom_server which already handles env vars
        connect_custom_server(args)
    end
  end

  defp disconnect_server(args) do
    with {:ok, args} <- require_arg(args, "/disconnect <name>"),
         name <- parse_args(args) do
      case ServerManager.stop_server(name) do
        :ok ->
          show_success("Disconnected from server: #{name}")

        {:error, :not_found} ->
          show_error("Server not found: #{name}")

        {:error, reason} ->
          show_error("Failed to disconnect: #{inspect(reason)}")
      end
    else
      {:error, msg} -> show_error(msg)
    end
  end

  # Tool commands

  defp list_tools() do
    servers = ServerManager.list_servers()

    if Enum.empty?(servers) do
      show_info("No MCP servers connected")
    else
      all_tools =
        servers
        |> Enum.filter(fn %{status: status} -> status == :connected end)
        |> Enum.flat_map(fn %{name: server_name} ->
          # Get tools for this server
          case get_server_tools(server_name) do
            {:ok, %{"tools" => tool_list}} when is_list(tool_list) ->
              # Extract the tools list from the map
              Enum.map(tool_list, &{server_name, &1})

            {:ok, tools} when is_list(tools) ->
              # Already a list (for backward compatibility)
              Enum.map(tools, &{server_name, &1})

            _ ->
              []
          end
        end)

      if Enum.empty?(all_tools) do
        show_info("No tools available from connected servers")
      else
        show_info("Available MCP tools:")

        all_tools
        |> Enum.group_by(fn {server, _} -> server end)
        |> Enum.each(fn {server, tools} ->
          IO.puts("\n#{server}:")

          Enum.each(tools, fn {_, tool} ->
            IO.puts("  • #{tool["name"]} - #{tool["description"]}")
          end)
        end)
      end
    end

    :ok
  end

  defp call_tool(args) do
    case args do
      [] ->
        show_error("Usage: /tool <server> <tool> [args...]")

      [_server] ->
        show_error("Usage: /tool <server> <tool> [args...]")

      [server, tool | tool_args] ->
        execute_tool(server, tool, tool_args)
    end
  end

  # Resource commands

  defp list_resources() do
    servers = ServerManager.list_servers()

    if Enum.empty?(servers) do
      show_info("No MCP servers connected")
    else
      all_resources =
        servers
        |> Enum.filter(fn %{status: status} -> status == :connected end)
        |> Enum.flat_map(fn %{name: server_name} ->
          # Get resources for this server
          case get_server_resources(server_name) do
            {:ok, resources} ->
              Enum.map(resources, &{server_name, &1})

            _ ->
              []
          end
        end)

      if Enum.empty?(all_resources) do
        show_info("No resources available from connected servers")
      else
        show_info("Available MCP resources:")

        all_resources
        |> Enum.group_by(fn {server, _} -> server end)
        |> Enum.each(fn {server, resources} ->
          IO.puts("\n#{server}:")

          Enum.each(resources, fn {_, resource} ->
            IO.puts("  • #{resource["uri"]} - #{resource["name"]}")

            if resource["description"] do
              IO.puts("    #{resource["description"]}")
            end
          end)
        end)
      end
    end

    :ok
  end

  defp read_resource(args) do
    case args do
      [] ->
        show_error("Usage: /resource <server> <uri>")

      [_server] ->
        show_error("Usage: /resource <server> <uri>")

      [server | uri_parts] ->
        uri = Enum.join(uri_parts, " ")

        case ServerManager.read_resource(server, uri) do
          {:ok, content} ->
            display_resource_content(content)

          {:error, reason} ->
            show_error("Failed to read resource: #{inspect(reason)}")
        end
    end
  end

  # Prompt commands

  defp list_prompts() do
    servers = ServerManager.list_servers()

    if Enum.empty?(servers) do
      show_info("No MCP servers connected")
    else
      all_prompts =
        servers
        |> Enum.filter(fn %{status: status} -> status == :connected end)
        |> Enum.flat_map(fn %{name: server_name} ->
          # Get prompts for this server
          case get_server_prompts(server_name) do
            {:ok, prompts} ->
              Enum.map(prompts, &{server_name, &1})

            _ ->
              []
          end
        end)

      if Enum.empty?(all_prompts) do
        show_info("No prompts available from connected servers")
      else
        show_info("Available MCP prompts:")

        all_prompts
        |> Enum.group_by(fn {server, _} -> server end)
        |> Enum.each(fn {server, prompts} ->
          IO.puts("\n#{server}:")

          Enum.each(prompts, fn {_, prompt} ->
            IO.puts("  • #{prompt["name"]} - #{prompt["description"]}")
          end)
        end)
      end
    end

    :ok
  end

  defp get_prompt(args) do
    case args do
      [] ->
        show_error("Usage: /prompt <server> <name> [arg1=value1 arg2=value2 ...]")

      [_server] ->
        show_error("Usage: /prompt <server> <name> [arg1=value1 arg2=value2 ...]")

      [server, name | arg_pairs] ->
        # Parse arguments
        arguments = parse_prompt_arguments(arg_pairs)

        case ServerManager.get_prompt(server, name, arguments) do
          {:ok, result} ->
            display_prompt_result(result)

          {:error, reason} ->
            show_error("Failed to get prompt: #{inspect(reason)}")
        end
    end
  end

  # Helper functions

  defp connect_quick_setup_server(name) do
    quick_servers = Discovery.quick_setup_servers()

    case Enum.find(quick_servers, &(&1.name == name)) do
      nil ->
        show_error("Unknown server: #{name}")
        show_info("Use /discover to see available servers")

      %{status: :missing_requirements, missing: missing} ->
        show_error("Server #{name} requires: #{Enum.join(missing, ", ")}")
        show_info("Set these environment variables and try again")

      server ->
        show_info("Connecting to #{server.name}...")

        case ServerManager.start_server(server) do
          {:ok, _} ->
            show_success("Connected to #{server.name}")
            ServerPersistence.save_server(server)

          {:error, reason} ->
            show_error("Failed to connect: #{inspect(reason)}")
        end
    end
  end

  defp connect_custom_server(args) do
    # Parse environment variables
    {args, env} = parse_env_args(args)

    if Enum.empty?(args) do
      show_error("No command specified")
    else
      name = generate_server_name(args)

      server_config = %{
        name: name,
        command: args,
        env: env
      }

      show_info("Connecting to custom server...")

      case ServerManager.start_server(server_config) do
        {:ok, _} ->
          show_success("Connected to #{name}")
          ServerPersistence.save_server(server_config)

        {:error, reason} ->
          show_error("Failed to connect: #{inspect(reason)}")
      end
    end
  end

  defp parse_env_args(args) do
    # Split args into command args and env args
    # --env KEY=VALUE can appear anywhere in the args
    {cmd_args, env_pairs} =
      args
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
      |> Enum.reduce({[], []}, fn
        {:env, kv}, {cmd, env} ->
          case String.split(kv, "=", parts: 2) do
            [key, value] -> {cmd, [{key, value} | env]}
            _ -> {cmd, env}
          end

        list, {cmd, env} when is_list(list) ->
          {cmd ++ list, env}
      end)

    env = Map.new(Enum.reverse(env_pairs))
    {cmd_args, env}
  end

  defp generate_server_name([cmd | _]) do
    Path.basename(cmd)
    |> String.replace(~r/\.(js|py|rb|go|rs)$/, "")
  end

  defp execute_tool(server, tool, args) do
    # Check for --progress flag
    {args, with_progress} =
      case List.last(args) do
        "--progress" -> {List.delete_at(args, -1), true}
        _ -> {args, false}
      end

    # Parse arguments - could be JSON or key=value pairs
    arguments = parse_tool_arguments(args)

    show_info("Executing #{tool} on #{server}...")

    # Call with progress tracking if requested
    result =
      if with_progress do
        case ServerManager.get_server(server) do
          {:ok, %{client: client}} ->
            MCPChat.MCP.NotificationClient.call_tool(client, tool, arguments, with_progress: true)

          error ->
            error
        end
      else
        ServerManager.call_tool(server, tool, arguments)
      end

    case result do
      {:ok, result} ->
        display_tool_result(result)

      {:error, reason} ->
        show_error("Tool execution failed: #{inspect(reason)}")
    end
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

  defp parse_prompt_arguments(args) do
    args
    |> Enum.map(&String.split(&1, "=", parts: 2))
    |> Enum.filter(&(length(&1) == 2))
    |> Map.new(fn [k, v] -> {k, v} end)
  end

  defp display_tool_result(result) do
    case result do
      %{"content" => content} when is_list(content) ->
        Enum.each(content, &display_content_item/1)

      %{"error" => error} ->
        show_error("Tool error: #{inspect(error)}")

      _ ->
        IO.puts(Jason.encode!(result, pretty: true))
    end
  end

  defp display_resource_content(content) when is_list(content) do
    Enum.each(content, &display_content_item/1)
  end

  defp display_resource_content(content) do
    IO.puts(inspect(content))
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

  defp display_prompt_result(%{"template" => template, "arguments" => args}) do
    IO.puts("Template:")
    IO.puts(template)

    if args && Enum.any?(args) do
      IO.puts("\nArguments:")

      Enum.each(args, fn arg ->
        required = if arg["required"], do: " (required)", else: ""
        IO.puts("  • #{arg["name"]}#{required}: #{arg["description"]}")
      end)
    end
  end

  defp display_prompt_result(result) do
    IO.puts(Jason.encode!(result, pretty: true))
  end

  # Helper functions to get server-specific data

  defp get_server_tools(server_name) do
    ServerManager.get_tools(server_name)
  end

  defp get_server_resources(server_name) do
    ServerManager.get_resources(server_name)
  end

  defp get_server_prompts(server_name) do
    ServerManager.get_prompts(server_name)
  end
end
