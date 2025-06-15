defmodule MCPChat.MCPServerHandler do
  @moduledoc """
  MCP server handler that exposes mcp_chat functionality as MCP tools.
  """

  use ExMCP.Server.Handler

  require Logger
  alias MCPChat.LLM.ExLLMAdapter
  alias MCPChat.Session

  @impl true
  def init(_args) do
    {:ok, %{}}
  end

  @impl true
  def handle_initialize(_params, state) do
    Logger.info("MCP server initializing")

    {:ok,
     %{
       server_info: %{
         name: "mcp_chat",
         version: "0.1.0",
         vendor: "mcp_chat"
       },
       capabilities: %{
         tools: %{},
         resources: %{list: true, read: true},
         prompts: %{list: true, get: true}
       }
     }, state}
  end

  @impl true
  def handle_list_tools(_params, state) do
    tools = [
      %{
        name: "chat",
        description: "Send a message to the chat and get a response",
        input_schema: %{
          type: "object",
          properties: %{
            "message" => %{
              type: "string",
              description: "The message to send"
            },
            "backend" => %{
              type: "string",
              description: "Optional: LLM backend to use",
              enum: ["anthropic", "openai", "ollama", "bedrock", "gemini", "local"]
            }
          },
          required: ["message"]
        }
      },
      %{
        name: "new_session",
        description: "Start a new chat session",
        input_schema: %{
          type: "object",
          properties: %{
            "backend" => %{
              type: "string",
              description: "Optional: LLM backend to use"
            }
          }
        }
      },
      %{
        name: "get_history",
        description: "Get the chat history",
        input_schema: %{
          type: "object",
          properties: %{
            "limit" => %{
              type: "integer",
              description: "Optional: Maximum number of messages to return"
            }
          }
        }
      },
      %{
        name: "clear_history",
        description: "Clear the chat history",
        input_schema: %{
          type: "object",
          properties: %{}
        }
      },
      %{
        name: "switch_backend",
        description: "Switch the LLM backend",
        input_schema: %{
          type: "object",
          properties: %{
            "backend" => %{
              type: "string",
              description: "LLM backend to switch to",
              enum: ["anthropic", "openai", "ollama", "bedrock", "gemini", "local"]
            }
          },
          required: ["backend"]
        }
      }
    ]

    {:ok, tools, state}
  end

  @impl true
  def handle_call_tool("chat", %{"message" => message} = args, state) do
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

    # Pass the provider as an option
    options = [{:provider, String.to_atom(session.llm_backend)}]

    case ExLLMAdapter.chat(messages, options) do
      {:ok, response} ->
        content =
          case response do
            %{content: content} -> content
            content when is_binary(content) -> content
            _ -> "No response"
          end

        Session.add_message("assistant", content)
        {:ok, [%{type: "text", text: content}], state}

      {:error, reason} ->
        {:error, "Chat failed: #{inspect(reason)}", state}
    end
  end

  def handle_call_tool("new_session", args, state) do
    backend = Map.get(args, "backend")
    Session.new_session(backend)
    {:ok, [%{type: "text", text: "New session started"}], state}
  end

  def handle_call_tool("get_history", args, state) do
    limit = Map.get(args, "limit", 50)
    messages = Session.get_messages()

    # Format messages for display
    formatted =
      messages
      |> Enum.take(-limit)
      |> Enum.map_join(
        fn msg ->
          "#{msg.role}: #{msg.content}"
        end,
        "\n\n"
      )

    {:ok, [%{type: "text", text: formatted}], state}
  end

  def handle_call_tool("clear_history", _args, state) do
    Session.clear_session()
    {:ok, [%{type: "text", text: "History cleared"}], state}
  end

  def handle_call_tool("switch_backend", %{"backend" => backend}, state) do
    Session.update_session(%{llm_backend: backend})
    {:ok, [%{type: "text", text: "Switched to #{backend} backend"}], state}
  end

  def handle_call_tool(name, _args, state) do
    {:error, "Unknown tool: #{name}", state}
  end

  @impl true
  def handle_list_resources(_params, state) do
    resources = [
      %{
        uri: "chat://history",
        name: "Chat History",
        description: "Current chat session history",
        mimeType: "application/json"
      },
      %{
        uri: "chat://session",
        name: "Session Info",
        description: "Current session information",
        mimeType: "application/json"
      }
    ]

    {:ok, resources, state}
  end

  @impl true
  def handle_read_resource("chat://history", state) do
    messages = Session.get_messages()
    content = Jason.encode!(messages)
    {:ok, [%{type: "text", text: content}], state}
  end

  def handle_read_resource("chat://session", state) do
    session = Session.get_current_session()

    content =
      Jason.encode!(%{
        id: session.id,
        backend: session.llm_backend,
        message_count: length(session.messages),
        created_at: session.created_at
      })

    {:ok, [%{type: "text", text: content}], state}
  end

  def handle_read_resource(uri, state) do
    {:error, "Unknown resource: #{uri}", state}
  end

  @impl true
  def handle_list_prompts(_params, state) do
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
        description: "Explain a concept or code",
        arguments: [
          %{
            name: "topic",
            description: "What to explain",
            required: true
          },
          %{
            name: "level",
            description: "Explanation level (beginner, intermediate, advanced)",
            required: false
          }
        ]
      },
      %{
        name: "refactor",
        description: "Suggest refactoring for code",
        arguments: [
          %{
            name: "code",
            description: "The code to refactor",
            required: true
          },
          %{
            name: "goals",
            description: "Refactoring goals (readability, performance, etc)",
            required: false
          }
        ]
      }
    ]

    {:ok, prompts, state}
  end

  @impl true
  def handle_get_prompt("code_review", args, state) do
    code = Map.get(args, "code", "")
    language = Map.get(args, "language", "unknown")

    messages = [
      %{
        role: "user",
        content: """
        Please review the following #{language} code for best practices, potential issues, and improvements:

        ```#{language}
        #{code}
        ```
        """
      }
    ]

    {:ok, messages, state}
  end

  def handle_get_prompt("explain", args, state) do
    topic = Map.get(args, "topic", "")
    level = Map.get(args, "level", "intermediate")

    messages = [
      %{
        role: "user",
        content: "Please explain #{topic} at a #{level} level."
      }
    ]

    {:ok, messages, state}
  end

  def handle_get_prompt("refactor", args, state) do
    code = Map.get(args, "code", "")
    goals = Map.get(args, "goals", "readability and maintainability")

    messages = [
      %{
        role: "user",
        content: """
        Please refactor the following code for #{goals}:

        ```
        #{code}
        ```
        """
      }
    ]

    {:ok, messages, state}
  end

  def handle_get_prompt(name, _args, state) do
    {:error, "Unknown prompt: #{name}", state}
  end

  @impl true
  def handle_complete(_ref, _params, state) do
    {:error, "Completion not implemented", state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end
end
