defmodule MCPChat.UI.ProgressDisplay do
  @moduledoc """
  Owl-based TUI component for displaying progress of MCP operations.
  Integrates with MCPChat.MCP.ProgressTracker to show real-time progress bars.
  """

  use GenServer
  require Logger

  alias MCPChat.MCP.ProgressTracker

  # Update display every 100ms
  @update_interval 100

  defstruct [
    :timer_ref,
    :active_bars,
    :display_pid,
    :last_render
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def show do
    GenServer.cast(__MODULE__, :show)
  end

  def hide do
    GenServer.cast(__MODULE__, :hide)
  end

  def visible? do
    GenServer.call(__MODULE__, :is_visible?)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      active_bars: %{},
      display_pid: nil,
      last_render: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_cast(:show, state) do
    if state.display_pid do
      {:noreply, state}
    else
      # Start the update timer
      timer_ref = :timer.send_interval(@update_interval, :update_display)

      {:noreply, %{state | timer_ref: timer_ref, display_pid: self()}}
    end
  end

  @impl true
  def handle_cast(:hide, state) do
    # Cancel timer
    if state.timer_ref do
      :timer.cancel(state.timer_ref)
    end

    # Clear the display
    if state.display_pid do
      clear_display()
    end

    {:noreply, %{state | timer_ref: nil, display_pid: nil, active_bars: %{}}}
  end

  @impl true
  def handle_call(:is_visible?, _from, state) do
    {:reply, state.display_pid != nil, state}
  end

  @impl true
  def handle_info(:update_display, state) do
    # Get all active progress items from ProgressTracker
    progress_items = ProgressTracker.get_all_progress()

    # Update our internal state and render
    new_state = update_and_render(state, progress_items)

    {:noreply, new_state}
  end

  # Private Functions

  defp update_and_render(state, progress_items) do
    # Convert progress items to bar configurations
    bars =
      Enum.map(progress_items, fn {token, progress} ->
        %{
          id: token,
          label: progress.operation || "Operation",
          total: progress.total || 100,
          current: progress.current || 0,
          suffix: build_suffix(progress),
          color: get_color_for_status(progress.status)
        }
      end)

    # Only render if something changed
    if bars != state.last_render do
      render_bars(bars)
      %{state | last_render: bars, active_bars: Map.new(bars, fn bar -> {bar.id, bar} end)}
    else
      state
    end
  end

  defp render_bars([]), do: clear_display()

  defp render_bars(bars) do
    # Build the Owl UI
    ui =
      bars
      |> Enum.map(&build_progress_bar/1)
      |> Enum.intersperse("\n")
      |> IO.iodata_to_binary()

    # Clear screen area and display
    # Clear from cursor to end of screen
    IO.write("\e[J")
    Owl.IO.puts(ui)
  end

  defp build_progress_bar(bar) do
    # Build a progress bar data structure that can be rendered
    # Note: In actual usage with LiveScreen, we'd use start/inc pattern
    label = "#{bar.label} [#{bar.suffix}]"
    percentage = if bar.total > 0, do: round(bar.current / bar.total * 100), else: 0
    # 50 char width
    filled = round(percentage / 100 * 50)
    empty = 50 - filled

    bar_display = String.duplicate("█", filled) <> String.duplicate("░", empty)

    Owl.Data.tag("#{label}: [#{bar_display}] #{percentage}%", bar.color)
  end

  defp build_suffix(progress) do
    parts = []

    # Add percentage if we have total
    parts =
      if progress.total && progress.total > 0 do
        percentage = round(progress.current / progress.total * 100)
        ["#{percentage}%"]
      else
        parts
      end

    # Add status if not :in_progress
    parts =
      if progress.status && progress.status != :in_progress do
        parts ++ [Atom.to_string(progress.status)]
      else
        parts
      end

    # Add custom message if present
    parts =
      if progress.message do
        parts ++ [progress.message]
      else
        parts
      end

    Enum.join(parts, " | ")
  end

  defp get_color_for_status(nil), do: :blue
  defp get_color_for_status(:in_progress), do: :blue
  defp get_color_for_status(:completed), do: :green
  defp get_color_for_status(:error), do: :red
  defp get_color_for_status(:cancelled), do: :yellow
  defp get_color_for_status(_), do: :white

  defp clear_display do
    # Clear from cursor to end of screen
    IO.write("\e[J")
  end
end
