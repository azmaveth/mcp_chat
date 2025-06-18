defmodule MCPChat.Autocomplete.HistoryTracker do
  @moduledoc """
  Tracks command history for intelligent autocomplete suggestions.

  Maintains a record of executed commands, their frequency,
  success rates, and contextual patterns to improve future
  completion suggestions.
  """

  use GenServer
  require Logger

  @history_file "~/.mcp_chat/command_history.dat"
  @max_history_entries 10_000
  # 1 hour
  @cleanup_interval 3_600_000

  # History tracker state
  defstruct [
    # List of command history entries
    :history_entries,
    # Map of command -> frequency count
    :command_frequency,
    # Map of command -> success rate
    :success_rates,
    # Recent commands for quick access
    :recent_commands,
    # Patterns based on context
    :context_patterns,
    # Timer for periodic cleanup
    :cleanup_timer
  ]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Record a command execution.
  """
  def record_command(command, context \\ %{}, success \\ true) do
    GenServer.cast(__MODULE__, {:record_command, command, context, success})
  end

  @doc """
  Get recent command context for autocomplete.
  """
  def get_recent_context(pid \\ __MODULE__, limit \\ 10) do
    GenServer.call(pid, {:get_recent_context, limit})
  end

  @doc """
  Get command frequency for a specific command.
  """
  def get_command_frequency(pid \\ __MODULE__, command) do
    GenServer.call(pid, {:get_command_frequency, command})
  end

  @doc """
  Get commands similar to the input.
  """
  def get_similar_commands(input, opts \\ []) do
    GenServer.call(__MODULE__, {:get_similar_commands, input, opts})
  end

  @doc """
  Get command suggestions based on current context.
  """
  def get_context_suggestions(context, opts \\ []) do
    GenServer.call(__MODULE__, {:get_context_suggestions, context, opts})
  end

  @doc """
  Get statistics about command usage.
  """
  def get_statistics do
    GenServer.call(__MODULE__, :get_statistics)
  end

  @doc """
  Clear command history.
  """
  def clear_history do
    GenServer.call(__MODULE__, :clear_history)
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    Logger.info("Starting History Tracker")

    state = %__MODULE__{
      history_entries: [],
      command_frequency: %{},
      success_rates: %{},
      recent_commands: [],
      context_patterns: %{}
    }

    case initialize_history_tracker(state, opts) do
      {:ok, initialized_state} ->
        # Start cleanup timer
        timer = Process.send_after(self(), :cleanup_history, @cleanup_interval)
        final_state = %{initialized_state | cleanup_timer: timer}

        Logger.info("History Tracker initialized",
          entries: length(final_state.history_entries),
          unique_commands: map_size(final_state.command_frequency)
        )

        {:ok, final_state}

      {:error, reason} ->
        Logger.error("Failed to initialize History Tracker", reason: inspect(reason))
        {:stop, reason}
    end
  end

  @impl true
  def handle_cast({:record_command, command, context, success}, state) do
    new_state = record_command_execution(command, context, success, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_call({:get_recent_context, limit}, _from, state) do
    recent_context = %{
      recent_commands: Enum.take(state.recent_commands, limit),
      commands: state.command_frequency,
      patterns: extract_recent_patterns(state, limit)
    }

    {:reply, recent_context, state}
  end

  @impl true
  def handle_call({:get_command_frequency, command}, _from, state) do
    frequency = Map.get(state.command_frequency, command, 0)
    {:reply, frequency, state}
  end

  @impl true
  def handle_call({:get_similar_commands, input, opts}, _from, state) do
    similar_commands = find_similar_commands(input, state, opts)
    {:reply, similar_commands, state}
  end

  @impl true
  def handle_call({:get_context_suggestions, context, opts}, _from, state) do
    suggestions = find_context_suggestions(context, state, opts)
    {:reply, suggestions, state}
  end

  @impl true
  def handle_call(:get_statistics, _from, state) do
    stats = %{
      total_entries: length(state.history_entries),
      unique_commands: map_size(state.command_frequency),
      most_used_command: get_most_used_command(state),
      success_rate: calculate_overall_success_rate(state),
      recent_activity: analyze_recent_activity(state)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:clear_history, _from, state) do
    new_state = %{
      state
      | history_entries: [],
        command_frequency: %{},
        success_rates: %{},
        recent_commands: [],
        context_patterns: %{}
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:cleanup_history, state) do
    new_state = cleanup_old_entries(state)

    # Schedule next cleanup
    timer = Process.send_after(self(), :cleanup_history, @cleanup_interval)
    final_state = %{new_state | cleanup_timer: timer}

    {:noreply, final_state}
  end

  # Private functions

  defp initialize_history_tracker(state, _opts) do
    case load_history_from_disk() do
      {:ok, loaded_state} ->
        merged_state = merge_loaded_history(state, loaded_state)
        {:ok, merged_state}

      {:error, :not_found} ->
        Logger.info("No existing history file found, starting fresh")
        {:ok, state}

      {:error, reason} ->
        Logger.warning("Failed to load history", reason: inspect(reason))
        {:ok, state}
    end
  end

  defp record_command_execution(command, context, success, state) do
    timestamp = DateTime.utc_now()

    # Create history entry
    entry = %{
      command: command,
      context: sanitize_context(context),
      success: success,
      timestamp: timestamp
    }

    # Update history entries
    new_entries =
      [entry | state.history_entries]
      |> Enum.take(@max_history_entries)

    # Update command frequency
    new_frequency = Map.update(state.command_frequency, command, 1, &(&1 + 1))

    # Update success rates
    new_success_rates = update_success_rate(command, success, state.success_rates)

    # Update recent commands
    new_recent =
      [command | state.recent_commands]
      |> Enum.take(50)
      |> Enum.uniq()

    # Update context patterns
    new_patterns = update_context_patterns(command, context, state.context_patterns)

    # Persist to disk (async)
    new_state = %{
      state
      | history_entries: new_entries,
        command_frequency: new_frequency,
        success_rates: new_success_rates,
        recent_commands: new_recent,
        context_patterns: new_patterns
    }

    # Save to disk periodically
    if rem(length(new_entries), 100) == 0 do
      Task.start(fn -> save_history_to_disk(new_state) end)
    end

    new_state
  end

  defp sanitize_context(context) do
    # Remove sensitive information from context before storing
    context
    |> Map.delete(:auth_token)
    |> Map.delete(:password)
    |> Map.delete(:secret)
    |> Map.take([:working_directory, :project_type, :git_branch, :timestamp])
  end

  defp update_success_rate(command, success, success_rates) do
    case Map.get(success_rates, command) do
      nil ->
        Map.put(success_rates, command, %{total: 1, successes: if(success, do: 1, else: 0)})

      %{total: total, successes: successes} ->
        new_total = total + 1
        new_successes = if success, do: successes + 1, else: successes
        Map.put(success_rates, command, %{total: new_total, successes: new_successes})
    end
  end

  defp update_context_patterns(command, context, patterns) do
    # Extract context keys for pattern matching
    context_key = extract_context_key(context)

    current_patterns = Map.get(patterns, context_key, %{})
    new_count = Map.get(current_patterns, command, 0) + 1
    updated_patterns = Map.put(current_patterns, command, new_count)

    Map.put(patterns, context_key, updated_patterns)
  end

  defp extract_context_key(context) do
    # Create a simplified context key for pattern matching
    %{
      project_type: Map.get(context, :project_type),
      directory_type: classify_directory_type(Map.get(context, :working_directory)),
      time_of_day: get_time_period(DateTime.utc_now())
    }
  end

  defp classify_directory_type(nil), do: :unknown

  defp classify_directory_type(dir) do
    cond do
      String.contains?(dir, "/home/") -> :home
      String.contains?(dir, "/tmp/") -> :temp
      String.contains?(dir, "/var/") -> :system
      true -> :project
    end
  end

  defp get_time_period(datetime) do
    case datetime.hour do
      h when h < 6 -> :night
      h when h < 12 -> :morning
      h when h < 18 -> :afternoon
      _ -> :evening
    end
  end

  defp extract_recent_patterns(state, limit) do
    state.history_entries
    |> Enum.take(limit)
    |> Enum.group_by(fn entry -> extract_context_key(entry.context) end)
    |> Enum.map(fn {context_key, entries} ->
      commands = Enum.map(entries, & &1.command)
      {context_key, Enum.frequencies(commands)}
    end)
    |> Enum.into(%{})
  end

  defp find_similar_commands(input, state, opts) do
    max_results = Keyword.get(opts, :max_results, 10)
    threshold = Keyword.get(opts, :similarity_threshold, 0.5)

    state.command_frequency
    |> Enum.filter(fn {command, _freq} ->
      similarity = calculate_similarity(input, command)
      similarity >= threshold
    end)
    |> Enum.sort_by(
      fn {command, freq} ->
        similarity = calculate_similarity(input, command)
        # Score combines similarity and frequency
        similarity * 0.7 + freq / 100.0 * 0.3
      end,
      :desc
    )
    |> Enum.take(max_results)
    |> Enum.map(fn {command, _freq} -> command end)
  end

  defp find_context_suggestions(context, state, opts) do
    max_results = Keyword.get(opts, :max_results, 10)
    context_key = extract_context_key(context)

    case Map.get(state.context_patterns, context_key) do
      nil ->
        []

      command_counts ->
        command_counts
        |> Enum.sort_by(fn {_command, count} -> count end, :desc)
        |> Enum.take(max_results)
        |> Enum.map(fn {command, _count} -> command end)
    end
  end

  defp calculate_similarity(str1, str2) do
    # Simple string similarity based on common characters
    str1_chars = String.graphemes(String.downcase(str1)) |> MapSet.new()
    str2_chars = String.graphemes(String.downcase(str2)) |> MapSet.new()

    intersection = MapSet.intersection(str1_chars, str2_chars)
    union = MapSet.union(str1_chars, str2_chars)

    if MapSet.size(union) == 0 do
      0.0
    else
      MapSet.size(intersection) / MapSet.size(union)
    end
  end

  defp get_most_used_command(state) do
    case Enum.max_by(state.command_frequency, fn {_cmd, freq} -> freq end, fn -> {nil, 0} end) do
      {nil, 0} -> nil
      {command, frequency} -> %{command: command, frequency: frequency}
    end
  end

  defp calculate_overall_success_rate(state) do
    if map_size(state.success_rates) == 0 do
      0.0
    else
      {total_successes, total_attempts} =
        Enum.reduce(state.success_rates, {0, 0}, fn {_cmd, %{total: total, successes: successes}},
                                                    {acc_succ, acc_total} ->
          {acc_succ + successes, acc_total + total}
        end)

      if total_attempts > 0, do: total_successes / total_attempts, else: 0.0
    end
  end

  defp analyze_recent_activity(state) do
    recent_entries = Enum.take(state.history_entries, 20)

    %{
      recent_command_count: length(recent_entries),
      unique_recent_commands: recent_entries |> Enum.map(& &1.command) |> Enum.uniq() |> length(),
      last_command_time:
        case recent_entries do
          [%{timestamp: time} | _] -> time
          [] -> nil
        end
    }
  end

  defp cleanup_old_entries(state) do
    # Remove entries older than 30 days
    cutoff_date = DateTime.add(DateTime.utc_now(), -30, :day)

    new_entries =
      Enum.filter(state.history_entries, fn entry ->
        DateTime.compare(entry.timestamp, cutoff_date) == :gt
      end)

    # Rebuild frequency and success rate maps from remaining entries
    {new_frequency, new_success_rates} = rebuild_stats_from_entries(new_entries)

    Logger.info("Cleaned up history",
      removed: length(state.history_entries) - length(new_entries),
      remaining: length(new_entries)
    )

    %{state | history_entries: new_entries, command_frequency: new_frequency, success_rates: new_success_rates}
  end

  defp rebuild_stats_from_entries(entries) do
    {frequency, success_rates} =
      Enum.reduce(entries, {%{}, %{}}, fn entry, {freq_acc, success_acc} ->
        command = entry.command
        success = entry.success

        # Update frequency
        new_freq = Map.update(freq_acc, command, 1, &(&1 + 1))

        # Update success rates
        new_success = update_success_rate(command, success, success_acc)

        {new_freq, new_success}
      end)

    {frequency, success_rates}
  end

  defp load_history_from_disk do
    history_path = Path.expand(@history_file)

    if File.exists?(history_path) do
      try do
        history_data = File.read!(history_path)
        loaded_state = :erlang.binary_to_term(history_data)
        {:ok, loaded_state}
      rescue
        error ->
          Logger.error("Failed to load history file", error: inspect(error))
          {:error, error}
      end
    else
      {:error, :not_found}
    end
  end

  defp save_history_to_disk(state) do
    history_path = Path.expand(@history_file)
    history_dir = Path.dirname(history_path)

    # Ensure directory exists
    File.mkdir_p!(history_dir)

    # Prepare data for serialization
    data_to_save = %{
      # Limit saved entries
      history_entries: Enum.take(state.history_entries, 1000),
      command_frequency: state.command_frequency,
      success_rates: state.success_rates,
      context_patterns: state.context_patterns
    }

    try do
      serialized_data = :erlang.term_to_binary(data_to_save)
      File.write!(history_path, serialized_data)
      Logger.debug("History saved to disk", path: history_path)
    rescue
      error ->
        Logger.error("Failed to save history", error: inspect(error))
    end
  end

  defp merge_loaded_history(current_state, loaded_data) do
    %{
      current_state
      | history_entries: Map.get(loaded_data, :history_entries, []),
        command_frequency: Map.get(loaded_data, :command_frequency, %{}),
        success_rates: Map.get(loaded_data, :success_rates, %{}),
        context_patterns: Map.get(loaded_data, :context_patterns, %{}),
        recent_commands: extract_recent_commands(Map.get(loaded_data, :history_entries, []))
    }
  end

  defp extract_recent_commands(history_entries) do
    history_entries
    |> Enum.take(50)
    |> Enum.map(& &1.command)
    |> Enum.uniq()
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("History Tracker shutting down")

    # Save final state to disk
    save_history_to_disk(state)

    # Cancel cleanup timer
    if state.cleanup_timer do
      Process.cancel_timer(state.cleanup_timer)
    end

    :ok
  end
end
