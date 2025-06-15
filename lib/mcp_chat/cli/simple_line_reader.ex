defmodule MCPChat.CLI.SimpleLineReader do
  @moduledoc """
  Simple line reader that uses Erlang's built-in line editing.
  This avoids the complexity of raw terminal mode.
  """

  use GenServer
  require Logger

  @history_file "~/.config/mcp_chat/history"
  @max_history_size 1_000

  defstruct [:history, :completion_fn]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def read_line(prompt, _opts \\ []) do
    # Use Erlang's IO system which has built-in line editing
    input = IO.gets(prompt)

    case input do
      :eof ->
        :eof

      {:error, _reason} ->
        :eof

      line when is_binary(line) ->
        line = String.trim_trailing(line, "\n")

        # Add to history if not empty
        if line != "" do
          GenServer.cast(__MODULE__, {:add_to_history, line})
        end

        line
    end
  end

  def add_to_history(line) do
    GenServer.cast(__MODULE__, {:add_to_history, line})
  end

  def set_completion_fn(fun) do
    GenServer.cast(__MODULE__, {:set_completion_fn, fun})
  end

  # Server callbacks

  def init(_opts) do
    # Load history
    history = load_history()

    # Set up readline-like behavior using Erlang's edlin
    # This gives us arrow keys and basic line editing
    Application.put_env(:elixir, :ansi_enabled, true)

    {:ok, %__MODULE__{history: history}}
  end

  def handle_cast({:add_to_history, line}, state) do
    new_history = add_line_to_history(line, state.history)
    save_history(new_history)
    {:noreply, %{state | history: new_history}}
  end

  def handle_cast({:set_completion_fn, fun}, state) do
    {:noreply, %{state | completion_fn: fun}}
  end

  # Private functions

  defp add_line_to_history(line, history) do
    # Don't add duplicates of the last entry
    if history == [] or hd(history) != line do
      [line | history]
      |> Enum.take(@max_history_size)
    else
      history
    end
  end

  defp load_history do
    path = Path.expand(@history_file)

    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.reverse()
        |> Enum.take(@max_history_size)

      {:error, _} ->
        []
    end
  end

  defp save_history(history) do
    path = Path.expand(@history_file)
    dir = Path.dirname(path)

    # Ensure directory exists
    File.mkdir_p!(dir)

    # Write history (newest first in file)
    content =
      history
      |> Enum.reverse()
      |> Enum.join("\n")

    File.write!(path, content <> "\n")
  rescue
    e ->
      Logger.warning("Failed to save history: #{Exception.message(e)}")
  end
end
