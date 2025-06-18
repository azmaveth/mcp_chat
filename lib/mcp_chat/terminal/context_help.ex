defmodule MCPChat.Terminal.ContextHelp do
  @moduledoc """
  Context-sensitive help system for intelligent assistance.

  Provides help based on current context, command being typed,
  error messages, and user activity.
  """

  use GenServer
  require Logger

  # alias MCPChat.CLI.Commands
  # Will be used for command integration

  # Context help state
  defstruct [
    # Help content database
    :help_database,
    # Context analysis logic
    :context_analyzer,
    # Recent error tracking
    :recent_errors,
    # User behavior patterns
    :usage_patterns,
    # Help system settings
    :settings
  ]

  # Help database structure
  @help_database %{
    commands: %{
      "/help" => %{
        description: "Show available commands and get help",
        usage: "/help [command]",
        examples: [
          "/help - Show all commands",
          "/help model - Get help for /model command",
          "/help alias - Learn about aliases"
        ],
        related: ["/commands", "/tutorial", "/docs"]
      },
      "/model" => %{
        description: "Switch between AI models",
        usage: "/model [model_name]",
        examples: [
          "/model - Show current model and list available",
          "/model gpt-4 - Switch to GPT-4",
          "/model claude-3-opus - Switch to Claude 3 Opus"
        ],
        tips: [
          "Different models have different capabilities and costs",
          "Use /models to see detailed model information"
        ],
        related: ["/models", "/cost", "/settings"]
      },
      "/servers" => %{
        description: "Manage MCP servers",
        usage: "/servers [subcommand]",
        examples: [
          "/servers - List all configured servers",
          "/servers add <name> <command> - Add a new server",
          "/servers remove <name> - Remove a server",
          "/servers restart <name> - Restart a server"
        ],
        tips: [
          "MCP servers extend functionality with tools and resources",
          "Server configuration is saved in config.toml"
        ],
        related: ["/tools", "/discover", "/config"]
      },
      "/context" => %{
        description: "Manage conversation context",
        usage: "/context [subcommand]",
        examples: [
          "/context show - Display current context",
          "/context clear - Clear conversation history",
          "/context add file.txt - Add file to context",
          "/context remove 3 - Remove item from context"
        ],
        tips: [
          "Context affects token usage and costs",
          "Use /stats to see current token count"
        ],
        related: ["/stats", "/cost", "/session"]
      },
      "/alias" => %{
        description: "Create command shortcuts",
        usage: "/alias [subcommand]",
        examples: [
          "/alias list - Show all aliases",
          "/alias add gpt '/model gpt-4' - Create alias",
          "/alias remove gpt - Remove alias"
        ],
        tips: [
          "Aliases can include multiple commands separated by ;",
          "Use quotes for aliases with spaces"
        ],
        related: ["/config", "/settings"]
      },
      "/session" => %{
        description: "Manage chat sessions",
        usage: "/session [subcommand]",
        examples: [
          "/session list - List all sessions",
          "/session new - Start a new session",
          "/session load <id> - Load a session",
          "/session export - Export current session"
        ],
        tips: [
          "Sessions auto-save your conversation",
          "Export sessions as markdown or JSON"
        ],
        related: ["/export", "/import", "/history"]
      }
    },
    errors: %{
      "API key not found" => %{
        problem: "The API key for the selected provider is not configured",
        solutions: [
          "Set the API key in your environment: export ANTHROPIC_API_KEY=your-key",
          "Add it to config.toml under [llm.anthropic]",
          "Use /config to edit settings"
        ],
        related: ["/config", "/settings", "/model"]
      },
      "Model not available" => %{
        problem: "The requested model is not available",
        solutions: [
          "Use /models to see available models",
          "Check if you have the right API access",
          "Try a different model provider"
        ],
        related: ["/models", "/model", "/providers"]
      },
      "Context too long" => %{
        problem: "The conversation context exceeds the model's token limit",
        solutions: [
          "Use /context clear to reset the conversation",
          "Use /context remove to remove specific items",
          "Switch to a model with higher token limits"
        ],
        related: ["/context", "/stats", "/model"]
      },
      "Server connection failed" => %{
        problem: "Could not connect to the MCP server",
        solutions: [
          "Check if the server command is correct",
          "Ensure the server executable exists and is accessible",
          "Use /servers restart to retry connection",
          "Check server logs for errors"
        ],
        related: ["/servers", "/logs", "/debug"]
      }
    },
    concepts: %{
      "mcp" => %{
        title: "Model Context Protocol (MCP)",
        explanation: """
        MCP is a protocol for extending AI assistants with tools and resources.

        MCP servers can provide:
        • File system access
        • Database connections
        • API integrations
        • Custom tools

        The AI can use these tools automatically to help answer your questions.
        """,
        learn_more: ["/servers", "/tools", "/discover"]
      },
      "context" => %{
        title: "Conversation Context",
        explanation: """
        Context is what the AI remembers from your conversation.

        It includes:
        • Your messages and AI responses
        • Files you've added
        • Tool outputs

        More context = better understanding but higher costs.
        """,
        learn_more: ["/context", "/stats", "/cost"]
      },
      "tokens" => %{
        title: "Tokens and Costs",
        explanation: """
        AI models process text in units called tokens.

        • ~4 characters = 1 token (rough estimate)
        • Different models have different costs per token
        • Both input and output tokens count

        Use /stats to see current usage.
        """,
        learn_more: ["/stats", "/cost", "/model"]
      }
    }
  }

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get help for a specific command or topic.
  """
  def get_help(pid \\ __MODULE__, query) do
    GenServer.call(pid, {:get_help, query})
  end

  @doc """
  Get contextual help based on current state.
  """
  def get_contextual_help(pid \\ __MODULE__, context) do
    GenServer.call(pid, {:get_contextual_help, context})
  end

  @doc """
  Record an error for contextual help.
  """
  def record_error(pid \\ __MODULE__, error, context) do
    GenServer.cast(pid, {:record_error, error, context})
  end

  @doc """
  Search help database.
  """
  def search(pid \\ __MODULE__, query) do
    GenServer.call(pid, {:search, query})
  end

  @doc """
  Get quick tips based on usage.
  """
  def get_tips(pid \\ __MODULE__, context \\ %{}) do
    GenServer.call(pid, {:get_tips, context})
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    Logger.info("Starting Context Help")

    settings = %{
      max_recent_errors: Keyword.get(opts, :max_recent_errors, 10),
      enable_smart_tips: Keyword.get(opts, :enable_smart_tips, true),
      track_usage: Keyword.get(opts, :track_usage, true)
    }

    state = %__MODULE__{
      help_database: @help_database,
      recent_errors: [],
      usage_patterns: %{},
      settings: settings
    }

    Logger.info("Context Help initialized",
      commands: map_size(@help_database.commands),
      error_helps: map_size(@help_database.errors)
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:get_help, query}, _from, state) do
    help = find_help(query, state)
    {:reply, help, state}
  end

  @impl true
  def handle_call({:get_contextual_help, context}, _from, state) do
    help = analyze_context_for_help(context, state)
    {:reply, help, state}
  end

  @impl true
  def handle_call({:search, query}, _from, state) do
    results = search_help_database(query, state)
    {:reply, results, state}
  end

  @impl true
  def handle_call({:get_tips, context}, _from, state) do
    tips = generate_tips(context, state)
    {:reply, tips, state}
  end

  @impl true
  def handle_cast({:record_error, error, context}, state) do
    new_error = %{
      error: error,
      context: context,
      timestamp: System.monotonic_time(:millisecond)
    }

    new_errors =
      [new_error | state.recent_errors]
      |> Enum.take(state.settings.max_recent_errors)

    {:noreply, %{state | recent_errors: new_errors}}
  end

  # Private functions

  defp find_help(query, state) do
    # Normalize query
    normalized = normalize_query(query)

    # Try exact command match first
    case Map.get(state.help_database.commands, normalized) do
      nil ->
        # Try concept match
        case Map.get(state.help_database.concepts, normalized) do
          nil ->
            # Try fuzzy search
            search_help_database(query, state)
            |> format_search_results()

          concept ->
            format_concept_help(concept)
        end

      command_help ->
        format_command_help(normalized, command_help)
    end
  end

  defp analyze_context_for_help(context, state) do
    helps = []

    # Check for recent errors
    helps =
      if context[:last_error] do
        error_help = find_error_help(context.last_error, state)
        if error_help, do: [error_help | helps], else: helps
      else
        helps
      end

    # Check current input
    helps =
      if context[:current_input] do
        input_help = analyze_input_for_help(context.current_input, state)
        if input_help, do: [input_help | helps], else: helps
      else
        helps
      end

    # Check for common patterns
    helps =
      if state.settings.enable_smart_tips do
        pattern_tips = detect_usage_patterns(context, state)
        helps ++ pattern_tips
      else
        helps
      end

    format_contextual_helps(helps)
  end

  defp find_error_help(error_message, state) do
    # Find matching error help
    state.help_database.errors
    |> Enum.find(fn {pattern, _help} ->
      String.contains?(String.downcase(error_message), String.downcase(pattern))
    end)
    |> case do
      {_pattern, help} -> help
      nil -> nil
    end
  end

  defp analyze_input_for_help(input, state) do
    cond do
      # Incomplete command
      String.starts_with?(input, "/") and not String.contains?(input, " ") ->
        command = String.trim(input)
        matching_commands = find_matching_commands(command, state)

        if length(matching_commands) > 0 do
          %{
            type: :command_completion,
            commands: matching_commands
          }
        else
          nil
        end

      # Command with arguments
      String.starts_with?(input, "/") ->
        [command | _] = String.split(input, " ")
        Map.get(state.help_database.commands, command)

      true ->
        nil
    end
  end

  defp find_matching_commands(prefix, state) do
    state.help_database.commands
    |> Enum.filter(fn {cmd, _} ->
      String.starts_with?(cmd, prefix)
    end)
    |> Enum.map(fn {cmd, help} ->
      %{command: cmd, description: help.description}
    end)
    |> Enum.take(5)
  end

  defp detect_usage_patterns(_context, _state) do
    # Detect common usage patterns and provide tips
    # This would analyze user behavior over time
    []
  end

  defp search_help_database(query, state) do
    query_lower = String.downcase(query)

    # Search commands
    command_results =
      state.help_database.commands
      |> Enum.filter(fn {cmd, help} ->
        String.contains?(String.downcase(cmd), query_lower) or
          String.contains?(String.downcase(help.description), query_lower)
      end)
      |> Enum.map(fn {cmd, help} ->
        %{type: :command, command: cmd, help: help}
      end)

    # Search concepts
    concept_results =
      state.help_database.concepts
      |> Enum.filter(fn {name, concept} ->
        String.contains?(String.downcase(name), query_lower) or
          String.contains?(String.downcase(concept.title), query_lower) or
          String.contains?(String.downcase(concept.explanation), query_lower)
      end)
      |> Enum.map(fn {name, concept} ->
        %{type: :concept, name: name, concept: concept}
      end)

    # Search error helps
    error_results =
      state.help_database.errors
      |> Enum.filter(fn {pattern, help} ->
        String.contains?(String.downcase(pattern), query_lower) or
          String.contains?(String.downcase(help.problem), query_lower)
      end)
      |> Enum.map(fn {pattern, help} ->
        %{type: :error, pattern: pattern, help: help}
      end)

    command_results ++ concept_results ++ error_results
  end

  defp generate_tips(context, _state) do
    tips = []

    # New user tips
    tips =
      if Map.get(context, :is_new_user, false) do
        [
          "💡 Type /tutorial to start the interactive tutorial",
          "💡 Press Tab to see autocomplete suggestions",
          "💡 Use /help <command> to learn about specific commands"
          | tips
        ]
      else
        tips
      end

    # Context-based tips
    tips =
      cond do
        Map.get(context, :high_token_usage, false) ->
          ["💡 Use /context clear to reduce token usage and costs" | tips]

        Map.get(context, :no_mcp_servers, false) ->
          ["💡 Add MCP servers with /servers add to extend functionality" | tips]

        Map.get(context, :frequent_model_switches, false) ->
          ["💡 Create model aliases like /alias add gpt '/model gpt-4'" | tips]

        true ->
          tips
      end

    Enum.take(tips, 3)
  end

  defp format_command_help(command, help) do
    """
    #{IO.ANSI.cyan()}#{command}#{IO.ANSI.reset()} - #{help.description}

    Usage: #{help.usage}

    Examples:
    #{format_examples(help.examples)}
    #{format_tips(Map.get(help, :tips, []))}
    #{format_related(Map.get(help, :related, []))}
    """
  end

  defp format_concept_help(concept) do
    """
    #{IO.ANSI.cyan()}#{concept.title}#{IO.ANSI.reset()}

    #{concept.explanation}

    Learn more: #{Enum.join(concept.learn_more, ", ")}
    """
  end

  defp format_search_results([]), do: "No help found. Try /help for general assistance."

  defp format_search_results(results) do
    grouped = Enum.group_by(results, & &1.type)

    sections = []

    sections =
      if grouped[:command] do
        command_section = """
        #{IO.ANSI.yellow()}Commands:#{IO.ANSI.reset()}
        #{format_command_results(grouped[:command])}
        """

        [command_section | sections]
      else
        sections
      end

    sections =
      if grouped[:concept] do
        concept_section = """
        #{IO.ANSI.yellow()}Concepts:#{IO.ANSI.reset()}
        #{format_concept_results(grouped[:concept])}
        """

        [concept_section | sections]
      else
        sections
      end

    sections =
      if grouped[:error] do
        error_section = """
        #{IO.ANSI.yellow()}Error Help:#{IO.ANSI.reset()}
        #{format_error_results(grouped[:error])}
        """

        [error_section | sections]
      else
        sections
      end

    Enum.join(sections, "\n")
  end

  defp format_contextual_helps([]), do: nil

  defp format_contextual_helps(helps) do
    helps
    |> Enum.map(&format_contextual_help/1)
    |> Enum.join("\n\n")
  end

  defp format_contextual_help(%{type: :command_completion, commands: commands}) do
    """
    #{IO.ANSI.yellow()}Did you mean:#{IO.ANSI.reset()}
    #{format_command_suggestions(commands)}
    """
  end

  defp format_contextual_help(help) when is_map(help) do
    """
    #{IO.ANSI.red()}Error: #{help.problem}#{IO.ANSI.reset()}

    Solutions:
    #{format_solutions(help.solutions)}

    Related: #{Enum.join(help.related, ", ")}
    """
  end

  defp format_examples(examples) do
    examples
    |> Enum.map(fn ex -> "  • #{ex}" end)
    |> Enum.join("\n")
  end

  defp format_tips([]), do: ""

  defp format_tips(tips) do
    "\nTips:\n" <>
      (tips
       |> Enum.map(fn tip -> "  💡 #{tip}" end)
       |> Enum.join("\n"))
  end

  defp format_related([]), do: ""

  defp format_related(related) do
    "\nRelated: #{Enum.join(related, ", ")}"
  end

  defp format_command_results(results) do
    results
    |> Enum.map(fn %{command: cmd, help: help} ->
      "  • #{cmd} - #{help.description}"
    end)
    |> Enum.join("\n")
  end

  defp format_concept_results(results) do
    results
    |> Enum.map(fn %{name: name, concept: concept} ->
      "  • #{name} - #{concept.title}"
    end)
    |> Enum.join("\n")
  end

  defp format_error_results(results) do
    results
    |> Enum.map(fn %{pattern: pattern, help: _help} ->
      "  • #{pattern}"
    end)
    |> Enum.join("\n")
  end

  defp format_solutions(solutions) do
    solutions
    |> Enum.with_index(1)
    |> Enum.map(fn {solution, idx} ->
      "  #{idx}. #{solution}"
    end)
    |> Enum.join("\n")
  end

  defp format_command_suggestions(commands) do
    commands
    |> Enum.map(fn %{command: cmd, description: desc} ->
      "  #{cmd} - #{desc}"
    end)
    |> Enum.join("\n")
  end

  defp normalize_query(query) do
    query
    |> String.trim()
    |> String.downcase()
    |> then(fn q ->
      if String.starts_with?(q, "/") do
        q
      else
        "/" <> q
      end
    end)
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.info("Context Help shutting down")
    :ok
  end
end
