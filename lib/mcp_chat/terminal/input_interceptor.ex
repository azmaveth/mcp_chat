defmodule MCPChat.Terminal.InputInterceptor do
  @moduledoc """
  Advanced input interception system for terminal enhancements.

  Provides sophisticated input handling including autocomplete integration,
  multi-line editing, history navigation, and enhanced keyboard support.
  """

  use GenServer
  require Logger

  alias MCPChat.Autocomplete.AutocompleteEngine
  alias MCPChat.Terminal.{DisplayOverlay, KeyboardHandler}

  @tab_key 9
  @enter_key 13
  @escape_key 27
  @backspace_key 127
  @delete_key "\e[3~"
  @up_arrow "\e[A"
  @down_arrow "\e[B"
  @right_arrow "\e[C"
  @left_arrow "\e[D"
  @ctrl_c 3
  @ctrl_d 4
  @ctrl_l 12
  @ctrl_r 18
  @ctrl_u 21
  @ctrl_w 23

  # Input interceptor state
  defstruct [
    # Current input buffer
    :input_buffer,
    # Cursor position in buffer
    :cursor_position,
    # Command history
    :history,
    # Current position in history
    :history_position,
    # Autocomplete suggestions state
    :autocomplete_state,
    # Display overlay for suggestions
    :display_overlay,
    # Keyboard input handler
    :keyboard_handler,
    # Current session ID
    :session_id,
    # Input handling settings
    :settings,
    # Multi-line editing mode
    :multi_line_mode,
    # Current prompt state
    :prompt_state
  ]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start input interception for a session.
  """
  def start_session(pid \\ __MODULE__, session_id, opts \\ []) do
    GenServer.call(pid, {:start_session, session_id, opts})
  end

  @doc """
  Stop input interception for a session.
  """
  def stop_session(pid \\ __MODULE__, session_id) do
    GenServer.call(pid, {:stop_session, session_id})
  end

  @doc """
  Process a single input character or sequence.
  """
  def process_input(pid \\ __MODULE__, input_data) do
    GenServer.call(pid, {:process_input, input_data})
  end

  @doc """
  Get current input buffer state.
  """
  def get_buffer_state(pid \\ __MODULE__) do
    GenServer.call(pid, :get_buffer_state)
  end

  @doc """
  Force refresh of autocomplete suggestions.
  """
  def refresh_suggestions(pid \\ __MODULE__) do
    GenServer.call(pid, :refresh_suggestions)
  end

  @doc """
  Update input handling settings.
  """
  def update_settings(pid \\ __MODULE__, new_settings) do
    GenServer.call(pid, {:update_settings, new_settings})
  end

  @doc """
  Register a callback for input events.
  """
  def register_callback(pid \\ __MODULE__, callback_pid, event_type) do
    GenServer.call(pid, {:register_callback, callback_pid, event_type})
  end

  @doc """
  Apply a completion suggestion.
  """
  def apply_completion(pid \\ __MODULE__, completion_text, suggestion_data) do
    GenServer.call(pid, {:apply_completion, completion_text, suggestion_data})
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    Logger.info("Starting Input Interceptor")

    settings = %{
      autocomplete_enabled: Keyword.get(opts, :autocomplete_enabled, true),
      history_enabled: Keyword.get(opts, :history_enabled, true),
      multi_line_enabled: Keyword.get(opts, :multi_line_enabled, true),
      suggestion_delay: Keyword.get(opts, :suggestion_delay, 150),
      max_suggestions: Keyword.get(opts, :max_suggestions, 10),
      enable_syntax_highlighting: Keyword.get(opts, :enable_syntax_highlighting, true),
      vim_mode: Keyword.get(opts, :vim_mode, false),
      emacs_mode: Keyword.get(opts, :emacs_mode, true)
    }

    state = %__MODULE__{
      input_buffer: "",
      cursor_position: 0,
      history: [],
      history_position: -1,
      autocomplete_state: %{},
      session_id: nil,
      settings: settings,
      multi_line_mode: false,
      prompt_state: %{prompt: "> ", continuation: "... "}
    }

    # Initialize supporting components
    case initialize_components(state, opts) do
      {:ok, initialized_state} ->
        Logger.info("Input Interceptor initialized", settings: settings)
        {:ok, initialized_state}

      {:error, reason} ->
        Logger.error("Failed to initialize Input Interceptor", reason: inspect(reason))
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:start_session, session_id, opts}, _from, state) do
    new_state = %{
      state
      | session_id: session_id,
        input_buffer: "",
        cursor_position: 0,
        history_position: -1,
        autocomplete_state: %{}
    }

    # Load session-specific history if available
    updated_state = load_session_history(new_state, session_id)

    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call({:stop_session, session_id}, _from, state) do
    if state.session_id == session_id do
      # Save session history
      save_session_history(state)

      new_state = %{state | session_id: nil, input_buffer: "", cursor_position: 0, autocomplete_state: %{}}
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :session_not_active}, state}
    end
  end

  @impl true
  def handle_call({:process_input, input_data}, _from, state) do
    case process_input_sequence(input_data, state) do
      {:continue, new_state} ->
        {:reply, {:continue, get_display_info(new_state)}, new_state}

      {:complete, command, new_state} ->
        # Add to history and reset buffer
        final_state =
          add_to_history(command, new_state)
          |> reset_input_buffer()

        {:reply, {:complete, command}, final_state}

      {:cancel, new_state} ->
        reset_state = reset_input_buffer(new_state)
        {:reply, {:cancel, get_display_info(reset_state)}, reset_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call(:get_buffer_state, _from, state) do
    buffer_info = %{
      input: state.input_buffer,
      cursor_position: state.cursor_position,
      multi_line_mode: state.multi_line_mode,
      suggestions: get_current_suggestions(state),
      prompt: get_current_prompt(state)
    }

    {:reply, buffer_info, state}
  end

  @impl true
  def handle_call(:refresh_suggestions, _from, state) do
    new_state = update_autocomplete_suggestions(state)
    {:reply, get_current_suggestions(new_state), new_state}
  end

  @impl true
  def handle_call({:update_settings, new_settings}, _from, state) do
    updated_settings = Map.merge(state.settings, new_settings)
    new_state = %{state | settings: updated_settings}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:register_callback, callback_pid, event_type}, _from, state) do
    # Store callbacks in state
    callbacks = Map.get(state, :callbacks, %{})
    type_callbacks = Map.get(callbacks, event_type, [])
    new_callbacks = Map.put(callbacks, event_type, [callback_pid | type_callbacks])

    new_state = Map.put(state, :callbacks, new_callbacks)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:apply_completion, completion_text, _suggestion_data}, _from, state) do
    # Replace current input with completion
    new_state = %{state | input_buffer: completion_text, cursor_position: String.length(completion_text)}

    # Notify callbacks
    notify_callbacks(:completion_applied, completion_text, new_state)

    {:reply, :ok, new_state}
  end

  # Private functions

  defp initialize_components(state, opts) do
    with {:ok, display_overlay} <- DisplayOverlay.start_link(opts),
         {:ok, keyboard_handler} <- KeyboardHandler.start_link(opts) do
      initialized_state = %{state | display_overlay: display_overlay, keyboard_handler: keyboard_handler}

      {:ok, initialized_state}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp process_input_sequence(input_data, state) when is_binary(input_data) do
    cond do
      # Handle special key sequences
      input_data == @up_arrow ->
        handle_history_navigation(:up, state)

      input_data == @down_arrow ->
        handle_history_navigation(:down, state)

      input_data == @left_arrow ->
        handle_cursor_movement(:left, state)

      input_data == @right_arrow ->
        handle_cursor_movement(:right, state)

      input_data == @delete_key ->
        handle_delete(:forward, state)

      # Handle control sequences
      String.starts_with?(input_data, "\e[") ->
        handle_escape_sequence(input_data, state)

      # Handle regular input
      true ->
        handle_regular_input(input_data, state)
    end
  end

  defp process_input_sequence(input_char, state) when is_integer(input_char) do
    case input_char do
      @tab_key ->
        handle_tab_completion(state)

      @enter_key ->
        handle_enter_key(state)

      @escape_key ->
        handle_escape_key(state)

      @backspace_key ->
        handle_delete(:backward, state)

      @ctrl_c ->
        handle_ctrl_c(state)

      @ctrl_d ->
        handle_ctrl_d(state)

      @ctrl_l ->
        handle_ctrl_l(state)

      @ctrl_r ->
        handle_ctrl_r(state)

      @ctrl_u ->
        handle_ctrl_u(state)

      @ctrl_w ->
        handle_ctrl_w(state)

      char when char >= 32 and char <= 126 ->
        handle_regular_input(<<char>>, state)

      _ ->
        # Ignore other control characters
        {:continue, state}
    end
  end

  defp handle_regular_input(text, state) do
    new_buffer = insert_at_cursor(state.input_buffer, state.cursor_position, text)
    new_cursor = state.cursor_position + String.length(text)

    new_state = %{state | input_buffer: new_buffer, cursor_position: new_cursor}

    # Update autocomplete suggestions if enabled
    updated_state =
      if state.settings.autocomplete_enabled do
        update_autocomplete_suggestions(new_state)
      else
        new_state
      end

    {:continue, updated_state}
  end

  defp handle_tab_completion(state) do
    if state.settings.autocomplete_enabled do
      case get_current_suggestions(state) do
        [] ->
          # No suggestions, just continue
          {:continue, state}

        [suggestion | _] ->
          # Apply first suggestion
          apply_suggestion(suggestion, state)

        suggestions when length(suggestions) > 1 ->
          # Multiple suggestions, cycle through them
          cycle_suggestions(suggestions, state)
      end
    else
      # Tab completion disabled, insert literal tab
      handle_regular_input("\t", state)
    end
  end

  defp handle_enter_key(state) do
    if state.multi_line_mode and should_continue_multi_line?(state.input_buffer) do
      # Continue multi-line input
      new_buffer = state.input_buffer <> "\n"
      new_cursor = String.length(new_buffer)

      new_state = %{state | input_buffer: new_buffer, cursor_position: new_cursor}

      {:continue, new_state}
    else
      # Complete the input
      command = String.trim(state.input_buffer)

      if command != "" do
        {:complete, command, state}
      else
        {:continue, reset_input_buffer(state)}
      end
    end
  end

  defp handle_escape_key(state) do
    # Clear current input and autocomplete
    new_state = %{state | input_buffer: "", cursor_position: 0, autocomplete_state: %{}}
    {:cancel, new_state}
  end

  defp handle_delete(direction, state) do
    case direction do
      :backward ->
        if state.cursor_position > 0 do
          new_buffer = delete_at_cursor(state.input_buffer, state.cursor_position - 1, 1)
          new_cursor = state.cursor_position - 1

          new_state = %{state | input_buffer: new_buffer, cursor_position: new_cursor}

          updated_state = update_autocomplete_suggestions(new_state)
          {:continue, updated_state}
        else
          {:continue, state}
        end

      :forward ->
        if state.cursor_position < String.length(state.input_buffer) do
          new_buffer = delete_at_cursor(state.input_buffer, state.cursor_position, 1)

          new_state = %{state | input_buffer: new_buffer}
          updated_state = update_autocomplete_suggestions(new_state)
          {:continue, updated_state}
        else
          {:continue, state}
        end
    end
  end

  defp handle_history_navigation(direction, state) do
    if state.settings.history_enabled and length(state.history) > 0 do
      case direction do
        :up ->
          new_position = min(state.history_position + 1, length(state.history) - 1)

          if new_position != state.history_position do
            command = Enum.at(state.history, new_position)

            new_state = %{
              state
              | input_buffer: command,
                cursor_position: String.length(command),
                history_position: new_position
            }

            {:continue, new_state}
          else
            {:continue, state}
          end

        :down ->
          new_position = max(state.history_position - 1, -1)

          if new_position != state.history_position do
            command =
              if new_position >= 0 do
                Enum.at(state.history, new_position)
              else
                ""
              end

            new_state = %{
              state
              | input_buffer: command,
                cursor_position: String.length(command),
                history_position: new_position
            }

            {:continue, new_state}
          else
            {:continue, state}
          end
      end
    else
      {:continue, state}
    end
  end

  defp handle_cursor_movement(direction, state) do
    case direction do
      :left ->
        new_cursor = max(state.cursor_position - 1, 0)
        new_state = %{state | cursor_position: new_cursor}
        {:continue, new_state}

      :right ->
        max_position = String.length(state.input_buffer)
        new_cursor = min(state.cursor_position + 1, max_position)
        new_state = %{state | cursor_position: new_cursor}
        {:continue, new_state}
    end
  end

  defp handle_escape_sequence(sequence, state) do
    # Handle complex escape sequences (e.g., function keys, modified arrows)
    case sequence do
      # Ctrl+Right
      "\e[1;5C" -> handle_word_movement(:right, state)
      # Ctrl+Left
      "\e[1;5D" -> handle_word_movement(:left, state)
      # Home
      "\e[H" -> handle_cursor_movement(:home, state)
      # End
      "\e[F" -> handle_cursor_movement(:end, state)
      # Ignore unknown sequences
      _ -> {:continue, state}
    end
  end

  defp handle_word_movement(direction, state) do
    case direction do
      :left ->
        new_cursor = find_word_boundary(state.input_buffer, state.cursor_position, :left)
        new_state = %{state | cursor_position: new_cursor}
        {:continue, new_state}

      :right ->
        new_cursor = find_word_boundary(state.input_buffer, state.cursor_position, :right)
        new_state = %{state | cursor_position: new_cursor}
        {:continue, new_state}
    end
  end

  defp handle_ctrl_c(_state) do
    # Interrupt signal - handled at higher level
    {:error, :interrupted, %__MODULE__{}}
  end

  defp handle_ctrl_d(state) do
    if state.input_buffer == "" do
      # EOF signal
      {:error, :eof, state}
    else
      # Delete character at cursor
      handle_delete(:forward, state)
    end
  end

  defp handle_ctrl_l(state) do
    # Clear screen - handled by display system
    {:continue, state}
  end

  defp handle_ctrl_r(state) do
    # Reverse history search
    if state.settings.history_enabled do
      start_history_search(state)
    else
      {:continue, state}
    end
  end

  defp handle_ctrl_u(state) do
    # Clear from cursor to beginning of line
    new_buffer = String.slice(state.input_buffer, state.cursor_position..-1)
    new_state = %{state | input_buffer: new_buffer, cursor_position: 0}
    {:continue, new_state}
  end

  defp handle_ctrl_w(state) do
    # Delete word backward
    word_start = find_word_boundary(state.input_buffer, state.cursor_position, :left)

    new_buffer =
      String.slice(state.input_buffer, 0, word_start) <>
        String.slice(state.input_buffer, state.cursor_position..-1)

    new_state = %{state | input_buffer: new_buffer, cursor_position: word_start}
    {:continue, new_state}
  end

  defp update_autocomplete_suggestions(state) do
    if state.settings.autocomplete_enabled and state.input_buffer != "" do
      context = build_input_context(state)

      case AutocompleteEngine.get_suggestions(state.input_buffer, context) do
        suggestions when is_list(suggestions) ->
          new_autocomplete_state = %{
            suggestions: suggestions,
            selected_index: 0,
            timestamp: System.monotonic_time(:millisecond)
          }

          %{state | autocomplete_state: new_autocomplete_state}

        _ ->
          %{state | autocomplete_state: %{}}
      end
    else
      %{state | autocomplete_state: %{}}
    end
  end

  defp build_input_context(state) do
    %{
      session_id: state.session_id,
      working_directory: File.cwd!(),
      cursor_position: state.cursor_position,
      multi_line_mode: state.multi_line_mode,
      history: Enum.take(state.history, 10)
    }
  end

  defp get_current_suggestions(state) do
    Map.get(state.autocomplete_state, :suggestions, [])
  end

  defp apply_suggestion(suggestion, state) do
    # Apply the suggestion to the current input
    # This is a simplified version - could be more sophisticated
    new_buffer = suggestion
    new_cursor = String.length(new_buffer)

    new_state = %{state | input_buffer: new_buffer, cursor_position: new_cursor, autocomplete_state: %{}}

    {:continue, new_state}
  end

  defp cycle_suggestions(suggestions, state) do
    current_index = Map.get(state.autocomplete_state, :selected_index, 0)
    new_index = rem(current_index + 1, length(suggestions))

    new_autocomplete_state = Map.put(state.autocomplete_state, :selected_index, new_index)
    new_state = %{state | autocomplete_state: new_autocomplete_state}

    {:continue, new_state}
  end

  defp should_continue_multi_line?(buffer) do
    # Simple heuristic for multi-line continuation
    trimmed = String.trim(buffer)

    String.ends_with?(trimmed, "\\") or
      String.ends_with?(trimmed, "{") or
      String.ends_with?(trimmed, "[") or
      String.ends_with?(trimmed, "(")
  end

  defp insert_at_cursor(buffer, position, text) do
    {before, after_text} = String.split_at(buffer, position)
    before <> text <> after_text
  end

  defp delete_at_cursor(buffer, position, count) do
    {before, after_text} = String.split_at(buffer, position)
    before <> String.slice(after_text, count..-1)
  end

  defp find_word_boundary(buffer, position, direction) do
    case direction do
      :left ->
        buffer
        |> String.slice(0, position)
        |> String.reverse()
        |> find_next_word_char()
        |> then(fn offset -> max(0, position - offset) end)

      :right ->
        buffer
        |> String.slice(position..-1)
        |> find_next_word_char()
        |> then(fn offset -> min(String.length(buffer), position + offset) end)
    end
  end

  defp find_next_word_char(text) do
    # Find the next word boundary (space or punctuation)
    text
    |> String.graphemes()
    |> Enum.find_index(fn char -> char =~ ~r/\s/ end)
    |> case do
      nil -> String.length(text)
      index -> index
    end
  end

  defp start_history_search(state) do
    # Start interactive history search mode
    # This would integrate with a search interface
    {:continue, state}
  end

  defp add_to_history(command, state) do
    # Add command to history, avoiding duplicates
    new_history =
      [command | Enum.reject(state.history, &(&1 == command))]
      # Limit history size
      |> Enum.take(1000)

    %{state | history: new_history, history_position: -1}
  end

  defp reset_input_buffer(state) do
    %{state | input_buffer: "", cursor_position: 0, autocomplete_state: %{}, multi_line_mode: false}
  end

  defp get_display_info(state) do
    %{
      input: state.input_buffer,
      cursor_position: state.cursor_position,
      suggestions: get_current_suggestions(state),
      prompt: get_current_prompt(state),
      multi_line: state.multi_line_mode
    }
  end

  defp get_current_prompt(state) do
    if state.multi_line_mode do
      state.prompt_state.continuation
    else
      state.prompt_state.prompt
    end
  end

  defp load_session_history(_state, _session_id) do
    # Load history from persistent storage
    # This would integrate with the persistence system
  end

  defp save_session_history(_state) do
    # Save history to persistent storage
    # This would integrate with the persistence system
  end

  defp notify_callbacks(event_type, data, state) do
    callbacks = Map.get(state, :callbacks, %{})

    case Map.get(callbacks, event_type, []) do
      [] ->
        :ok

      pids ->
        Enum.each(pids, fn pid ->
          if Process.alive?(pid) do
            send(pid, {:input_interceptor_event, {event_type, data}})
          end
        end)
    end
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.info("Input Interceptor shutting down")
    :ok
  end
end
