defmodule MCPChat.Autocomplete.AutocompleteEngine do
  @moduledoc """
  Intelligent autocomplete engine for MCP Chat.

  Provides context-aware command completion, file path suggestions,
  and AI-powered recommendations based on command history, project
  structure, and Git context.
  """

  use GenServer
  require Logger

  alias MCPChat.Autocomplete.{
    SuggestionProvider,
    ContextAnalyzer,
    HistoryTracker,
    ProjectDetector,
    GitHelper,
    ToolRegistry
  }

  # 1 minute
  @completion_cache_ttl 60_000
  @max_suggestions 10
  @min_input_length 2

  # Autocomplete engine state
  defstruct [
    # List of active suggestion providers
    :suggestion_providers,
    # Cached context information
    :context_cache,
    # Cached completion results
    :completion_cache,
    # Command history tracking
    :history_tracker,
    # Project context detection
    :project_detector,
    # Git-aware suggestions
    :git_helper,
    # CLI tool database
    :tool_registry,
    # Machine learning insights
    :learning_data,
    # User preferences
    :settings
  ]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get autocomplete suggestions for the current input.
  """
  def get_suggestions(input, context \\ %{}) do
    GenServer.call(__MODULE__, {:get_suggestions, input, context})
  end

  @doc """
  Register a custom suggestion provider.
  """
  def register_provider(provider_module, opts \\ []) do
    GenServer.call(__MODULE__, {:register_provider, provider_module, opts})
  end

  @doc """
  Update autocomplete settings.
  """
  def update_settings(new_settings) do
    GenServer.call(__MODULE__, {:update_settings, new_settings})
  end

  @doc """
  Record a command execution for learning.
  """
  def record_command(command, context, success \\ true) do
    GenServer.cast(__MODULE__, {:record_command, command, context, success})
  end

  @doc """
  Get autocomplete statistics and performance metrics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Clear suggestion cache.
  """
  def clear_cache do
    GenServer.call(__MODULE__, :clear_cache)
  end

  @doc """
  Get detailed suggestions with metadata.
  """
  def get_detailed_suggestions(input, context \\ %{}) do
    GenServer.call(__MODULE__, {:get_detailed_suggestions, input, context})
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    Logger.info("Starting Autocomplete Engine")

    settings = %{
      enabled: Keyword.get(opts, :enabled, true),
      max_suggestions: Keyword.get(opts, :max_suggestions, @max_suggestions),
      min_input_length: Keyword.get(opts, :min_input_length, @min_input_length),
      case_sensitive: Keyword.get(opts, :case_sensitive, false),
      fuzzy_matching: Keyword.get(opts, :fuzzy_matching, true),
      context_aware: Keyword.get(opts, :context_aware, true),
      learning_enabled: Keyword.get(opts, :learning_enabled, true),
      git_integration: Keyword.get(opts, :git_integration, true)
    }

    state = %__MODULE__{
      suggestion_providers: [],
      context_cache: %{},
      completion_cache: %{},
      learning_data: %{},
      settings: settings
    }

    case initialize_autocomplete_engine(state, opts) do
      {:ok, initialized_state} ->
        Logger.info("Autocomplete Engine initialized",
          providers: length(initialized_state.suggestion_providers),
          settings: initialized_state.settings
        )

        {:ok, initialized_state}

      {:error, reason} ->
        Logger.error("Failed to initialize Autocomplete Engine", reason: inspect(reason))
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:get_suggestions, input, context}, _from, state) do
    if state.settings.enabled and String.length(input) >= state.settings.min_input_length do
      suggestions = generate_suggestions(input, context, state)
      {:reply, suggestions, state}
    else
      {:reply, [], state}
    end
  end

  @impl true
  def handle_call({:get_detailed_suggestions, input, context}, _from, state) do
    if state.settings.enabled and String.length(input) >= state.settings.min_input_length do
      detailed_suggestions = generate_detailed_suggestions(input, context, state)
      {:reply, detailed_suggestions, state}
    else
      {:reply, [], state}
    end
  end

  @impl true
  def handle_call({:register_provider, provider_module, opts}, _from, state) do
    case register_suggestion_provider(provider_module, opts, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:update_settings, new_settings}, _from, state) do
    updated_settings = Map.merge(state.settings, new_settings)
    new_state = %{state | settings: updated_settings}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      enabled: state.settings.enabled,
      providers_count: length(state.suggestion_providers),
      cache_size: map_size(state.completion_cache),
      context_cache_size: map_size(state.context_cache),
      learning_data_points: count_learning_data(state.learning_data),
      settings: state.settings
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:clear_cache, _from, state) do
    new_state = %{state | completion_cache: %{}, context_cache: %{}}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast({:record_command, command, context, success}, state) do
    if state.settings.learning_enabled do
      new_state = record_command_execution(command, context, success, state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:update_cache, new_cache}, state) do
    {:noreply, %{state | completion_cache: new_cache}}
  end

  # Private functions

  defp initialize_autocomplete_engine(state, opts) do
    with {:ok, history_tracker} <- HistoryTracker.start_link(opts),
         {:ok, project_detector} <- ProjectDetector.start_link(opts),
         {:ok, git_helper} <- GitHelper.start_link(opts),
         {:ok, tool_registry} <- ToolRegistry.start_link(opts) do
      # Register default suggestion providers
      default_providers = [
        {SuggestionProvider.CommandProvider, []},
        {SuggestionProvider.FilePathProvider, []},
        {SuggestionProvider.GitProvider, []},
        {SuggestionProvider.HistoryProvider, []},
        {SuggestionProvider.MCPProvider, []},
        {SuggestionProvider.ToolProvider, []}
      ]

      initialized_state = %{
        state
        | history_tracker: history_tracker,
          project_detector: project_detector,
          git_helper: git_helper,
          tool_registry: tool_registry
      }

      final_state =
        Enum.reduce(default_providers, initialized_state, fn {provider, opts}, acc_state ->
          case register_suggestion_provider(provider, opts, acc_state) do
            {:ok, new_state} -> new_state
            {:error, _reason} -> acc_state
          end
        end)

      {:ok, final_state}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp generate_suggestions(input, context, state) do
    # Check cache first
    cache_key = generate_cache_key(input, context)

    cached_suggestions =
      case Map.get(state.completion_cache, cache_key) do
        {suggestions, timestamp} ->
          current_time = System.monotonic_time(:millisecond)

          if timestamp > current_time - @completion_cache_ttl do
            suggestions
          else
            nil
          end

        _ ->
          nil
      end

    case cached_suggestions do
      nil ->
        # Generate fresh suggestions
        fresh_suggestions = generate_fresh_suggestions(input, context, state)

        # Cache results
        cache_entry = {fresh_suggestions, System.monotonic_time(:millisecond)}
        updated_cache = Map.put(state.completion_cache, cache_key, cache_entry)

        # Update state with new cache (async)
        GenServer.cast(self(), {:update_cache, updated_cache})

        fresh_suggestions

      suggestions ->
        suggestions
    end
  end

  defp generate_fresh_suggestions(input, context, state) do
    # Enhanced context with current state
    enhanced_context = enhance_context(input, context, state)

    # Collect suggestions from all providers
    all_suggestions =
      state.suggestion_providers
      |> Enum.flat_map(fn {provider, provider_opts} ->
        try do
          provider.get_suggestions(input, enhanced_context, provider_opts)
        rescue
          error ->
            Logger.warning("Suggestion provider failed",
              provider: provider,
              error: inspect(error)
            )

            []
        end
      end)

    # Score, rank, and filter suggestions
    all_suggestions
    |> score_suggestions(input, enhanced_context, state)
    |> rank_suggestions(state)
    |> filter_suggestions(state)
    |> Enum.take(state.settings.max_suggestions)
  end

  defp generate_detailed_suggestions(input, context, state) do
    # Similar to generate_suggestions but with full metadata
    enhanced_context = enhance_context(input, context, state)

    state.suggestion_providers
    |> Enum.flat_map(fn {provider, provider_opts} ->
      try do
        case provider.get_detailed_suggestions(input, enhanced_context, provider_opts) do
          suggestions when is_list(suggestions) -> suggestions
          _ -> []
        end
      rescue
        error ->
          Logger.warning("Detailed suggestion provider failed",
            provider: provider,
            error: inspect(error)
          )

          []
      end
    end)
    |> score_detailed_suggestions(input, enhanced_context, state)
    |> rank_detailed_suggestions(state)
    |> Enum.take(state.settings.max_suggestions)
  end

  defp enhance_context(input, context, state) do
    base_context =
      Map.merge(context, %{
        input: input,
        timestamp: DateTime.utc_now(),
        working_directory: File.cwd!()
      })

    # Add project context if enabled
    project_context =
      if state.settings.context_aware do
        ProjectDetector.get_project_context(state.project_detector)
      else
        %{}
      end

    # Add Git context if enabled
    git_context =
      if state.settings.git_integration do
        GitHelper.get_git_context(state.git_helper)
      else
        %{}
      end

    # Add command history context
    history_context = HistoryTracker.get_recent_context(state.history_tracker, 10)

    Map.merge(base_context, %{
      project: project_context,
      git: git_context,
      history: history_context
    })
  end

  defp score_suggestions(suggestions, input, context, state) do
    Enum.map(suggestions, fn suggestion ->
      score = calculate_suggestion_score(suggestion, input, context, state)
      {suggestion, score}
    end)
  end

  defp score_detailed_suggestions(suggestions, input, context, state) do
    Enum.map(suggestions, fn suggestion ->
      score = calculate_detailed_suggestion_score(suggestion, input, context, state)
      Map.put(suggestion, :score, score)
    end)
  end

  defp calculate_suggestion_score(suggestion, input, context, state) do
    base_score = 0.0

    # Exact prefix match gets highest score
    base_score =
      if String.starts_with?(suggestion, input) do
        base_score + 100.0
      else
        base_score
      end

    # Fuzzy match scoring
    base_score =
      if state.settings.fuzzy_matching do
        base_score + calculate_fuzzy_score(suggestion, input)
      else
        base_score
      end

    # Context relevance
    base_score = base_score + calculate_context_relevance(suggestion, context)

    # Learning-based scoring
    base_score =
      if state.settings.learning_enabled do
        base_score + calculate_learning_score(suggestion, context, state)
      else
        base_score
      end

    # Frequency-based scoring from history
    base_score + calculate_frequency_score(suggestion, state)
  end

  defp calculate_detailed_suggestion_score(suggestion, input, context, state) do
    # Similar to calculate_suggestion_score but for detailed suggestions
    text = Map.get(suggestion, :text, Map.get(suggestion, :completion, ""))
    calculate_suggestion_score(text, input, context, state)
  end

  defp calculate_fuzzy_score(suggestion, input) do
    # Simple fuzzy scoring based on character overlap
    suggestion_chars = String.graphemes(String.downcase(suggestion))
    input_chars = String.graphemes(String.downcase(input))

    overlap = Enum.count(input_chars, fn char -> char in suggestion_chars end)
    overlap / length(input_chars) * 50.0
  end

  defp calculate_context_relevance(suggestion, context) do
    # Score based on context relevance
    score = 0.0

    # File path relevance
    score =
      if context[:working_directory] && String.contains?(suggestion, context[:working_directory]) do
        score + 20.0
      else
        score
      end

    # Git context relevance
    score =
      if context[:git][:branch] && String.contains?(suggestion, context[:git][:branch]) do
        score + 15.0
      else
        score
      end

    # Project type relevance
    score =
      if context[:project][:type] do
        project_type = context[:project][:type]

        case {project_type, suggestion} do
          {:elixir, suggestion} ->
            if String.contains?(suggestion, "mix") or String.contains?(suggestion, "iex") or
                 String.contains?(suggestion, "elixir") do
              score + 25.0
            else
              score
            end

          {:javascript, suggestion} ->
            if String.contains?(suggestion, "npm") or String.contains?(suggestion, "node") or
                 String.contains?(suggestion, "yarn") do
              score + 25.0
            else
              score
            end

          {:python, suggestion} ->
            if String.contains?(suggestion, "pip") or String.contains?(suggestion, "python") or
                 String.contains?(suggestion, "venv") do
              score + 25.0
            else
              score
            end

          _ ->
            score
        end
      else
        score
      end

    score
  end

  defp calculate_learning_score(suggestion, context, state) do
    # Score based on learning data
    learning_key = generate_learning_key(suggestion, context)

    case Map.get(state.learning_data, learning_key) do
      %{usage_count: count, success_rate: rate} ->
        count * 2.0 + rate * 30.0

      _ ->
        0.0
    end
  end

  defp calculate_frequency_score(suggestion, state) do
    # Score based on command frequency
    case HistoryTracker.get_command_frequency(state.history_tracker, suggestion) do
      freq when freq > 0 -> min(freq * 5.0, 40.0)
      _ -> 0.0
    end
  end

  defp rank_suggestions(scored_suggestions, _state) do
    scored_suggestions
    |> Enum.sort_by(fn {_suggestion, score} -> score end, :desc)
    |> Enum.map(fn {suggestion, _score} -> suggestion end)
  end

  defp rank_detailed_suggestions(suggestions, _state) do
    suggestions
    |> Enum.sort_by(fn suggestion -> Map.get(suggestion, :score, 0) end, :desc)
  end

  defp filter_suggestions(suggestions, state) do
    suggestions
    |> Enum.uniq()
    |> Enum.reject(&(String.trim(&1) == ""))
    |> apply_custom_filters(state)
  end

  defp apply_custom_filters(suggestions, _state) do
    # Apply any custom filtering logic
    suggestions
    |> Enum.reject(fn suggestion ->
      # Filter out potentially dangerous commands
      dangerous_patterns = ["rm -rf", "sudo rm", "> /dev/", "format c:"]
      Enum.any?(dangerous_patterns, &String.contains?(suggestion, &1))
    end)
  end

  defp register_suggestion_provider(provider_module, opts, state) do
    if Code.ensure_loaded?(provider_module) and function_exported?(provider_module, :get_suggestions, 3) do
      new_providers = [{provider_module, opts} | state.suggestion_providers]
      new_state = %{state | suggestion_providers: new_providers}
      {:ok, new_state}
    else
      {:error, "Invalid suggestion provider: #{inspect(provider_module)}"}
    end
  end

  defp record_command_execution(command, context, success, state) do
    learning_key = generate_learning_key(command, context)

    current_data =
      Map.get(state.learning_data, learning_key, %{
        usage_count: 0,
        success_count: 0,
        success_rate: 0.0,
        last_used: DateTime.utc_now()
      })

    new_usage_count = current_data.usage_count + 1
    new_success_count = if success, do: current_data.success_count + 1, else: current_data.success_count
    new_success_rate = new_success_count / new_usage_count

    updated_data = %{
      usage_count: new_usage_count,
      success_count: new_success_count,
      success_rate: new_success_rate,
      last_used: DateTime.utc_now()
    }

    new_learning_data = Map.put(state.learning_data, learning_key, updated_data)
    %{state | learning_data: new_learning_data}
  end

  defp generate_cache_key(input, context) do
    # Generate a cache key based on input and relevant context
    context_hash = :crypto.hash(:md5, inspect(context)) |> Base.encode16()
    "#{input}:#{context_hash}"
  end

  defp generate_learning_key(command, context) do
    # Generate a learning key based on command and context
    context_snippet = %{
      project_type: get_in(context, [:project, :type]),
      git_branch: get_in(context, [:git, :branch]),
      working_dir_type: classify_directory(context[:working_directory])
    }

    "#{command}:#{inspect(context_snippet)}"
  end

  defp classify_directory(nil), do: :unknown

  defp classify_directory(dir) do
    cond do
      File.exists?(Path.join(dir, "mix.exs")) -> :elixir
      File.exists?(Path.join(dir, "package.json")) -> :javascript
      File.exists?(Path.join(dir, "requirements.txt")) -> :python
      File.exists?(Path.join(dir, ".git")) -> :git_repo
      true -> :generic
    end
  end

  defp count_learning_data(learning_data) do
    learning_data
    |> Map.values()
    |> Enum.reduce(0, fn data, acc -> acc + data.usage_count end)
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.info("Autocomplete Engine shutting down")
    :ok
  end
end
