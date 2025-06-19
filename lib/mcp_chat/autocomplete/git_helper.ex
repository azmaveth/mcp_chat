defmodule MCPChat.Autocomplete.GitHelper do
  @moduledoc """
  Git-aware helper for intelligent autocomplete suggestions.

  Provides Git context including branches, tags, file status,
  and repository information to enhance autocomplete relevance.
  """

  use GenServer
  require Logger

  # 1 minute
  @git_cache_ttl 60_000
  @max_branches 20
  @max_tags 15
  @max_files 50

  # Git helper state
  defstruct [
    # Cached Git information
    :git_cache,
    # Repository metadata cache
    :repository_cache,
    # Git status cache
    :status_cache,
    # Git detection settings
    :settings
  ]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get Git context for the current or specified directory.
  """
  def get_git_context(pid \\ __MODULE__, directory \\ nil) do
    GenServer.call(pid, {:get_git_context, directory})
  end

  @doc """
  Get Git branches for autocomplete.
  """
  def get_branches(pid \\ __MODULE__, directory \\ nil) do
    GenServer.call(pid, {:get_branches, directory})
  end

  @doc """
  Get Git tags for autocomplete.
  """
  def get_tags(pid \\ __MODULE__, directory \\ nil) do
    GenServer.call(pid, {:get_tags, directory})
  end

  @doc """
  Get modified files for autocomplete.
  """
  def get_modified_files(pid \\ __MODULE__, directory \\ nil) do
    GenServer.call(pid, {:get_modified_files, directory})
  end

  @doc """
  Check if directory is a Git repository.
  """
  def is_git_repo?(directory \\ nil) do
    GenServer.call(__MODULE__, {:is_git_repo, directory})
  end

  @doc """
  Get Git status information.
  """
  def get_git_status(pid \\ __MODULE__, directory \\ nil) do
    GenServer.call(pid, {:get_git_status, directory})
  end

  @doc """
  Clear Git cache.
  """
  def clear_cache(pid \\ __MODULE__) do
    GenServer.call(pid, :clear_cache)
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    Logger.info("Starting Git Helper")

    settings = %{
      cache_ttl: Keyword.get(opts, :cache_ttl, @git_cache_ttl),
      max_branches: Keyword.get(opts, :max_branches, @max_branches),
      max_tags: Keyword.get(opts, :max_tags, @max_tags),
      max_files: Keyword.get(opts, :max_files, @max_files),
      enable_caching: Keyword.get(opts, :enable_caching, true)
    }

    state = %__MODULE__{
      git_cache: %{},
      repository_cache: %{},
      status_cache: %{},
      settings: settings
    }

    Logger.info("Git Helper initialized", settings: settings)
    {:ok, state}
  end

  @impl true
  def handle_call({:get_git_context, directory}, _from, state) do
    working_dir = directory || File.cwd!()

    case get_cached_git_context(working_dir, state) do
      {:hit, context} ->
        {:reply, context, state}

      {:miss, _reason} ->
        {context, new_state} = detect_and_cache_git_context(working_dir, state)
        {:reply, context, new_state}
    end
  end

  @impl true
  def handle_call({:get_branches, directory}, _from, state) do
    working_dir = directory || File.cwd!()

    if is_git_repository?(working_dir) do
      branches = get_git_branches(working_dir, state.settings)
      {:reply, branches, state}
    else
      {:reply, [], state}
    end
  end

  @impl true
  def handle_call({:get_tags, directory}, _from, state) do
    working_dir = directory || File.cwd!()

    if is_git_repository?(working_dir) do
      tags = get_git_tags(working_dir, state.settings)
      {:reply, tags, state}
    else
      {:reply, [], state}
    end
  end

  @impl true
  def handle_call({:get_modified_files, directory}, _from, state) do
    working_dir = directory || File.cwd!()

    if is_git_repository?(working_dir) do
      files = get_git_modified_files(working_dir, state.settings)
      {:reply, files, state}
    else
      {:reply, [], state}
    end
  end

  @impl true
  def handle_call({:is_git_repo, directory}, _from, state) do
    working_dir = directory || File.cwd!()
    is_repo = is_git_repository?(working_dir)
    {:reply, is_repo, state}
  end

  @impl true
  def handle_call({:get_git_status, directory}, _from, state) do
    working_dir = directory || File.cwd!()

    if is_git_repository?(working_dir) do
      status = get_repository_status(working_dir)
      {:reply, status, state}
    else
      {:reply, %{}, state}
    end
  end

  @impl true
  def handle_call(:clear_cache, _from, state) do
    new_state = %{state | git_cache: %{}, repository_cache: %{}, status_cache: %{}}
    {:reply, :ok, new_state}
  end

  # Private functions

  defp get_cached_git_context(directory, state) do
    if state.settings.enable_caching do
      case Map.get(state.git_cache, directory) do
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
    else
      {:miss, :caching_disabled}
    end
  end

  defp detect_and_cache_git_context(directory, state) do
    context = perform_git_context_detection(directory, state.settings)

    new_state =
      if state.settings.enable_caching do
        timestamp = System.monotonic_time(:millisecond)
        new_cache = Map.put(state.git_cache, directory, {context, timestamp})
        %{state | git_cache: new_cache}
      else
        state
      end

    {context, new_state}
  end

  defp perform_git_context_detection(directory, settings) do
    if is_git_repository?(directory) do
      %{
        is_git_repo: true,
        repository_root: find_git_root(directory),
        current_branch: get_current_branch(directory),
        branches: get_git_branches(directory, settings),
        tags: get_git_tags(directory, settings),
        status: get_repository_status(directory),
        modified_files: get_git_modified_files(directory, settings),
        remotes: get_git_remotes(directory),
        stash_count: get_stash_count(directory),
        ahead_behind: get_ahead_behind_status(directory)
      }
    else
      %{is_git_repo: false}
    end
  end

  defp is_git_repository?(directory) do
    git_dir = Path.join(directory, ".git")
    File.exists?(git_dir)
  end

  defp find_git_root(directory) do
    find_git_root_recursive(directory)
  end

  defp find_git_root_recursive(directory) do
    git_dir = Path.join(directory, ".git")

    if File.exists?(git_dir) do
      directory
    else
      parent = Path.dirname(directory)

      if parent == directory do
        # Reached filesystem root
        nil
      else
        find_git_root_recursive(parent)
      end
    end
  end

  defp get_current_branch(directory) do
    case System.cmd("git", ["rev-parse", "--abbrev-ref", "HEAD"], cd: directory, stderr_to_stdout: true) do
      {output, 0} ->
        String.trim(output)

      _ ->
        nil
    end
  end

  defp get_git_branches(directory, settings) do
    case System.cmd("git", ["branch", "--format=%(refname:short)"], cd: directory, stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.take(settings.max_branches)

      _ ->
        []
    end
  end

  defp get_git_tags(directory, settings) do
    case System.cmd("git", ["tag", "--sort=-version:refname"], cd: directory, stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.take(settings.max_tags)

      _ ->
        []
    end
  end

  defp get_git_modified_files(directory, settings) do
    case System.cmd("git", ["status", "--porcelain"], cd: directory, stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.map(&parse_status_line/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.take(settings.max_files)

      _ ->
        []
    end
  end

  defp parse_status_line(line) do
    case String.trim(line) do
      "" ->
        nil

      status_line ->
        # Git status format: XY filename
        case String.split(status_line, " ", parts: 2) do
          [status, filename] ->
            %{
              file: filename,
              status: parse_git_status(status),
              raw_status: status
            }

          _ ->
            nil
        end
    end
  end

  defp parse_git_status(status) do
    case status do
      "M" <> _ -> :modified
      "A" <> _ -> :added
      "D" <> _ -> :deleted
      "R" <> _ -> :renamed
      "C" <> _ -> :copied
      "U" <> _ -> :unmerged
      "??" -> :untracked
      "!!" -> :ignored
      _ -> :unknown
    end
  end

  defp get_repository_status(directory) do
    status_info = %{}

    # Get ahead/behind status
    status_info = Map.put(status_info, :ahead_behind, get_ahead_behind_status(directory))

    # Get working tree status
    status_info = Map.put(status_info, :working_tree, get_working_tree_status(directory))

    # Get stash count
    status_info = Map.put(status_info, :stash_count, get_stash_count(directory))

    status_info
  end

  defp get_ahead_behind_status(directory) do
    case System.cmd("git", ["status", "--porcelain=v1", "--branch"], cd: directory, stderr_to_stdout: true) do
      {output, 0} ->
        parse_ahead_behind(output)

      _ ->
        %{ahead: 0, behind: 0}
    end
  end

  defp parse_ahead_behind(output) do
    lines = String.split(output, "\n", trim: true)

    case Enum.find(lines, &String.starts_with?(&1, "##")) do
      nil ->
        %{ahead: 0, behind: 0}

      branch_line ->
        cond do
          String.contains?(branch_line, "[ahead ") ->
            extract_ahead_behind_numbers(branch_line)

          String.contains?(branch_line, "[behind ") ->
            extract_ahead_behind_numbers(branch_line)

          true ->
            %{ahead: 0, behind: 0}
        end
    end
  end

  defp extract_ahead_behind_numbers(branch_line) do
    ahead_regex = ~r/\[ahead (\d+)/
    behind_regex = ~r/behind (\d+)/

    ahead =
      case Regex.run(ahead_regex, branch_line) do
        [_, num] -> String.to_integer(num)
        _ -> 0
      end

    behind =
      case Regex.run(behind_regex, branch_line) do
        [_, num] -> String.to_integer(num)
        _ -> 0
      end

    %{ahead: ahead, behind: behind}
  end

  defp get_working_tree_status(directory) do
    case System.cmd("git", ["status", "--porcelain"], cd: directory, stderr_to_stdout: true) do
      {output, 0} ->
        lines = String.split(output, "\n", trim: true)

        %{
          clean: lines == [],
          modified_count: count_status_files(lines, ["M", " M"]),
          added_count: count_status_files(lines, ["A", " A"]),
          deleted_count: count_status_files(lines, ["D", " D"]),
          untracked_count: count_status_files(lines, ["??"]),
          total_changes: length(lines)
        }

      _ ->
        %{clean: true, total_changes: 0}
    end
  end

  defp count_status_files(lines, status_codes) do
    Enum.count(lines, fn line ->
      status = String.slice(line, 0, 2)
      status in status_codes
    end)
  end

  defp get_stash_count(directory) do
    case System.cmd("git", ["stash", "list"], cd: directory, stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> length()

      _ ->
        0
    end
  end

  defp get_git_remotes(directory) do
    case System.cmd("git", ["remote", "-v"], cd: directory, stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.map(&parse_remote_line/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(fn {name, _url, _type} -> name end)

      _ ->
        []
    end
  end

  defp parse_remote_line(line) do
    case String.split(line, "\t") do
      [name, url_and_type] ->
        case String.split(url_and_type, " ") do
          [url, type] ->
            clean_type = String.trim(type, "()")
            {name, url, clean_type}

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.info("Git Helper shutting down")
    :ok
  end
end
