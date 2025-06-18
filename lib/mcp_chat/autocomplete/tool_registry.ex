defmodule MCPChat.Autocomplete.ToolRegistry do
  @moduledoc """
  Registry and database of CLI tools for intelligent autocomplete.

  Maintains a comprehensive database of available CLI tools,
  their capabilities, and provides intelligent suggestions
  based on context and tool availability.
  """

  use GenServer
  require Logger

  # 5 minutes
  @tool_scan_interval 300_000
  # 10 minutes
  @path_cache_ttl 600_000
  @max_tools_per_category 50

  # Tool registry state
  defstruct [
    # Comprehensive tool information
    :tool_database,
    # Tools available in system PATH
    :system_tools,
    # Project-specific tools
    :project_tools,
    # User-defined tools
    :custom_tools,
    # Categorized tool listings
    :tool_categories,
    # Cached PATH scanning results
    :path_cache,
    # Last tool scan timestamp
    :scan_timestamp,
    # Registry settings
    :settings
  ]

  # Tool categories for organization
  @tool_categories %{
    development: ["git", "docker", "npm", "yarn", "pip", "cargo", "go", "mix", "maven"],
    file_management: ["ls", "cp", "mv", "rm", "find", "grep", "awk", "sed", "sort"],
    network: ["curl", "wget", "ssh", "ping", "netstat", "nmap", "tcpdump"],
    system: ["ps", "top", "htop", "kill", "systemctl", "service", "crontab"],
    text_processing: ["cat", "less", "more", "head", "tail", "cut", "tr", "wc"],
    compression: ["tar", "gzip", "zip", "unzip", "7z", "bzip2"],
    monitoring: ["watch", "df", "du", "free", "iostat", "vmstat"],
    database: ["mysql", "psql", "sqlite3", "redis-cli", "mongo"]
  }

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get tool suggestions based on input and context.
  """
  def get_tool_suggestions(pid \\ __MODULE__, input, context \\ %{}) do
    GenServer.call(pid, {:get_tool_suggestions, input, context})
  end

  @doc """
  Get tools by category.
  """
  def get_tools_by_category(pid \\ __MODULE__, category) do
    GenServer.call(pid, {:get_tools_by_category, category})
  end

  @doc """
  Check if a tool is available in the system.
  """
  def is_tool_available?(pid \\ __MODULE__, tool_name) do
    GenServer.call(pid, {:is_tool_available, tool_name})
  end

  @doc """
  Get detailed information about a specific tool.
  """
  def get_tool_info(pid \\ __MODULE__, tool_name) do
    GenServer.call(pid, {:get_tool_info, tool_name})
  end

  @doc """
  Register a custom tool with the registry.
  """
  def register_custom_tool(pid \\ __MODULE__, tool_info) do
    GenServer.call(pid, {:register_custom_tool, tool_info})
  end

  @doc """
  Refresh the tool database by rescanning the system.
  """
  def refresh_tools(pid \\ __MODULE__) do
    GenServer.call(pid, :refresh_tools)
  end

  @doc """
  Get comprehensive tool statistics.
  """
  def get_tool_stats(pid \\ __MODULE__) do
    GenServer.call(pid, :get_tool_stats)
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    Logger.info("Starting Tool Registry")

    settings = %{
      scan_interval: Keyword.get(opts, :scan_interval, @tool_scan_interval),
      cache_ttl: Keyword.get(opts, :cache_ttl, @path_cache_ttl),
      max_tools_per_category: Keyword.get(opts, :max_tools_per_category, @max_tools_per_category),
      enable_periodic_scan: Keyword.get(opts, :enable_periodic_scan, true),
      include_system_tools: Keyword.get(opts, :include_system_tools, true)
    }

    state = %__MODULE__{
      tool_database: %{},
      system_tools: %{},
      project_tools: %{},
      custom_tools: %{},
      tool_categories: @tool_categories,
      path_cache: %{},
      scan_timestamp: nil,
      settings: settings
    }

    # Perform initial tool scan
    initial_state = perform_initial_tool_scan(state)

    # Schedule periodic rescans if enabled
    if settings.enable_periodic_scan do
      schedule_tool_scan(settings.scan_interval)
    end

    Logger.info("Tool Registry initialized",
      system_tools: map_size(initial_state.system_tools),
      categories: map_size(initial_state.tool_categories),
      settings: settings
    )

    {:ok, initial_state}
  end

  @impl true
  def handle_call({:get_tool_suggestions, input, context}, _from, state) do
    suggestions = generate_tool_suggestions(input, context, state)
    {:reply, suggestions, state}
  end

  @impl true
  def handle_call({:get_tools_by_category, category}, _from, state) do
    tools = get_category_tools(category, state)
    {:reply, tools, state}
  end

  @impl true
  def handle_call({:is_tool_available, tool_name}, _from, state) do
    available = check_tool_availability(tool_name, state)
    {:reply, available, state}
  end

  @impl true
  def handle_call({:get_tool_info, tool_name}, _from, state) do
    info = get_detailed_tool_info(tool_name, state)
    {:reply, info, state}
  end

  @impl true
  def handle_call({:register_custom_tool, tool_info}, _from, state) do
    new_state = register_tool_in_database(tool_info, state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:refresh_tools, _from, state) do
    new_state = perform_complete_tool_scan(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_tool_stats, _from, state) do
    stats = compile_tool_statistics(state)
    {:reply, stats, state}
  end

  @impl true
  def handle_info(:scan_tools, state) do
    new_state = perform_incremental_tool_scan(state)

    # Schedule next scan
    if state.settings.enable_periodic_scan do
      schedule_tool_scan(state.settings.scan_interval)
    end

    {:noreply, new_state}
  end

  # Private functions

  defp perform_initial_tool_scan(state) do
    Logger.info("Performing initial tool scan")

    # Scan system PATH for available tools
    system_tools =
      if state.settings.include_system_tools do
        scan_system_path()
      else
        %{}
      end

    # Build comprehensive tool database
    tool_database = build_tool_database(system_tools, state.tool_categories)

    %{state | system_tools: system_tools, tool_database: tool_database, scan_timestamp: DateTime.utc_now()}
  end

  defp perform_complete_tool_scan(state) do
    Logger.info("Performing complete tool rescan")

    # Clear existing caches
    cleared_state = %{state | path_cache: %{}, system_tools: %{}}

    # Perform full scan
    perform_initial_tool_scan(cleared_state)
  end

  defp perform_incremental_tool_scan(state) do
    # For now, just update timestamp and refresh core tools
    # Could be enhanced to detect PATH changes
    current_time = DateTime.utc_now()

    if DateTime.diff(current_time, state.scan_timestamp || current_time, :millisecond) > state.settings.cache_ttl do
      perform_complete_tool_scan(state)
    else
      state
    end
  end

  defp scan_system_path do
    path_env = System.get_env("PATH", "")

    path_separator =
      case :os.type() do
        {:win32, _} -> ";"
        _ -> ":"
      end

    path_env
    |> String.split(path_separator)
    |> Enum.reject(&(&1 == ""))
    |> Enum.flat_map(&scan_path_directory/1)
    |> Enum.reduce(%{}, fn {tool, path}, acc ->
      Map.put_new(acc, tool, %{
        name: tool,
        path: path,
        type: :system_tool,
        available: true,
        source: :path_scan
      })
    end)
  end

  defp scan_path_directory(directory) do
    case File.ls(directory) do
      {:ok, files} ->
        files
        |> Enum.filter(&is_executable?(Path.join(directory, &1)))
        |> Enum.map(fn file ->
          {file, Path.join(directory, file)}
        end)

      {:error, _} ->
        []
    end
  end

  defp is_executable?(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, mode: mode}} ->
        # Check if executable bit is set (basic check)
        import Bitwise
        (mode &&& 0o111) != 0

      _ ->
        false
    end
  end

  defp build_tool_database(system_tools, categories) do
    # Start with system tools
    database = system_tools

    # Add categorized tools with enhanced information
    Enum.reduce(categories, database, fn {category, tool_list}, acc ->
      Enum.reduce(tool_list, acc, fn tool, tool_acc ->
        enhanced_info = enhance_tool_info(tool, category, system_tools)
        Map.put(tool_acc, tool, enhanced_info)
      end)
    end)
  end

  defp enhance_tool_info(tool_name, category, system_tools) do
    base_info = %{
      name: tool_name,
      category: category,
      description: get_tool_description(tool_name),
      common_flags: get_common_flags(tool_name),
      examples: get_tool_examples(tool_name)
    }

    case Map.get(system_tools, tool_name) do
      nil ->
        Map.merge(base_info, %{
          available: false,
          path: nil,
          type: :known_tool,
          source: :database
        })

      system_info ->
        Map.merge(base_info, system_info)
    end
  end

  defp get_tool_description(tool_name) do
    descriptions = %{
      # Development tools
      "git" => "Distributed version control system",
      "docker" => "Container platform for applications",
      "npm" => "Node.js package manager",
      "yarn" => "Fast, reliable package manager",
      "pip" => "Python package installer",
      "cargo" => "Rust package manager and build system",
      "go" => "Go programming language compiler",
      "mix" => "Elixir build tool and task runner",
      "maven" => "Java project management tool",

      # File management
      "ls" => "List directory contents",
      "cp" => "Copy files and directories",
      "mv" => "Move/rename files and directories",
      "rm" => "Remove files and directories",
      "find" => "Search for files and directories",
      "grep" => "Search text patterns in files",
      "awk" => "Text processing and data extraction",
      "sed" => "Stream editor for filtering and transforming text",
      "sort" => "Sort lines of text files",

      # Network tools
      "curl" => "Command line HTTP client",
      "wget" => "Web file downloader",
      "ssh" => "Secure shell remote access",
      "ping" => "Network connectivity test",
      "netstat" => "Network connections and statistics",

      # System tools
      "ps" => "Display running processes",
      "top" => "Display and update sorted information about running processes",
      "htop" => "Interactive process viewer",
      "kill" => "Terminate processes by PID",
      "systemctl" => "Control systemd services",

      # Text processing
      "cat" => "Display file contents",
      "less" => "View file contents with pagination",
      "head" => "Display first lines of files",
      "tail" => "Display last lines of files",
      "cut" => "Extract columns from text",
      "wc" => "Count lines, words, and characters"
    }

    Map.get(descriptions, tool_name, "Command line tool: #{tool_name}")
  end

  defp get_common_flags(tool_name) do
    flags = %{
      "ls" => ["-l", "-a", "-la", "-lh", "-R"],
      "git" => ["status", "add", "commit", "push", "pull", "log", "diff"],
      "docker" => ["ps", "images", "run", "build", "logs", "exec"],
      "grep" => ["-r", "-n", "-i", "-v", "--color"],
      "find" => ["-name", "-type", "-exec", "-print"],
      "curl" => ["-X", "-H", "-d", "-o", "-s", "-v"],
      "ssh" => ["-i", "-p", "-L", "-R", "-X"],
      "tar" => ["-czf", "-xzf", "-tzf", "-cjf", "-xjf"],
      "ps" => ["aux", "-ef", "-A"],
      "kill" => ["-9", "-15", "-TERM", "-KILL"]
    }

    Map.get(flags, tool_name, [])
  end

  defp get_tool_examples(tool_name) do
    examples = %{
      "git" => [
        "git status",
        "git add .",
        "git commit -m \"message\"",
        "git push origin main"
      ],
      "docker" => [
        "docker ps",
        "docker images",
        "docker run -it ubuntu",
        "docker logs container_name"
      ],
      "curl" => [
        "curl -X GET https://api.example.com",
        "curl -H \"Content-Type: application/json\" -d '{\"key\":\"value\"}' https://api.example.com",
        "curl -o file.txt https://example.com/file.txt"
      ],
      "grep" => [
        "grep -r \"pattern\" .",
        "grep -n \"search\" file.txt",
        "grep -i \"case_insensitive\" file.txt"
      ]
    }

    Map.get(examples, tool_name, [])
  end

  defp generate_tool_suggestions(input, context, state) do
    suggestions = []

    # Get suggestions from different sources
    suggestions = suggestions ++ get_prefix_matches(input, state)
    suggestions = suggestions ++ get_fuzzy_matches(input, state)
    suggestions = suggestions ++ get_context_suggestions(input, context, state)

    # Sort and deduplicate
    suggestions
    |> Enum.uniq()
    |> sort_tool_suggestions(input, context, state)
    |> Enum.take(20)
  end

  defp get_prefix_matches(input, state) do
    input_lower = String.downcase(input)

    state.tool_database
    |> Enum.filter(fn {tool_name, _info} ->
      String.starts_with?(String.downcase(tool_name), input_lower)
    end)
    |> Enum.map(fn {tool_name, _info} -> tool_name end)
  end

  defp get_fuzzy_matches(input, state) do
    if String.length(input) >= 2 do
      input_lower = String.downcase(input)

      state.tool_database
      |> Enum.filter(fn {tool_name, _info} ->
        tool_lower = String.downcase(tool_name)

        String.contains?(tool_lower, input_lower) and
          not String.starts_with?(tool_lower, input_lower)
      end)
      |> Enum.map(fn {tool_name, _info} -> tool_name end)
    else
      []
    end
  end

  defp get_context_suggestions(input, context, _state) do
    # Get tools relevant to current project type
    project_type = get_in(context, [:project, :type])

    case project_type do
      :elixir -> ["mix", "iex", "elixir"]
      :javascript -> ["npm", "yarn", "node", "npx"]
      :python -> ["pip", "python", "pytest"]
      :rust -> ["cargo", "rustc", "rustfmt"]
      :go -> ["go", "gofmt"]
      _ -> []
    end
    |> Enum.filter(fn tool ->
      String.starts_with?(String.downcase(tool), String.downcase(input))
    end)
  end

  defp sort_tool_suggestions(suggestions, input, context, state) do
    input_lower = String.downcase(input)

    suggestions
    |> Enum.map(fn tool ->
      score = calculate_tool_score(tool, input_lower, context, state)
      {tool, score}
    end)
    |> Enum.sort_by(fn {_tool, score} -> score end, :desc)
    |> Enum.map(fn {tool, _score} -> tool end)
  end

  defp calculate_tool_score(tool, input_lower, context, state) do
    tool_lower = String.downcase(tool)
    base_score = 0

    # Exact prefix match gets highest score
    base_score =
      if String.starts_with?(tool_lower, input_lower) do
        base_score + 1000
      else
        base_score
      end

    # Available tools get higher score
    base_score =
      if check_tool_availability(tool, state) do
        base_score + 500
      else
        base_score
      end

    # Context relevance
    base_score = base_score + calculate_context_score(tool, context, state)

    # Category priority
    base_score + calculate_category_score(tool, state)
  end

  defp calculate_context_score(tool, context, _state) do
    project_type = get_in(context, [:project, :type])

    case {project_type, tool} do
      {:elixir, tool} when tool in ["mix", "iex", "elixir"] -> 200
      {:javascript, tool} when tool in ["npm", "yarn", "node"] -> 200
      {:python, tool} when tool in ["pip", "python", "pytest"] -> 200
      {:rust, tool} when tool in ["cargo", "rustc"] -> 200
      {:go, tool} when tool in ["go", "gofmt"] -> 200
      _ -> 0
    end
  end

  defp calculate_category_score(tool, state) do
    case get_tool_category(tool, state) do
      :development -> 100
      :file_management -> 80
      :network -> 60
      :system -> 40
      _ -> 20
    end
  end

  defp get_tool_category(tool, state) do
    case Map.get(state.tool_database, tool) do
      %{category: category} -> category
      _ -> :unknown
    end
  end

  defp get_category_tools(category, state) do
    case Map.get(state.tool_categories, category) do
      nil ->
        []

      tool_list ->
        tool_list
        |> Enum.take(state.settings.max_tools_per_category)
        |> Enum.map(fn tool ->
          case Map.get(state.tool_database, tool) do
            nil -> %{name: tool, available: false}
            info -> info
          end
        end)
    end
  end

  defp check_tool_availability(tool_name, state) do
    case Map.get(state.tool_database, tool_name) do
      %{available: available} ->
        available

      _ ->
        # Fallback to direct check
        case System.cmd("which", [tool_name], stderr_to_stdout: true) do
          {_, 0} -> true
          _ -> false
        end
    end
  end

  defp get_detailed_tool_info(tool_name, state) do
    case Map.get(state.tool_database, tool_name) do
      nil -> %{name: tool_name, available: false, source: :unknown}
      info -> info
    end
  end

  defp register_tool_in_database(tool_info, state) do
    tool_name = Map.get(tool_info, :name) || Map.get(tool_info, "name")

    if tool_name do
      new_custom_tools = Map.put(state.custom_tools, tool_name, tool_info)
      new_database = Map.put(state.tool_database, tool_name, tool_info)

      %{state | custom_tools: new_custom_tools, tool_database: new_database}
    else
      state
    end
  end

  defp compile_tool_statistics(state) do
    %{
      total_tools: map_size(state.tool_database),
      system_tools: map_size(state.system_tools),
      custom_tools: map_size(state.custom_tools),
      available_tools: count_available_tools(state.tool_database),
      categories: map_size(state.tool_categories),
      last_scan: state.scan_timestamp,
      cache_size: map_size(state.path_cache)
    }
  end

  defp count_available_tools(tool_database) do
    tool_database
    |> Map.values()
    |> Enum.count(fn info -> Map.get(info, :available, false) end)
  end

  defp schedule_tool_scan(interval) do
    Process.send_after(self(), :scan_tools, interval)
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.info("Tool Registry shutting down")
    :ok
  end
end
