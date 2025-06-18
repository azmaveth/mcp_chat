defmodule MCPChat.Terminal.CommandExamples do
  @moduledoc """
  Command examples and usage demonstrations.

  Provides practical examples for all commands with
  explanations and common use cases.
  """

  use GenServer
  require Logger

  # Command examples state
  defstruct [
    # Examples for each command
    :examples_database,
    # Command categories
    :categories,
    # User's favorite examples
    :favorites,
    # Examples settings
    :settings
  ]

  # Command examples database
  @examples_database %{
    # Basic commands
    "/help" => [
      %{
        command: "/help",
        description: "Show all available commands",
        output: "Lists all commands with brief descriptions"
      },
      %{
        command: "/help model",
        description: "Get detailed help for the /model command",
        output: "Shows usage, examples, and tips for /model"
      },
      %{
        command: "/help context",
        description: "Learn about context management",
        output: "Explains how to manage conversation context"
      }
    ],
    "/model" => [
      %{
        command: "/model",
        description: "Show current model and list available models",
        output: "Current: claude-3-opus-20240229\nAvailable: gpt-4, claude-3-sonnet, ..."
      },
      %{
        command: "/model gpt-4",
        description: "Switch to GPT-4 model",
        output: "Model switched to: gpt-4"
      },
      %{
        command: "/model claude-3-opus",
        description: "Switch to Claude 3 Opus",
        output: "Model switched to: claude-3-opus-20240229"
      }
    ],
    "/context" => [
      %{
        command: "/context show",
        description: "Display current conversation context",
        output: "Shows messages, files, and token count"
      },
      %{
        command: "/context add README.md",
        description: "Add a file to the context",
        output: "Added README.md (1,234 tokens)"
      },
      %{
        command: "/context clear",
        description: "Clear all context to start fresh",
        output: "Context cleared. Token count: 0"
      },
      %{
        command: "/context remove 2",
        description: "Remove the 2nd item from context",
        output: "Removed: previous_file.py"
      }
    ],
    "/alias" => [
      %{
        command: "/alias list",
        description: "Show all configured aliases",
        output: "gpt -> /model gpt-4\nclaude -> /model claude-3-opus"
      },
      %{
        command: "/alias add gpt '/model gpt-4'",
        description: "Create shortcut 'gpt' for switching to GPT-4",
        output: "Alias 'gpt' created"
      },
      %{
        command: "/alias add clear-all '/context clear; /cost reset'",
        description: "Create alias that runs multiple commands",
        output: "Alias 'clear-all' created"
      },
      %{
        command: "/alias remove gpt",
        description: "Remove the 'gpt' alias",
        output: "Alias 'gpt' removed"
      }
    ],
    "/session" => [
      %{
        command: "/session list",
        description: "List all saved sessions",
        output: "1. Project Planning (2 hours ago)\n2. Code Review (yesterday)"
      },
      %{
        command: "/session new",
        description: "Start a fresh session",
        output: "New session started: session_12345"
      },
      %{
        command: "/session load 12345",
        description: "Resume a previous session",
        output: "Session loaded: Project Planning"
      },
      %{
        command: "/session export markdown",
        description: "Export current session as markdown",
        output: "Session exported to: chat_2024-01-18.md"
      }
    ],
    "/servers" => [
      %{
        command: "/servers",
        description: "List all configured MCP servers",
        output: "filesystem (running)\ndatabase (stopped)"
      },
      %{
        command: "/servers add filesystem 'npx -y @modelcontextprotocol/server-filesystem /path'",
        description: "Add a filesystem MCP server",
        output: "Server 'filesystem' added and started"
      },
      %{
        command: "/servers restart filesystem",
        description: "Restart a server",
        output: "Server 'filesystem' restarted"
      },
      %{
        command: "/servers remove database",
        description: "Remove a server",
        output: "Server 'database' removed"
      }
    ],
    "/tools" => [
      %{
        command: "/tools",
        description: "List available MCP tools",
        output: "read_file - Read file contents\nlist_directory - List files"
      },
      %{
        command: "/tool read_file",
        description: "Get details about a specific tool",
        output: "read_file(path: string) - Reads file contents"
      }
    ],
    "/cost" => [
      %{
        command: "/cost",
        description: "Show current session costs",
        output: "Input: $0.15 | Output: $0.45 | Total: $0.60"
      },
      %{
        command: "/cost details",
        description: "Show detailed cost breakdown",
        output: "Shows per-model costs and token counts"
      },
      %{
        command: "/cost reset",
        description: "Reset cost tracking",
        output: "Cost tracking reset"
      }
    ],
    "/export" => [
      %{
        command: "/export",
        description: "Export conversation as markdown",
        output: "Exported to: conversation_2024-01-18.md"
      },
      %{
        command: "/export json",
        description: "Export as JSON with metadata",
        output: "Exported to: conversation_2024-01-18.json"
      },
      %{
        command: "/export pdf",
        description: "Export as PDF (if supported)",
        output: "Exported to: conversation_2024-01-18.pdf"
      }
    ],
    "/stats" => [
      %{
        command: "/stats",
        description: "Show conversation statistics",
        output: "Messages: 15 | Tokens: 4,523 | Duration: 45m"
      },
      %{
        command: "/stats verbose",
        description: "Show detailed statistics",
        output: "Includes model usage, tool calls, and timing"
      }
    ]
  }

  @command_categories %{
    "Session Management" => ["/session", "/export", "/import"],
    "Model & Cost" => ["/model", "/models", "/cost", "/stats"],
    "Context Control" => ["/context", "/clear", "/reset"],
    "MCP Servers" => ["/servers", "/tools", "/discover"],
    "Configuration" => ["/config", "/settings", "/alias"],
    "Help & Info" => ["/help", "/tutorial", "/about", "/version"]
  }

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get examples for a specific command.
  """
  def get_examples(pid \\ __MODULE__, command) do
    GenServer.call(pid, {:get_examples, command})
  end

  @doc """
  Get examples by category.
  """
  def get_category_examples(pid \\ __MODULE__, category) do
    GenServer.call(pid, {:get_category_examples, category})
  end

  @doc """
  Search for examples.
  """
  def search_examples(pid \\ __MODULE__, query) do
    GenServer.call(pid, {:search_examples, query})
  end

  @doc """
  Get random example.
  """
  def get_random_example(pid \\ __MODULE__, options \\ %{}) do
    GenServer.call(pid, {:get_random_example, options})
  end

  @doc """
  Mark example as favorite.
  """
  def add_favorite(pid \\ __MODULE__, command, example_index) do
    GenServer.call(pid, {:add_favorite, command, example_index})
  end

  @doc """
  Get favorite examples.
  """
  def get_favorites(pid \\ __MODULE__) do
    GenServer.call(pid, :get_favorites)
  end

  @doc """
  Get command categories.
  """
  def get_categories(pid \\ __MODULE__) do
    GenServer.call(pid, :get_categories)
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    Logger.info("Starting Command Examples")

    settings = %{
      max_examples_per_command: Keyword.get(opts, :max_examples_per_command, 5),
      include_output: Keyword.get(opts, :include_output, true),
      syntax_highlighting: Keyword.get(opts, :syntax_highlighting, true)
    }

    # Load user favorites
    favorites = load_user_favorites()

    state = %__MODULE__{
      examples_database: @examples_database,
      categories: @command_categories,
      favorites: favorites,
      settings: settings
    }

    Logger.info("Command Examples initialized",
      commands: map_size(@examples_database),
      total_examples: count_total_examples(@examples_database)
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:get_examples, command}, _from, state) do
    examples = Map.get(state.examples_database, normalize_command(command), [])
    formatted = format_examples(examples, command, state)
    {:reply, formatted, state}
  end

  @impl true
  def handle_call({:get_category_examples, category}, _from, state) do
    commands = Map.get(state.categories, category, [])

    examples =
      commands
      |> Enum.flat_map(fn cmd ->
        Map.get(state.examples_database, cmd, [])
        |> Enum.map(fn ex -> Map.put(ex, :command_name, cmd) end)
      end)

    formatted = format_category_examples(examples, category, state)
    {:reply, formatted, state}
  end

  @impl true
  def handle_call({:search_examples, query}, _from, state) do
    results = search_in_examples(query, state)
    formatted = format_search_results(results, query, state)
    {:reply, formatted, state}
  end

  @impl true
  def handle_call({:get_random_example, options}, _from, state) do
    category = Map.get(options, :category)
    command = Map.get(options, :command)

    example = get_random_from_criteria(state, category, command)
    formatted = format_single_example(example, state)
    {:reply, formatted, state}
  end

  @impl true
  def handle_call({:add_favorite, command, example_index}, _from, state) do
    normalized = normalize_command(command)

    case Map.get(state.examples_database, normalized) do
      nil ->
        {:reply, {:error, :command_not_found}, state}

      examples ->
        if example_index >= 0 and example_index < length(examples) do
          favorite_key = {normalized, example_index}
          new_favorites = MapSet.put(state.favorites, favorite_key)
          new_state = %{state | favorites: new_favorites}
          save_user_favorites(new_favorites)
          {:reply, :ok, new_state}
        else
          {:reply, {:error, :invalid_index}, state}
        end
    end
  end

  @impl true
  def handle_call(:get_favorites, _from, state) do
    favorite_examples =
      state.favorites
      |> Enum.map(fn {cmd, idx} ->
        examples = Map.get(state.examples_database, cmd, [])
        example = Enum.at(examples, idx)
        if example, do: Map.put(example, :command_name, cmd), else: nil
      end)
      |> Enum.filter(&(&1 != nil))

    formatted = format_favorites(favorite_examples, state)
    {:reply, formatted, state}
  end

  @impl true
  def handle_call(:get_categories, _from, state) do
    categories =
      state.categories
      |> Enum.map(fn {name, commands} ->
        %{
          name: name,
          commands: commands,
          example_count: count_category_examples(commands, state)
        }
      end)

    {:reply, categories, state}
  end

  # Private functions

  defp format_examples([], command, _state) do
    "No examples found for #{command}. Try /help #{command} for basic usage."
  end

  defp format_examples(examples, command, state) do
    header = "#{IO.ANSI.cyan()}Examples for #{command}:#{IO.ANSI.reset()}\n"

    formatted_examples =
      examples
      |> Enum.with_index(1)
      |> Enum.map(fn {example, idx} ->
        format_example_item(example, idx, state)
      end)
      |> Enum.join("\n\n")

    header <> formatted_examples
  end

  defp format_example_item(example, index, state) do
    lines = [
      "#{IO.ANSI.yellow()}#{index}.#{IO.ANSI.reset()} #{example.description}",
      "   #{IO.ANSI.green()}$#{IO.ANSI.reset()} #{highlight_command(example.command, state)}"
    ]

    lines =
      if state.settings.include_output and example[:output] do
        lines ++ ["   #{IO.ANSI.light_black()}→ #{example.output}#{IO.ANSI.reset()}"]
      else
        lines
      end

    Enum.join(lines, "\n")
  end

  defp format_category_examples([], category, _state) do
    "No examples found for category: #{category}"
  end

  defp format_category_examples(examples, category, state) do
    header = "#{IO.ANSI.cyan()}#{category} Examples:#{IO.ANSI.reset()}\n"

    grouped = Enum.group_by(examples, & &1.command_name)

    formatted =
      grouped
      |> Enum.map(fn {cmd, cmd_examples} ->
        "#{IO.ANSI.yellow()}#{cmd}#{IO.ANSI.reset()}\n" <>
          (cmd_examples
           |> Enum.map(fn ex ->
             "  • #{ex.description}\n    #{highlight_command(ex.command, state)}"
           end)
           |> Enum.join("\n"))
      end)
      |> Enum.join("\n\n")

    header <> formatted
  end

  defp format_search_results([], query, _state) do
    "No examples found matching '#{query}'"
  end

  defp format_search_results(results, query, state) do
    header = "#{IO.ANSI.cyan()}Examples matching '#{query}':#{IO.ANSI.reset()}\n"

    formatted =
      results
      |> Enum.map(fn {cmd, example} ->
        "#{IO.ANSI.yellow()}#{cmd}#{IO.ANSI.reset()}\n" <>
          "  #{example.description}\n" <>
          "  #{highlight_command(example.command, state)}"
      end)
      |> Enum.join("\n\n")

    header <> formatted
  end

  defp format_single_example(nil, _state) do
    "No example available"
  end

  defp format_single_example(example, state) do
    """
    #{IO.ANSI.cyan()}Random Example:#{IO.ANSI.reset()}

    #{example.description}
    #{highlight_command(example.command, state)}
    #{if example[:output], do: "\n→ #{example.output}", else: ""}

    #{IO.ANSI.light_black()}Command: #{example.command_name}#{IO.ANSI.reset()}
    """
  end

  defp format_favorites([], _state) do
    "No favorite examples saved. Use /example favorite <command> <number> to add favorites."
  end

  defp format_favorites(favorites, state) do
    header = "#{IO.ANSI.cyan()}Favorite Examples:#{IO.ANSI.reset()}\n"

    formatted =
      favorites
      |> Enum.with_index(1)
      |> Enum.map(fn {example, idx} ->
        format_example_item(example, idx, state)
      end)
      |> Enum.join("\n\n")

    header <> formatted
  end

  defp highlight_command(command, state) do
    if state.settings.syntax_highlighting do
      # Simple command highlighting
      command
      |> String.replace(~r/^(\/\w+)/, "#{IO.ANSI.green()}\\1#{IO.ANSI.reset()}")
      |> String.replace(~r/'([^']+)'/, "#{IO.ANSI.yellow()}'\\1'#{IO.ANSI.reset()}")
    else
      command
    end
  end

  defp search_in_examples(query, state) do
    query_lower = String.downcase(query)

    state.examples_database
    |> Enum.flat_map(fn {cmd, examples} ->
      examples
      |> Enum.filter(fn ex ->
        String.contains?(String.downcase(ex.command), query_lower) or
          String.contains?(String.downcase(ex.description), query_lower) or
          String.contains?(String.downcase(Map.get(ex, :output, "")), query_lower)
      end)
      |> Enum.map(fn ex -> {cmd, ex} end)
    end)
    |> Enum.take(10)
  end

  defp get_random_from_criteria(state, nil, nil) do
    # Get random from all examples
    all_examples =
      state.examples_database
      |> Enum.flat_map(fn {cmd, examples} ->
        Enum.map(examples, fn ex -> Map.put(ex, :command_name, cmd) end)
      end)

    if length(all_examples) > 0 do
      Enum.random(all_examples)
    else
      nil
    end
  end

  defp get_random_from_criteria(state, category, nil) when is_binary(category) do
    # Get random from category
    commands = Map.get(state.categories, category, [])

    examples =
      commands
      |> Enum.flat_map(fn cmd ->
        Map.get(state.examples_database, cmd, [])
        |> Enum.map(fn ex -> Map.put(ex, :command_name, cmd) end)
      end)

    if length(examples) > 0 do
      Enum.random(examples)
    else
      nil
    end
  end

  defp get_random_from_criteria(state, _category, command) when is_binary(command) do
    # Get random from specific command
    normalized = normalize_command(command)
    examples = Map.get(state.examples_database, normalized, [])

    if length(examples) > 0 do
      example = Enum.random(examples)
      Map.put(example, :command_name, normalized)
    else
      nil
    end
  end

  defp normalize_command(command) do
    command
    |> String.trim()
    |> then(fn cmd ->
      if String.starts_with?(cmd, "/") do
        cmd
      else
        "/" <> cmd
      end
    end)
  end

  defp count_total_examples(database) do
    database
    |> Enum.map(fn {_cmd, examples} -> length(examples) end)
    |> Enum.sum()
  end

  defp count_category_examples(commands, state) do
    commands
    |> Enum.map(fn cmd ->
      length(Map.get(state.examples_database, cmd, []))
    end)
    |> Enum.sum()
  end

  defp load_user_favorites() do
    # Load from persistent storage
    # This would integrate with the persistence system
    MapSet.new()
  end

  defp save_user_favorites(_favorites) do
    # Save to persistent storage
    # This would integrate with the persistence system
    :ok
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.info("Command Examples shutting down")
    :ok
  end
end
