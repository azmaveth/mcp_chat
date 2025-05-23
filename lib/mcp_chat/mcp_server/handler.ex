defmodule MCPChat.MCPServer.Handler do
  @moduledoc """
  Handles MCP protocol requests and provides chat functionality as MCP tools.
  """
  
  # alias MCPChat.MCP.Protocol
  alias MCPChat.Session
  # alias MCPChat.LLM
  
  require Logger

  @server_info %{
    name: "mcp_chat",
    version: "0.1.0",
    vendor: "mcp_chat"
  }

  @capabilities %{
    tools: %{},
    resources: %{},
    prompts: %{}
  }

  # Initialize handler state
  def init(transport) do
    Logger.info("Initializing MCP server handler for transport: #{transport}")
    {:ok, %{transport: transport, initialized: false}}
  end

  # Protocol message handlers

  def handle_request("initialize", params, _state) do
    Logger.info("MCP client initializing: #{inspect(params["clientInfo"])}")
    
    result = %{
      protocolVersion: "2024-11-05",
      serverInfo: @server_info,
      capabilities: @capabilities
    }
    
    {:ok, result, :initialized}
  end

  def handle_request("tools/list", _params, state) do
    tools = [
      %{
        name: "chat",
        description: "Send a message to the AI chat and get a response",
        inputSchema: %{
          type: "object",
          properties: %{
            message: %{
              type: "string",
              description: "The message to send to the AI"
            },
            backend: %{
              type: "string",
              description: "Optional: LLM backend to use (anthropic, openai, local)",
              enum: ["anthropic", "openai", "local"]
            }
          },
          required: ["message"]
        }
      },
      %{
        name: "new_session",
        description: "Start a new chat session",
        inputSchema: %{
          type: "object",
          properties: %{
            backend: %{
              type: "string",
              description: "Optional: LLM backend to use",
              enum: ["anthropic", "openai", "local"]
            }
          }
        }
      },
      %{
        name: "get_history",
        description: "Get the chat history",
        inputSchema: %{
          type: "object",
          properties: %{
            limit: %{
              type: "integer",
              description: "Optional: Maximum number of messages to return"
            }
          }
        }
      },
      %{
        name: "clear_history",
        description: "Clear the chat history",
        inputSchema: %{
          type: "object",
          properties: %{}
        }
      }
    ]
    
    {:ok, %{tools: tools}, state}
  end

  def handle_request("tools/call", %{"name" => tool_name, "arguments" => args}, state) do
    Logger.info("MCP tool call: #{tool_name} with args: #{inspect(args)}")
    
    case call_tool(tool_name, args) do
      {:ok, result} ->
        {:ok, result, state}
      {:error, reason} ->
        {:error, %{code: -32603, message: "Tool execution failed: #{inspect(reason)}"}, state}
    end
  end

  def handle_request("resources/list", _params, state) do
    resources = [
      %{
        uri: "chat://history",
        name: "Chat History",
        description: "Current chat conversation history",
        mimeType: "application/json"
      },
      %{
        uri: "chat://session",
        name: "Session Info",
        description: "Current chat session information",
        mimeType: "application/json"
      }
    ]
    
    {:ok, %{resources: resources}, state}
  end

  def handle_request("resources/read", %{"uri" => uri}, state) do
    case read_resource(uri) do
      {:ok, content} ->
        result = %{
          contents: [
            %{
              uri: uri,
              mimeType: "application/json",
              text: Jason.encode!(content)
            }
          ]
        }
        {:ok, result, state}
      {:error, reason} ->
        {:error, %{code: -32602, message: "Invalid resource: #{reason}"}, state}
    end
  end

  def handle_request("prompts/list", _params, state) do
    prompts = [
      %{
        name: "code_review",
        description: "Review code for best practices and potential issues",
        arguments: [
          %{
            name: "code",
            description: "The code to review",
            required: true
          },
          %{
            name: "language",
            description: "Programming language",
            required: false
          }
        ]
      },
      %{
        name: "explain",
        description: "Explain a concept or topic",
        arguments: [
          %{
            name: "topic",
            description: "The topic to explain",
            required: true
          },
          %{
            name: "level",
            description: "Explanation level (beginner, intermediate, expert)",
            required: false
          }
        ]
      }
    ]
    
    {:ok, %{prompts: prompts}, state}
  end

  def handle_request("prompts/get", %{"name" => name, "arguments" => args}, state) do
    case get_prompt(name, args) do
      {:ok, messages} ->
        {:ok, %{messages: messages}, state}
      {:error, reason} ->
        {:error, %{code: -32602, message: "Invalid prompt: #{reason}"}, state}
    end
  end

  def handle_request("completion/complete", _params, state) do
    # Handle completion requests
    {:error, %{code: -32601, message: "Completion not implemented"}, state}
  end

  def handle_request(method, _params, state) do
    {:error, %{code: -32601, message: "Method not found: #{method}"}, state}
  end

  def handle_notification("notifications/initialized", _params, state) do
    Logger.info("MCP client initialized")
    {:ok, state}
  end

  def handle_notification(method, params, state) do
    Logger.debug("Received notification: #{method} - #{inspect(params)}")
    {:ok, state}
  end

  # Tool implementations

  defp call_tool("chat", %{"message" => message} = args) do
    backend = Map.get(args, "backend")
    
    # Switch backend if specified
    if backend do
      Session.new_session(backend)
    end
    
    # Add user message
    Session.add_message("user", message)
    
    # Get LLM response
    session = Session.get_current_session()
    messages = Session.get_messages()
    
    adapter = get_llm_adapter(session.llm_backend)
    
    case adapter.chat(messages) do
      {:ok, response} ->
        Session.add_message("assistant", response)
        {:ok, %{content: [%{type: "text", text: response}]}}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call_tool("new_session", args) do
    backend = Map.get(args, "backend")
    Session.new_session(backend)
    {:ok, %{content: [%{type: "text", text: "New session started"}]}}
  end

  defp call_tool("get_history", args) do
    limit = Map.get(args, "limit")
    messages = Session.get_messages(limit)
    {:ok, %{content: [%{type: "text", text: format_history(messages)}]}}
  end

  defp call_tool("clear_history", _args) do
    Session.clear_session()
    {:ok, %{content: [%{type: "text", text: "Chat history cleared"}]}}
  end

  defp call_tool(name, _args) do
    {:error, "Unknown tool: #{name}"}
  end

  # Resource implementations

  defp read_resource("chat://history") do
    messages = Session.get_messages()
    {:ok, %{messages: messages}}
  end

  defp read_resource("chat://session") do
    session = Session.get_current_session()
    {:ok, %{
      id: session.id,
      backend: session.llm_backend,
      created_at: session.created_at,
      updated_at: session.updated_at,
      message_count: length(session.messages)
    }}
  end

  defp read_resource(_uri) do
    {:error, "Unknown resource"}
  end

  # Prompt implementations

  defp get_prompt("code_review", %{"code" => code} = args) do
    language = Map.get(args, "language", "unknown")
    
    messages = [
      %{
        role: "user",
        content: %{
          type: "text",
          text: """
          Please review the following #{language} code for best practices, potential issues, and improvements:

          ```#{language}
          #{code}
          ```
          """
        }
      }
    ]
    
    {:ok, messages}
  end

  defp get_prompt("explain", %{"topic" => topic} = args) do
    level = Map.get(args, "level", "intermediate")
    
    messages = [
      %{
        role: "user",
        content: %{
          type: "text",
          text: "Please explain #{topic} at a #{level} level."
        }
      }
    ]
    
    {:ok, messages}
  end

  defp get_prompt(_name, _args) do
    {:error, "Unknown prompt"}
  end

  # Helper functions

  defp get_llm_adapter("anthropic"), do: MCPChat.LLM.Anthropic
  defp get_llm_adapter(_), do: MCPChat.LLM.Anthropic

  defp format_history(messages) do
    messages
    |> Enum.map(fn msg ->
      "#{String.upcase(msg.role)}: #{msg.content}"
    end)
    |> Enum.join("\n\n")
  end
end