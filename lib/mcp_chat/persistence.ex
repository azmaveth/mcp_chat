defmodule MCPChat.Persistence do
  @moduledoc """
  Handles saving and loading chat sessions to/from disk.
  """
  
  alias MCPChat.Session
  
  @sessions_dir "~/.config/mcp_chat/sessions"
  @extension ".json"
  
  # Public API
  
  @doc """
  Save the current session to disk.
  """
  def save_current_session(name \\ nil) do
    session = Session.get_current_session()
    save_session(session, name)
  end
  
  @doc """
  Save a specific session to disk.
  """
  def save_session(session, name \\ nil) do
    ensure_sessions_dir()
    
    filename = build_filename(session, name)
    path = Path.join(sessions_dir(), filename)
    
    data = serialize_session(session)
    
    case File.write(path, data) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Load a session from disk by name or ID.
  """
  def load_session(identifier) do
    path = find_session_file(identifier)
    
    with {:ok, data} <- File.read(path),
         {:ok, session} <- deserialize_session(data) do
      {:ok, session}
    else
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  List all saved sessions.
  """
  def list_sessions do
    ensure_sessions_dir()
    
    case File.ls(sessions_dir()) do
      {:ok, files} ->
        sessions = files
        |> Enum.filter(&String.ends_with?(&1, @extension))
        |> Enum.map(&load_session_metadata/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
        
        {:ok, sessions}
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Delete a saved session.
  """
  def delete_session(identifier) do
    path = find_session_file(identifier)
    File.rm(path)
  end
  
  @doc """
  Export session to a specific format.
  """
  def export_session(session, format, path) do
    content = case format do
      :markdown -> export_as_markdown(session)
      :json -> export_as_json(session)
      _ -> {:error, :unsupported_format}
    end
    
    case content do
      {:error, reason} -> 
        {:error, reason}
      data -> 
        case File.write(path, data) do
          :ok -> {:ok, path}
          {:error, reason} -> {:error, reason}
        end
    end
  end
  
  # Private Functions
  
  defp sessions_dir do
    Path.expand(@sessions_dir)
  end
  
  defp ensure_sessions_dir do
    dir = sessions_dir()
    File.mkdir_p!(dir)
  end
  
  defp build_filename(session, nil) do
    timestamp = DateTime.to_unix(session.created_at)
    "session_#{session.id}_#{timestamp}#{@extension}"
  end
  
  defp build_filename(session, name) do
    # Sanitize the name for filesystem
    safe_name = name
    |> String.replace(~r/[^a-zA-Z0-9_\-]/, "_")
    |> String.slice(0, 50)
    
    "#{safe_name}_#{session.id}#{@extension}"
  end
  
  defp find_session_file(identifier) when is_integer(identifier) do
    ensure_sessions_dir()
    
    # Load by index
    case list_sessions() do
      {:ok, sessions} ->
        case Enum.at(sessions, identifier - 1) do
          nil -> Path.join(sessions_dir(), "not_found")
          session -> Path.join(sessions_dir(), session.filename)
        end
      _ ->
        Path.join(sessions_dir(), "not_found")
    end
  end
  
  defp find_session_file(identifier) when is_binary(identifier) do
    ensure_sessions_dir()
    
    # Try exact filename first
    exact_path = Path.join(sessions_dir(), identifier <> @extension)
    if File.exists?(exact_path) do
      exact_path
    else
      # Search by ID or name
      case File.ls(sessions_dir()) do
        {:ok, files} ->
          matching_file = files
          |> Enum.filter(&String.ends_with?(&1, @extension))
          |> Enum.find(fn file ->
            String.contains?(file, identifier)
          end)
          
          if matching_file do
            Path.join(sessions_dir(), matching_file)
          else
            Path.join(sessions_dir(), "not_found")
          end
        
        _ ->
          Path.join(sessions_dir(), "not_found")
      end
    end
  end
  
  defp serialize_session(session) do
    data = %{
      id: session.id,
      llm_backend: session.llm_backend,
      messages: Enum.map(session.messages, &serialize_message/1),
      context: session.context,
      created_at: DateTime.to_iso8601(session.created_at),
      updated_at: DateTime.to_iso8601(session.updated_at),
      token_usage: session.token_usage
    }
    
    Jason.encode!(data, pretty: true)
  end
  
  defp serialize_message(message) do
    %{
      role: message.role,
      content: message.content,
      timestamp: DateTime.to_iso8601(message.timestamp)
    }
  end
  
  defp deserialize_session(data) do
    case Jason.decode(data) do
      {:ok, json} ->
        session = %Session{
          id: json["id"],
          llm_backend: json["llm_backend"],
          messages: Enum.map(json["messages"] || [], &deserialize_message/1),
          context: json["context"] || %{},
          created_at: parse_datetime(json["created_at"]),
          updated_at: parse_datetime(json["updated_at"]),
          token_usage: json["token_usage"] || %{input_tokens: 0, output_tokens: 0}
        }
        {:ok, session}
      
      {:error, reason} ->
        {:error, {:decode_error, reason}}
    end
  end
  
  defp deserialize_message(data) do
    %{
      role: data["role"],
      content: data["content"],
      timestamp: parse_datetime(data["timestamp"])
    }
  end
  
  defp parse_datetime(nil), do: DateTime.utc_now()
  defp parse_datetime(string) do
    case DateTime.from_iso8601(string) do
      {:ok, datetime, _} -> datetime
      _ -> DateTime.utc_now()
    end
  end
  
  defp load_session_metadata(filename) do
    path = Path.join(sessions_dir(), filename)
    
    with {:ok, data} <- File.read(path),
         {:ok, json} <- Jason.decode(data),
         {:ok, %{size: size}} <- File.stat(path) do
      %{
        filename: filename,
        id: json["id"],
        llm_backend: json["llm_backend"],
        message_count: length(json["messages"] || []),
        created_at: parse_datetime(json["created_at"]),
        updated_at: parse_datetime(json["updated_at"]),
        size: size,
        relative_time: format_relative_time(parse_datetime(json["updated_at"]))
      }
    else
      _ -> nil
    end
  end
  
  defp export_as_markdown(session) do
    header = """
    # Chat Session Export
    
    **Session ID**: #{session.id}  
    **Created**: #{format_datetime(session.created_at)}  
    **Updated**: #{format_datetime(session.updated_at)}  
    **Backend**: #{session.llm_backend}  
    **Total Messages**: #{length(session.messages)}
    
    ---
    
    """
    
    messages = session.messages
    |> Enum.reverse()
    |> Enum.map(fn msg ->
      """
      ## #{String.capitalize(msg.role)}
      *#{format_datetime(msg.timestamp)}*
      
      #{msg.content}
      
      ---
      
      """
    end)
    |> Enum.join("")
    
    header <> messages
  end
  
  defp export_as_json(session) do
    serialize_session(session)
  end
  
  defp format_datetime(datetime) do
    datetime
    |> DateTime.to_naive()
    |> NaiveDateTime.to_string()
  end
  
  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime)
    
    cond do
      diff_seconds < 60 ->
        "just now"
      
      diff_seconds < 3600 ->
        minutes = div(diff_seconds, 60)
        if minutes == 1, do: "1 minute ago", else: "#{minutes} minutes ago"
      
      diff_seconds < 86400 ->
        hours = div(diff_seconds, 3600)
        if hours == 1, do: "1 hour ago", else: "#{hours} hours ago"
      
      diff_seconds < 604800 ->
        days = div(diff_seconds, 86400)
        if days == 1, do: "1 day ago", else: "#{days} days ago"
      
      true ->
        Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
    end
  end
end