defmodule MCPChat.Alias.ExAliasAdapter do
  @moduledoc """
  Adapter that wraps ExAlias to work with MCPChat's existing alias interface.

  This adapter allows mcp_chat to use the ex_alias library while maintaining
  compatibility with the existing MCPChat.Alias interface.
  """

  use GenServer

  # Client API - matches MCPChat.Alias interface

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def define_alias(name, commands) when is_binary(name) and is_list(commands) do
    GenServer.call(__MODULE__, {:define_alias, name, commands})
  end

  def remove_alias(name) do
    GenServer.call(__MODULE__, {:remove_alias, name})
  end

  def get_alias(name) do
    GenServer.call(__MODULE__, {:get_alias, name})
  end

  def list_aliases() do
    GenServer.call(__MODULE__, :list_aliases)
  end

  def expand_alias(input) do
    GenServer.call(__MODULE__, {:expand_alias, input})
  end

  def is_alias?(name) do
    case get_alias(name) do
      {:ok, _} -> true
      {:error, :not_found} -> false
      _ -> false
    end
  end

  def save() do
    GenServer.call(__MODULE__, :save)
  end

  def load() do
    GenServer.call(__MODULE__, :load)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    # Load existing aliases if available
    load_mcp_chat_aliases()

    # Use ExAlias as the name - it should already be started by the supervision tree
    {:ok, %{ex_alias_name: ExAlias}}
  end

  @impl true
  def handle_call({:define_alias, name, commands}, _from, state) do
    result = GenServer.call(state.ex_alias_name, {:define_alias, name, commands})
    {:reply, result, state}
  end

  def handle_call({:remove_alias, name}, _from, state) do
    result = GenServer.call(state.ex_alias_name, {:remove_alias, name})
    {:reply, result, state}
  end

  def handle_call({:get_alias, name}, _from, state) do
    result = GenServer.call(state.ex_alias_name, {:get_alias, name})
    {:reply, result, state}
  end

  def handle_call(:list_aliases, _from, state) do
    result = GenServer.call(state.ex_alias_name, :list_aliases)
    {:reply, result, state}
  end

  def handle_call({:expand_alias, input}, _from, state) do
    result = GenServer.call(state.ex_alias_name, {:expand_alias, input})
    {:reply, result, state}
  end

  def handle_call(:save, _from, state) do
    # Save to mcp_chat's expected location
    aliases = GenServer.call(state.ex_alias_name, :list_aliases)
    result = save_to_mcp_chat_format(aliases)
    {:reply, result, state}
  end

  def handle_call(:load, _from, state) do
    # Load from mcp_chat's expected location
    case load_from_mcp_chat_format() do
      {:ok, aliases} ->
        # Clear existing aliases and load new ones
        # Note: ExAlias doesn't have clear_aliases, we'll need to remove individually
        current_aliases = GenServer.call(state.ex_alias_name, :list_aliases)

        Enum.each(current_aliases, fn %{name: name} ->
          GenServer.call(state.ex_alias_name, {:remove_alias, name})
        end)

        Enum.each(aliases, fn {name, commands} ->
          GenServer.call(state.ex_alias_name, {:define_alias, name, commands})
        end)

        {:reply, :ok, state}

      error ->
        {:reply, error, state}
    end
  end

  # Private helper functions

  defp load_mcp_chat_aliases() do
    case load_from_mcp_chat_format() do
      {:ok, aliases} ->
        Enum.each(aliases, fn {name, commands} ->
          GenServer.call(ExAlias, {:define_alias, name, commands})
        end)

      {:error, _reason} ->
        # No existing aliases to load, that's fine
        :ok
    end
  end

  defp save_to_mcp_chat_format(aliases) do
    # Convert ExAlias format (list of maps) to MCPChat's expected JSON format (map)
    alias_map =
      aliases
      |> Enum.map(fn %{name: name, commands: commands} -> {name, commands} end)
      |> Enum.into(%{})

    case Jason.encode(alias_map) do
      {:ok, json} ->
        file_path = get_mcp_chat_alias_file()

        case File.write(file_path, json) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, {:json_encode_error, reason}}
    end
  end

  defp load_from_mcp_chat_format() do
    file_path = get_mcp_chat_alias_file()

    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, aliases_map} ->
            # Convert from map to list of {name, commands} tuples
            aliases =
              Enum.map(aliases_map, fn {name, commands} ->
                {name, commands}
              end)

            {:ok, aliases}

          {:error, reason} ->
            {:error, {:json_decode_error, reason}}
        end

      {:error, :enoent} ->
        # File doesn't exist, return empty aliases
        {:ok, []}

      {:error, reason} ->
        {:error, {:file_read_error, reason}}
    end
  end

  defp get_mcp_chat_alias_file() do
    # Use the same path that MCPChat.Alias.Core would use
    Path.expand("~/.config/mcp_chat/aliases.json")
  end
end
