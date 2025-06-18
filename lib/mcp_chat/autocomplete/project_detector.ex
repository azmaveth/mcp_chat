defmodule MCPChat.Autocomplete.ProjectDetector do
  @moduledoc """
  Detects and analyzes project context for intelligent autocomplete.

  Identifies project type, structure, available tools, and other
  contextual information to provide more relevant suggestions.
  """

  use GenServer
  require Logger

  # 5 minutes
  @context_cache_ttl 300_000
  @scan_depth 3
  @supported_project_types [
    :elixir,
    :javascript,
    :python,
    :rust,
    :go,
    :ruby,
    :java,
    :c_cpp,
    :php,
    :unknown
  ]

  # Project detector state
  defstruct [
    # Cached project information
    :project_cache,
    # Directory scan results
    :scan_results,
    # Last context update
    :context_timestamp,
    # Detection settings
    :settings
  ]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get current project context.
  """
  def get_project_context(pid \\ __MODULE__, directory \\ nil) do
    GenServer.call(pid, {:get_project_context, directory})
  end

  @doc """
  Detect project type for a specific directory.
  """
  def detect_project_type(directory \\ nil) do
    GenServer.call(__MODULE__, {:detect_project_type, directory})
  end

  @doc """
  Get available project tools and commands.
  """
  def get_project_tools(pid \\ __MODULE__, directory \\ nil) do
    GenServer.call(pid, {:get_project_tools, directory})
  end

  @doc """
  Refresh project context cache.
  """
  def refresh_context(pid \\ __MODULE__) do
    GenServer.call(pid, :refresh_context)
  end

  @doc """
  Get project structure information.
  """
  def analyze_project_structure(pid \\ __MODULE__, directory \\ nil) do
    GenServer.call(pid, {:analyze_project_structure, directory})
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    Logger.info("Starting Project Detector")

    settings = %{
      cache_ttl: Keyword.get(opts, :cache_ttl, @context_cache_ttl),
      scan_depth: Keyword.get(opts, :scan_depth, @scan_depth),
      auto_refresh: Keyword.get(opts, :auto_refresh, true)
    }

    state = %__MODULE__{
      project_cache: %{},
      scan_results: %{},
      context_timestamp: nil,
      settings: settings
    }

    # Initial context detection
    initial_state = perform_initial_scan(state)

    Logger.info("Project Detector initialized",
      cache_size: map_size(initial_state.project_cache),
      settings: initial_state.settings
    )

    {:ok, initial_state}
  end

  @impl true
  def handle_call({:get_project_context, directory}, _from, state) do
    working_dir = directory || File.cwd!()

    case get_cached_context(working_dir, state) do
      {:hit, context} ->
        {:reply, context, state}

      {:miss, _reason} ->
        {context, new_state} = detect_and_cache_context(working_dir, state)
        {:reply, context, new_state}
    end
  end

  @impl true
  def handle_call({:detect_project_type, directory}, _from, state) do
    working_dir = directory || File.cwd!()
    project_type = perform_project_type_detection(working_dir)
    {:reply, project_type, state}
  end

  @impl true
  def handle_call({:get_project_tools, directory}, _from, state) do
    working_dir = directory || File.cwd!()

    # Get project context first
    {context, new_state} =
      case get_cached_context(working_dir, state) do
        {:hit, ctx} -> {ctx, state}
        {:miss, _} -> detect_and_cache_context(working_dir, state)
      end

    tools = extract_project_tools(context)
    {:reply, tools, new_state}
  end

  @impl true
  def handle_call(:refresh_context, _from, state) do
    new_state = %{state | project_cache: %{}, scan_results: %{}, context_timestamp: nil}

    refreshed_state = perform_initial_scan(new_state)
    {:reply, :ok, refreshed_state}
  end

  @impl true
  def handle_call({:analyze_project_structure, directory}, _from, state) do
    working_dir = directory || File.cwd!()
    structure = perform_structure_analysis(working_dir, state.settings.scan_depth)
    {:reply, structure, state}
  end

  # Private functions

  defp perform_initial_scan(state) do
    current_dir = File.cwd!()
    {_context, new_state} = detect_and_cache_context(current_dir, state)
    new_state
  end

  defp get_cached_context(directory, state) do
    case Map.get(state.project_cache, directory) do
      nil ->
        {:miss, :not_found}

      {context, timestamp} ->
        current_time = System.monotonic_time(:millisecond)

        if timestamp > current_time - state.settings.cache_ttl do
          {:hit, context}
        else
          {:miss, :expired}
        end
    end
  end

  defp detect_and_cache_context(directory, state) do
    context = perform_context_detection(directory)
    timestamp = System.monotonic_time(:millisecond)

    new_cache = Map.put(state.project_cache, directory, {context, timestamp})
    new_state = %{state | project_cache: new_cache, context_timestamp: DateTime.utc_now()}

    {context, new_state}
  end

  defp perform_context_detection(directory) do
    %{
      type: perform_project_type_detection(directory),
      root: find_project_root(directory),
      structure: perform_structure_analysis(directory, @scan_depth),
      tools: detect_available_tools(directory),
      dependencies: analyze_dependencies(directory),
      configuration: detect_configuration_files(directory),
      scripts: detect_project_scripts(directory),
      metadata: extract_project_metadata(directory)
    }
  end

  defp perform_project_type_detection(directory) do
    markers = [
      {:elixir, ["mix.exs"]},
      {:javascript, ["package.json", "yarn.lock", "package-lock.json"]},
      {:python, ["requirements.txt", "pyproject.toml", "setup.py", "Pipfile"]},
      {:rust, ["Cargo.toml", "Cargo.lock"]},
      {:go, ["go.mod", "go.sum"]},
      {:ruby, ["Gemfile", "Gemfile.lock", ".ruby-version"]},
      {:java, ["pom.xml", "build.gradle", "gradlew"]},
      {:c_cpp, ["Makefile", "CMakeLists.txt", "configure", "configure.ac"]},
      {:php, ["composer.json", "composer.lock"]}
    ]

    detected_types =
      Enum.filter(markers, fn {_type, files} ->
        Enum.any?(files, fn file ->
          File.exists?(Path.join(directory, file))
        end)
      end)

    case detected_types do
      [{type, _} | _] -> type
      [] -> :unknown
    end
  end

  defp find_project_root(directory) do
    root_markers = [
      ".git",
      ".hg",
      ".svn",
      "mix.exs",
      "package.json",
      "requirements.txt",
      "Cargo.toml",
      "go.mod",
      "Gemfile",
      "pom.xml",
      "composer.json"
    ]

    find_project_root_recursive(directory, root_markers)
  end

  defp find_project_root_recursive(directory, markers) do
    if Enum.any?(markers, fn marker ->
         File.exists?(Path.join(directory, marker))
       end) do
      directory
    else
      parent = Path.dirname(directory)

      if parent == directory do
        # Reached filesystem root
        directory
      else
        find_project_root_recursive(parent, markers)
      end
    end
  end

  defp perform_structure_analysis(directory, depth) do
    analyze_directory_recursive(directory, depth, 0)
  end

  defp analyze_directory_recursive(directory, max_depth, current_depth) do
    if current_depth >= max_depth do
      %{depth_limit_reached: true}
    else
      case File.ls(directory) do
        {:ok, entries} ->
          %{
            files: count_files(directory, entries),
            directories: count_directories(directory, entries),
            hidden_files: count_hidden_files(entries),
            total_entries: length(entries),
            subdirectories: analyze_subdirectories(directory, entries, max_depth, current_depth),
            notable_files: find_notable_files(entries),
            size_estimate: estimate_directory_size(entries)
          }

        {:error, reason} ->
          %{error: reason, accessible: false}
      end
    end
  end

  defp analyze_subdirectories(directory, entries, max_depth, current_depth) do
    entries
    |> Enum.filter(fn entry ->
      path = Path.join(directory, entry)
      File.dir?(path) and not String.starts_with?(entry, ".")
    end)
    # Limit subdirectory analysis
    |> Enum.take(5)
    |> Enum.map(fn subdir ->
      subdir_path = Path.join(directory, subdir)
      {subdir, analyze_directory_recursive(subdir_path, max_depth, current_depth + 1)}
    end)
    |> Enum.into(%{})
  end

  defp count_files(directory, entries) do
    Enum.count(entries, fn entry ->
      File.regular?(Path.join(directory, entry))
    end)
  end

  defp count_directories(directory, entries) do
    Enum.count(entries, fn entry ->
      File.dir?(Path.join(directory, entry))
    end)
  end

  defp count_hidden_files(entries) do
    Enum.count(entries, &String.starts_with?(&1, "."))
  end

  defp find_notable_files(entries) do
    notable_patterns = [
      "README",
      "LICENSE",
      "CHANGELOG",
      "CONTRIBUTING",
      "Dockerfile",
      "docker-compose",
      ".gitignore",
      ".env"
    ]

    Enum.filter(entries, fn entry ->
      Enum.any?(notable_patterns, fn pattern ->
        String.contains?(String.upcase(entry), String.upcase(pattern))
      end)
    end)
  end

  defp estimate_directory_size(entries) do
    case length(entries) do
      count when count < 10 -> :small
      count when count < 50 -> :medium
      count when count < 200 -> :large
      _ -> :very_large
    end
  end

  defp detect_available_tools(directory) do
    tools = []

    # Check project-specific tools
    tools =
      case perform_project_type_detection(directory) do
        :elixir ->
          ["mix", "iex", "elixir", "dialyzer", "credo"] ++ tools

        :javascript ->
          check_js_tools(directory) ++ tools

        :python ->
          check_python_tools(directory) ++ tools

        :rust ->
          ["cargo", "rustc", "rustfmt", "clippy"] ++ tools

        :go ->
          ["go", "gofmt", "golint"] ++ tools

        _ ->
          tools
      end

    # Check for common development tools
    system_tools = ["git", "docker", "make", "curl", "jq"]
    available_system_tools = Enum.filter(system_tools, &tool_available?/1)

    tools ++ available_system_tools
  end

  defp check_js_tools(directory) do
    tools = ["node", "npm"]

    tools =
      if File.exists?(Path.join(directory, "yarn.lock")) do
        ["yarn" | tools]
      else
        tools
      end

    tools =
      if File.exists?(Path.join(directory, "webpack.config.js")) do
        ["webpack" | tools]
      else
        tools
      end

    tools
  end

  defp check_python_tools(directory) do
    tools = ["python", "pip"]

    tools =
      if File.exists?(Path.join(directory, "Pipfile")) do
        ["pipenv" | tools]
      else
        tools
      end

    tools =
      if File.exists?(Path.join(directory, "poetry.lock")) do
        ["poetry" | tools]
      else
        tools
      end

    tools
  end

  defp tool_available?(tool) do
    case System.cmd("which", [tool], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  end

  defp analyze_dependencies(directory) do
    case perform_project_type_detection(directory) do
      :elixir -> analyze_elixir_dependencies(directory)
      :javascript -> analyze_js_dependencies(directory)
      :python -> analyze_python_dependencies(directory)
      :rust -> analyze_rust_dependencies(directory)
      _ -> %{}
    end
  end

  defp analyze_elixir_dependencies(directory) do
    mix_file = Path.join(directory, "mix.exs")

    if File.exists?(mix_file) do
      try do
        content = File.read!(mix_file)

        %{
          has_deps: String.contains?(content, "deps"),
          has_phoenix: String.contains?(content, "phoenix"),
          has_ecto: String.contains?(content, "ecto"),
          has_livebook: String.contains?(content, "livebook")
        }
      rescue
        _ -> %{error: :read_failed}
      end
    else
      %{}
    end
  end

  defp analyze_js_dependencies(directory) do
    package_file = Path.join(directory, "package.json")

    if File.exists?(package_file) do
      try do
        content = File.read!(package_file)
        decoded = Jason.decode!(content)

        %{
          has_dependencies: Map.has_key?(decoded, "dependencies"),
          has_dev_dependencies: Map.has_key?(decoded, "devDependencies"),
          has_scripts: Map.has_key?(decoded, "scripts"),
          dependency_count: count_dependencies(decoded)
        }
      rescue
        _ -> %{error: :parse_failed}
      end
    else
      %{}
    end
  end

  defp analyze_python_dependencies(directory) do
    requirements_file = Path.join(directory, "requirements.txt")
    pyproject_file = Path.join(directory, "pyproject.toml")

    cond do
      File.exists?(requirements_file) ->
        %{type: :requirements_txt, file: requirements_file}

      File.exists?(pyproject_file) ->
        %{type: :pyproject_toml, file: pyproject_file}

      true ->
        %{}
    end
  end

  defp analyze_rust_dependencies(directory) do
    cargo_file = Path.join(directory, "Cargo.toml")

    if File.exists?(cargo_file) do
      %{type: :cargo_toml, file: cargo_file}
    else
      %{}
    end
  end

  defp count_dependencies(package_json) do
    deps = Map.get(package_json, "dependencies", %{})
    dev_deps = Map.get(package_json, "devDependencies", %{})
    map_size(deps) + map_size(dev_deps)
  end

  defp detect_configuration_files(directory) do
    config_patterns = [
      ".env",
      ".env.local",
      ".env.production",
      "config.json",
      "config.yaml",
      "config.toml",
      ".eslintrc",
      ".prettierrc",
      "tsconfig.json",
      "tox.ini",
      "setup.cfg",
      "pyproject.toml"
    ]

    case File.ls(directory) do
      {:ok, entries} ->
        Enum.filter(entries, fn entry ->
          Enum.any?(config_patterns, fn pattern ->
            String.contains?(entry, pattern)
          end)
        end)

      {:error, _} ->
        []
    end
  end

  defp detect_project_scripts(directory) do
    script_files = []

    # Check package.json scripts
    package_file = Path.join(directory, "package.json")

    script_files =
      if File.exists?(package_file) do
        case read_package_json_scripts(package_file) do
          {:ok, scripts} -> [{"package.json", scripts} | script_files]
          {:error, _} -> script_files
        end
      else
        script_files
      end

    # Check for shell scripts
    case File.ls(directory) do
      {:ok, entries} ->
        shell_scripts =
          entries
          |> Enum.filter(&String.ends_with?(&1, ".sh"))
          |> Enum.take(5)

        if length(shell_scripts) > 0 do
          [{"shell_scripts", shell_scripts} | script_files]
        else
          script_files
        end

      {:error, _} ->
        script_files
    end
  end

  defp read_package_json_scripts(package_file) do
    try do
      content = File.read!(package_file)
      decoded = Jason.decode!(content)
      scripts = Map.get(decoded, "scripts", %{})
      {:ok, Map.keys(scripts)}
    rescue
      _ -> {:error, :parse_failed}
    end
  end

  defp extract_project_metadata(directory) do
    %{
      directory_name: Path.basename(directory),
      absolute_path: Path.expand(directory),
      is_git_repo: File.exists?(Path.join(directory, ".git")),
      last_modified: get_directory_mtime(directory),
      readable: File.exists?(directory) and File.dir?(directory)
    }
  end

  defp get_directory_mtime(directory) do
    case File.stat(directory) do
      {:ok, %{mtime: mtime}} -> mtime
      {:error, _} -> nil
    end
  end

  defp extract_project_tools(context) do
    base_tools = Map.get(context, :tools, [])

    # Add tools based on project type
    type_tools =
      case Map.get(context, :type) do
        :elixir -> ["mix compile", "mix test", "mix deps.get", "mix phx.server"]
        :javascript -> ["npm install", "npm start", "npm test", "npm run build"]
        :python -> ["pip install", "python -m", "pytest", "python setup.py"]
        :rust -> ["cargo build", "cargo test", "cargo run", "cargo check"]
        :go -> ["go build", "go test", "go run", "go mod tidy"]
        _ -> []
      end

    base_tools ++ type_tools
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.info("Project Detector shutting down")
    :ok
  end
end
