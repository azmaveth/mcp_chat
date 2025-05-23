defmodule MCPChat.CLI.Commands do
  @moduledoc """
  CLI command handling for the chat interface.
  """
  
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
    "tools" => "List available MCP tools",
    "tool" => "Call an MCP tool (usage: /tool <server> <tool> [args...])",
    "resources" => "List available MCP resources",
    "resource" => "Read an MCP resource (usage: /resource <server> <uri>)",
    "prompts" => "List available MCP prompts",
    "prompt" => "Get an MCP prompt (usage: /prompt <server> <name>)",
    "backend" => "Switch LLM backend (usage: /backend <name>)",
    "model" => "Switch model (usage: /model <name>)",
    "export" => "Export conversation (usage: /export [format] [path])",
    "context" => "Show context statistics",
    "system" => "Set system prompt (usage: /system <prompt>)",
    "tokens" => "Set max tokens (usage: /tokens <number>)",
    "strategy" => "Set context strategy (usage: /strategy <sliding_window|smart>)",
    "cost" => "Show session cost"
  }
  
  def handle_command(command) do
    [cmd | args] = String.split(command, " ", parts: 2)
    args = List.wrap(args)
    
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
      "tools" -> list_tools()
      "tool" -> call_tool(args)
      "resources" -> list_resources()
      "resource" -> read_resource(args)
      "prompts" -> list_prompts()
      "prompt" -> get_prompt(args)
      "backend" -> switch_backend(args)
      "model" -> switch_model(args)
      "export" -> export_conversation(args)
      "context" -> show_context_stats()
      "system" -> set_system_prompt(args)
      "tokens" -> set_max_tokens(args)
      "strategy" -> set_strategy(args)
      "cost" -> show_session_cost()
      _ -> Renderer.show_error("Unknown command: /#{cmd}")
    end
  end
  
  defp show_help do
    rows = @commands
    |> Enum.map(fn {cmd, desc} ->
      %{"Command" => "/#{cmd}", "Description" => desc}
    end)
    |> Enum.sort_by(&Map.get(&1, "Command"))
    
    Renderer.show_table(["Command", "Description"], rows)
  end
  
  defp clear_screen do
    Renderer.clear_screen()
  end
  
  defp show_history do
    messages = Session.get_messages()
    
    if Enum.empty?(messages) do
      Renderer.show_info("No messages in history")
    else
      Enum.each(messages, fn msg ->
        role = String.capitalize(msg.role)
        color = case msg.role do
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
  
  defp new_conversation do
    Session.new_session()
    Renderer.show_info("Started new conversation")
  end
  
  defp show_config do
    config = %{
      "LLM Backend" => Session.get_current_session().llm_backend,
      "Model" => get_current_model(),
      "MCP Servers" => length(MCPChat.MCP.ServerManager.list_servers()),
      "Streaming" => Config.get([:ui, :streaming]) != false
    }
    
    rows = Enum.map(config, fn {k, v} -> %{"Setting" => k, "Value" => to_string(v)} end)
    Renderer.show_table(["Setting", "Value"], rows)
  end
  
  defp list_servers do
    servers = MCPChat.MCP.ServerManager.list_servers()
    
    if Enum.empty?(servers) do
      Renderer.show_info("No MCP servers connected")
    else
      rows = Enum.map(servers, fn server ->
        %{
          "Name" => server.name,
          "Status" => to_string(server.status),
          "Port" => to_string(server.port || "stdio")
        }
      end)
      
      Renderer.show_table(["Name", "Status", "Port"], rows)
    end
  end
  
  defp list_tools do
    tools = MCPChat.MCP.ServerManager.list_all_tools()
    
    if Enum.empty?(tools) do
      Renderer.show_info("No MCP tools available")
    else
      rows = Enum.map(tools, fn tool ->
        %{
          "Server" => Map.get(tool, :server, "unknown"),
          "Tool" => Map.get(tool, "name", "unnamed"),
          "Description" => Map.get(tool, "description", "")
        }
      end)
      
      Renderer.show_table(["Server", "Tool", "Description"], rows)
    end
  end
  
  defp list_resources do
    resources = MCPChat.MCP.ServerManager.list_all_resources()
    
    if Enum.empty?(resources) do
      Renderer.show_info("No MCP resources available")
    else
      rows = Enum.map(resources, fn resource ->
        %{
          "Server" => Map.get(resource, :server, "unknown"),
          "URI" => Map.get(resource, "uri", ""),
          "Name" => Map.get(resource, "name", "unnamed")
        }
      end)
      
      Renderer.show_table(["Server", "URI", "Name"], rows)
    end
  end
  
  defp list_prompts do
    prompts = MCPChat.MCP.ServerManager.list_all_prompts()
    
    if Enum.empty?(prompts) do
      Renderer.show_info("No MCP prompts available")
    else
      rows = Enum.map(prompts, fn prompt ->
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
    backends = ["anthropic", "openai", "local"]
    
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
    
    format_atom = case format do
      "markdown" -> :markdown
      "json" -> :json
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
  
  
  defp show_context_stats do
    stats = Session.get_context_stats()
    session = Session.get_current_session()
    
    Renderer.show_info("Context Statistics:")
    Renderer.show_text("  Messages: #{stats.message_count}")
    Renderer.show_text("  Estimated tokens: #{stats.estimated_tokens}/#{stats.max_tokens} (#{stats.tokens_used_percentage}%)")
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
  
  defp show_session_cost do
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
  
  defp get_current_model do
    session = Session.get_current_session()
    backend = session.llm_backend
    
    case backend do
      "anthropic" -> Config.get([:llm, :anthropic, :model]) || "claude-sonnet-4-20250514"
      "openai" -> Config.get([:llm, :openai, :model]) || "gpt-4"
      "local" -> Config.get([:llm, :local, :model_path]) || "none"
      _ -> "unknown"
    end
  end
  
  defp call_tool([args_string]) do
    case String.split(args_string, " ", parts: 3) do
      [server_name, tool_name | rest] ->
        # Parse arguments - try JSON first, then treat as string
        arguments = case rest do
          [] -> %{}
          [json_args] ->
            case Jason.decode(json_args) do
              {:ok, args} -> args
              {:error, _} -> %{"input" => json_args}  # Wrap string as input
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
        arguments = case rest do
          [] -> %{}
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
  
  defp list_sessions do
    case Session.list_saved_sessions() do
      {:ok, sessions} ->
        if Enum.empty?(sessions) do
          Renderer.show_info("No saved sessions found")
        else
          rows = Enum.map(sessions, fn session ->
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
      diff < 3600 -> "#{div(diff, 60)} min ago"
      diff < 86400 -> "#{div(diff, 3600)} hours ago"
      diff < 604800 -> "#{div(diff, 86400)} days ago"
      true -> DateTime.to_date(datetime) |> Date.to_string()
    end
  end
  
end