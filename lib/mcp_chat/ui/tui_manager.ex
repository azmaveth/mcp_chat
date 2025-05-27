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
  def show_progress() do
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
  def show_both() do
    GenServer.cast(__MODULE__, :show_both)
  end

  @doc """
  Hide all displays.
  """
  def hide_all() do
    GenServer.cast(__MODULE__, :hide_all)
  end

  @doc """
  Toggle between display modes.
  """
  def toggle_display() do
    GenServer.cast(__MODULE__, :toggle_display)
  end

  @doc """
  Get current display status.
  """
  def status() do
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
    new_display =
      case state.active_display do
        :none -> :progress
        :progress -> :cache
        :cache -> :both
        :both -> :none
      end

    # Update displays
    case {state.active_display, new_display} do
      {:none, :progress} ->
        ProgressDisplay.show()

      {:none, :cache} ->
        ResourceCacheDisplay.show()

      {:none, :both} ->
        ProgressDisplay.show()
        ResourceCacheDisplay.show()

      {:progress, :cache} ->
        ProgressDisplay.hide()
        ResourceCacheDisplay.show()

      {:progress, :both} ->
        ResourceCacheDisplay.show()

      {:cache, :progress} ->
        ResourceCacheDisplay.hide()
        ProgressDisplay.show()

      {:cache, :both} ->
        ProgressDisplay.show()

      {:both, :none} ->
        ProgressDisplay.hide()
        ResourceCacheDisplay.hide()

      {:both, :progress} ->
        ResourceCacheDisplay.hide()

      {:both, :cache} ->
        ProgressDisplay.hide()

      _ ->
        :ok
    end

    {:noreply, %{state | active_display: new_display}}
  end

  @impl true
  def handle_cast({:handle_key, key}, state) do
    case key do
      # Display toggles
      "p" ->
        handle_cast(:show_progress, state)

      "c" ->
        handle_cast({:show_cache, :summary}, state)

      "b" ->
        handle_cast(:show_both, state)

      "h" ->
        handle_cast(:hide_all, state)

      # Cache display modes
      "d" when state.active_display in [:cache, :both] ->
        ResourceCacheDisplay.show(:detailed)
        {:noreply, state}

      "s" when state.active_display in [:cache, :both] ->
        ResourceCacheDisplay.show(:summary)
        {:noreply, state}

      # Layout toggle
      "l" ->
        new_layout = if state.layout_mode == :stacked, do: :side_by_side, else: :stacked
        Logger.info("TUI layout mode: #{new_layout}")
        {:noreply, %{state | layout_mode: new_layout}}

      _ ->
        {:noreply, state}
    end
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
