defmodule MCPChat.CLI.LineEditor do
  @moduledoc """
  Line editor with history support, arrow keys, and Emacs keybindings.
  Provides readline-like functionality for the chat interface.
  """

  use GenServer
  require Logger

  @history_file "~/.config/mcp_chat/history"
  @max_history_size 1_000

  # ANSI escape sequences
  @cursor_right "\e[C"
  @cursor_left "\e[D"

  # Key codes
  @backspace 127
  @enter 13
  @escape 27
  @ctrl_a 1
  @ctrl_b 2
  @ctrl_c 3
  @ctrl_d 4
  @ctrl_e 5
  @ctrl_f 6
  @ctrl_k 11
  @ctrl_l 12
  @ctrl_n 14
  @ctrl_p 16
  @ctrl_u 21
  @ctrl_w 23
  @tab 9

  defstruct [
    :buffer,
    :cursor,
    :history,
    :history_index,
    :prompt,
    :saved_line,
    :completion_fn
  ]

  # Client API

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

  # Server callbacks

  def init(_opts) do
    history = load_history()
    {:ok, %__MODULE__{history: history}}
  end

  def handle_call({:read_line, prompt, _opts}, _from, state) do
    # Set up terminal for raw input
    old_settings = :io.getopts(:standard_io)
    :io.setopts(:standard_io, binary: true, echo: false)

    # Initialize line state
    line_state = %__MODULE__{
      buffer: "",
      cursor: 0,
      history: state.history,
      history_index: length(state.history),
      prompt: prompt,
      saved_line: nil,
      completion_fn: state.completion_fn
    }

    # Show prompt
    IO.write(prompt)

    # Read input
    result = read_loop(line_state)

    # Restore terminal settings
    :io.setopts(:standard_io, old_settings)

    # Add to history if not empty
    case result do
      {:ok, line} when line != "" ->
        new_history = add_line_to_history(line, state.history)
        save_history(new_history)
        {:reply, line, %{state | history: new_history}}

      {:ok, line} ->
        {:reply, line, state}

      {:error, :interrupted} ->
        {:reply, :eof, state}
    end
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

  defp read_loop(state) do
    case read_key() do
      {:ok, @enter} ->
        IO.write("\n")
        {:ok, state.buffer}

      {:ok, @ctrl_c} ->
        IO.write("^C\n")
        {:error, :interrupted}

      {:ok, @ctrl_d} ->
        if state.buffer == "" do
          IO.write("\n")
          {:error, :interrupted}
        else
          read_loop(delete_char_at_cursor(state))
        end

      {:ok, @backspace} ->
        read_loop(backspace(state))

      {:ok, @escape} ->
        read_escape_sequence(state)

      {:ok, @ctrl_a} ->
        read_loop(move_to_start(state))

      {:ok, @ctrl_e} ->
        read_loop(move_to_end(state))

      {:ok, @ctrl_b} ->
        read_loop(move_left(state))

      {:ok, @ctrl_f} ->
        read_loop(move_right(state))

      {:ok, @ctrl_k} ->
        read_loop(kill_to_end(state))

      {:ok, @ctrl_u} ->
        read_loop(kill_to_start(state))

      {:ok, @ctrl_w} ->
        read_loop(kill_word(state))

      {:ok, @ctrl_l} ->
        clear_screen()
        redraw_line(state)
        read_loop(state)

      {:ok, @ctrl_p} ->
        read_loop(history_prev(state))

      {:ok, @ctrl_n} ->
        read_loop(history_next(state))

      {:ok, @tab} ->
        read_loop(handle_tab(state))

      {:ok, char} when char >= 32 and char <= 126 ->
        read_loop(insert_char(state, char))

      _ ->
        read_loop(state)
    end
  end

  defp read_escape_sequence(state) do
    case read_key() do
      {:ok, ?[} ->
        case read_key() do
          # Up arrow
          {:ok, ?A} ->
            read_loop(history_prev(state))

          # Down arrow
          {:ok, ?B} ->
            read_loop(history_next(state))

          # Right arrow
          {:ok, ?C} ->
            read_loop(move_right(state))

          # Left arrow
          {:ok, ?D} ->
            read_loop(move_left(state))

          {:ok, ?3} ->
            # Delete key sequence
            case read_key() do
              {:ok, ?~} -> read_loop(delete_char_at_cursor(state))
              _ -> read_loop(state)
            end

          _ ->
            read_loop(state)
        end

      # Alt-b
      {:ok, ?b} ->
        read_loop(move_word_backward(state))

      # Alt-f
      {:ok, ?f} ->
        read_loop(move_word_forward(state))

      # Alt-d
      {:ok, ?d} ->
        read_loop(delete_word_forward(state))

      _ ->
        read_loop(state)
    end
  end

  defp read_key() do
    case IO.getn("", 1) do
      :eof -> {:error, :eof}
      {:error, reason} -> {:error, reason}
      data when is_binary(data) -> {:ok, :binary.first(data)}
    end
  end

  defp insert_char(state, char) do
    {before, after_} = String.split_at(state.buffer, state.cursor)
    new_buffer = before <> <<char>> <> after_
    new_state = %{state | buffer: new_buffer, cursor: state.cursor + 1}
    redraw_line(new_state)
    new_state
  end

  defp backspace(state) do
    if state.cursor > 0 do
      {before, after_} = String.split_at(state.buffer, state.cursor)
      new_buffer = String.slice(before, 0..-2//1) <> after_
      new_state = %{state | buffer: new_buffer, cursor: state.cursor - 1}
      redraw_line(new_state)
      new_state
    else
      state
    end
  end

  defp delete_char_at_cursor(state) do
    if state.cursor < String.length(state.buffer) do
      {before, after_} = String.split_at(state.buffer, state.cursor)
      new_buffer = before <> String.slice(after_, 1..-1//1)
      new_state = %{state | buffer: new_buffer}
      redraw_line(new_state)
      new_state
    else
      state
    end
  end

  defp move_left(state) do
    if state.cursor > 0 do
      new_state = %{state | cursor: state.cursor - 1}
      IO.write(@cursor_left)
      new_state
    else
      state
    end
  end

  defp move_right(state) do
    if state.cursor < String.length(state.buffer) do
      new_state = %{state | cursor: state.cursor + 1}
      IO.write(@cursor_right)
      new_state
    else
      state
    end
  end

  defp move_to_start(state) do
    if state.cursor > 0 do
      IO.write("\e[#{state.cursor}D")
      %{state | cursor: 0}
    else
      state
    end
  end

  defp move_to_end(state) do
    len = String.length(state.buffer)

    if state.cursor < len do
      IO.write("\e[#{len - state.cursor}C")
      %{state | cursor: len}
    else
      state
    end
  end

  defp move_word_backward(state) do
    new_cursor = find_word_boundary_backward(state.buffer, state.cursor)

    if new_cursor < state.cursor do
      IO.write("\e[#{state.cursor - new_cursor}D")
      %{state | cursor: new_cursor}
    else
      state
    end
  end

  defp move_word_forward(state) do
    new_cursor = find_word_boundary_forward(state.buffer, state.cursor)

    if new_cursor > state.cursor do
      IO.write("\e[#{new_cursor - state.cursor}C")
      %{state | cursor: new_cursor}
    else
      state
    end
  end

  defp find_word_boundary_backward(buffer, pos) do
    chars = String.graphemes(buffer)
    before = Enum.take(chars, pos)

    # Skip non-word chars, then skip word chars
    before
    |> Enum.reverse()
    |> Enum.drop_while(&(!word_char?(&1)))
    |> Enum.drop_while(&word_char?/1)
    |> length()
  end

  defp find_word_boundary_forward(buffer, pos) do
    chars = String.graphemes(buffer)
    after_ = Enum.drop(chars, pos)

    # Skip non-word chars, then skip word chars
    skipped =
      after_
      |> Enum.drop_while(&(!word_char?(&1)))
      |> Enum.drop_while(&word_char?/1)
      |> length()

    pos + (length(after_) - skipped)
  end

  defp word_char?(char) do
    char =~ ~r/[a-zA-Z0-9_]/
  end

  defp kill_to_end(state) do
    new_buffer = String.slice(state.buffer, 0, state.cursor)
    new_state = %{state | buffer: new_buffer}
    IO.write("\r\e[2K")
    IO.write(state.prompt <> new_buffer)
    new_state
  end

  defp kill_to_start(state) do
    new_buffer = String.slice(state.buffer, state.cursor..-1)
    new_state = %{state | buffer: new_buffer, cursor: 0}
    redraw_line(new_state)
    new_state
  end

  defp kill_word(state) do
    word_start = find_word_boundary_backward(state.buffer, state.cursor)
    {before, rest} = String.split_at(state.buffer, word_start)
    after_ = String.slice(rest, (state.cursor - word_start)..-1)
    new_buffer = before <> after_
    new_state = %{state | buffer: new_buffer, cursor: word_start}
    redraw_line(new_state)
    new_state
  end

  defp delete_word_forward(state) do
    word_end = find_word_boundary_forward(state.buffer, state.cursor)
    {before, rest} = String.split_at(state.buffer, state.cursor)
    after_ = String.slice(rest, (word_end - state.cursor)..-1)
    new_buffer = before <> after_
    new_state = %{state | buffer: new_buffer}
    redraw_line(new_state)
    new_state
  end

  defp history_prev(state) do
    if state.history_index > 0 do
      # Save current line if moving from the end
      saved_line =
        if state.history_index == length(state.history) do
          state.buffer
        else
          state.saved_line
        end

      new_index = state.history_index - 1
      new_buffer = Enum.at(state.history, new_index)

      new_state = %{
        state
        | buffer: new_buffer,
          cursor: String.length(new_buffer),
          history_index: new_index,
          saved_line: saved_line
      }

      redraw_line(new_state)
      new_state
    else
      state
    end
  end

  defp history_next(state) do
    if state.history_index < length(state.history) do
      new_index = state.history_index + 1

      new_buffer =
        if new_index == length(state.history) do
          state.saved_line || ""
        else
          Enum.at(state.history, new_index)
        end

      new_state = %{state | buffer: new_buffer, cursor: String.length(new_buffer), history_index: new_index}
      redraw_line(new_state)
      new_state
    else
      state
    end
  end

  defp handle_tab(state) do
    if state.completion_fn && String.starts_with?(state.buffer, "/") do
      # Extract the partial command
      partial = String.slice(state.buffer, 1..-1//1) |> String.split(" ") |> hd()

      case state.completion_fn.(partial) do
        [] ->
          # No completions, just beep
          IO.write("\a")
          state

        [single] ->
          # Single completion, complete it
          new_buffer = "/" <> single <> " "
          new_state = %{state | buffer: new_buffer, cursor: String.length(new_buffer)}
          redraw_line(new_state)
          new_state

        multiple ->
          # Multiple completions, show them
          IO.write("\n")
          Enum.each(multiple, &IO.write("  /#{&1}\n"))
          IO.write(state.prompt)
          redraw_line(state)
          state
      end
    else
      # Not a command, insert tab
      insert_char(state, ?\t)
    end
  end

  defp redraw_line(state) do
    # Move to beginning of line and clear entire line
    IO.write("\r\e[2K")
    IO.write(state.prompt <> state.buffer)
    # Move cursor to correct position
    if state.cursor < String.length(state.buffer) do
      IO.write("\e[#{String.length(state.buffer) - state.cursor}D")
    end
  end

  defp clear_screen() do
    IO.write("\e[2J\e[H")
  end

  defp add_line_to_history(line, history) do
    # Don't add duplicates of the last entry
    if history == [] or hd(history) != line do
      [line | history]
      |> Enum.take(@max_history_size)
    else
      history
    end
  end

  defp load_history() do
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
