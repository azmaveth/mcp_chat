defmodule MCPChat.Terminal.InputBuffer do
  @moduledoc """
  Advanced input buffer management for multi-line editing.

  Handles complex text manipulation, cursor management, and
  provides undo/redo functionality for the terminal input.
  """

  use GenServer
  require Logger

  alias MCPChat.Terminal.SyntaxHighlighter

  @undo_history_limit 100
  @clipboard_history_limit 20

  # Input buffer state
  defstruct [
    # List of input lines
    :lines,
    # {line, column} position
    :cursor,
    # Selection range if any
    :selection,
    # Undo stack
    :undo_history,
    # Redo stack
    :redo_history,
    # Clipboard content
    :clipboard,
    # Clipboard history
    :clipboard_history,
    # Named marks for positions
    :marks,
    # Buffer settings
    :settings
  ]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Insert text at current cursor position.
  """
  def insert_text(pid \\ __MODULE__, text) do
    GenServer.call(pid, {:insert_text, text})
  end

  @doc """
  Delete text in specified direction and amount.
  """
  def delete_text(pid \\ __MODULE__, direction, amount \\ 1) do
    GenServer.call(pid, {:delete_text, direction, amount})
  end

  @doc """
  Move cursor to new position.
  """
  def move_cursor(pid \\ __MODULE__, movement) do
    GenServer.call(pid, {:move_cursor, movement})
  end

  @doc """
  Get current buffer content as a single string.
  """
  def get_content(pid \\ __MODULE__) do
    GenServer.call(pid, :get_content)
  end

  @doc """
  Get current buffer state including cursor position.
  """
  def get_state(pid \\ __MODULE__) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Clear the buffer.
  """
  def clear(pid \\ __MODULE__) do
    GenServer.call(pid, :clear)
  end

  @doc """
  Undo last operation.
  """
  def undo(pid \\ __MODULE__) do
    GenServer.call(pid, :undo)
  end

  @doc """
  Redo previously undone operation.
  """
  def redo(pid \\ __MODULE__) do
    GenServer.call(pid, :redo)
  end

  @doc """
  Copy selected text or current line to clipboard.
  """
  def copy(pid \\ __MODULE__) do
    GenServer.call(pid, :copy)
  end

  @doc """
  Cut selected text or current line to clipboard.
  """
  def cut(pid \\ __MODULE__) do
    GenServer.call(pid, :cut)
  end

  @doc """
  Paste from clipboard at cursor position.
  """
  def paste(pid \\ __MODULE__) do
    GenServer.call(pid, :paste)
  end

  @doc """
  Set selection range.
  """
  def set_selection(pid \\ __MODULE__, start_pos, end_pos) do
    GenServer.call(pid, {:set_selection, start_pos, end_pos})
  end

  @doc """
  Clear current selection.
  """
  def clear_selection(pid \\ __MODULE__) do
    GenServer.call(pid, :clear_selection)
  end

  @doc """
  Set a named mark at current position.
  """
  def set_mark(pid \\ __MODULE__, name) do
    GenServer.call(pid, {:set_mark, name})
  end

  @doc """
  Jump to a named mark.
  """
  def goto_mark(pid \\ __MODULE__, name) do
    GenServer.call(pid, {:goto_mark, name})
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    Logger.info("Starting Input Buffer")

    settings = %{
      syntax_highlighting: Keyword.get(opts, :syntax_highlighting, true),
      auto_indent: Keyword.get(opts, :auto_indent, true),
      smart_pairs: Keyword.get(opts, :smart_pairs, true),
      tab_width: Keyword.get(opts, :tab_width, 2),
      max_line_length: Keyword.get(opts, :max_line_length, 1000)
    }

    state = %__MODULE__{
      lines: [""],
      cursor: {0, 0},
      selection: nil,
      undo_history: [],
      redo_history: [],
      clipboard: "",
      clipboard_history: [],
      marks: %{},
      settings: settings
    }

    Logger.info("Input Buffer initialized", settings: settings)
    {:ok, state}
  end

  @impl true
  def handle_call({:insert_text, text}, _from, state) do
    # Save state for undo
    new_state = save_undo_state(state)

    # Clear selection if any
    cleared_state =
      if new_state.selection do
        delete_selection(new_state)
      else
        new_state
      end

    # Insert text at cursor
    final_state = insert_at_cursor(cleared_state, text)

    {:reply, :ok, final_state}
  end

  @impl true
  def handle_call({:delete_text, direction, amount}, _from, state) do
    new_state = save_undo_state(state)

    final_state =
      case direction do
        :backward -> delete_backward(new_state, amount)
        :forward -> delete_forward(new_state, amount)
        :word_backward -> delete_word_backward(new_state)
        :word_forward -> delete_word_forward(new_state)
        :line -> delete_line(new_state)
        :to_line_end -> delete_to_line_end(new_state)
        :to_line_start -> delete_to_line_start(new_state)
      end

    {:reply, :ok, final_state}
  end

  @impl true
  def handle_call({:move_cursor, movement}, _from, state) do
    new_cursor = calculate_new_cursor_position(state, movement)
    new_state = %{state | cursor: new_cursor}

    # Clear selection unless extending
    final_state =
      unless movement == :extend_selection do
        %{new_state | selection: nil}
      else
        new_state
      end

    {:reply, :ok, final_state}
  end

  @impl true
  def handle_call(:get_content, _from, state) do
    content = Enum.join(state.lines, "\n")
    {:reply, content, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    buffer_info = %{
      lines: state.lines,
      cursor: state.cursor,
      selection: state.selection,
      content: Enum.join(state.lines, "\n"),
      line_count: length(state.lines),
      current_line: get_current_line(state),
      cursor_position: cursor_to_linear_position(state)
    }

    {:reply, buffer_info, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    new_state = save_undo_state(state)
    cleared_state = %{new_state | lines: [""], cursor: {0, 0}, selection: nil}
    {:reply, :ok, cleared_state}
  end

  @impl true
  def handle_call(:undo, _from, state) do
    case state.undo_history do
      [] ->
        {:reply, {:error, :nothing_to_undo}, state}

      [previous_state | rest_history] ->
        # Save current state to redo history
        redo_state = extract_buffer_state(state)

        new_redo_history =
          [redo_state | state.redo_history]
          |> Enum.take(@undo_history_limit)

        # Restore previous state
        restored_state =
          restore_buffer_state(state, previous_state)
          |> Map.put(:undo_history, rest_history)
          |> Map.put(:redo_history, new_redo_history)

        {:reply, :ok, restored_state}
    end
  end

  @impl true
  def handle_call(:redo, _from, state) do
    case state.redo_history do
      [] ->
        {:reply, {:error, :nothing_to_redo}, state}

      [next_state | rest_history] ->
        # Save current state to undo history
        undo_state = extract_buffer_state(state)

        new_undo_history =
          [undo_state | state.undo_history]
          |> Enum.take(@undo_history_limit)

        # Restore next state
        restored_state =
          restore_buffer_state(state, next_state)
          |> Map.put(:redo_history, rest_history)
          |> Map.put(:undo_history, new_undo_history)

        {:reply, :ok, restored_state}
    end
  end

  @impl true
  def handle_call(:copy, _from, state) do
    text = get_selected_or_current_line(state)
    new_state = add_to_clipboard(state, text)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:cut, _from, state) do
    new_state = save_undo_state(state)

    text = get_selected_or_current_line(new_state)
    clipboard_state = add_to_clipboard(new_state, text)

    final_state =
      if clipboard_state.selection do
        delete_selection(clipboard_state)
      else
        delete_line(clipboard_state)
      end

    {:reply, :ok, final_state}
  end

  @impl true
  def handle_call(:paste, _from, state) do
    new_state = save_undo_state(state)

    # Delete selection if any
    cleared_state =
      if new_state.selection do
        delete_selection(new_state)
      else
        new_state
      end

    # Insert clipboard content
    final_state = insert_at_cursor(cleared_state, new_state.clipboard)

    {:reply, :ok, final_state}
  end

  @impl true
  def handle_call({:set_selection, start_pos, end_pos}, _from, state) do
    new_state = %{state | selection: {start_pos, end_pos}}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:clear_selection, _from, state) do
    new_state = %{state | selection: nil}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:set_mark, name}, _from, state) do
    new_marks = Map.put(state.marks, name, state.cursor)
    new_state = %{state | marks: new_marks}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:goto_mark, name}, _from, state) do
    case Map.get(state.marks, name) do
      nil ->
        {:reply, {:error, :mark_not_found}, state}

      position ->
        new_state = %{state | cursor: position}
        {:reply, :ok, new_state}
    end
  end

  # Private functions

  defp insert_at_cursor(state, text) do
    {line_idx, col} = state.cursor
    lines = state.lines

    # Handle multi-line text
    text_lines = String.split(text, "\n", parts: :infinity)

    case text_lines do
      [single_line] ->
        # Single line insertion
        updated_line = insert_in_line(Enum.at(lines, line_idx), col, single_line)
        new_lines = List.replace_at(lines, line_idx, updated_line)
        new_cursor = {line_idx, col + String.length(single_line)}

        %{state | lines: new_lines, cursor: new_cursor}

      [first | rest] ->
        # Multi-line insertion
        current_line = Enum.at(lines, line_idx)
        {before, after_text} = String.split_at(current_line, col)

        # First line gets prefix + first text line
        first_updated = before <> first

        # Last line gets last text line + suffix
        {middle_lines, [last_text]} = Enum.split(rest, -1)
        last_updated = last_text <> after_text

        # Build new lines array
        {before_lines, [_current | after_lines]} = Enum.split(lines, line_idx)

        new_lines =
          before_lines ++
            [first_updated] ++
            middle_lines ++
            [last_updated] ++
            after_lines

        # Update cursor to end of inserted text
        new_line_idx = line_idx + length(text_lines) - 1
        new_col = String.length(last_text)

        %{state | lines: new_lines, cursor: {new_line_idx, new_col}}
    end
  end

  defp insert_in_line(line, position, text) do
    {before, after_text} = String.split_at(line, position)
    before <> text <> after_text
  end

  defp delete_backward(state, amount) do
    {line_idx, col} = state.cursor

    cond do
      col >= amount ->
        # Delete within current line
        line = Enum.at(state.lines, line_idx)
        new_line = delete_from_line(line, col - amount, amount)
        new_lines = List.replace_at(state.lines, line_idx, new_line)
        new_cursor = {line_idx, col - amount}

        %{state | lines: new_lines, cursor: new_cursor}

      line_idx > 0 ->
        # Delete across lines
        prev_line = Enum.at(state.lines, line_idx - 1)
        current_line = Enum.at(state.lines, line_idx)

        merged_line = prev_line <> String.slice(current_line, col..-1)

        {before_lines, [_prev, _current | after_lines]} = Enum.split(state.lines, line_idx - 1)
        new_lines = before_lines ++ [merged_line] ++ after_lines
        new_cursor = {line_idx - 1, String.length(prev_line)}

        %{state | lines: new_lines, cursor: new_cursor}

      true ->
        # At beginning of buffer
        state
    end
  end

  defp delete_forward(state, amount) do
    {line_idx, col} = state.cursor
    line = Enum.at(state.lines, line_idx)

    cond do
      col + amount <= String.length(line) ->
        # Delete within current line
        new_line = delete_from_line(line, col, amount)
        new_lines = List.replace_at(state.lines, line_idx, new_line)

        %{state | lines: new_lines}

      line_idx < length(state.lines) - 1 ->
        # Delete across lines
        next_line = Enum.at(state.lines, line_idx + 1)
        merged_line = String.slice(line, 0, col) <> next_line

        {before_lines, [_current, _next | after_lines]} = Enum.split(state.lines, line_idx)
        new_lines = before_lines ++ [merged_line] ++ after_lines

        %{state | lines: new_lines}

      true ->
        # At end of buffer
        state
    end
  end

  defp delete_from_line(line, position, amount) do
    {before, after_text} = String.split_at(line, position)
    before <> String.slice(after_text, amount..-1)
  end

  defp delete_word_backward(state) do
    {line_idx, col} = state.cursor
    line = Enum.at(state.lines, line_idx)

    # Find word boundary
    word_start = find_word_start(line, col)
    amount = col - word_start

    if amount > 0 do
      delete_backward(state, amount)
    else
      # Delete at least one character
      delete_backward(state, 1)
    end
  end

  defp delete_word_forward(state) do
    {line_idx, col} = state.cursor
    line = Enum.at(state.lines, line_idx)

    # Find word boundary
    word_end = find_word_end(line, col)
    amount = word_end - col

    if amount > 0 do
      delete_forward(state, amount)
    else
      # Delete at least one character
      delete_forward(state, 1)
    end
  end

  defp delete_line(state) do
    {line_idx, _col} = state.cursor

    if length(state.lines) > 1 do
      new_lines = List.delete_at(state.lines, line_idx)
      new_line_idx = min(line_idx, length(new_lines) - 1)
      new_cursor = {new_line_idx, 0}

      %{state | lines: new_lines, cursor: new_cursor}
    else
      # Last line - just clear it
      %{state | lines: [""], cursor: {0, 0}}
    end
  end

  defp delete_to_line_end(state) do
    {line_idx, col} = state.cursor
    line = Enum.at(state.lines, line_idx)

    new_line = String.slice(line, 0, col)
    new_lines = List.replace_at(state.lines, line_idx, new_line)

    %{state | lines: new_lines}
  end

  defp delete_to_line_start(state) do
    {line_idx, col} = state.cursor
    line = Enum.at(state.lines, line_idx)

    new_line = String.slice(line, col..-1)
    new_lines = List.replace_at(state.lines, line_idx, new_line)
    new_cursor = {line_idx, 0}

    %{state | lines: new_lines, cursor: new_cursor}
  end

  defp delete_selection(state) do
    case state.selection do
      nil ->
        state

      {{start_line, start_col}, {end_line, end_col}} ->
        # Ensure start is before end
        {start, end_pos} =
          if {start_line, start_col} <= {end_line, end_col} do
            {{start_line, start_col}, {end_line, end_col}}
          else
            {{end_line, end_col}, {start_line, start_col}}
          end

        # Delete the selection
        delete_range(state, start, end_pos)
        |> Map.put(:selection, nil)
    end
  end

  defp delete_range(state, {start_line, start_col}, {end_line, end_col}) do
    cond do
      start_line == end_line ->
        # Single line deletion
        line = Enum.at(state.lines, start_line)
        new_line = String.slice(line, 0, start_col) <> String.slice(line, end_col..-1)
        new_lines = List.replace_at(state.lines, start_line, new_line)

        %{state | lines: new_lines, cursor: {start_line, start_col}}

      true ->
        # Multi-line deletion
        start_line_text = Enum.at(state.lines, start_line)
        end_line_text = Enum.at(state.lines, end_line)

        merged_line =
          String.slice(start_line_text, 0, start_col) <>
            String.slice(end_line_text, end_col..-1)

        # Remove lines between start and end
        {before_lines, rest} = Enum.split(state.lines, start_line)
        {_to_delete, after_lines} = Enum.split(rest, end_line - start_line + 1)

        new_lines = before_lines ++ [merged_line] ++ after_lines

        %{state | lines: new_lines, cursor: {start_line, start_col}}
    end
  end

  defp calculate_new_cursor_position(state, movement) do
    {line_idx, col} = state.cursor
    lines = state.lines

    case movement do
      :left ->
        if col > 0 do
          {line_idx, col - 1}
        else
          if line_idx > 0 do
            prev_line = Enum.at(lines, line_idx - 1)
            {line_idx - 1, String.length(prev_line)}
          else
            {0, 0}
          end
        end

      :right ->
        current_line = Enum.at(lines, line_idx)

        if col < String.length(current_line) do
          {line_idx, col + 1}
        else
          if line_idx < length(lines) - 1 do
            {line_idx + 1, 0}
          else
            {line_idx, col}
          end
        end

      :up ->
        if line_idx > 0 do
          prev_line = Enum.at(lines, line_idx - 1)
          new_col = min(col, String.length(prev_line))
          {line_idx - 1, new_col}
        else
          {0, 0}
        end

      :down ->
        if line_idx < length(lines) - 1 do
          next_line = Enum.at(lines, line_idx + 1)
          new_col = min(col, String.length(next_line))
          {line_idx + 1, new_col}
        else
          {line_idx, String.length(Enum.at(lines, line_idx))}
        end

      :line_start ->
        {line_idx, 0}

      :line_end ->
        line = Enum.at(lines, line_idx)
        {line_idx, String.length(line)}

      :word_forward ->
        line = Enum.at(lines, line_idx)
        new_col = find_word_end(line, col)

        if new_col == col and line_idx < length(lines) - 1 do
          {line_idx + 1, 0}
        else
          {line_idx, new_col}
        end

      :word_backward ->
        line = Enum.at(lines, line_idx)
        new_col = find_word_start(line, col)

        if new_col == col and line_idx > 0 do
          prev_line = Enum.at(lines, line_idx - 1)
          {line_idx - 1, String.length(prev_line)}
        else
          {line_idx, new_col}
        end

      :buffer_start ->
        {0, 0}

      :buffer_end ->
        last_idx = length(lines) - 1
        last_line = Enum.at(lines, last_idx)
        {last_idx, String.length(last_line)}

      _ ->
        {line_idx, col}
    end
  end

  defp find_word_start(line, position) do
    before = String.slice(line, 0, position)

    # Find last word boundary
    case Regex.run(~r/\b\w+$/, before) do
      [match] -> position - String.length(match)
      _ -> max(0, position - 1)
    end
  end

  defp find_word_end(line, position) do
    after_text = String.slice(line, position..-1)

    # Find next word boundary
    case Regex.run(~r/^\w+/, after_text) do
      [match] -> position + String.length(match)
      _ -> min(String.length(line), position + 1)
    end
  end

  defp get_selected_or_current_line(state) do
    case state.selection do
      nil ->
        # Get current line
        {line_idx, _col} = state.cursor
        Enum.at(state.lines, line_idx)

      {{start_line, start_col}, {end_line, end_col}} ->
        # Get selected text
        extract_text_range(state.lines, {start_line, start_col}, {end_line, end_col})
    end
  end

  defp extract_text_range(lines, {start_line, start_col}, {end_line, end_col}) do
    cond do
      start_line == end_line ->
        # Single line selection
        line = Enum.at(lines, start_line)
        String.slice(line, start_col, end_col - start_col)

      true ->
        # Multi-line selection
        first_line = Enum.at(lines, start_line) |> String.slice(start_col..-1)

        middle_lines =
          if end_line - start_line > 1 do
            lines
            |> Enum.slice((start_line + 1)..(end_line - 1))
          else
            []
          end

        last_line = Enum.at(lines, end_line) |> String.slice(0, end_col)

        ([first_line] ++ middle_lines ++ [last_line])
        |> Enum.join("\n")
    end
  end

  defp add_to_clipboard(state, text) do
    new_history =
      [text | state.clipboard_history]
      |> Enum.take(@clipboard_history_limit)

    %{state | clipboard: text, clipboard_history: new_history}
  end

  defp save_undo_state(state) do
    buffer_state = extract_buffer_state(state)

    new_history =
      [buffer_state | state.undo_history]
      |> Enum.take(@undo_history_limit)

    %{
      state
      | undo_history: new_history,
        # Clear redo on new action
        redo_history: []
    }
  end

  defp extract_buffer_state(state) do
    %{
      lines: state.lines,
      cursor: state.cursor,
      selection: state.selection
    }
  end

  defp restore_buffer_state(state, buffer_state) do
    %{state | lines: buffer_state.lines, cursor: buffer_state.cursor, selection: buffer_state.selection}
  end

  defp get_current_line(state) do
    {line_idx, _col} = state.cursor
    Enum.at(state.lines, line_idx, "")
  end

  defp cursor_to_linear_position(state) do
    {line_idx, col} = state.cursor

    # Calculate total characters before current line
    chars_before =
      state.lines
      |> Enum.take(line_idx)
      |> Enum.map(&String.length/1)
      |> Enum.sum()

    # Add newlines
    chars_before + line_idx + col
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.info("Input Buffer shutting down")
    :ok
  end
end
