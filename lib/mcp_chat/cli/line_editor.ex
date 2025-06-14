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
    # Ensure we flush any pending output first
    IO.write("")
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
      {:ok, key} -> handle_key_input(state, key)
      _ -> read_loop(state)
    end
  end

  defp read_escape_sequence(state) do
    case read_key() do
      {:ok, ?[} -> handle_bracket_sequence(state)
      {:ok, key} when key in [?b, ?f, ?d] -> handle_alt_key(state, key)
      _ -> read_loop(state)
    end
  end

  # Input handling helpers

  defp handle_enter(state) do
    IO.write("\n")
    {:ok, state.buffer}
  end

  defp handle_ctrl_c() do
    IO.write("^C\n")
    {:error, :interrupted}
  end

  defp handle_ctrl_d(state) do
    if state.buffer == "" do
      IO.write("\n")
      {:error, :interrupted}
    else
      read_loop(delete_char_at_cursor(state))
    end
  end

  defp handle_ctrl_l(state) do
    clear_screen()
    redraw_line(state)
    read_loop(state)
  end

  defp handle_key_input(state, key) do
    # Try direct key handlers first
    case handle_single_key(state, key) do
      {:handled, result} -> result
      :not_handled -> handle_key_category(state, key)
    end
  end

  defp handle_single_key(state, key) do
    case key do
      @enter -> {:handled, handle_enter(state)}
      @ctrl_c -> {:handled, handle_ctrl_c()}
      @ctrl_d -> {:handled, handle_ctrl_d(state)}
      @backspace -> {:handled, continue_with(backspace(state))}
      @escape -> {:handled, read_escape_sequence(state)}
      @ctrl_l -> {:handled, handle_ctrl_l(state)}
      @tab -> {:handled, continue_with(handle_tab(state))}
      _ -> :not_handled
    end
  end

  defp handle_key_category(state, key) do
    cond do
      is_movement_key?(key) ->
        continue_with(handle_movement_key(state, key))

      is_kill_key?(key) ->
        continue_with(handle_kill_key(state, key))

      is_history_key?(key) ->
        continue_with(handle_history_key(state, key))

      is_printable_char?(key) ->
        continue_with(insert_char(state, key))

      true ->
        read_loop(state)
    end
  end

  defp is_movement_key?(key), do: key in [@ctrl_a, @ctrl_e, @ctrl_b, @ctrl_f]
  defp is_kill_key?(key), do: key in [@ctrl_k, @ctrl_u, @ctrl_w]
  defp is_history_key?(key), do: key in [@ctrl_p, @ctrl_n]
  defp is_printable_char?(char), do: char >= 32 and char <= 126

  defp continue_with(new_state) do
    read_loop(new_state)
  end

  defp handle_movement_key(state, key) do
    case key do
      @ctrl_a -> move_to_start(state)
      @ctrl_e -> move_to_end(state)
      @ctrl_b -> move_left(state)
      @ctrl_f -> move_right(state)
    end
  end

  defp handle_kill_key(state, key) do
    case key do
      @ctrl_k -> kill_to_end(state)
      @ctrl_u -> kill_to_start(state)
      @ctrl_w -> kill_word(state)
    end
  end

  defp handle_history_key(state, key) do
    case key do
      @ctrl_p -> history_prev(state)
      @ctrl_n -> history_next(state)
    end
  end

  defp handle_bracket_sequence(state) do
    case read_key() do
      # Up arrow
      {:ok, ?A} -> continue_with(history_prev(state))
      # Down arrow
      {:ok, ?B} -> continue_with(history_next(state))
      # Right arrow
      {:ok, ?C} -> continue_with(move_right(state))
      # Left arrow
      {:ok, ?D} -> continue_with(move_left(state))
      # Delete key
      {:ok, ?3} -> handle_delete_sequence(state)
      _ -> read_loop(state)
    end
  end

  defp handle_delete_sequence(state) do
    case read_key() do
      {:ok, ?~} -> continue_with(delete_char_at_cursor(state))
      _ -> read_loop(state)
    end
  end

  defp handle_alt_key(state, key) do
    case key do
      # Alt-b
      ?b -> continue_with(move_word_backward(state))
      # Alt-f
      ?f -> continue_with(move_word_forward(state))
      # Alt-d
      ?d -> continue_with(delete_word_forward(state))
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
