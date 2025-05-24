defmodule MCPChat.CLI.Commands do
  @moduledoc """
  CLI command handling for the chat interface.
  """

  require Logger

  alias MCPChat.{Session, Config}
  alias MCPChat.CLI.Renderer

  @commands %{
    "help" => "Show available commands",
    "clear" => "Clear the screen",
    "history" => "Show conversation history",
    "new" => "Start a new conversation",
    "save" => "Save current session (usage: /save [name])",
    "load" => "Load a saved session (usage: /load <name|id>)",
    "sessions" => "List saved sessions",
    "config" => "Show current configuration",
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
    "prompt" => "Get an MCP prompt (usage: /prompt <server> <name>)",
    "backend" => "Switch LLM backend (usage: /backend <name>)",
    "model" => "Switch model (usage: /model <name>)",
    "models" => "List available models for current backend",
    "loadmodel" => "Load a local model (usage: /loadmodel <model-id|path>)",
    "unloadmodel" => "Unload a local model (usage: /unloadmodel <model-id>)",
    "acceleration" => "Show hardware acceleration info",
    "export" => "Export conversation (usage: /export [format] [path])",
    "context" => "Show context statistics",
    "system" => "Set system prompt (usage: /system <prompt>)",
    "tokens" => "Set max tokens (usage: /tokens <number>)",
    "strategy" => "Set context strategy (usage: /strategy <sliding_window|smart>)",
    "cost" => "Show session cost",
    "alias" => "Manage command aliases (usage: /alias [add|remove|list] ...)"
  }

  def handle_command(command) do
    [cmd | args] = String.split(command, " ", parts: 2)
    args = List.wrap(args)

    # Check if it's an alias first
    if MCPChat.Alias.is_alias?(cmd) do
      handle_alias(cmd, args)
    else
      case cmd do
        "help" -> show_help()
        "clear" -> clear_screen()
        "history" -> show_history()
        "new" -> new_conversation()
        "save" -> save_session(args)
        "load" -> load_session(args)
        "sessions" -> list_sessions()
        "config" -> show_config()
        "servers" -> list_servers()
        "saved" -> list_saved_servers()
        "discover" -> discover_servers()
        "connect" -> connect_server(args)
        "disconnect" -> disconnect_server(args)
        "tools" -> list_tools()
        "tool" -> call_tool(args)
        "resources" -> list_resources()
        "resource" -> read_resource(args)
        "prompts" -> list_prompts()
        "prompt" -> get_prompt(args)
        "backend" -> switch_backend(args)
        "model" -> switch_model(args)
        "models" -> list_models()
        "loadmodel" -> load_model(args)
        "unloadmodel" -> unload_model(args)
        "acceleration" -> show_acceleration_info()
        "export" -> export_conversation(args)
        "context" -> show_context_stats()
        "system" -> set_system_prompt(args)
        "tokens" -> set_max_tokens(args)
        "strategy" -> set_strategy(args)
        "cost" -> show_session_cost()
        "alias" -> handle_alias_command(args)
        "exit" -> :exit
        "quit" -> :exit
        _ -> Renderer.show_error("Unknown command: /#{cmd}")
      end
    end
  end

  defp show_help() do
    rows =
      @commands
      |> Enum.map(fn {cmd, desc} ->
        %{"Command" => "/#{cmd}", "Description" => desc}
      end)
      |> Enum.sort_by(&Map.get(&1, "Command"))

    Renderer.show_table(["Command", "Description"], rows)
  end

  defp clear_screen() do
    Renderer.clear_screen()
  end

  defp show_history() do
    messages = Session.get_messages()

    if Enum.empty?(messages) do
      Renderer.show_info("No messages in history")
    else
      Enum.each(messages, fn msg ->
        role = String.capitalize(msg.role)

        color =
          case msg.role do
            "user" -> :cyan
            "assistant" -> :green
            _ -> :yellow
          end

        Owl.IO.puts([
          "\n",
          Owl.Data.tag(role, color),
          Owl.Data.tag(" › ", :light_black),
          msg.content
        ])
      end)
    end
  end

  defp new_conversation() do
    Session.new_session()
    Renderer.show_info("Started new conversation")
  end

  defp show_config() do
    config = %{
      "LLM Backend" => Session.get_current_session().llm_backend,
      "Model" => get_current_model(),
      "MCP Servers" => length(MCPChat.MCP.ServerManager.list_servers()),
      "Streaming" => Config.get([:ui, :streaming]) != false
    }

    rows = Enum.map(config, fn {k, v} -> %{"Setting" => k, "Value" => to_string(v)} end)
    Renderer.show_table(["Setting", "Value"], rows)
  end

  defp list_servers() do
    servers = MCPChat.MCP.ServerManager.list_servers()

    if Enum.empty?(servers) do
      Renderer.show_info("No MCP servers connected")
    else
      rows =
        Enum.map(servers, fn server ->
          %{
            "Name" => server.name,
            "Status" => to_string(server.status),
            "Port" => to_string(server.port || "stdio")
          }
        end)

      Renderer.show_table(["Name", "Status", "Port"], rows)
    end
  end

  defp list_saved_servers() do
    saved_servers = MCPChat.MCP.ServerPersistence.load_all_servers()

    if Enum.empty?(saved_servers) do
      Renderer.show_info("No saved MCP server connections")
    else
      connected_servers = MCPChat.MCP.ServerManager.list_servers()
      connected_names = MapSet.new(connected_servers, & &1.name)

      rows =
        Enum.map(saved_servers, fn server ->
          is_connected = MapSet.member?(connected_names, server["name"])

          %{
            "Name" => server["name"],
            "Transport" => if(server["url"], do: "SSE", else: "stdio"),
            "Auto-connect" => if(server["auto_connect"], do: "✓", else: ""),
            "Connected" => if(is_connected, do: "✓", else: "")
          }
        end)

      Renderer.show_table(["Name", "Transport", "Auto-connect", "Connected"], rows)
    end
  end

  defp discover_servers() do
    Renderer.show_thinking()
    Renderer.show_info("Discovering MCP servers...")

    discovered = MCPChat.MCP.Discovery.discover_servers()

    if discovered == [] do
      Renderer.show_info("No MCP servers discovered")
      Renderer.show_text("")
      Renderer.show_text("You can install MCP servers using:")
      Renderer.show_text("  npm install -g @modelcontextprotocol/server-filesystem")
      Renderer.show_text("  npm install -g @modelcontextprotocol/server-github")
      Renderer.show_text("")
      Renderer.show_text("Or configure servers manually in ~/.config/mcp_chat/config.toml")
    else
      # Show discovered servers
      rows =
        Enum.map(discovered, fn server ->
          base = %{
            "Name" => server.name,
            "Source" => to_string(server.source),
            "Type" => if(server[:command], do: "stdio", else: "sse")
          }

          # Add status for quick setup servers
          if server[:status] == :missing_requirements do
            Map.merge(base, %{
              "Status" => "Missing: #{Enum.join(server.missing, ", ")}",
              "Description" => server[:description] || ""
            })
          else
            Map.merge(base, %{
              "Status" => "Available",
              "Description" => server[:description] || format_server_location(server)
            })
          end
        end)

      # Adjust columns based on source type
      columns =
        if Enum.any?(discovered, &(&1.source == :quick_setup)) do
          ["Name", "Source", "Type", "Status", "Description"]
        else
          ["Name", "Source", "Type", "Status", "Description"]
        end

      Renderer.show_table(columns, rows)

      # Ask if user wants to connect any
      Renderer.show_text("")
      Renderer.show_info("You can:")
      Renderer.show_text("  1. Connect now: /connect <server-name>")
      Renderer.show_text("  2. Add to config: Edit ~/.config/mcp_chat/config.toml")

      # Store discovered servers temporarily for connection
      Process.put(:discovered_servers, Map.new(discovered, &{&1.name, &1}))

      # Show example configuration
      if server = List.first(discovered) do
        Renderer.show_text("")
        Renderer.show_text("Example configuration for config.toml:")
        Renderer.show_code(format_server_config(server))
      end
    end
  end

  defp format_server_location(%{command: [cmd | args]}) do
    "#{cmd} #{Enum.join(args, " ")}" |> String.trim()
  end

  defp format_server_location(%{url: url}), do: url
  defp format_server_location(_), do: "unknown"

  defp format_server_config(%{command: command} = server) do
    env_part =
      if server[:env] do
        server.env
        |> Enum.map_join(fn {k, v} -> "#{k} = \"#{v}\"" end, ", ")
        |> then(&" { #{&1} }")
      else
        ""
      end

    """
    [[mcp.servers]]
    name = "#{server.name}"
    command = #{inspect(command)}#{if env_part != "", do: "\nenv =#{env_part}", else: ""}
    """
  end

  defp format_server_config(%{url: url} = server) do
    """
    [[mcp.servers]]
    name = "#{server.name}"
    url = "#{url}"
    """
  end

  defp connect_server([name]) do
    # Check if it's a discovered server
    discovered = Process.get(:discovered_servers, %{})

    server_config =
      case Map.get(discovered, name) do
        nil ->
          # Try to find in config
          case MCPChat.Config.get([:mcp, :servers]) do
            servers when is_list(servers) ->
              Enum.find(servers, fn s -> s[:name] == name end)

            _ ->
              nil
          end

        config ->
          config
      end

    if server_config do
      Renderer.show_info("Connecting to #{name}...")

      case MCPChat.MCP.ServerManager.start_server(server_config) do
        {:ok, _pid} ->
          Renderer.show_info("Successfully connected to #{name}")

          # Save the server configuration for auto-reconnect
          save_config = normalize_server_config(server_config)
          MCPChat.MCP.ServerPersistence.save_server(save_config)

        {:error, {:already_started, _}} ->
          Renderer.show_info("Server #{name} is already connected")

        {:error, reason} ->
          Renderer.show_error("Failed to connect: #{inspect(reason)}")
      end
    else
      Renderer.show_error("Server '#{name}' not found. Run /discover first or check your config.")
    end
  end

  defp connect_server(_) do
    Renderer.show_error("Usage: /connect <server-name>")
  end

  defp disconnect_server([name]) do
    case MCPChat.MCP.ServerManager.stop_server(name) do
      :ok ->
        Renderer.show_info("Disconnected from #{name}")

        # Remove from persistent storage
        MCPChat.MCP.ServerPersistence.remove_server(name)

      {:error, :not_found} ->
        Renderer.show_error("Server '#{name}' is not connected")

      {:error, reason} ->
        Renderer.show_error("Failed to disconnect: #{inspect(reason)}")
    end
  end

  defp disconnect_server(_) do
    Renderer.show_error("Usage: /disconnect <server-name>")
  end

  defp list_tools() do
    tools = MCPChat.MCP.ServerManager.list_all_tools()

    if Enum.empty?(tools) do
      Renderer.show_info("No MCP tools available")
    else
      # Group tools by server for better display
      tools_by_server = Enum.group_by(tools, &Map.get(&1, :server, "unknown"))

      Enum.each(tools_by_server, fn {server, server_tools} ->
        Renderer.show_info("Server: #{server}")

        # Display tools in a more readable format
        Enum.each(server_tools, fn tool ->
          name = Map.get(tool, "name", "unnamed")
          desc = Map.get(tool, "description", "")

          # Format as a definition list with colored name
          IO.puts("")
          IO.puts("  " <> IO.ANSI.cyan() <> name <> IO.ANSI.reset())
          IO.puts("    #{desc}")
        end)
      end)
    end
  end

  defp list_resources() do
    resources = MCPChat.MCP.ServerManager.list_all_resources()

    if Enum.empty?(resources) do
      Renderer.show_info("No MCP resources available")
    else
      rows =
        Enum.map(resources, fn resource ->
          %{
            "Server" => Map.get(resource, :server, "unknown"),
            "URI" => Map.get(resource, "uri", ""),
            "Name" => Map.get(resource, "name", "unnamed")
          }
        end)

      Renderer.show_table(["Server", "URI", "Name"], rows)
    end
  end

  defp list_prompts() do
    prompts = MCPChat.MCP.ServerManager.list_all_prompts()

    if Enum.empty?(prompts) do
      Renderer.show_info("No MCP prompts available")
    else
      rows =
        Enum.map(prompts, fn prompt ->
          %{
            "Server" => Map.get(prompt, :server, "unknown"),
            "Name" => Map.get(prompt, "name", "unnamed"),
            "Description" => Map.get(prompt, "description", "")
          }
        end)

      Renderer.show_table(["Server", "Name", "Description"], rows)
    end
  end

  defp switch_backend([backend]) do
    backends = ["anthropic", "openai", "local", "ollama"]

    if backend in backends do
      Session.new_session(backend)
      Renderer.show_info("Switched to #{backend} backend")
    else
      Renderer.show_error("Invalid backend. Available: #{Enum.join(backends, ", ")}")
    end
  end

  defp switch_backend(_) do
    Renderer.show_error("Usage: /backend <name>")
  end

  defp switch_model([model]) do
    # TODO: Validate model against current backend
    Session.set_context(%{model: model})
    Renderer.show_info("Switched to model: #{model}")
  end

  defp switch_model(_) do
    Renderer.show_error("Usage: /model <name>")
  end

  defp export_conversation([format]) do
    export_conversation_with_format(format)
  end

  defp export_conversation([]) do
    export_conversation_with_format("markdown")
  end

  defp export_conversation_with_format(format) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)
    filename = "chat_export_#{timestamp}.#{format}"

    format_atom =
      case format do
        "markdown" ->
          :markdown

        "json" ->
          :json

        _ ->
          Renderer.show_error("Unknown format. Available: markdown, json")
          nil
      end

    if format_atom do
      case Session.export_session(format_atom, filename) do
        {:ok, path} -> Renderer.show_info("Exported to #{path}")
        {:error, reason} -> Renderer.show_error("Export failed: #{inspect(reason)}")
      end
    end
  end

  defp show_context_stats() do
    stats = Session.get_context_stats()
    session = Session.get_current_session()

    Renderer.show_info("Context Statistics:")
    Renderer.show_text("  Messages: #{stats.message_count}")

    Renderer.show_text(
      "  Estimated tokens: #{stats.estimated_tokens}/#{stats.max_tokens} (#{stats.tokens_used_percentage}%)"
    )

    Renderer.show_text("  Tokens remaining: #{stats.tokens_remaining}")

    # Calculate estimated cost for next message
    # Get prepared messages that would actually be sent
    prepared_messages = Session.get_messages_for_llm()
    input_tokens = MCPChat.Context.estimate_tokens(prepared_messages)

    # Estimate output tokens (assume ~30% of input tokens as a reasonable estimate)
    estimated_output_tokens = round(input_tokens * 0.3)

    # Calculate cost
    # First check context for model override, then use default
    model = session.context[:model] || get_current_model()
    pricing = MCPChat.Cost.get_pricing(session.llm_backend, model)

    if pricing do
      input_cost = input_tokens / 1_000_000 * pricing.input
      output_cost = estimated_output_tokens / 1_000_000 * pricing.output
      total_cost = input_cost + output_cost

      Renderer.show_text("")
      Renderer.show_text("  Estimated cost for next message:")
      Renderer.show_text("    Input: ~#{input_tokens} tokens (#{MCPChat.Cost.format_cost(input_cost)})")
      Renderer.show_text("    Output: ~#{estimated_output_tokens} tokens (#{MCPChat.Cost.format_cost(output_cost)})")
      Renderer.show_text("    Total: ~#{MCPChat.Cost.format_cost(total_cost)}")
    end

    # Show warning if approaching limit
    if stats.tokens_used_percentage > 80 do
      Renderer.show_warning("Context is #{stats.tokens_used_percentage}% full. Older messages may be truncated.")
    end
  end

  defp set_system_prompt([prompt]) do
    config = %{system_prompt: prompt}
    Session.update_context_config(config)
    Renderer.show_info("System prompt set")
  end

  defp set_system_prompt([]) do
    # Clear system prompt
    config = %{system_prompt: nil}
    Session.update_context_config(config)
    Renderer.show_info("System prompt cleared")
  end

  defp set_max_tokens([tokens_str]) do
    case Integer.parse(tokens_str) do
      {tokens, _} when tokens > 0 ->
        config = %{max_tokens: tokens}
        Session.update_context_config(config)
        Renderer.show_info("Max tokens set to #{tokens}")

      _ ->
        Renderer.show_error("Invalid token count. Please provide a positive number.")
    end
  end

  defp set_max_tokens(_) do
    Renderer.show_error("Usage: /tokens <number>")
  end

  defp set_strategy([strategy]) when strategy in ["sliding_window", "smart"] do
    atom_strategy = String.to_atom(strategy)
    config = %{strategy: atom_strategy}
    Session.update_context_config(config)
    Renderer.show_info("Context strategy set to #{strategy}")
  end

  defp set_strategy(_) do
    Renderer.show_error("Usage: /strategy <sliding_window|smart>")
  end

  defp show_session_cost() do
    cost_info = Session.get_session_cost()

    if cost_info[:error] do
      Renderer.show_error(cost_info.error)
    else
      Renderer.show_info("Session Cost Summary")
      Renderer.show_text("  Model: #{cost_info.backend}/#{cost_info.model}")
      Renderer.show_text("  Input tokens: #{cost_info.input_tokens}")
      Renderer.show_text("  Output tokens: #{cost_info.output_tokens}")
      Renderer.show_text("  Total tokens: #{cost_info.total_tokens}")
      Renderer.show_text("")
      Renderer.show_text("  Input cost: #{MCPChat.Cost.format_cost(cost_info.input_cost)}")
      Renderer.show_text("  Output cost: #{MCPChat.Cost.format_cost(cost_info.output_cost)}")
      Renderer.show_text("  Total cost: #{MCPChat.Cost.format_cost(cost_info.total_cost)}")

      if cost_info.pricing do
        Renderer.show_text("")
        Renderer.show_text("  Pricing: $#{cost_info.pricing.input}/1M input, $#{cost_info.pricing.output}/1M output")
      end
    end
  end

  defp handle_alias_command([]) do
    # Default to list if no subcommand
    handle_alias_command(["list"])
  end

  defp handle_alias_command([subcommand | rest]) do
    case subcommand do
      "add" -> add_alias(rest)
      "remove" -> remove_alias(rest)
      "list" -> list_aliases()
      _ -> Renderer.show_error("Unknown alias subcommand. Use: add, remove, or list")
    end
  end

  defp add_alias([definition]) do
    # Parse alias definition: name=command1;command2;command3
    case String.split(definition, "=", parts: 2) do
      [name, commands_str] ->
        commands =
          commands_str
          |> String.split(";")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        case MCPChat.Alias.define_alias(name, commands) do
          :ok ->
            Renderer.show_info("Alias '#{name}' created with #{length(commands)} command(s)")

          {:error, reason} ->
            Renderer.show_error("Failed to create alias: #{reason}")
        end

      _ ->
        Renderer.show_error("Invalid alias format. Use: /alias add name=command1;command2")
    end
  end

  defp add_alias(_) do
    Renderer.show_error("Usage: /alias add name=command1;command2;...")
  end

  defp remove_alias([name]) do
    case MCPChat.Alias.remove_alias(name) do
      :ok ->
        Renderer.show_info("Alias '#{name}' removed")

      {:error, reason} ->
        Renderer.show_error("Failed to remove alias: #{reason}")
    end
  end

  defp remove_alias(_) do
    Renderer.show_error("Usage: /alias remove <name>")
  end

  defp list_aliases() do
    aliases = MCPChat.Alias.list_aliases()

    if aliases == [] do
      Renderer.show_info("No aliases defined")
      Renderer.show_text("")
      Renderer.show_text("Create an alias with: /alias add name=command1;command2")
    else
      Renderer.show_info("Defined aliases:")

      aliases
      |> Enum.each(fn %{name: name, commands: commands} ->
        Renderer.show_text("")
        Renderer.show_text("  /#{name}")

        commands
        |> Enum.each(fn cmd ->
          Renderer.show_text("    → #{cmd}")
        end)
      end)

      Renderer.show_text("")
      Renderer.show_text("Total: #{length(aliases)} alias(es)")
    end
  end

  defp handle_alias(alias_name, args) do
    case MCPChat.Alias.expand_alias(alias_name) do
      {:ok, commands} ->
        # Execute each command in sequence
        Renderer.show_info("Executing alias '#{alias_name}'...")

        results =
          commands
          |> Enum.map(fn cmd ->
            # Substitute arguments if command contains $1, $2, etc.
            expanded_cmd = expand_alias_arguments(cmd, args)

            # Show the command being executed
            Renderer.show_text("  → #{expanded_cmd}")

            # Execute the command
            if String.starts_with?(expanded_cmd, "/") do
              # Remove leading slash and execute
              handle_command(String.slice(expanded_cmd, 1..-1//1))
            else
              # It's a regular message
              {:message, expanded_cmd}
            end
          end)

        # Return any messages that should be sent to the LLM
        messages =
          results
          |> Enum.filter(fn
            {:message, _} -> true
            _ -> false
          end)
          |> Enum.map(fn {:message, text} -> text end)

        case messages do
          [] -> :ok
          [msg] -> {:message, msg}
          msgs -> {:message, Enum.join(msgs, "\n")}
        end

      {:error, reason} ->
        Renderer.show_error(reason)
    end
  end

  defp expand_alias_arguments(command, args) do
    # Replace $1, $2, etc. with actual arguments
    # Also support $* for all arguments
    arg_list =
      case args do
        [] -> []
        [arg_string] -> String.split(arg_string, " ")
      end

    command
    |> String.replace("$*", Enum.join(arg_list, " "))
    |> then(fn cmd ->
      Enum.with_index(arg_list, 1)
      |> Enum.reduce(cmd, fn {arg, index}, acc ->
        String.replace(acc, "$#{index}", arg)
      end)
    end)
  end

  defp get_current_model() do
    session = Session.get_current_session()
    backend = session.llm_backend

    case backend do
      "anthropic" -> Config.get([:llm, :anthropic, :model]) || "claude-sonnet-4-20_250_514"
      "openai" -> Config.get([:llm, :openai, :model]) || "gpt-4"
      "local" -> Config.get([:llm, :local, :model_path]) || "none"
      "ollama" -> Config.get([:llm, :ollama, :model]) || "llama2"
      _ -> "unknown"
    end
  end

  defp call_tool([args_string]) do
    case String.split(args_string, " ", parts: 3) do
      [server_name, tool_name | rest] ->
        # Parse arguments - try JSON first, then treat as string
        arguments =
          case rest do
            [] ->
              %{}

            [json_args] ->
              case Jason.decode(json_args) do
                {:ok, args} -> args
                # Wrap string as input
                {:error, _} -> %{"input" => json_args}
              end
          end

        Renderer.show_thinking()

        case MCPChat.MCP.ServerManager.call_tool(server_name, tool_name, arguments) do
          {:ok, result} ->
            Renderer.show_info("Tool result:")

            case result do
              %{"content" => content} when is_list(content) ->
                Enum.each(content, &display_content_item/1)

              %{"content" => content} ->
                Renderer.show_code(inspect(content, pretty: true))

              %{"text" => text} ->
                Renderer.show_text(text)

              _ ->
                Renderer.show_code(inspect(result, pretty: true))
            end

          {:error, reason} ->
            Renderer.show_error("Failed to call tool: #{inspect(reason)}")
        end

      _ ->
        Renderer.show_error("Usage: /tool <server> <tool> [arguments]")
        Renderer.show_info("Arguments can be JSON object or plain text")
    end
  end

  defp call_tool(_), do: Renderer.show_error("Usage: /tool <server> <tool> [arguments]")

  defp display_content_item(%{"type" => "text", "text" => text}) do
    Renderer.show_text(text)
  end

  defp display_content_item(%{"type" => "image", "data" => data, "mimeType" => mime}) do
    Renderer.show_info("Image (#{mime}): #{String.slice(data, 0, 50)}...")
  end

  defp display_content_item(item) do
    Renderer.show_code(inspect(item, pretty: true))
  end

  defp read_resource([args_string]) do
    case String.split(args_string, " ", parts: 2) do
      [server_name, uri] ->
        Renderer.show_thinking()

        case MCPChat.MCP.ServerManager.read_resource(server_name, uri) do
          {:ok, contents} when is_list(contents) ->
            Renderer.show_info("Resource contents:")
            Enum.each(contents, &display_content_item/1)

          {:ok, result} ->
            Renderer.show_info("Resource contents:")
            Renderer.show_code(inspect(result, pretty: true))

          {:error, reason} ->
            Renderer.show_error("Failed to read resource: #{inspect(reason)}")
        end

      _ ->
        Renderer.show_error("Usage: /resource <server> <uri>")
    end
  end

  defp read_resource(_), do: Renderer.show_error("Usage: /resource <server> <uri>")

  defp get_prompt([args_string]) do
    case String.split(args_string, " ", parts: 3) do
      [server_name, prompt_name | rest] ->
        # Parse arguments
        arguments =
          case rest do
            [] ->
              %{}

            [json_args] ->
              case Jason.decode(json_args) do
                {:ok, args} -> args
                {:error, _} -> %{}
              end
          end

        Renderer.show_thinking()

        case MCPChat.MCP.ServerManager.get_prompt(server_name, prompt_name, arguments) do
          {:ok, messages} when is_list(messages) ->
            Renderer.show_info("Prompt messages:")

            Enum.each(messages, fn msg ->
              role = Map.get(msg, "role", "unknown")
              content = Map.get(msg, "content", "")
              Renderer.show_text("#{String.upcase(role)}: #{content}")
            end)

          {:ok, result} ->
            Renderer.show_info("Prompt result:")
            Renderer.show_code(inspect(result, pretty: true))

          {:error, reason} ->
            Renderer.show_error("Failed to get prompt: #{inspect(reason)}")
        end

      _ ->
        Renderer.show_error("Usage: /prompt <server> <name> [arguments]")
    end
  end

  defp get_prompt(_), do: Renderer.show_error("Usage: /prompt <server> <name> [arguments]")

  defp save_session([]) do
    save_session_with_name(nil)
  end

  defp save_session([name]) do
    save_session_with_name(name)
  end

  defp save_session_with_name(name) do
    case Session.save_session(name) do
      {:ok, path} ->
        Renderer.show_info("Session saved to: #{path}")

      {:error, reason} ->
        Renderer.show_error("Failed to save session: #{inspect(reason)}")
    end
  end

  defp load_session([identifier]) do
    case Session.load_session(identifier) do
      {:ok, session} ->
        Renderer.show_info("Loaded session: #{session.id}")
        Renderer.show_info("Created: #{format_datetime(session.created_at)}")
        Renderer.show_info("Messages: #{length(session.messages)}")

      {:error, :not_found} ->
        Renderer.show_error("Session not found: #{identifier}")

      {:error, reason} ->
        Renderer.show_error("Failed to load session: #{inspect(reason)}")
    end
  end

  defp load_session(_) do
    Renderer.show_error("Usage: /load <name|id>")
  end

  defp list_sessions() do
    case Session.list_saved_sessions() do
      {:ok, sessions} ->
        if Enum.empty?(sessions) do
          Renderer.show_info("No saved sessions found")
        else
          rows =
            Enum.map(sessions, fn session ->
              %{
                "Name/ID" => String.slice(session.filename || session.id, 0, 30),
                "Backend" => session.llm_backend,
                "Messages" => to_string(session.message_count),
                "Updated" => format_relative_time(session.updated_at)
              }
            end)

          Renderer.show_table(["Name/ID", "Backend", "Messages", "Updated"], rows)
        end

      {:error, reason} ->
        Renderer.show_error("Failed to list sessions: #{inspect(reason)}")
    end
  end

  defp format_datetime(datetime) do
    datetime
    |> DateTime.to_naive()
    |> NaiveDateTime.to_string()
  end

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3_600 -> "#{div(diff, 60)} min ago"
      diff < 86_400 -> "#{div(diff, 3_600)} hours ago"
      diff < 604_800 -> "#{div(diff, 86_400)} days ago"
      true -> DateTime.to_date(datetime) |> Date.to_string()
    end
  end

  defp list_models() do
    backend = Session.get_current_session().llm_backend

    case backend do
      "anthropic" ->
        fetch_and_display_models(MCPChat.LLM.Anthropic, backend)

      "openai" ->
        fetch_and_display_models(MCPChat.LLM.OpenAI, backend)

      "local" ->
        fetch_and_display_local_models()

      "ollama" ->
        fetch_and_display_models(MCPChat.LLM.Ollama, backend)

      _ ->
        Renderer.show_error("Unknown backend: #{backend}")
    end
  end

  defp fetch_and_display_models(adapter, backend_name) do
    Renderer.show_thinking()
    Renderer.show_info("Fetching available models...")

    case adapter.list_models() do
      {:ok, models} when is_list(models) and models != [] ->
        current_model = get_current_model()

        # Handle both map and string formats
        rows =
          Enum.map(models, fn
            model when is_map(model) ->
              %{
                "Model ID" => model.id || model[:id],
                "Name" => model.name || model[:name] || model.id || model[:id],
                "Current" => if((model.id || model[:id]) == current_model, do: "✓", else: "")
              }

            model when is_binary(model) ->
              %{
                "Model ID" => model,
                "Name" => model,
                "Current" => if(model == current_model, do: "✓", else: "")
              }
          end)

        Renderer.show_table(["Model ID", "Name", "Current"], rows)

      {:ok, []} ->
        Renderer.show_info("No models available for #{backend_name}")

      {:error, reason} ->
        Renderer.show_error("Failed to fetch models: #{inspect(reason)}")
    end
  end

  defp fetch_and_display_local_models() do
    case MCPChat.LLM.Local.list_models() do
      {:ok, models} when is_list(models) and models != [] ->
        current_model = get_current_model()

        rows =
          Enum.map(models, fn model ->
            status_indicator =
              case model.status do
                "loaded" -> " (loaded)"
                _ -> ""
              end

            %{
              "Model ID" => model.id,
              "Name" => model.name <> status_indicator,
              "Acceleration" => model[:acceleration] || "Unknown",
              "Current" => if(model.id == current_model, do: "✓", else: "")
            }
          end)

        Renderer.show_table(["Model ID", "Name", "Acceleration", "Current"], rows)

      {:ok, []} ->
        Renderer.show_info("No local models available")

      {:error, reason} ->
        Renderer.show_error("Failed to list local models: #{inspect(reason)}")
    end
  end

  defp load_model([model_id]) do
    backend = Session.get_current_session().llm_backend

    if backend != "local" do
      Renderer.show_error("Model loading is only available for the local backend")
    else
      Renderer.show_thinking()
      Renderer.show_info("Loading model: #{model_id}")

      case MCPChat.LLM.ModelLoader.load_model(model_id) do
        {:ok, _model_info} ->
          # Get acceleration info
          acc_info = MCPChat.LLM.ModelLoader.get_acceleration_info()
          Renderer.show_success("Model loaded successfully: #{model_id}")
          Renderer.show_info("Using acceleration: #{acc_info.name}")

          # Update current model in config
          Config.put([:llm, :local, :model_path], model_id)
          Session.set_context(%{model: model_id})

        {:error, reason} ->
          Renderer.show_error("Failed to load model: #{inspect(reason)}")
      end
    end
  end

  defp load_model(_) do
    Renderer.show_error("Usage: /loadmodel <model-id|path>")
  end

  defp unload_model([model_id]) do
    backend = Session.get_current_session().llm_backend

    if backend != "local" do
      Renderer.show_error("Model unloading is only available for the local backend")
    else
      case MCPChat.LLM.ModelLoader.unload_model(model_id) do
        :ok ->
          Renderer.show_info("Model unloaded: #{model_id}")

        {:error, :not_loaded} ->
          Renderer.show_error("Model not loaded: #{model_id}")

        {:error, reason} ->
          Renderer.show_error("Failed to unload model: #{inspect(reason)}")
      end
    end
  end

  defp unload_model(_) do
    Renderer.show_error("Usage: /unloadmodel <model-id>")
  end

  defp show_acceleration_info() do
    if Code.ensure_loaded?(MCPChat.LLM.EXLAConfig) do
      acc_info = MCPChat.LLM.EXLAConfig.acceleration_info()

      Renderer.show_info("Hardware Acceleration Info")
      Renderer.show_text("  Type: #{acc_info.name}")

      case acc_info.type do
        :cuda ->
          Renderer.show_text("  Devices: #{acc_info.device_count}")

          if acc_info.memory do
            Renderer.show_text("  Memory: #{acc_info.memory.total_gb} GB")
          end

        :metal ->
          if acc_info.memory do
            Renderer.show_text("  Unified Memory: #{acc_info.memory.total_gb} GB")
          end

          Renderer.show_text("  Backend: #{acc_info.backend}")

        :cpu ->
          Renderer.show_text("  Cores: #{acc_info.cores}")

        _ ->
          :ok
      end

      # Show backend status
      Renderer.show_text("")

      cond do
        Code.ensure_loaded?(EMLX) ->
          Renderer.show_text("  EMLX Status: ✓ Loaded (Apple Silicon optimized)")

          if acc_info.type == :metal do
            Renderer.show_text("  Mixed Precision: Automatic")
            Renderer.show_text("  Memory Optimization: Unified memory")
          end

        Code.ensure_loaded?(EXLA) ->
          Renderer.show_text("  EXLA Status: ✓ Loaded")
          Renderer.show_text("  Mixed Precision: Enabled")
          Renderer.show_text("  Memory Optimization: Enabled")

        true ->
          Renderer.show_text("  Acceleration Status: Not loaded")
          Renderer.show_text("")
          Renderer.show_text("  Install acceleration backends:")
          Renderer.show_text("    mix deps.get             # For EMLX on Apple Silicon")
          Renderer.show_text("    XLA_TARGET=cuda12 mix deps.get  # For NVIDIA GPUs")
          Renderer.show_text("    XLA_TARGET=cpu mix deps.get     # For CPU optimization")
      end
    else
      Renderer.show_info("Acceleration info not available (local backend not initialized)")
    end
  end

  defp normalize_server_config(config) do
    # Convert atom keys to strings for JSON serialization
    config
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {to_string(k), v}
      {k, v} -> {k, v}
    end)
    |> Enum.into(%{})
    |> Map.put("auto_connect", true)
  end
end
