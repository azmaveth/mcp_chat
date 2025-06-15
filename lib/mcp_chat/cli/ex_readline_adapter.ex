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
    # If we're in IEx, just use IO.gets directly
    if Code.ensure_loaded?(IEx) and IEx.started?() do
      case IO.gets(prompt) do
        :eof -> :eof
        {:error, _} -> :eof
        data when is_binary(data) -> String.trim_trailing(data, "\n")
      end
    else
      GenServer.call(__MODULE__, {:read_line, prompt, opts}, :infinity)
    end
  end

  def add_to_history(line) do
    GenServer.cast(__MODULE__, {:add_to_history, line})
  end

  def set_completion_fn(fun) do
    GenServer.cast(__MODULE__, {:set_completion_fn, fun})
  end

  def stop do
    GenServer.stop(__MODULE__)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    # Determine which ExReadline implementation to use
    # Use :simple for escript mode to avoid terminal input issues
    implementation = Keyword.get(opts, :implementation, detect_best_implementation())

    # Debug log
    Logger.info("ExReadlineAdapter: Detected implementation: #{implementation}")

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
    # Use the same pattern as in line 70 - direct call without pid
    ExReadline.add_to_history(line)
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

  defp detect_best_implementation do
    if iex_running?() do
      :simple
    else
      detect_from_environment()
    end
  end

  defp iex_running?() do
    Code.ensure_loaded?(IEx) and IEx.started?()
  end

  defp detect_from_environment do
    case System.get_env("MCP_READLINE_MODE") do
      "advanced" -> :advanced
      "simple" -> :simple
      _ -> detect_from_terminal()
    end
  end

  defp detect_from_terminal do
    case :io.getopts(:standard_io) do
      opts when is_list(opts) ->
        check_terminal_options(opts)

      _ ->
        :simple
    end
  end

  defp check_terminal_options(opts) do
    terminal = Keyword.get(opts, :terminal, :undefined)

    if terminal in [:ebadf, false] do
      :simple
    else
      :advanced
    end
  end

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

  defp load_history do
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
end
