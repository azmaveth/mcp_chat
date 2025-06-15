defmodule MCPChat.UI.TUIManager do
  @moduledoc """
  Manages the TUI (Text User Interface) components for MCP Chat.
  Coordinates between progress display and resource cache display.
  """

  use GenServer
  require Logger

  alias MCPChat.UI.{ProgressDisplay, ResourceCacheDisplay}

  defstruct [
    # :none | :progress | :cache | :both
    :active_display,
    # :stacked | :side_by_side
    :layout_mode
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Show progress display.
  """
  def show_progress do
    GenServer.cast(__MODULE__, :show_progress)
  end

  @doc """
  Show cache display in specified mode.
  """
  def show_cache(mode \\ :summary) do
    GenServer.cast(__MODULE__, {:show_cache, mode})
  end

  @doc """
  Show both displays.
  """
  def show_both do
    GenServer.cast(__MODULE__, :show_both)
  end

  @doc """
  Hide all displays.
  """
  def hide_all do
    GenServer.cast(__MODULE__, :hide_all)
  end

  @doc """
  Toggle between display modes.
  """
  def toggle_display do
    GenServer.cast(__MODULE__, :toggle_display)
  end

  @doc """
  Get current display status.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Handle keyboard input for TUI controls.
  """
  def handle_key(key) do
    GenServer.cast(__MODULE__, {:handle_key, key})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      active_display: :none,
      layout_mode: opts[:layout_mode] || :stacked
    }

    {:ok, state}
  end

  @impl true
  def handle_cast(:show_progress, state) do
    new_state =
      case state.active_display do
        :none ->
          ProgressDisplay.show()
          %{state | active_display: :progress}

        :cache ->
          # Switch to both
          ProgressDisplay.show()
          %{state | active_display: :both}

        _ ->
          state
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:show_cache, mode}, state) do
    new_state =
      case state.active_display do
        :none ->
          ResourceCacheDisplay.show(mode)
          %{state | active_display: :cache}

        :progress ->
          # Switch to both
          ResourceCacheDisplay.show(mode)
          %{state | active_display: :both}

        _ ->
          state
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:show_both, state) do
    unless state.active_display == :both do
      ProgressDisplay.show()
      ResourceCacheDisplay.show()
    end

    {:noreply, %{state | active_display: :both}}
  end

  @impl true
  def handle_cast(:hide_all, state) do
    if state.active_display != :none do
      ProgressDisplay.hide()
      ResourceCacheDisplay.hide()
    end

    {:noreply, %{state | active_display: :none}}
  end

  @impl true
  def handle_cast(:toggle_display, state) do
    new_display = get_next_display_mode(state.active_display)
    transition_display(state.active_display, new_display)
    {:noreply, %{state | active_display: new_display}}
  end

  @impl true
  def handle_cast({:handle_key, key}, state) do
    case key do
      key when key in ["p", "c", "b", "h"] ->
        handle_display_toggle_key(state, key)

      key when key in ["d", "s"] and state.active_display in [:cache, :both] ->
        handle_cache_mode_key(state, key)

      "l" ->
        handle_layout_toggle_key(state)

      _ ->
        {:noreply, state}
    end
  end

  # Display transition helpers

  defp get_next_display_mode(current) do
    case current do
      :none -> :progress
      :progress -> :cache
      :cache -> :both
      :both -> :none
    end
  end

  defp transition_display(from, to) do
    case from do
      :none -> transition_from_none(to)
      :progress -> transition_from_progress(to)
      :cache -> transition_from_cache(to)
      :both -> transition_from_both(to)
    end
  end

  defp show_both_displays do
    ProgressDisplay.show()
    ResourceCacheDisplay.show()
  end

  defp switch_to_cache_only do
    ProgressDisplay.hide()
    ResourceCacheDisplay.show()
  end

  defp switch_to_progress_only do
    ResourceCacheDisplay.hide()
    ProgressDisplay.show()
  end

  defp hide_all_displays do
    ProgressDisplay.hide()
    ResourceCacheDisplay.hide()
  end

  defp transition_from_none(to) do
    case to do
      :progress -> ProgressDisplay.show()
      :cache -> ResourceCacheDisplay.show()
      :both -> show_both_displays()
      _ -> :ok
    end
  end

  defp transition_from_progress(to) do
    case to do
      :cache -> switch_to_cache_only()
      :both -> ResourceCacheDisplay.show()
      _ -> :ok
    end
  end

  defp transition_from_cache(to) do
    case to do
      :progress -> switch_to_progress_only()
      :both -> ProgressDisplay.show()
      _ -> :ok
    end
  end

  defp transition_from_both(to) do
    case to do
      :none -> hide_all_displays()
      :progress -> ResourceCacheDisplay.hide()
      :cache -> ProgressDisplay.hide()
      _ -> :ok
    end
  end

  # Key handling helpers

  defp handle_display_toggle_key(state, key) do
    case key do
      "p" -> handle_cast(:show_progress, state)
      "c" -> handle_cast({:show_cache, :summary}, state)
      "b" -> handle_cast(:show_both, state)
      "h" -> handle_cast(:hide_all, state)
    end
  end

  defp handle_cache_mode_key(state, key) do
    case key do
      "d" -> ResourceCacheDisplay.show(:detailed)
      "s" -> ResourceCacheDisplay.show(:summary)
    end

    {:noreply, state}
  end

  defp handle_layout_toggle_key(state) do
    new_layout = if state.layout_mode == :stacked, do: :side_by_side, else: :stacked
    Logger.info("TUI layout mode: #{new_layout}")
    {:noreply, %{state | layout_mode: new_layout}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      active_display: state.active_display,
      layout_mode: state.layout_mode,
      progress_visible: ProgressDisplay.is_visible?(),
      cache_visible: ResourceCacheDisplay.is_visible?()
    }

    {:reply, status, state}
  end
end
