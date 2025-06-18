defmodule MCPChat.Autocomplete.SuggestionProvider do
  @moduledoc """
  Behavior and base implementations for autocomplete suggestion providers.

  Suggestion providers are modular components that generate context-aware
  completions for different types of input (commands, file paths, Git refs, etc.).
  """

  @doc """
  Generate basic suggestions for the given input and context.
  """
  @callback get_suggestions(input :: String.t(), context :: map(), opts :: keyword()) :: [String.t()]

  @doc """
  Generate detailed suggestions with metadata.
  """
  @callback get_detailed_suggestions(input :: String.t(), context :: map(), opts :: keyword()) :: [map()]

  @doc """
  Get provider information and capabilities.
  """
  @callback get_provider_info() :: map()

  @optional_callbacks [get_detailed_suggestions: 3, get_provider_info: 0]

  # Default implementations for common suggestion types

  defmodule CommandProvider do
    @moduledoc """
    Provides suggestions for common shell commands and MCP Chat commands.
    """

    @behaviour MCPChat.Autocomplete.SuggestionProvider

    # Common shell commands
    @shell_commands [
      "ls",
      "cd",
      "pwd",
      "mkdir",
      "rmdir",
      "rm",
      "cp",
      "mv",
      "cat",
      "less",
      "more",
      "grep",
      "find",
      "which",
      "whereis",
      "locate",
      "head",
      "tail",
      "sort",
      "uniq",
      "wc",
      "cut",
      "awk",
      "sed",
      "tar",
      "gzip",
      "gunzip",
      "zip",
      "unzip",
      "ps",
      "top",
      "htop",
      "kill",
      "killall",
      "jobs",
      "nohup",
      "screen",
      "tmux",
      "chmod",
      "chown",
      "chgrp",
      "du",
      "df",
      "mount",
      "umount",
      "ln",
      "ssh",
      "scp",
      "rsync",
      "curl",
      "wget",
      "ping",
      "traceroute",
      "netstat"
    ]

    # MCP Chat specific commands
    @mcp_commands [
      "/help",
      "/model",
      "/context",
      "/alias",
      "/session",
      "/export",
      "/plan",
      "/agent",
      "/discover",
      "/resume",
      "/cost",
      "/budget",
      "/analyze"
    ]

    # Development tools
    @dev_commands [
      "git",
      "docker",
      "npm",
      "yarn",
      "pip",
      "conda",
      "make",
      "cmake",
      "gcc",
      "clang",
      "node",
      "python",
      "ruby",
      "elixir",
      "iex",
      "mix"
    ]

    @impl true
    def get_suggestions(input, context, _opts) do
      all_commands = @shell_commands ++ @mcp_commands ++ @dev_commands

      # Add project-specific commands based on context
      project_commands = get_project_commands(context)
      extended_commands = all_commands ++ project_commands

      extended_commands
      |> filter_by_input(input)
      |> Enum.take(20)
    end

    @impl true
    def get_detailed_suggestions(input, context, opts) do
      get_suggestions(input, context, opts)
      |> Enum.map(fn command ->
        %{
          text: command,
          completion: command,
          type: classify_command(command),
          description: get_command_description(command),
          source: "CommandProvider"
        }
      end)
    end

    @impl true
    def get_provider_info do
      %{
        name: "CommandProvider",
        description: "Shell commands and MCP Chat commands",
        priority: 100,
        categories: ["commands", "shell", "mcp"]
      }
    end

    defp get_project_commands(context) do
      case get_in(context, [:project, :type]) do
        :elixir -> ["mix compile", "mix test", "mix deps.get", "mix phx.server", "iex -S mix"]
        :javascript -> ["npm install", "npm start", "npm test", "npm run build", "yarn install"]
        :python -> ["pip install", "python -m", "pytest", "python setup.py", "pip freeze"]
        :rust -> ["cargo build", "cargo test", "cargo run", "cargo check", "rustc"]
        :go -> ["go build", "go test", "go run", "go mod", "go get"]
        _ -> []
      end
    end

    defp filter_by_input(commands, input) do
      input_lower = String.downcase(input)

      commands
      |> Enum.filter(fn command ->
        command_lower = String.downcase(command)

        String.starts_with?(command_lower, input_lower) or
          String.contains?(command_lower, input_lower)
      end)
      |> Enum.sort_by(fn command ->
        command_lower = String.downcase(command)

        cond do
          String.starts_with?(command_lower, input_lower) -> 0
          String.contains?(command_lower, input_lower) -> 1
          true -> 2
        end
      end)
    end

    defp classify_command(command) do
      cond do
        String.starts_with?(command, "/") -> :mcp_command
        command in @shell_commands -> :shell_command
        command in @dev_commands -> :dev_command
        String.contains?(command, " ") -> :command_with_args
        true -> :unknown_command
      end
    end

    defp get_command_description(command) do
      case command do
        "ls" -> "List directory contents"
        "cd" -> "Change directory"
        "pwd" -> "Print working directory"
        "git" -> "Git version control"
        "docker" -> "Docker container management"
        "/help" -> "Show MCP Chat help"
        "/model" -> "Switch LLM model"
        "/cost" -> "Show cost information"
        _ -> "Command: #{command}"
      end
    end
  end

  defmodule FilePathProvider do
    @moduledoc """
    Provides file and directory path completions.
    """

    @behaviour MCPChat.Autocomplete.SuggestionProvider

    @impl true
    def get_suggestions(input, context, opts) do
      max_results = Keyword.get(opts, :max_results, 15)
      show_hidden = Keyword.get(opts, :show_hidden, false)

      base_dir = get_base_directory(input, context)
      search_pattern = get_search_pattern(input)

      find_matching_paths(base_dir, search_pattern, show_hidden)
      |> Enum.take(max_results)
    end

    @impl true
    def get_detailed_suggestions(input, context, opts) do
      get_suggestions(input, context, opts)
      |> Enum.map(fn path ->
        %{
          text: path,
          completion: path,
          type: get_path_type(path),
          description: get_path_description(path),
          source: "FilePathProvider",
          metadata: get_path_metadata(path)
        }
      end)
    end

    defp get_base_directory(input, context) do
      cond do
        String.starts_with?(input, "/") ->
          "/"

        String.starts_with?(input, "~/") ->
          System.user_home!()

        String.starts_with?(input, "./") ->
          File.cwd!()

        String.contains?(input, "/") ->
          Path.dirname(input)

        true ->
          Map.get(context, :working_directory, File.cwd!())
      end
    end

    defp get_search_pattern(input) do
      if String.contains?(input, "/") do
        Path.basename(input)
      else
        input
      end
    end

    defp find_matching_paths(base_dir, pattern, show_hidden) do
      case File.ls(base_dir) do
        {:ok, entries} ->
          entries
          |> Enum.filter(fn entry ->
            (show_hidden or not String.starts_with?(entry, ".")) and
              (pattern == "" or String.starts_with?(String.downcase(entry), String.downcase(pattern)))
          end)
          |> Enum.map(fn entry ->
            full_path = Path.join(base_dir, entry)
            if File.dir?(full_path), do: entry <> "/", else: entry
          end)
          |> Enum.sort()

        {:error, _} ->
          []
      end
    end

    defp get_path_type(path) do
      cond do
        String.ends_with?(path, "/") -> :directory
        File.dir?(path) -> :directory
        File.regular?(path) -> :file
        File.exists?(path) -> :special
        true -> :unknown
      end
    end

    defp get_path_description(path) do
      case get_path_type(path) do
        :directory -> "Directory: #{path}"
        :file -> "File: #{path} (#{get_file_size(path)})"
        :special -> "Special file: #{path}"
        :unknown -> "Path: #{path}"
      end
    end

    defp get_path_metadata(path) do
      case File.stat(path) do
        {:ok, stat} ->
          %{
            size: stat.size,
            modified: stat.mtime,
            permissions: stat.mode,
            type: stat.type
          }

        {:error, _} ->
          %{}
      end
    end

    defp get_file_size(path) do
      case File.stat(path) do
        {:ok, %{size: size}} -> format_file_size(size)
        {:error, _} -> "unknown"
      end
    end

    defp format_file_size(bytes) when bytes < 1024, do: "#{bytes}B"
    defp format_file_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)}KB"
    defp format_file_size(bytes) when bytes < 1024 * 1024 * 1024, do: "#{Float.round(bytes / (1024 * 1024), 1)}MB"
    defp format_file_size(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024), 1)}GB"
  end

  defmodule GitProvider do
    @moduledoc """
    Provides Git-aware suggestions (branches, tags, commits).
    """

    @behaviour MCPChat.Autocomplete.SuggestionProvider

    @impl true
    def get_suggestions(input, context, _opts) do
      if git_repo?(context) do
        git_suggestions = []

        # Add branch suggestions
        git_suggestions = git_suggestions ++ get_branch_suggestions(input, context)

        # Add tag suggestions
        git_suggestions = git_suggestions ++ get_tag_suggestions(input, context)

        # Add Git commands
        git_suggestions ++ get_git_command_suggestions(input)
      else
        []
      end
    end

    @impl true
    def get_detailed_suggestions(input, context, opts) do
      get_suggestions(input, context, opts)
      |> Enum.map(fn suggestion ->
        %{
          text: suggestion,
          completion: suggestion,
          type: classify_git_suggestion(suggestion),
          description: get_git_description(suggestion, context),
          source: "GitProvider"
        }
      end)
    end

    defp git_repo?(context) do
      working_dir = Map.get(context, :working_directory, File.cwd!())
      File.exists?(Path.join(working_dir, ".git"))
    end

    defp get_branch_suggestions(input, context) do
      working_dir = Map.get(context, :working_directory, File.cwd!())

      case System.cmd("git", ["branch", "--format=%(refname:short)"], cd: working_dir, stderr_to_stdout: true) do
        {output, 0} ->
          output
          |> String.split("\n", trim: true)
          |> Enum.filter(&String.starts_with?(&1, input))

        _ ->
          []
      end
    end

    defp get_tag_suggestions(input, context) do
      working_dir = Map.get(context, :working_directory, File.cwd!())

      case System.cmd("git", ["tag", "--list", "#{input}*"], cd: working_dir, stderr_to_stdout: true) do
        {output, 0} ->
          String.split(output, "\n", trim: true)

        _ ->
          []
      end
    end

    defp get_git_command_suggestions(input) do
      git_commands = [
        "git add",
        "git commit",
        "git push",
        "git pull",
        "git status",
        "git log",
        "git checkout",
        "git branch",
        "git merge",
        "git rebase",
        "git diff",
        "git reset",
        "git stash",
        "git tag",
        "git clone",
        "git fetch"
      ]

      git_commands
      |> Enum.filter(&String.starts_with?(&1, input))
    end

    defp classify_git_suggestion(suggestion) do
      cond do
        String.starts_with?(suggestion, "git ") -> :git_command
        String.match?(suggestion, ~r/^v?\d+\.\d+/) -> :tag
        true -> :branch
      end
    end

    defp get_git_description(suggestion, context) do
      case classify_git_suggestion(suggestion) do
        :git_command -> "Git command: #{suggestion}"
        :branch -> "Git branch: #{suggestion}"
        :tag -> "Git tag: #{suggestion}"
      end
    end
  end

  defmodule HistoryProvider do
    @moduledoc """
    Provides suggestions based on command history.
    """

    @behaviour MCPChat.Autocomplete.SuggestionProvider

    @impl true
    def get_suggestions(input, context, _opts) do
      case get_in(context, [:history, :recent_commands]) do
        commands when is_list(commands) ->
          commands
          |> Enum.filter(&String.starts_with?(&1, input))
          |> Enum.uniq()
          |> Enum.take(10)

        _ ->
          []
      end
    end

    @impl true
    def get_detailed_suggestions(input, context, opts) do
      get_suggestions(input, context, opts)
      |> Enum.map(fn command ->
        %{
          text: command,
          completion: command,
          type: :history_command,
          description: "From history: #{command}",
          source: "HistoryProvider",
          metadata: get_command_history_metadata(command, context)
        }
      end)
    end

    defp get_command_history_metadata(command, context) do
      history = get_in(context, [:history, :commands]) || %{}

      case Map.get(history, command) do
        metadata when is_map(metadata) -> metadata
        _ -> %{usage_count: 1, last_used: DateTime.utc_now()}
      end
    end
  end

  defmodule MCPProvider do
    @moduledoc """
    Provides MCP-specific suggestions (servers, tools, resources).
    """

    @behaviour MCPChat.Autocomplete.SuggestionProvider

    @impl true
    def get_suggestions(input, context, _opts) do
      mcp_suggestions = []

      # Add MCP server suggestions
      mcp_suggestions = mcp_suggestions ++ get_server_suggestions(input, context)

      # Add tool suggestions
      mcp_suggestions = mcp_suggestions ++ get_tool_suggestions(input, context)

      # Add resource suggestions
      mcp_suggestions ++ get_resource_suggestions(input, context)
    end

    @impl true
    def get_detailed_suggestions(input, context, opts) do
      get_suggestions(input, context, opts)
      |> Enum.map(fn suggestion ->
        %{
          text: suggestion,
          completion: suggestion,
          type: classify_mcp_suggestion(suggestion),
          description: get_mcp_description(suggestion, context),
          source: "MCPProvider"
        }
      end)
    end

    defp get_server_suggestions(_input, _context) do
      # This would integrate with actual MCP server registry
      ["filesystem", "git", "postgres", "brave-search", "github", "slack"]
    end

    defp get_tool_suggestions(_input, _context) do
      # This would integrate with actual MCP tool registry
      ["read_file", "write_file", "list_directory", "git_log", "search_files"]
    end

    defp get_resource_suggestions(_input, _context) do
      # This would integrate with actual MCP resource registry
      ["file://", "git://", "postgres://", "https://"]
    end

    defp classify_mcp_suggestion(suggestion) do
      cond do
        String.contains?(suggestion, "://") -> :mcp_resource
        String.contains?(suggestion, "_") -> :mcp_tool
        true -> :mcp_server
      end
    end

    defp get_mcp_description(suggestion, _context) do
      case classify_mcp_suggestion(suggestion) do
        :mcp_server -> "MCP Server: #{suggestion}"
        :mcp_tool -> "MCP Tool: #{suggestion}"
        :mcp_resource -> "MCP Resource: #{suggestion}"
      end
    end
  end

  defmodule ToolProvider do
    @moduledoc """
    Provides suggestions for CLI tools and utilities.
    """

    @behaviour MCPChat.Autocomplete.SuggestionProvider

    @impl true
    def get_suggestions(input, context, _opts) do
      # Get tools from system PATH
      system_tools = get_system_tools(input)

      # Get project-specific tools
      project_tools = get_project_tools(input, context)

      system_tools ++ project_tools
    end

    @impl true
    def get_detailed_suggestions(input, context, opts) do
      get_suggestions(input, context, opts)
      |> Enum.map(fn tool ->
        %{
          text: tool,
          completion: tool,
          type: :cli_tool,
          description: get_tool_description(tool),
          source: "ToolProvider",
          metadata: get_tool_metadata(tool)
        }
      end)
    end

    defp get_system_tools(input) do
      case System.cmd("which", [input], stderr_to_stdout: true) do
        {output, 0} ->
          [Path.basename(String.trim(output))]

        _ ->
          # Fallback to common tools
          common_tools = [
            "awk",
            "sed",
            "grep",
            "find",
            "xargs",
            "sort",
            "uniq",
            "cut",
            "jq",
            "curl",
            "wget",
            "ssh",
            "rsync",
            "tar",
            "gzip"
          ]

          Enum.filter(common_tools, &String.starts_with?(&1, input))
      end
    end

    defp get_project_tools(_input, context) do
      case get_in(context, [:project, :type]) do
        :javascript -> ["npx", "yarn", "webpack", "eslint", "prettier"]
        :python -> ["pip", "conda", "pytest", "flake8", "black"]
        :elixir -> ["mix", "iex", "elixir", "dialyzer", "credo"]
        _ -> []
      end
    end

    defp get_tool_description(tool) do
      descriptions = %{
        "jq" => "JSON processor",
        "curl" => "HTTP client",
        "wget" => "Web downloader",
        "ssh" => "Secure shell",
        "rsync" => "File synchronization",
        "tar" => "Archive utility",
        "gzip" => "Compression utility"
      }

      Map.get(descriptions, tool, "CLI tool: #{tool}")
    end

    defp get_tool_metadata(tool) do
      case System.cmd("which", [tool], stderr_to_stdout: true) do
        {path, 0} ->
          %{path: String.trim(path), available: true}

        _ ->
          %{available: false}
      end
    end
  end
end
