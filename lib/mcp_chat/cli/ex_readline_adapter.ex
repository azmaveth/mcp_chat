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
        load_history(ex_readline_pid)

        {:ok, %{
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
      {:ok, line} ->
        # Add to history if not empty
        if line != "" and String.trim(line) != "" do
          ExReadline.add_to_history(line)
          save_history_async(state.ex_readline_pid)
        end

        {:reply, line, state}

      :eof ->
        {:reply, :eof, state}

      {:error, reason} ->
        Logger.warning("ExReadline error: #{inspect(reason)}")
        {:reply, :eof, state}
    end
  end

  @impl true
  def handle_cast({:add_to_history, line}, state) do
    ExReadline.add_history(state.ex_readline_pid, line)
    save_history_async(state.ex_readline_pid)
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
  def terminate(_reason, state) do
    # Save history before terminating
    save_history(state.ex_readline_pid)
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

  defp load_history(ex_readline_pid) do
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
    # Note: ExReadline doesn't expose get_history, we'll need to track history differently
    case :not_implemented do
      {:ok, history} ->
        history_file = Path.expand(@history_file)

        # Ensure directory exists
        history_file
        |> Path.dirname()
        |> File.mkdir_p()

        # Write history
        content = Enum.join(history, "\n")
        case File.write(history_file, content) do
          :ok ->
            :ok
          {:error, reason} ->
            Logger.warning("Failed to save history: #{inspect(reason)}")
            :ok
        end

      {:error, reason} ->
        Logger.warning("Failed to get history: #{inspect(reason)}")
        :ok
    end
  end

  defp save_history_async(ex_readline_pid) do
    # Save history in a separate process to avoid blocking
    Task.start(fn ->
      save_history(ex_readline_pid)
    end)
  end
end
