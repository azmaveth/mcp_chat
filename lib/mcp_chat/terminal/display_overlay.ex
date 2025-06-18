defmodule MCPChat.Terminal.DisplayOverlay do
  @moduledoc """
  Display overlay system for terminal enhancements.

  Manages the visual presentation of autocomplete suggestions,
  progress indicators, and other overlays in the terminal.
  """

  use GenServer
  require Logger

  alias IO.ANSI

  @max_visible_suggestions 10
  @suggestion_box_padding 2
  @min_suggestion_width 20

  # Display overlay state
  defstruct [
    # Active overlay type
    :current_overlay,
    # Autocomplete suggestions
    :suggestions,
    # Selected suggestion index
    :selected_index,
    # Display configuration
    :display_settings,
    # Terminal dimensions
    :terminal_size,
    # Position of overlay
    :overlay_position,
    # Animation state for spinners
    :animation_state,
    # Active color scheme
    :color_scheme
  ]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Display autocomplete suggestions.
  """
  def show_suggestions(pid \\ __MODULE__, suggestions, selected_index \\ 0, cursor_position) do
    GenServer.call(pid, {:show_suggestions, suggestions, selected_index, cursor_position})
  end

  @doc """
  Hide current overlay.
  """
  def hide_overlay(pid \\ __MODULE__) do
    GenServer.call(pid, :hide_overlay)
  end

  @doc """
  Show progress bar.
  """
  def show_progress(pid \\ __MODULE__, label, current, total) do
    GenServer.call(pid, {:show_progress, label, current, total})
  end

  @doc """
  Show spinner animation.
  """
  def show_spinner(pid \\ __MODULE__, message) do
    GenServer.call(pid, {:show_spinner, message})
  end

  @doc """
  Update terminal size.
  """
  def update_terminal_size(pid \\ __MODULE__, width, height) do
    GenServer.call(pid, {:update_terminal_size, width, height})
  end

  @doc """
  Set color scheme.
  """
  def set_color_scheme(pid \\ __MODULE__, scheme) do
    GenServer.call(pid, {:set_color_scheme, scheme})
  end

  @doc """
  Render current overlay.
  """
  def render(pid \\ __MODULE__) do
    GenServer.call(pid, :render)
  end

  @doc """
  Hide suggestions overlay.
  """
  def hide_suggestions(pid \\ __MODULE__) do
    GenServer.call(pid, :hide_suggestions)
  end

  @doc """
  Update selected suggestion index.
  """
  def update_selection(pid \\ __MODULE__, new_index) do
    GenServer.call(pid, {:update_selection, new_index})
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    Logger.info("Starting Display Overlay")

    display_settings = %{
      max_suggestions: Keyword.get(opts, :max_suggestions, @max_visible_suggestions),
      show_descriptions: Keyword.get(opts, :show_descriptions, true),
      show_icons: Keyword.get(opts, :show_icons, true),
      animation_enabled: Keyword.get(opts, :animation_enabled, true),
      transparency: Keyword.get(opts, :transparency, false),
      rounded_corners: Keyword.get(opts, :rounded_corners, true)
    }

    # Get initial terminal size
    {width, height} = get_terminal_dimensions()

    state = %__MODULE__{
      current_overlay: nil,
      suggestions: [],
      selected_index: 0,
      display_settings: display_settings,
      terminal_size: {width, height},
      overlay_position: {0, 0},
      animation_state: %{frame: 0, last_update: nil},
      color_scheme: load_color_scheme(opts)
    }

    # Start animation timer if enabled
    if display_settings.animation_enabled do
      schedule_animation_update()
    end

    Logger.info("Display Overlay initialized",
      terminal_size: state.terminal_size,
      settings: display_settings
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:show_suggestions, suggestions, selected_index, cursor_position}, _from, state) do
    overlay_position = calculate_overlay_position(cursor_position, state.terminal_size)

    new_state = %{
      state
      | current_overlay: :suggestions,
        suggestions: suggestions,
        selected_index: selected_index,
        overlay_position: overlay_position
    }

    rendered = render_suggestions_overlay(new_state)
    {:reply, {:ok, rendered}, new_state}
  end

  @impl true
  def handle_call(:hide_overlay, _from, state) do
    new_state = %{state | current_overlay: nil, suggestions: [], selected_index: 0}

    # Clear overlay area
    clear_commands = clear_overlay_area(state)
    {:reply, {:ok, clear_commands}, new_state}
  end

  @impl true
  def handle_call({:show_progress, label, current, total}, _from, state) do
    new_state = %{
      state
      | current_overlay: :progress,
        overlay_position: calculate_progress_position(state.terminal_size)
    }

    rendered = render_progress_bar(label, current, total, new_state)
    {:reply, {:ok, rendered}, new_state}
  end

  @impl true
  def handle_call({:show_spinner, message}, _from, state) do
    new_state = %{
      state
      | current_overlay: :spinner,
        animation_state: %{state.animation_state | last_update: System.monotonic_time(:millisecond)}
    }

    rendered = render_spinner(message, new_state)
    {:reply, {:ok, rendered}, new_state}
  end

  @impl true
  def handle_call({:update_terminal_size, width, height}, _from, state) do
    new_state = %{state | terminal_size: {width, height}}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:set_color_scheme, scheme}, _from, state) do
    new_scheme = load_color_scheme([{:color_scheme, scheme}])
    new_state = %{state | color_scheme: new_scheme}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:render, _from, state) do
    rendered =
      case state.current_overlay do
        :suggestions -> render_suggestions_overlay(state)
        :progress -> render_current_progress(state)
        :spinner -> render_current_spinner(state)
        nil -> ""
      end

    {:reply, rendered, state}
  end

  @impl true
  def handle_call(:hide_suggestions, _from, state) do
    if state.current_overlay == :suggestions do
      new_state = %{state | current_overlay: nil, suggestions: [], selected_index: 0}

      # Clear overlay area
      clear_commands = clear_overlay_area(state)
      {:reply, {:ok, clear_commands}, new_state}
    else
      {:reply, {:ok, ""}, state}
    end
  end

  @impl true
  def handle_call({:update_selection, new_index}, _from, state) do
    if state.current_overlay == :suggestions do
      new_state = %{state | selected_index: new_index}

      # Re-render with new selection
      rendered = render_suggestions_overlay(new_state)
      {:reply, {:ok, rendered}, new_state}
    else
      {:reply, {:error, :no_suggestions}, state}
    end
  end

  @impl true
  def handle_info(:animate, state) do
    new_state =
      if state.current_overlay == :spinner do
        update_animation_frame(state)
      else
        state
      end

    # Schedule next animation frame
    if state.display_settings.animation_enabled do
      schedule_animation_update()
    end

    {:noreply, new_state}
  end

  # Private functions

  defp get_terminal_dimensions do
    case :io.columns() do
      {:ok, width} ->
        case :io.rows() do
          {:ok, height} -> {width, height}
          # Default fallback
          _ -> {80, 24}
        end

      # Default fallback
      _ ->
        {80, 24}
    end
  end

  defp load_color_scheme(opts) do
    scheme_name = Keyword.get(opts, :color_scheme, :default)

    base_scheme = %{
      background: :black,
      foreground: :white,
      selected: :cyan,
      border: :blue,
      description: :light_black,
      type_indicator: :yellow,
      match_highlight: :green,
      error: :red,
      warning: :yellow,
      success: :green,
      progress_bar: :cyan,
      progress_background: :black
    }

    # Apply theme-specific overrides
    case scheme_name do
      :solarized_dark ->
        %{
          base_scheme
          | background: :black,
            foreground: :light_white,
            selected: :blue,
            border: :cyan,
            description: :light_black
        }

      :monokai ->
        %{base_scheme | selected: :magenta, border: :yellow, type_indicator: :green}

      :nord ->
        %{base_scheme | selected: :light_blue, border: :blue, type_indicator: :cyan}

      _ ->
        base_scheme
    end
  end

  defp calculate_overlay_position({cursor_x, cursor_y}, {term_width, term_height}) do
    # Calculate optimal position for suggestion overlay
    # Try to show below cursor, but adjust if near bottom
    # Border
    overlay_height = @max_visible_suggestions + 2

    preferred_y = cursor_y + 1

    y =
      if preferred_y + overlay_height > term_height do
        # Show above cursor instead
        max(1, cursor_y - overlay_height - 1)
      else
        preferred_y
      end

    # Center horizontally if possible, but keep within bounds
    overlay_width = @min_suggestion_width + @suggestion_box_padding * 2
    x = max(0, min(cursor_x, term_width - overlay_width))

    {x, y}
  end

  defp calculate_overlay_position(cursor_position, terminal_size) when is_integer(cursor_position) do
    # Convert linear position to x,y coordinates
    # This is simplified - real implementation would need prompt info
    {term_width, _} = terminal_size
    cursor_x = rem(cursor_position, term_width)
    cursor_y = div(cursor_position, term_width)
    calculate_overlay_position({cursor_x, cursor_y}, terminal_size)
  end

  defp calculate_progress_position({term_width, term_height}) do
    # Progress bars typically shown at bottom
    # Center a 60-char progress bar
    x = div(term_width - 60, 2)
    y = term_height - 2
    {max(0, x), y}
  end

  defp render_suggestions_overlay(state) do
    {x, y} = state.overlay_position

    suggestions_to_show = Enum.take(state.suggestions, state.display_settings.max_suggestions)

    if length(suggestions_to_show) == 0 do
      ""
    else
      # Calculate box dimensions
      max_width = calculate_suggestion_box_width(suggestions_to_show, state)
      _box_height = length(suggestions_to_show) + 2

      # Build the overlay
      lines = []

      # Top border
      lines = [render_box_top(max_width, state) | lines]

      # Suggestions
      suggestion_lines =
        suggestions_to_show
        |> Enum.with_index()
        |> Enum.map(fn {suggestion, index} ->
          render_suggestion_line(suggestion, index, state.selected_index, max_width, state)
        end)

      lines = lines ++ suggestion_lines

      # Bottom border
      lines = lines ++ [render_box_bottom(max_width, state)]

      # Position and render
      position_overlay(lines, x, y)
    end
  end

  defp calculate_suggestion_box_width(suggestions, state) do
    base_width =
      suggestions
      |> Enum.map(&suggestion_display_width(&1, state))
      |> Enum.max()

    max(base_width + @suggestion_box_padding * 2, @min_suggestion_width)
  end

  defp suggestion_display_width(suggestion, state) do
    text_width = String.length(suggestion_text(suggestion))

    icon_width =
      if state.display_settings.show_icons do
        # Icon + space
        3
      else
        0
      end

    # Type indicator
    type_width = 10

    text_width + icon_width + type_width
  end

  defp suggestion_text(suggestion) when is_binary(suggestion), do: suggestion
  defp suggestion_text(%{text: text}), do: text
  defp suggestion_text(%{value: value}), do: value
  defp suggestion_text(_), do: ""

  defp render_box_top(width, state) do
    if state.display_settings.rounded_corners do
      color_for(:border, state) <> "╭" <> String.duplicate("─", width - 2) <> "╮" <> ANSI.reset()
    else
      color_for(:border, state) <> "┌" <> String.duplicate("─", width - 2) <> "┐" <> ANSI.reset()
    end
  end

  defp render_box_bottom(width, state) do
    if state.display_settings.rounded_corners do
      color_for(:border, state) <> "╰" <> String.duplicate("─", width - 2) <> "╯" <> ANSI.reset()
    else
      color_for(:border, state) <> "└" <> String.duplicate("─", width - 2) <> "┘" <> ANSI.reset()
    end
  end

  defp render_suggestion_line(suggestion, index, selected_index, width, state) do
    is_selected = index == selected_index

    # Extract suggestion details
    text = suggestion_text(suggestion)
    type = suggestion_type(suggestion)
    icon = suggestion_icon(suggestion, state)

    # Build the line
    prefix = color_for(:border, state) <> "│" <> ANSI.reset()
    suffix = color_for(:border, state) <> "│" <> ANSI.reset()

    # Content formatting
    content =
      if is_selected do
        bg_color = color_for(:selected, state)
        fg_color = color_for(:background, state)

        formatted_content = format_suggestion_content(text, type, icon, width - 2, state)
        bg_color <> fg_color <> formatted_content <> ANSI.reset()
      else
        format_suggestion_content(text, type, icon, width - 2, state)
      end

    prefix <> content <> suffix
  end

  defp format_suggestion_content(text, type, icon, available_width, state) do
    # Icon
    icon_part =
      if state.display_settings.show_icons and icon do
        icon <> " "
      else
        ""
      end

    # Type indicator
    type_part = format_type_indicator(type, state)

    # Calculate remaining space for text
    icon_width = String.length(icon_part)
    type_width = String.length(strip_ansi(type_part))
    # Padding
    text_space = available_width - icon_width - type_width - 2

    # Truncate text if needed
    truncated_text =
      if String.length(text) > text_space do
        String.slice(text, 0, text_space - 3) <> "..."
      else
        text
      end

    # Pad to fill width
    padding = available_width - icon_width - String.length(truncated_text) - type_width

    " " <> icon_part <> truncated_text <> String.duplicate(" ", max(1, padding)) <> type_part <> " "
  end

  defp suggestion_type(%{type: type}), do: type
  defp suggestion_type(_), do: :general

  defp suggestion_icon(suggestion, state) do
    if state.display_settings.show_icons do
      case suggestion_type(suggestion) do
        :command -> "⚡"
        :file -> "📄"
        :directory -> "📁"
        :git -> "🔀"
        :mcp_server -> "🖥️"
        :tool -> "🔧"
        :history -> "🕐"
        _ -> "•"
      end
    else
      nil
    end
  end

  defp format_type_indicator(type, state) do
    color = color_for(:type_indicator, state)

    text =
      case type do
        :command -> "[cmd]"
        :file -> "[file]"
        :directory -> "[dir]"
        :git -> "[git]"
        :mcp_server -> "[mcp]"
        :tool -> "[tool]"
        :history -> "[hist]"
        _ -> ""
      end

    if text != "" do
      color <> text <> ANSI.reset()
    else
      ""
    end
  end

  defp render_progress_bar(label, current, total, state) do
    {x, y} = state.overlay_position

    # Calculate progress
    percentage =
      if total > 0 do
        round(current / total * 100)
      else
        0
      end

    # Progress bar components
    bar_width = 50
    filled = round(bar_width * current / max(total, 1))
    empty = bar_width - filled

    # Build progress bar
    bar_color = color_for(:progress_bar, state)
    bg_color = color_for(:progress_background, state)

    progress_line =
      [
        label,
        " [",
        bar_color,
        String.duplicate("█", filled),
        bg_color,
        String.duplicate("░", empty),
        ANSI.reset(),
        "] ",
        Integer.to_string(percentage),
        "%"
      ]
      |> Enum.join()

    position_overlay([progress_line], x, y)
  end

  defp render_spinner(message, state) do
    frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    frame_index = rem(state.animation_state.frame, length(frames))
    spinner = Enum.at(frames, frame_index)

    color = color_for(:progress_bar, state)
    line = color <> spinner <> ANSI.reset() <> " " <> message

    {x, y} = calculate_progress_position(state.terminal_size)
    position_overlay([line], x, y)
  end

  defp render_current_progress(_state) do
    # Render cached progress state
    ""
  end

  defp render_current_spinner(state) do
    # Re-render spinner with current frame
    render_spinner("Loading...", state)
  end

  defp position_overlay(lines, x, y) do
    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, offset} ->
      cursor_position(x, y + offset) <> line
    end)
    |> Enum.join("\n")
  end

  defp cursor_position(x, y) do
    "\e[#{y};#{x}H"
  end

  defp clear_overlay_area(state) do
    case state.current_overlay do
      :suggestions ->
        # Clear suggestion box area
        {x, y} = state.overlay_position
        height = min(length(state.suggestions) + 2, @max_visible_suggestions + 2)
        width = calculate_suggestion_box_width(state.suggestions, state)

        clear_area(x, y, width, height)

      :progress ->
        # Clear progress bar area
        {x, y} = state.overlay_position
        clear_area(x, y, 60, 1)

      :spinner ->
        # Clear spinner area
        {x, y} = calculate_progress_position(state.terminal_size)
        clear_area(x, y, 40, 1)

      _ ->
        ""
    end
  end

  defp clear_area(x, y, width, height) do
    blank_line = String.duplicate(" ", width)

    0..(height - 1)
    |> Enum.map(fn offset ->
      cursor_position(x, y + offset) <> blank_line
    end)
    |> Enum.join()
  end

  defp color_for(element, state) do
    color = Map.get(state.color_scheme, element, :white)
    apply(ANSI, color, [])
  end

  defp strip_ansi(text) do
    # Remove ANSI escape codes for length calculation
    String.replace(text, ~r/\e\[[0-9;]*m/, "")
  end

  defp update_animation_frame(state) do
    new_frame = state.animation_state.frame + 1
    new_animation_state = %{state.animation_state | frame: new_frame}
    %{state | animation_state: new_animation_state}
  end

  defp schedule_animation_update do
    # 10 FPS
    Process.send_after(self(), :animate, 100)
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.info("Display Overlay shutting down")
    :ok
  end
end
