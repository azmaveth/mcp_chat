defmodule MCPChat.MCPServerHandler do
  @moduledoc """
  MCP server handler that exposes mcp_chat functionality as MCP tools.
  """

  use ExMCP.Server.Handler

  require Logger
  alias MCPChat.LLM.ExLLMAdapter
  alias MCPChat.Gateway

  @impl true
  def init(_args) do
    # Start with a session map to track MCP client sessions
    {:ok, %{sessions: %{}}}
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

    # Get or create session for this MCP client
    {session_id, new_state} = get_or_create_session(state, backend)

    # Send message through Gateway
    Gateway.send_message(session_id, message)

    # Get LLM response
    case Gateway.get_session_state(session_id) do
      {:ok, session} ->
        messages = format_messages_for_llm(session.messages)

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

            # The agent will automatically track the assistant message
            {:ok, [%{type: "text", text: content}], new_state}

          {:error, reason} ->
            {:error, "Chat failed: #{inspect(reason)}", new_state}
        end

      {:error, reason} ->
        {:error, "Failed to get session: #{inspect(reason)}", new_state}
    end
  end

  def handle_call_tool("new_session", args, state) do
    backend = Map.get(args, "backend", "anthropic")

    # Create new session
    user_id = "mcp_client_#{System.unique_integer([:positive])}"

    case Gateway.create_session(user_id, backend: backend, source: :mcp) do
      {:ok, session_id} ->
        # Store session ID for this MCP client
        new_state = put_in(state.sessions[self()], session_id)
        {:ok, [%{type: "text", text: "New session started"}], new_state}

      {:error, reason} ->
        {:error, "Failed to create session: #{inspect(reason)}", state}
    end
  end

  def handle_call_tool("get_history", args, state) do
    limit = Map.get(args, "limit", 50)

    case get_current_session_id(state) do
      {:ok, session_id} ->
        case Gateway.get_message_history(session_id, limit: limit) do
          {:ok, messages} ->
            # Format messages for display
            formatted =
              messages
              |> Enum.map_join(
                fn msg ->
                  "#{msg.role}: #{msg.content}"
                end,
                "\n\n"
              )

            {:ok, [%{type: "text", text: formatted}], state}

          {:error, reason} ->
            {:error, "Failed to get history: #{inspect(reason)}", state}
        end

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  def handle_call_tool("clear_history", _args, state) do
    # We need to create a new session as we can't clear existing one
    case get_current_session_id(state) do
      {:ok, session_id} ->
        # Destroy old session
        Gateway.destroy_session(session_id)

        # Create new session
        user_id = "mcp_client_#{System.unique_integer([:positive])}"

        case Gateway.create_session(user_id, backend: "anthropic", source: :mcp) do
          {:ok, new_session_id} ->
            new_state = put_in(state.sessions[self()], new_session_id)
            {:ok, [%{type: "text", text: "History cleared"}], new_state}

          {:error, reason} ->
            {:error, "Failed to create new session: #{inspect(reason)}", state}
        end

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  def handle_call_tool("switch_backend", %{"backend" => _backend}, state) do
    # For now, just return success - actual backend switching would need
    # to be implemented in the Session agent
    {:ok,
     [
       %{type: "text", text: "Backend switching not yet implemented. Please create a new session with desired backend."}
     ], state}
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
    case get_current_session_id(state) do
      {:ok, session_id} ->
        case Gateway.get_message_history(session_id) do
          {:ok, messages} ->
            content = Jason.encode!(messages)
            {:ok, [%{type: "text", text: content}], state}

          {:error, reason} ->
            {:error, "Failed to get history: #{inspect(reason)}", state}
        end

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  def handle_read_resource("chat://session", state) do
    case get_current_session_id(state) do
      {:ok, session_id} ->
        case Gateway.get_session_state(session_id) do
          {:ok, session} ->
            content =
              Jason.encode!(%{
                id: session.session_id,
                backend: session.llm_backend,
                message_count: length(session.messages),
                created_at: session.created_at
              })

            {:ok, [%{type: "text", text: content}], state}

          {:error, reason} ->
            {:error, "Failed to get session: #{inspect(reason)}", state}
        end

      {:error, reason} ->
        {:error, reason, state}
    end
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

  # Private helpers

  defp get_or_create_session(state, backend) do
    case get_current_session_id(state) do
      {:ok, session_id} ->
        {session_id, state}

      {:error, _} ->
        # Create new session
        user_id = "mcp_client_#{System.unique_integer([:positive])}"
        backend = backend || "anthropic"

        case Gateway.create_session(user_id, backend: backend, source: :mcp) do
          {:ok, session_id} ->
            new_state = put_in(state.sessions[self()], session_id)
            {session_id, new_state}

          {:error, reason} ->
            Logger.error("Failed to create session: #{inspect(reason)}")
            {nil, state}
        end
    end
  end

  defp get_current_session_id(state) do
    case Map.get(state.sessions, self()) do
      nil -> {:error, "No active session"}
      session_id -> {:ok, session_id}
    end
  end

  defp format_messages_for_llm(messages) do
    messages
    |> Enum.map(fn msg ->
      %{
        "role" => msg.role,
        "content" => msg.content
      }
    end)
  end
end
