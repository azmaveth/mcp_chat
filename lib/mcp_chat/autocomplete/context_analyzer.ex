defmodule MCPChat.Autocomplete.ContextAnalyzer do
  @moduledoc """
  Analyzes context for intelligent autocomplete suggestions.

  Examines the current working environment, command context,
  and user patterns to provide more relevant completions.
  """

  @doc """
  Analyze the current context and extract relevant information.
  """
  def analyze_context(input, base_context \\ %{}) do
    %{}
    |> add_input_analysis(input)
    |> add_working_directory_context(base_context)
    |> add_shell_context()
    |> add_timing_context()
    |> Map.merge(base_context)
  end

  @doc """
  Determine the completion type based on input.
  """
  def determine_completion_type(input) do
    cond do
      String.starts_with?(input, "/") -> :mcp_command
      String.starts_with?(input, "git ") -> :git_command
      String.starts_with?(input, "cd ") -> :directory_path
      String.starts_with?(input, "cat ") -> :file_path
      String.starts_with?(input, "ls ") -> :directory_path
      String.starts_with?(input, "./") -> :relative_path
      String.starts_with?(input, "~/") -> :home_path
      String.contains?(input, "/") -> :path
      String.match?(input, ~r/^\w+$/) -> :command
      true -> :general
    end
  end

  @doc """
  Extract command context from input.
  """
  def extract_command_context(input) do
    parts = String.split(input, " ", trim: true)

    case parts do
      [] -> %{type: :empty}
      [command] -> %{type: :command, command: command, args: []}
      [command | args] -> %{type: :command_with_args, command: command, args: args}
    end
  end

  @doc """
  Analyze project structure and type.
  """
  def analyze_project_structure(directory \\ nil) do
    dir = directory || File.cwd!()

    %{
      type: detect_project_type(dir),
      root: find_project_root(dir),
      structure: analyze_directory_structure(dir),
      tools: detect_available_tools(dir)
    }
  end

  # Private functions

  defp add_input_analysis(context, input) do
    Map.merge(context, %{
      input_length: String.length(input),
      completion_type: determine_completion_type(input),
      command_context: extract_command_context(input),
      last_word: get_last_word(input),
      cursor_position: String.length(input)
    })
  end

  defp add_working_directory_context(context, base_context) do
    working_dir = Map.get(base_context, :working_directory, File.cwd!())

    Map.merge(context, %{
      working_directory: working_dir,
      directory_type: classify_directory(working_dir),
      is_git_repo: File.exists?(Path.join(working_dir, ".git")),
      parent_directory: Path.dirname(working_dir),
      directory_name: Path.basename(working_dir)
    })
  end

  defp add_shell_context(context) do
    Map.merge(context, %{
      shell: System.get_env("SHELL"),
      user: System.get_env("USER"),
      home: System.user_home(),
      path: System.get_env("PATH"),
      platform: :os.type()
    })
  end

  defp add_timing_context(context) do
    now = DateTime.utc_now()

    Map.merge(context, %{
      timestamp: now,
      hour: now.hour,
      day_of_week: Date.day_of_week(DateTime.to_date(now)),
      is_weekend: Date.day_of_week(DateTime.to_date(now)) in [6, 7]
    })
  end

  defp get_last_word(input) do
    input
    |> String.split()
    |> List.last()
    |> Kernel.||(input)
  end

  defp classify_directory(dir) do
    cond do
      dir == System.user_home() -> :home
      dir == "/" -> :root
      String.starts_with?(dir, "/tmp") -> :temporary
      String.starts_with?(dir, "/var") -> :system
      File.exists?(Path.join(dir, "mix.exs")) -> :elixir_project
      File.exists?(Path.join(dir, "package.json")) -> :node_project
      File.exists?(Path.join(dir, "requirements.txt")) -> :python_project
      File.exists?(Path.join(dir, "Cargo.toml")) -> :rust_project
      File.exists?(Path.join(dir, ".git")) -> :git_repository
      true -> :generic
    end
  end

  defp detect_project_type(dir) do
    cond do
      File.exists?(Path.join(dir, "mix.exs")) -> :elixir
      File.exists?(Path.join(dir, "package.json")) -> :javascript
      File.exists?(Path.join(dir, "requirements.txt")) -> :python
      File.exists?(Path.join(dir, "pyproject.toml")) -> :python
      File.exists?(Path.join(dir, "Cargo.toml")) -> :rust
      File.exists?(Path.join(dir, "go.mod")) -> :go
      File.exists?(Path.join(dir, "Gemfile")) -> :ruby
      File.exists?(Path.join(dir, "pom.xml")) -> :java
      File.exists?(Path.join(dir, "Makefile")) -> :c_cpp
      true -> :unknown
    end
  end

  defp find_project_root(dir) do
    markers = [".git", "mix.exs", "package.json", "requirements.txt", "Cargo.toml", "go.mod"]

    find_project_root_recursive(dir, markers)
  end

  defp find_project_root_recursive(dir, markers) do
    if Enum.any?(markers, fn marker -> File.exists?(Path.join(dir, marker)) end) do
      dir
    else
      parent = Path.dirname(dir)

      if parent == dir do
        # Reached filesystem root
        dir
      else
        find_project_root_recursive(parent, markers)
      end
    end
  end

  defp analyze_directory_structure(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        %{
          file_count: count_files(dir, entries),
          directory_count: count_directories(dir, entries),
          has_hidden_files: Enum.any?(entries, &String.starts_with?(&1, ".")),
          common_files: find_common_files(entries),
          size_estimate: estimate_directory_size(dir, entries)
        }

      {:error, _} ->
        %{error: :access_denied}
    end
  end

  defp count_files(dir, entries) do
    Enum.count(entries, fn entry ->
      File.regular?(Path.join(dir, entry))
    end)
  end

  defp count_directories(dir, entries) do
    Enum.count(entries, fn entry ->
      File.dir?(Path.join(dir, entry))
    end)
  end

  defp find_common_files(entries) do
    common_patterns = [
      "README",
      "LICENSE",
      "Makefile",
      ".gitignore",
      "docker-compose",
      "requirements.txt",
      "package.json",
      "mix.exs",
      "Cargo.toml"
    ]

    Enum.filter(common_patterns, fn pattern ->
      Enum.any?(entries, &String.contains?(&1, pattern))
    end)
  end

  defp estimate_directory_size(dir, entries) do
    # Quick size estimation based on file count
    case length(entries) do
      count when count < 10 -> :small
      count when count < 50 -> :medium
      count when count < 200 -> :large
      _ -> :very_large
    end
  end

  defp detect_available_tools(dir) do
    tools = []

    # Check for common development tools
    tools =
      if File.exists?(Path.join(dir, "mix.exs")) do
        ["mix", "iex", "elixir" | tools]
      else
        tools
      end

    tools =
      if File.exists?(Path.join(dir, "package.json")) do
        ["npm", "yarn", "node" | tools]
      else
        tools
      end

    tools =
      if File.exists?(Path.join(dir, ".git")) do
        ["git" | tools]
      else
        tools
      end

    # Check system PATH for other tools
    system_tools = ["docker", "make", "curl", "jq"]
    available_system_tools = Enum.filter(system_tools, &tool_available?/1)

    tools ++ available_system_tools
  end

  defp tool_available?(tool) do
    case System.cmd("which", [tool], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  end
end
