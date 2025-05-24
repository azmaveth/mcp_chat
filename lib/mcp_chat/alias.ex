defmodule MCPChat.Alias do
  @moduledoc """
  GenServer wrapper for alias management.

  This module provides a stateful GenServer interface for alias management.
  For stateless usage, see MCPChat.Alias.Core.

  The functional operations are delegated to MCPChat.Alias.Core, while this
  module handles process state management and supervision.
  """

  use GenServer

  alias MCPChat.Alias.Core

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
  def init(opts) do
    path_provider = Keyword.get(opts, :path_provider, MCPChat.PathProvider.Default)

    aliases_path = get_aliases_path(path_provider)

    state = %{
      aliases: Core.load_aliases(aliases_path),
      path_provider: path_provider,
      aliases_path: aliases_path
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:define_alias, name, commands}, _from, state) do
    case Core.define_alias(state.aliases, name, commands) do
      {:ok, updated_aliases} ->
        new_state = %{state | aliases: updated_aliases}

        # Save to disk asynchronously
        GenServer.cast(self(), :save_aliases)

        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:remove_alias, name}, _from, state) do
    case Core.remove_alias(state.aliases, name) do
      {:ok, updated_aliases} ->
        new_state = %{state | aliases: updated_aliases}

        # Save to disk asynchronously
        GenServer.cast(self(), :save_aliases)

        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_alias, name}, _from, state) do
    result = Core.get_alias(state.aliases, name)
    {:reply, result, state}
  end

  def handle_call(:list_aliases, _from, state) do
    aliases = Core.list_aliases(state.aliases)

    formatted_aliases =
      aliases
      |> Enum.map(fn {name, commands} -> %{name: name, commands: commands} end)
      |> Enum.sort_by(& &1.name)

    {:reply, formatted_aliases, state}
  end

  def handle_call({:expand_alias, name}, _from, state) do
    result = Core.expand_alias(state.aliases, name)
    {:reply, result, state}
  end

  @impl true
  def handle_cast(:save_aliases, state) do
    Core.save_aliases(state.aliases, state.aliases_path)
    {:noreply, state}
  end

  # Private functions - only those specific to GenServer behavior

  # Note: Alias validation and expansion logic moved to MCPChat.Alias.Core

  defp get_aliases_path(path_provider) do
    case path_provider do
      MCPChat.PathProvider.Default ->
        MCPChat.PathProvider.Default.get_path(:aliases_file)

      provider when is_pid(provider) ->
        MCPChat.PathProvider.Static.get_path(provider, :aliases_file)

      provider ->
        provider.get_path(:aliases_file)
    end
  end
end
