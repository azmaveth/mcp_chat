defmodule MCPChat.Alias do
  @moduledoc """
  Manages custom command aliases for MCP Chat.

  Allows users to define shortcuts for command sequences.
  """

  use GenServer

  @aliases_file "~/.config/mcp_chat/aliases.json"

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Define a new alias.
  """
  def define_alias(name, commands) when is_binary(name) and is_list(commands) do
    GenServer.call(__MODULE__, {:define_alias, name, commands})
  end

  @doc """
  Remove an alias.
  """
  def remove_alias(name) do
    GenServer.call(__MODULE__, {:remove_alias, name})
  end

  @doc """
  Get alias definition.
  """
  def get_alias(name) do
    GenServer.call(__MODULE__, {:get_alias, name})
  end

  @doc """
  List all aliases.
  """
  def list_aliases() do
    GenServer.call(__MODULE__, :list_aliases)
  end

  @doc """
  Expand an alias to its commands.
  """
  def expand_alias(name) do
    GenServer.call(__MODULE__, {:expand_alias, name})
  end

  @doc """
  Check if a command is an alias.
  """
  def is_alias?(name) do
    case get_alias(name) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Save aliases to disk.
  """
  def save_aliases() do
    GenServer.cast(__MODULE__, :save_aliases)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      aliases: load_aliases()
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:define_alias, name, commands}, _from, state) do
    # Validate alias name
    cond do
      String.length(name) == 0 ->
        {:reply, {:error, "Alias name cannot be empty"}, state}

      String.contains?(name, " ") ->
        {:reply, {:error, "Alias name cannot contain spaces"}, state}

      is_reserved_command?(name) ->
        {:reply, {:error, "Cannot override built-in command '#{name}'"}, state}

      true ->
        # Validate commands
        case validate_commands(commands) do
          :ok ->
            updated_aliases = Map.put(state.aliases, name, commands)
            new_state = %{state | aliases: updated_aliases}

            # Save to disk asynchronously
            GenServer.cast(self(), :save_aliases)

            {:reply, :ok, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call({:remove_alias, name}, _from, state) do
    if Map.has_key?(state.aliases, name) do
      updated_aliases = Map.delete(state.aliases, name)
      new_state = %{state | aliases: updated_aliases}

      # Save to disk asynchronously
      GenServer.cast(self(), :save_aliases)

      {:reply, :ok, new_state}
    else
      {:reply, {:error, "Alias '#{name}' not found"}, state}
    end
  end

  def handle_call({:get_alias, name}, _from, state) do
    case Map.get(state.aliases, name) do
      nil -> {:reply, {:error, "Alias '#{name}' not found"}, state}
      commands -> {:reply, {:ok, commands}, state}
    end
  end

  def handle_call(:list_aliases, _from, state) do
    aliases =
      state.aliases
      |> Enum.map(fn {name, commands} -> %{name: name, commands: commands} end)
      |> Enum.sort_by(& &1.name)

    {:reply, aliases, state}
  end

  def handle_call({:expand_alias, name}, _from, state) do
    case Map.get(state.aliases, name) do
      nil ->
        {:reply, {:error, "Alias '#{name}' not found"}, state}

      commands ->
        # Recursively expand any nested aliases
        expanded = expand_commands(commands, state.aliases, [name])
        {:reply, {:ok, expanded}, state}
    end
  end

  @impl true
  def handle_cast(:save_aliases, state) do
    save_aliases_to_file(state.aliases)
    {:noreply, state}
  end

  # Private functions

  defp load_aliases() do
    path = Path.expand(@aliases_file)

    if File.exists?(path) do
      case File.read(path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, aliases} when is_map(aliases) ->
              # Convert string keys to atoms if needed
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

  defp save_aliases_to_file(aliases) do
    path = Path.expand(@aliases_file)
    dir = Path.dirname(path)

    # Ensure directory exists
    File.mkdir_p!(dir)

    # Write aliases
    content = Jason.encode!(aliases, pretty: true)
    File.write!(path, content)
  end

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
      "model",
      "export",
      "context",
      "system",
      "tokens",
      "strategy",
      "cost",
      "alias",
      "exit",
      "quit"
    ]

    name in reserved
  end

  defp validate_commands(commands) do
    cond do
      length(commands) == 0 ->
        {:error, "Alias must contain at least one command"}

      Enum.any?(commands, &(not is_binary(&1))) ->
        {:error, "All commands must be strings"}

      true ->
        :ok
    end
  end

  defp expand_commands(commands, aliases, visited) do
    Enum.flat_map(commands, fn cmd ->
      # Parse command to check if it's an alias
      case String.split(cmd, " ", parts: 2) do
        ["/" <> alias_name | _rest] ->
          if alias_name in visited do
            # Circular reference detected
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

        _ ->
          # Not a command, keep as is
          [cmd]
      end
    end)
  end
end
