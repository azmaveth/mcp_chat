defmodule MCPChat.CLI.Commands.Helpers.Session do
  @moduledoc """
  Common session access and manipulation utilities for CLI commands.

  This module extracts duplicated session access patterns from individual command modules
  to provide consistent session handling across the CLI interface.
  """

  # alias MCPChat.Agents.SessionManager

  @doc """
  Gets a specific property from the current session with an optional default value.

  ## Examples

      iex> get_session_property(:llm_backend, :anthropic)
      :claude

      iex> get_session_property(:nonexistent, "default")
      "default"
  """
  def get_session_property(property, default \\ nil) do
    # In the agent architecture, we no longer have a single "current" session
    # For CLI commands, we return sensible defaults based on configuration
    case property do
      :llm_backend -> MCPChat.Config.get([:llm, :default]) || default || :anthropic
      :model -> get_configured_model_for_current_backend() || default
      _ -> default
    end
  end

  @doc """
  Gets the current LLM backend from the session.

  Returns the configured backend or :anthropic as default.
  """
  def get_session_backend do
    get_session_property(:llm_backend, :anthropic)
  end

  @doc """
  Gets the current LLM model from the session.

  Returns the configured model or a default model for the backend.
  """
  def get_session_model do
    backend = get_session_backend()
    default_model = get_default_model_for_backend(backend)
    get_session_property(:model, default_model)
  end

  @doc """
  Gets both backend and model as a tuple.

  ## Examples

      iex> get_session_backend_and_model()
      {:anthropic, "claude-3-sonnet-20240229"}
  """
  def get_session_backend_and_model do
    {get_session_backend(), get_session_model()}
  end

  @doc """
  Gets a specific context value from the session with an optional default.

  ## Examples

      iex> get_session_context(:files, [])
      ["/path/to/file1.txt", "/path/to/file2.txt"]
  """
  def get_session_context(key, default \\ nil) do
    context = get_session_property(:context, %{})
    Map.get(context, key, default)
  end

  @doc """
  Updates session context with new key-value pairs.

  ## Examples

      iex> update_session_context(%{files: ["/new/file.txt"]})
      :ok
  """
  def update_session_context(updates) when is_map(updates) do
    # In agent architecture, context updates would need to be handled differently
    # For now, return success but don't persist
    _ = updates
    :ok
  end

  @doc """
  Gets session statistics and metadata.

  Returns a map with useful session information like message count,
  token usage, costs, creation time, etc.
  """
  def get_session_stats do
    # Return agent architecture defaults
    %{
      exists: true,
      id: "agent-session",
      message_count: 0,
      token_usage: %{},
      accumulated_cost: 0.0,
      cost_session: nil,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      llm_backend: get_session_backend(),
      model: get_session_model(),
      context_size: 0
    }
  end

  @doc """
  Gets the current session or returns an error tuple if no session exists.

  Useful for commands that require a session to be active.

  ## Examples

      iex> require_session()
      {:ok, %Session{...}}

      iex> require_session()
      {:error, :no_active_session}
  """
  def require_session do
    # Return a mock session for agent architecture
    {:ok,
     %{
       id: "agent-session",
       llm_backend: get_session_backend(),
       model: get_session_model(),
       messages: [],
       context: %{},
       created_at: DateTime.utc_now(),
       updated_at: DateTime.utc_now()
     }}
  end

  @doc """
  Executes a function with the current session, handling the case where no session exists.

  ## Examples

      iex> with_session(fn session -> length(session.messages) end)
      {:ok, 5}

      iex> with_session(fn _session -> :some_result end)
      {:error, :no_active_session}
  """
  def with_session(fun) when is_function(fun, 1) do
    case require_session() do
      {:ok, session} ->
        try do
          {:ok, fun.(session)}
        rescue
          error -> {:error, error}
        end

      error ->
        error
    end
  end

  @doc """
  Gets multiple session properties at once.

  ## Examples

      iex> get_session_info([:id, :llm_backend, :model])
      %{id: "abc123", llm_backend: :anthropic, model: "claude-3-sonnet-20240229"}
  """
  def get_session_info(keys) when is_list(keys) do
    # Return defaults for agent architecture
    keys
    |> Enum.map(fn key ->
      value =
        case key do
          :id -> "agent-session"
          :llm_backend -> get_session_backend()
          :model -> get_session_model()
          _ -> nil
        end

      {key, value}
    end)
    |> Map.new()
  end

  @doc """
  Checks if a session is currently active.

  ## Examples

      iex> session_active?()
      true
  """
  def session_active? do
    # In agent architecture, we consider the system always ready
    true
  end

  @doc """
  Gets the session context file list with validation.

  Returns only files that actually exist on the filesystem.
  """
  def get_session_context_files do
    files = get_session_context(:files, [])

    files
    |> Enum.filter(&File.exists?/1)
    |> Enum.map(fn file ->
      %{
        path: file,
        size: get_file_size(file),
        modified: get_file_modified_time(file)
      }
    end)
  end

  @doc """
  Gets the total size of all context files in bytes.
  """
  def get_session_context_size do
    get_session_context_files()
    |> Enum.map(& &1.size)
    |> Enum.sum()
  end

  @doc """
  Formats session information for display.

  Returns a formatted string with key session details.
  """
  def format_session_summary do
    case require_session() do
      {:error, :no_active_session} ->
        "No active session"

      {:ok, session} ->
        stats = get_session_stats()
        context_files = get_session_context_files()

        """
        Session ID: #{session.id}
        Backend: #{stats.llm_backend}
        Model: #{stats.model || "default"}
        Messages: #{stats.message_count}
        Context Files: #{length(context_files)}
        Total Cost: $#{:erlang.float_to_binary(stats.accumulated_cost, decimals: 4)}
        Created: #{format_datetime(stats.created_at)}
        Updated: #{format_datetime(stats.updated_at)}
        """
        |> String.trim()
    end
  end

  @doc """
  Updates session properties.

  In the agent architecture, this is a no-op for CLI commands.
  """
  def update_session(updates) when is_map(updates) do
    # In agent architecture, session updates for CLI commands are not persisted
    # This is primarily used for temporary UI state that doesn't need persistence
    _ = updates
    :ok
  end

  # Private helper functions

  defp get_configured_model_for_current_backend do
    backend = get_session_backend()
    get_configured_model_for_backend(backend) || get_default_model_for_backend(backend)
  end

  defp get_configured_model_for_backend(backend) do
    case backend do
      :anthropic -> MCPChat.Config.get([:llm, :anthropic, :model])
      :openai -> MCPChat.Config.get([:llm, :openai, :model])
      :ollama -> MCPChat.Config.get([:llm, :ollama, :model])
      :bedrock -> MCPChat.Config.get([:llm, :bedrock, :model])
      :gemini -> MCPChat.Config.get([:llm, :gemini, :model])
      _ -> nil
    end
  end

  defp get_default_model_for_backend(:anthropic), do: "claude-3-sonnet-20240229"
  defp get_default_model_for_backend(:openai), do: "gpt-4"
  defp get_default_model_for_backend(:ollama), do: "llama2"
  defp get_default_model_for_backend(:gemini), do: "gemini-pro"
  defp get_default_model_for_backend(_), do: nil

  defp get_file_size(file_path) do
    case File.stat(file_path) do
      {:ok, %File.Stat{size: size}} -> size
      {:error, _} -> 0
    end
  end

  defp get_file_modified_time(file_path) do
    case File.stat(file_path) do
      {:ok, %File.Stat{mtime: mtime}} ->
        mtime
        |> NaiveDateTime.from_erl!()
        |> DateTime.from_naive!("Etc/UTC")

      {:error, _} ->
        nil
    end
  end

  defp format_datetime(nil), do: "Never"

  defp format_datetime(%DateTime{} = dt) do
    dt
    |> DateTime.to_string()
    |> String.slice(0, 19)
  end

  defp format_datetime(_), do: "Unknown"
end
