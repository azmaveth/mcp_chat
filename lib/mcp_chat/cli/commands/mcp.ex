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
      "servers" => "List connected MCP servers",
      "saved" => "List saved MCP server connections",
      "discover" => "Discover available MCP servers",
      "connect" => "Connect to an MCP server (usage: /connect <name>)",
      "disconnect" => "Disconnect from an MCP server (usage: /disconnect <name>)",
      "tools" => "List available MCP tools",
      "tool" => "Call an MCP tool (usage: /tool <server> <tool> [args...])",
      "resources" => "List available MCP resources",
      "resource" => "Read an MCP resource (usage: /resource <server> <uri>)",
      "prompts" => "List available MCP prompts",
      "prompt" => "Get an MCP prompt (usage: /prompt <server> <name>)"
    }
  end

  @impl true
  def handle_command("servers", _args), do: list_servers()
  def handle_command("saved", _args), do: list_saved_servers()
  def handle_command("discover", _args), do: discover_servers()
  def handle_command("connect", args), do: connect_server(args)
  def handle_command("disconnect", args), do: disconnect_server(args)
  def handle_command("tools", _args), do: list_tools()
  def handle_command("tool", args), do: call_tool(args)
  def handle_command("resources", _args), do: list_resources()
  def handle_command("resource", args), do: read_resource(args)
  def handle_command("prompts", _args), do: list_prompts()
  def handle_command("prompt", args), do: get_prompt(args)

  def handle_command(cmd, _args) do
    {:error, "Unknown MCP command: #{cmd}"}
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

  defp connect_server(args) do
    case args do
      [] ->
        show_error("Usage: /connect <name> or /connect <command> [args...]")

      [name] ->
        # Try quick setup server first
        connect_quick_setup_server(name)

      _ ->
        # Parse as custom command
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
            {:ok, tools} ->
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

  defp format_capabilities(caps) do
    features = []
    features = if caps["tools"], do: ["tools" | features], else: features
    features = if caps["resources"], do: ["resources" | features], else: features
    features = if caps["prompts"], do: ["prompts" | features], else: features

    if Enum.empty?(features) do
      ""
    else
      "Capabilities: #{Enum.join(features, ", ")}"
    end
  end

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
    {env_args, cmd_args} = Enum.split_while(args, &String.contains?(&1, "--env"))

    env =
      env_args
      |> Enum.flat_map(fn arg ->
        case String.split(arg, "=", parts: 2) do
          ["--env", _] ->
            []

          [key_part, value] ->
            key = String.replace_prefix(key_part, "--env ", "")
            [{key, value}]

          _ ->
            []
        end
      end)
      |> Map.new()

    {cmd_args, env}
  end

  defp generate_server_name([cmd | _]) do
    Path.basename(cmd)
    |> String.replace(~r/\.(js|py|rb|go|rs)$/, "")
  end

  defp execute_tool(server, tool, args) do
    # Parse arguments - could be JSON or key=value pairs
    arguments = parse_tool_arguments(args)

    show_info("Executing #{tool} on #{server}...")

    case ServerManager.call_tool(server, tool, arguments) do
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
    case ServerManager.get_server(server_name) do
      {:ok, server_info} ->
        tools = Map.get(server_info.capabilities || %{}, "tools", [])
        {:ok, tools}

      {:error, _} = error ->
        error
    end
  end

  defp get_server_resources(server_name) do
    case ServerManager.get_server(server_name) do
      {:ok, server_info} ->
        resources = Map.get(server_info.capabilities || %{}, "resources", [])
        {:ok, resources}

      {:error, _} = error ->
        error
    end
  end

  defp get_server_prompts(server_name) do
    case ServerManager.get_server(server_name) do
      {:ok, server_info} ->
        prompts = Map.get(server_info.capabilities || %{}, "prompts", [])
        {:ok, prompts}

      {:error, _} = error ->
        error
    end
  end
end
