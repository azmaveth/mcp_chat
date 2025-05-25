defmodule MCPChat.CLI.ExReadlineAdapter do
  @moduledoc """
  Adapter that wraps ExReadline to work with MCPChat's line reading interface.

  This adapter allows mcp_chat to use the ex_readline library while maintaining
  compatibility with the existing MCPChat.CLI.SimpleLineReader interface.
  """

  use GenServer
  require Logger

  @history_file "~/.config/mcp_chat/history"

  # Client API - matches MCPChat.CLI.SimpleLineReader interface

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def read_line(prompt, opts \\ []) do
    GenServer.call(__MODULE__, {:read_line, prompt, opts}, :infinity)
  end

  def add_to_history(line) do
    GenServer.cast(__MODULE__, {:add_to_history, line})
  end

  def set_completion_fn(fun) do
    GenServer.cast(__MODULE__, {:set_completion_fn, fun})
  end

  def stop() do
    GenServer.stop(__MODULE__)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    # Determine which ExReadline implementation to use
    implementation = Keyword.get(opts, :implementation, :simple)

    # Start the appropriate ExReadline implementation
    case start_ex_readline(implementation, opts) do
      {:ok, ex_readline_pid} ->
        # Load history
        load_history()

        {:ok,
         %{
           ex_readline_pid: ex_readline_pid,
           implementation: implementation,
           completion_fn: nil
         }}

      error ->
        error
    end
  end

  @impl true
  def handle_call({:read_line, prompt, _opts}, _from, state) do
    case ExReadline.read_line(prompt) do
      :eof ->
        {:reply, :eof, state}

      line when is_binary(line) ->
        # Add to history if not empty
        if line != "" and String.trim(line) != "" do
          ExReadline.add_to_history(line)
          # History persistence not currently implemented
        end

        {:reply, line, state}
    end
  end

  @impl true
  def handle_cast({:add_to_history, line}, state) do
    ExReadline.add_history(state.ex_readline_pid, line)
    # History persistence not currently implemented
    {:noreply, state}
  end

  def handle_cast({:set_completion_fn, fun}, state) do
    # Set completion function in ExReadline if supported
    case state.implementation do
      :advanced ->
        ExReadline.set_completion_fn(fun)

      _ ->
        # Simple implementation doesn't support completion
        :ok
    end

    {:noreply, %{state | completion_fn: fun}}
  end

  @impl true
  def terminate(_reason, _state) do
    # History saving not currently implemented in ex_readline
    :ok
  end

  # Private helper functions

  defp start_ex_readline(implementation, opts) do
    case implementation do
      :simple ->
        ExReadline.start_link(opts ++ [implementation: :simple_reader])

      :advanced ->
        ExReadline.start_link(opts ++ [implementation: :line_editor])

      _ ->
        # Default to simple
        ExReadline.start_link(opts ++ [implementation: :simple_reader])
    end
  end

  defp load_history() do
    history_file = Path.expand(@history_file)

    case File.read(history_file) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.reject(&(&1 == ""))
        |> Enum.each(fn line ->
          ExReadline.add_to_history(line)
        end)

      {:error, :enoent} ->
        # No history file exists yet, that's fine
        :ok

      {:error, reason} ->
        Logger.warning("Failed to load history: #{inspect(reason)}")
        :ok
    end
  end

  defp save_history(_ex_readline_pid) do
    # ExReadline doesn't expose get_history API, so we can't save history
    # This is a limitation of the current ex_readline implementation
    # TODO: Add history tracking to ex_readline or track history in this adapter
    :ok
  end
end
