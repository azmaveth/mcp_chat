defmodule MCPChat.Terminal.ProgressIndicator do
  @moduledoc """
  Progress bars and spinner animations for terminal display.

  Provides smooth, animated progress indicators with
  customizable styles and themes.
  """

  use GenServer
  require Logger

  alias IO.ANSI

  # Progress indicator state
  defstruct [
    # Map of active progress indicators
    :active_indicators,
    # Animation timer reference
    :animation_timer,
    # Spinner animation frames
    :spinner_frames,
    # Progress bar styles
    :bar_styles,
    # Indicator settings
    :settings
  ]

  # Spinner types
  @spinner_types %{
    dots: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"],
    line: ["-", "\\", "|", "/"],
    arrow: ["←", "↖", "↑", "↗", "→", "↘", "↓", "↙"],
    circle: ["◐", "◓", "◑", "◒"],
    square: ["◰", "◳", "◲", "◱"],
    bounce: ["⠁", "⠂", "⠄", "⠂"],
    pulse: ["◯", "⬤", "◯", "◯"],
    wave: ["▁", "▃", "▄", "▅", "▆", "▇", "▆", "▅", "▄", "▃"],
    blocks: ["█", "▇", "▆", "▅", "▄", "▃", "▂", "▁", " "]
  }

  # Bar styles
  @bar_styles %{
    classic: %{
      filled: "█",
      empty: "░",
      left: "[",
      right: "]"
    },
    modern: %{
      filled: "━",
      empty: "─",
      left: "┃",
      right: "┃"
    },
    rounded: %{
      filled: "●",
      empty: "○",
      left: "(",
      right: ")"
    },
    arrow: %{
      filled: "▶",
      empty: "─",
      left: "",
      right: ""
    },
    dots: %{
      filled: "•",
      empty: "·",
      left: "",
      right: ""
    }
  }

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Create a new progress bar.
  """
  def create_progress_bar(pid \\ __MODULE__, id, options \\ %{}) do
    GenServer.call(pid, {:create_progress_bar, id, options})
  end

  @doc """
  Update progress bar value.
  """
  def update_progress(pid \\ __MODULE__, id, current, total \\ nil) do
    GenServer.call(pid, {:update_progress, id, current, total})
  end

  @doc """
  Create a new spinner.
  """
  def create_spinner(pid \\ __MODULE__, id, message, options \\ %{}) do
    GenServer.call(pid, {:create_spinner, id, message, options})
  end

  @doc """
  Update spinner message.
  """
  def update_spinner_message(pid \\ __MODULE__, id, message) do
    GenServer.call(pid, {:update_spinner_message, id, message})
  end

  @doc """
  Stop and remove an indicator.
  """
  def stop_indicator(pid \\ __MODULE__, id) do
    GenServer.call(pid, {:stop_indicator, id})
  end

  @doc """
  Get current frame for rendering.
  """
  def get_frame(pid \\ __MODULE__, id) do
    GenServer.call(pid, {:get_frame, id})
  end

  @doc """
  Set indicator style.
  """
  def set_style(pid \\ __MODULE__, id, style) do
    GenServer.call(pid, {:set_style, id, style})
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    Logger.info("Starting Progress Indicator")

    settings = %{
      animation_fps: Keyword.get(opts, :animation_fps, 10),
      default_bar_width: Keyword.get(opts, :default_bar_width, 40),
      show_percentage: Keyword.get(opts, :show_percentage, true),
      show_time: Keyword.get(opts, :show_time, true),
      show_speed: Keyword.get(opts, :show_speed, false),
      color_enabled: Keyword.get(opts, :color_enabled, true)
    }

    state = %__MODULE__{
      active_indicators: %{},
      animation_timer: nil,
      spinner_frames: @spinner_types,
      bar_styles: @bar_styles,
      settings: settings
    }

    # Start animation timer
    timer_ref = start_animation_timer(settings.animation_fps)

    Logger.info("Progress Indicator initialized", settings: settings)
    {:ok, %{state | animation_timer: timer_ref}}
  end

  @impl true
  def handle_call({:create_progress_bar, id, options}, _from, state) do
    indicator = %{
      type: :progress_bar,
      current: 0,
      total: Map.get(options, :total, 100),
      label: Map.get(options, :label, ""),
      style: Map.get(options, :style, :classic),
      width: Map.get(options, :width, state.settings.default_bar_width),
      color: Map.get(options, :color, :cyan),
      show_percentage: Map.get(options, :show_percentage, state.settings.show_percentage),
      show_time: Map.get(options, :show_time, state.settings.show_time),
      show_speed: Map.get(options, :show_speed, state.settings.show_speed),
      start_time: System.monotonic_time(:millisecond),
      last_update: System.monotonic_time(:millisecond)
    }

    new_indicators = Map.put(state.active_indicators, id, indicator)
    {:reply, :ok, %{state | active_indicators: new_indicators}}
  end

  @impl true
  def handle_call({:update_progress, id, current, total}, _from, state) do
    case Map.get(state.active_indicators, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      indicator ->
        updated_indicator =
          indicator
          |> Map.put(:current, current)
          |> Map.put(:total, total || indicator.total)
          |> Map.put(:last_update, System.monotonic_time(:millisecond))

        new_indicators = Map.put(state.active_indicators, id, updated_indicator)
        {:reply, :ok, %{state | active_indicators: new_indicators}}
    end
  end

  @impl true
  def handle_call({:create_spinner, id, message, options}, _from, state) do
    indicator = %{
      type: :spinner,
      message: message,
      style: Map.get(options, :style, :dots),
      color: Map.get(options, :color, :cyan),
      frame_index: 0,
      start_time: System.monotonic_time(:millisecond)
    }

    new_indicators = Map.put(state.active_indicators, id, indicator)
    {:reply, :ok, %{state | active_indicators: new_indicators}}
  end

  @impl true
  def handle_call({:update_spinner_message, id, message}, _from, state) do
    case Map.get(state.active_indicators, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{type: :spinner} = spinner ->
        updated_spinner = Map.put(spinner, :message, message)
        new_indicators = Map.put(state.active_indicators, id, updated_spinner)
        {:reply, :ok, %{state | active_indicators: new_indicators}}

      _ ->
        {:reply, {:error, :wrong_type}, state}
    end
  end

  @impl true
  def handle_call({:stop_indicator, id}, _from, state) do
    new_indicators = Map.delete(state.active_indicators, id)
    {:reply, :ok, %{state | active_indicators: new_indicators}}
  end

  @impl true
  def handle_call({:get_frame, id}, _from, state) do
    case Map.get(state.active_indicators, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{type: :progress_bar} = bar ->
        frame = render_progress_bar(bar, state)
        {:reply, {:ok, frame}, state}

      %{type: :spinner} = spinner ->
        frame = render_spinner(spinner, state)
        {:reply, {:ok, frame}, state}
    end
  end

  @impl true
  def handle_call({:set_style, id, style}, _from, state) do
    case Map.get(state.active_indicators, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      indicator ->
        updated_indicator = Map.put(indicator, :style, style)
        new_indicators = Map.put(state.active_indicators, id, updated_indicator)
        {:reply, :ok, %{state | active_indicators: new_indicators}}
    end
  end

  @impl true
  def handle_info(:animate, state) do
    # Update all spinner frame indices
    new_indicators =
      state.active_indicators
      |> Enum.map(fn
        {id, %{type: :spinner} = spinner} ->
          frames = Map.get(state.spinner_frames, spinner.style, @spinner_types.dots)
          new_frame_index = rem(spinner.frame_index + 1, length(frames))
          {id, Map.put(spinner, :frame_index, new_frame_index)}

        other ->
          other
      end)
      |> Enum.into(%{})

    {:noreply, %{state | active_indicators: new_indicators}}
  end

  # Private functions

  defp start_animation_timer(fps) do
    interval = div(1000, fps)
    :timer.send_interval(interval, :animate)
  end

  defp render_progress_bar(bar, state) do
    style = Map.get(state.bar_styles, bar.style, @bar_styles.classic)

    # Calculate progress
    percentage =
      if bar.total > 0 do
        bar.current / bar.total
      else
        0.0
      end

    # Calculate filled/empty portions
    filled_width = round(bar.width * percentage)
    empty_width = bar.width - filled_width

    # Build bar components
    components = []

    # Label
    components =
      if bar.label != "" do
        [bar.label, " " | components]
      else
        components
      end

    # Progress bar
    bar_parts = [
      style.left,
      apply_color(String.duplicate(style.filled, filled_width), bar.color, state),
      String.duplicate(style.empty, empty_width),
      style.right
    ]

    components = components ++ bar_parts

    # Percentage
    components =
      if bar.show_percentage do
        percentage_text = " #{round(percentage * 100)}%"
        components ++ [percentage_text]
      else
        components
      end

    # Time elapsed
    components =
      if bar.show_time do
        elapsed = format_time(System.monotonic_time(:millisecond) - bar.start_time)
        components ++ [" ", elapsed]
      else
        components
      end

    # Speed
    components =
      if bar.show_speed and bar.current > 0 do
        speed = calculate_speed(bar)
        components ++ [" ", format_speed(speed)]
      else
        components
      end

    Enum.join(components)
  end

  defp render_spinner(spinner, state) do
    frames = Map.get(state.spinner_frames, spinner.style, @spinner_types.dots)
    frame = Enum.at(frames, spinner.frame_index, " ")

    colored_frame = apply_color(frame, spinner.color, state)
    "#{colored_frame} #{spinner.message}"
  end

  defp apply_color(text, color, state) do
    if state.settings.color_enabled do
      color_code = apply(ANSI, color, [])
      color_code <> text <> ANSI.reset()
    else
      text
    end
  end

  defp format_time(milliseconds) do
    seconds = div(milliseconds, 1000)
    minutes = div(seconds, 60)
    hours = div(minutes, 60)

    cond do
      hours > 0 ->
        "#{hours}h #{rem(minutes, 60)}m"

      minutes > 0 ->
        "#{minutes}m #{rem(seconds, 60)}s"

      true ->
        "#{seconds}s"
    end
  end

  defp calculate_speed(bar) do
    elapsed_ms = System.monotonic_time(:millisecond) - bar.start_time
    elapsed_s = elapsed_ms / 1000

    if elapsed_s > 0 do
      bar.current / elapsed_s
    else
      0.0
    end
  end

  defp format_speed(speed) do
    cond do
      speed >= 1_000_000 ->
        "#{Float.round(speed / 1_000_000, 1)}M/s"

      speed >= 1_000 ->
        "#{Float.round(speed / 1_000, 1)}K/s"

      true ->
        "#{Float.round(speed, 1)}/s"
    end
  end

  @impl true
  def terminate(_reason, state) do
    # Cancel animation timer
    if state.animation_timer do
      :timer.cancel(state.animation_timer)
    end

    Logger.info("Progress Indicator shutting down")
    :ok
  end
end
