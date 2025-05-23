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
    "config" => "Show current configuration",
    "servers" => "List connected MCP servers",
    "tools" => "List available MCP tools",
    "resources" => "List available MCP resources",
    "prompts" => "List available MCP prompts",
    "backend" => "Switch LLM backend (usage: /backend <name>)",
    "model" => "Switch model (usage: /model <name>)",
    "export" => "Export conversation (usage: /export [format])"
  }
  
  def handle_command(command) do
    [cmd | args] = String.split(command, " ", parts: 2)
    args = List.wrap(args)
    
    case cmd do
      "help" -> show_help()
      "clear" -> clear_screen()
      "history" -> show_history()
      "new" -> new_conversation()
      "config" -> show_config()
      "servers" -> list_servers()
      "tools" -> list_tools()
      "resources" -> list_resources()
      "prompts" -> list_prompts()
      "backend" -> switch_backend(args)
      "model" -> switch_model(args)
      "export" -> export_conversation(args)
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
    messages = Session.get_messages()
    session = Session.get_current_session()
    
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)
    filename = "chat_export_#{timestamp}.#{format}"
    
    content = case format do
      "markdown" -> format_as_markdown(messages, session)
      "json" -> format_as_json(messages, session)
      _ -> 
        Renderer.show_error("Unknown format. Available: markdown, json")
        nil
    end
    
    if content do
      case File.write(filename, content) do
        :ok -> Renderer.show_info("Exported to #{filename}")
        {:error, reason} -> Renderer.show_error("Export failed: #{inspect(reason)}")
      end
    end
  end
  
  defp format_as_markdown(messages, session) do
    header = """
    # Chat Export
    
    **Session ID**: #{session.id}
    **Created**: #{session.created_at}
    **Backend**: #{session.llm_backend}
    
    ---
    
    """
    
    body = messages
    |> Enum.map(fn msg ->
      "### #{String.capitalize(msg.role)}\n\n#{msg.content}\n"
    end)
    |> Enum.join("\n")
    
    header <> body
  end
  
  defp format_as_json(messages, session) do
    data = %{
      session_id: session.id,
      created_at: session.created_at,
      backend: session.llm_backend,
      messages: messages
    }
    
    Jason.encode!(data, pretty: true)
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
  
end