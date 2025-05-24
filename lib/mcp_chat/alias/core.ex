defmodule MCPChat.Alias.Core do
  @moduledoc """
  Functional core for alias operations without process state.

  This module provides pure functions for managing command aliases,
  making it suitable for library usage without requiring GenServer supervision.

  Example usage:

      # Load aliases from file
      aliases = MCPChat.Alias.Core.load_aliases("/path/to/aliases.json")

      # Define a new alias
      {:ok, updated_aliases} = MCPChat.Alias.Core.define_alias(aliases, "ll", ["ls", "-la"])

      # Expand an alias
      {:ok, commands} = MCPChat.Alias.Core.expand_alias(updated_aliases, "ll")
      # => {:ok, ["ls", "-la"]}
  """

  alias MCPChat.Error

  @doc """
  Load aliases from a file path.

  ## Parameters
  - `path` - File path to aliases JSON file

  ## Returns
  Map of aliases or empty map if file doesn't exist.
  """
  def load_aliases(path) do
    if File.exists?(path) do
      case File.read(path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, aliases} when is_map(aliases) ->
              # Convert string keys to strings if needed
              Map.new(aliases, fn {k, v} -> {to_string(k), v} end)

            _ ->
              %{}
          end

        _ ->
          %{}
      end
    else
      %{}
    end
  end

  @doc """
  Save aliases to a file path.

  ## Parameters
  - `aliases` - Map of aliases
  - `path` - File path to save to

  ## Returns
  :ok on success, {:error, reason} on failure.
  """
  def save_aliases(aliases, path) do
    dir = Path.dirname(path)

    # Ensure directory exists
    case File.mkdir_p(dir) do
      :ok ->
        # Write aliases
        content = Jason.encode!(aliases, pretty: true)
        File.write(path, content)

      error ->
        error
    end
  end

  @doc """
  Define a new alias.

  ## Parameters
  - `aliases` - Current aliases map
  - `name` - Alias name
  - `commands` - List of commands for the alias

  ## Returns
  {:ok, updated_aliases} on success, {:error, reason} on failure.
  """
  def define_alias(aliases, name, commands) when is_binary(name) and is_list(commands) do
    # Validate alias name
    cond do
      String.length(name) == 0 ->
        Error.validation_error(:name, "cannot be empty")

      String.contains?(name, " ") ->
        Error.validation_error(:name, "cannot contain spaces")

      is_reserved_command?(name) ->
        Error.validation_error(:name, "cannot override built-in command '#{name}'")

      true ->
        # Validate commands
        case validate_commands(commands) do
          :ok ->
            updated_aliases = Map.put(aliases, name, commands)
            {:ok, updated_aliases}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Remove an alias.

  ## Parameters
  - `aliases` - Current aliases map
  - `name` - Alias name to remove

  ## Returns
  {:ok, updated_aliases} on success, {:error, reason} on failure.
  """
  def remove_alias(aliases, name) do
    if Map.has_key?(aliases, name) do
      updated_aliases = Map.delete(aliases, name)
      {:ok, updated_aliases}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Get an alias by name.

  ## Parameters
  - `aliases` - Current aliases map
  - `name` - Alias name

  ## Returns
  {:ok, commands} on success, {:error, reason} on failure.
  """
  def get_alias(aliases, name) do
    case Map.get(aliases, name) do
      nil -> {:error, :not_found}
      commands -> {:ok, commands}
    end
  end

  @doc """
  List all aliases.

  ## Parameters
  - `aliases` - Current aliases map

  ## Returns
  Map of aliases.
  """
  def list_aliases(aliases) do
    aliases
  end

  @doc """
  Expand an alias to its commands, handling recursive expansion.

  ## Parameters
  - `aliases` - Current aliases map
  - `name` - Alias name to expand

  ## Returns
  {:ok, expanded_commands} on success, {:error, reason} on failure.
  """
  def expand_alias(aliases, name) do
    case Map.get(aliases, name) do
      nil ->
        {:error, :not_found}

      commands ->
        expanded = expand_commands(commands, aliases, [name])
        {:ok, expanded}
    end
  end

  @doc """
  Check if a command is an alias.

  ## Parameters
  - `aliases` - Current aliases map
  - `name` - Command name to check

  ## Returns
  Boolean indicating if the name is an alias.
  """
  def is_alias?(aliases, name) do
    Map.has_key?(aliases, name)
  end

  # Private helper functions

  defp is_reserved_command?(name) do
    # List of built-in commands that cannot be overridden
    reserved = [
      "help",
      "clear",
      "history",
      "new",
      "save",
      "load",
      "sessions",
      "config",
      "servers",
      "discover",
      "connect",
      "disconnect",
      "tools",
      "tool",
      "resources",
      "resource",
      "prompts",
      "prompt",
      "backend",
      "models",
      "alias",
      "aliases",
      "unalias",
      "cost",
      "export",
      "exit",
      "quit"
    ]

    Enum.member?(reserved, name)
  end

  defp validate_commands(commands) do
    cond do
      length(commands) == 0 ->
        Error.validation_error(:commands, "cannot be empty")

      Enum.any?(commands, &(not is_binary(&1))) ->
        Error.validation_error(:commands, "must all be strings")

      true ->
        :ok
    end
  end

  defp expand_commands(commands, aliases, visited) do
    Enum.flat_map(commands, fn cmd ->
      # Split command to check if first part is an alias
      case String.split(cmd, " ", parts: 2) do
        [alias_name] ->
          if alias_name in visited do
            # Circular reference detected, return as-is
            [cmd]
          else
            case Map.get(aliases, alias_name) do
              nil ->
                # Not an alias, keep as is
                [cmd]

              alias_commands ->
                # Recursively expand
                expand_commands(alias_commands, aliases, [alias_name | visited])
            end
          end

        [alias_name, args] ->
          if alias_name in visited do
            # Circular reference detected, return as-is
            [cmd]
          else
            case Map.get(aliases, alias_name) do
              nil ->
                # Not an alias, keep as is
                [cmd]

              alias_commands ->
                # Recursively expand and append args to each command
                expanded = expand_commands(alias_commands, aliases, [alias_name | visited])
                Enum.map(expanded, fn expanded_cmd -> "#{expanded_cmd} #{args}" end)
            end
          end

        _ ->
          # Not a command, keep as is
          [cmd]
      end
    end)
  end
end
