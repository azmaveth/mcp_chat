defmodule MCPChat.Terminal.AutocompleteIntegration do
  @moduledoc """
  Integration layer connecting the Autocomplete system with Terminal components.

  Orchestrates the interaction between AutocompleteEngine, InputInterceptor,
  DisplayOverlay, and KeyboardHandler for seamless autocomplete functionality.
  """

  use GenServer
  require Logger

  alias MCPChat.Autocomplete.{AutocompleteEngine, ContextAnalyzer}
  alias MCPChat.Terminal.{InputInterceptor, DisplayOverlay, KeyboardHandler}

  # Integration state
  defstruct [
    # AutocompleteEngine pid
    :autocomplete_engine,
    # InputInterceptor pid
    :input_interceptor,
    # DisplayOverlay pid
    :display_overlay,
    # KeyboardHandler pid
    :keyboard_handler,
    # Current suggestions
    :active_suggestions,
    # Selected suggestion index
    :selected_index,
    # Integration mode settings
    :integration_mode,
    # Integration settings
    :settings
  ]

  # Keyboard shortcuts
  @tab_key 9
  @enter_key 13
  @escape_key 27
  @up_arrow "↑"
  @down_arrow "↓"
  @ctrl_space 0

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enable autocomplete integration for a session.
  """
  def enable(pid \\ __MODULE__, session_id, opts \\ []) do
    GenServer.call(pid, {:enable, session_id, opts})
  end

  @doc """
  Disable autocomplete integration.
  """
  def disable(pid \\ __MODULE__, session_id) do
    GenServer.call(pid, {:disable, session_id})
  end

  @doc """
  Handle input change from InputInterceptor.
  """
  def on_input_change(pid \\ __MODULE__, input, cursor_position, context) do
    GenServer.cast(pid, {:input_changed, input, cursor_position, context})
  end

  @doc """
  Handle key press for autocomplete actions.
  """
  def handle_key(pid \\ __MODULE__, key, modifiers \\ []) do
    GenServer.call(pid, {:handle_key, key, modifiers})
  end

  @doc """
  Get current autocomplete state.
  """
  def get_state(pid \\ __MODULE__) do
    GenServer.call(pid, :get_state)
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    Logger.info("Starting Autocomplete Integration")

    settings = %{
      suggestion_delay: Keyword.get(opts, :suggestion_delay, 150),
      max_suggestions: Keyword.get(opts, :max_suggestions, 10),
      min_input_length: Keyword.get(opts, :min_input_length, 1),
      show_preview: Keyword.get(opts, :show_preview, true),
      inline_preview: Keyword.get(opts, :inline_preview, true),
      fuzzy_matching: Keyword.get(opts, :fuzzy_matching, true)
    }

    # Get or start required components
    autocomplete_engine = ensure_component_started(AutocompleteEngine, opts)
    input_interceptor = ensure_component_started(InputInterceptor, opts)
    display_overlay = ensure_component_started(DisplayOverlay, opts)
    keyboard_handler = ensure_component_started(KeyboardHandler, opts)

    state = %__MODULE__{
      autocomplete_engine: autocomplete_engine,
      input_interceptor: input_interceptor,
      display_overlay: display_overlay,
      keyboard_handler: keyboard_handler,
      active_suggestions: [],
      selected_index: 0,
      integration_mode: :inactive,
      settings: settings
    }

    # Register for input events
    register_input_callbacks(state)

    Logger.info("Autocomplete Integration initialized")
    {:ok, state}
  end

  @impl true
  def handle_call({:enable, session_id, opts}, _from, state) do
    # Configure components for the session
    configure_for_session(session_id, opts, state)

    new_state = %{state | integration_mode: :active}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:disable, _session_id}, _from, state) do
    # Clear any active suggestions
    DisplayOverlay.hide_suggestions(state.display_overlay)

    new_state = %{state | integration_mode: :inactive, active_suggestions: [], selected_index: 0}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:handle_key, key, modifiers}, _from, state) do
    result =
      case state.integration_mode do
        :active -> process_key_input(key, modifiers, state)
        :inactive -> {:pass_through, state}
      end

    case result do
      {:handled, new_state} ->
        {:reply, :handled, new_state}

      {:pass_through, new_state} ->
        {:reply, :pass_through, new_state}

      {:complete, suggestion, new_state} ->
        {:reply, {:complete, suggestion}, new_state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    state_info = %{
      mode: state.integration_mode,
      suggestions_count: length(state.active_suggestions),
      selected_index: state.selected_index,
      has_suggestions: length(state.active_suggestions) > 0
    }

    {:reply, state_info, state}
  end

  @impl true
  def handle_cast({:input_changed, input, cursor_position, context}, state) do
    if state.integration_mode == :active do
      # Debounce suggestions
      Process.send_after(self(), {:fetch_suggestions, input, cursor_position, context}, state.settings.suggestion_delay)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:fetch_suggestions, input, cursor_position, context}, state) do
    new_state =
      if String.length(input) >= state.settings.min_input_length do
        fetch_and_display_suggestions(input, cursor_position, context, state)
      else
        hide_suggestions(state)
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:input_interceptor_event, event}, state) do
    new_state = handle_input_event(event, state)
    {:noreply, new_state}
  end

  # Private functions

  defp ensure_component_started(module, _opts) do
    case Process.whereis(module) do
      nil ->
        {:ok, pid} = module.start_link()
        pid

      pid ->
        pid
    end
  end

  defp register_input_callbacks(state) do
    # Register callback with InputInterceptor
    InputInterceptor.register_callback(state.input_interceptor, self(), :input_change)

    # Register keyboard handler for autocomplete shortcuts
    KeyboardHandler.register_handler(state.keyboard_handler, self(), [
      {@tab_key, :tab_complete},
      {@ctrl_space, :force_complete},
      {@up_arrow, :navigate_up},
      {@down_arrow, :navigate_down},
      {@enter_key, :accept_suggestion},
      {@escape_key, :cancel_suggestions}
    ])
  end

  defp configure_for_session(_session_id, _opts, _state) do
    # Configure session-specific settings
    :ok
  end

  defp process_key_input(key, _modifiers, state) do
    cond do
      # No suggestions active
      length(state.active_suggestions) == 0 ->
        case key do
          @tab_key -> trigger_completion(state)
          @ctrl_space -> trigger_completion(state)
          _ -> {:pass_through, state}
        end

      # Suggestions active
      true ->
        case key do
          @up_arrow -> navigate_suggestions(:up, state)
          @down_arrow -> navigate_suggestions(:down, state)
          @tab_key -> accept_current_suggestion(state)
          @enter_key -> accept_current_suggestion(state)
          @escape_key -> cancel_suggestions(state)
          _ -> {:pass_through, state}
        end
    end
  end

  defp trigger_completion(state) do
    # Get current input from InputInterceptor
    case InputInterceptor.get_buffer_state(state.input_interceptor) do
      %{input: input, cursor_position: cursor} ->
        context = build_completion_context(state)
        new_state = fetch_and_display_suggestions(input, cursor, context, state)
        {:handled, new_state}

      _ ->
        {:pass_through, state}
    end
  end

  defp fetch_and_display_suggestions(input, cursor_position, context, state) do
    # Get suggestions from AutocompleteEngine
    suggestions =
      AutocompleteEngine.get_suggestions(
        input,
        Map.merge(context, %{
          cursor_position: cursor_position,
          max_suggestions: state.settings.max_suggestions
        })
      )

    if length(suggestions) > 0 do
      # Display suggestions using DisplayOverlay
      DisplayOverlay.show_suggestions(
        state.display_overlay,
        suggestions,
        0,
        cursor_position
      )

      %{state | active_suggestions: suggestions, selected_index: 0}
    else
      hide_suggestions(state)
    end
  end

  defp navigate_suggestions(direction, state) do
    new_index =
      case direction do
        :up ->
          if state.selected_index > 0 do
            state.selected_index - 1
          else
            length(state.active_suggestions) - 1
          end

        :down ->
          if state.selected_index < length(state.active_suggestions) - 1 do
            state.selected_index + 1
          else
            0
          end
      end

    # Update display
    DisplayOverlay.update_selection(
      state.display_overlay,
      new_index
    )

    new_state = %{state | selected_index: new_index}
    {:handled, new_state}
  end

  defp accept_current_suggestion(state) do
    if state.selected_index < length(state.active_suggestions) do
      suggestion = Enum.at(state.active_suggestions, state.selected_index)

      # Apply the suggestion
      apply_suggestion(suggestion, state)

      # Hide suggestions
      new_state = hide_suggestions(state)

      {:complete, suggestion, new_state}
    else
      {:pass_through, state}
    end
  end

  defp cancel_suggestions(state) do
    new_state = hide_suggestions(state)
    {:handled, new_state}
  end

  defp hide_suggestions(state) do
    DisplayOverlay.hide_suggestions(state.display_overlay)

    %{state | active_suggestions: [], selected_index: 0}
  end

  defp apply_suggestion(suggestion, state) do
    # Get the completion text
    completion = get_completion_text(suggestion)

    # Apply through InputInterceptor
    InputInterceptor.apply_completion(
      state.input_interceptor,
      completion,
      suggestion
    )
  end

  defp get_completion_text(suggestion) do
    case suggestion do
      %{completion: text} -> text
      %{text: text} -> text
      text when is_binary(text) -> text
      _ -> ""
    end
  end

  defp build_completion_context(state) do
    # Get buffer state
    buffer_state = InputInterceptor.get_buffer_state(state.input_interceptor)

    # Analyze context
    context =
      ContextAnalyzer.analyze_context(
        buffer_state.input,
        %{
          cursor_position: buffer_state.cursor_position,
          multi_line: buffer_state.multi_line_mode
        }
      )

    context
  end

  defp handle_input_event(event, state) do
    case event do
      {:input_changed, input, cursor_position} ->
        # Schedule suggestion fetch
        context = build_completion_context(state)

        Process.send_after(
          self(),
          {:fetch_suggestions, input, cursor_position, context},
          state.settings.suggestion_delay
        )

        state

      {:input_cleared} ->
        hide_suggestions(state)

      _ ->
        state
    end
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.info("Autocomplete Integration shutting down")
    :ok
  end
end
