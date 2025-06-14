defmodule MCPChat.UI.ResourceCacheDisplay do
  @moduledoc """
  Owl-based TUI component for displaying resource cache status.
  Shows cached resources, their sizes, hit rates, and last access times.
  """

  use GenServer
  require Logger

  alias MCPChat.MCP.ResourceCache

  # Update every second
  @update_interval 1_000
  @max_resources_shown 10

  defstruct [
    :timer_ref,
    :display_pid,
    :last_render,
    # :summary | :detailed
    :display_mode
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def show(mode \\ :summary) when mode in [:summary, :detailed] do
    GenServer.cast(__MODULE__, {:show, mode})
  end

  def hide() do
    GenServer.cast(__MODULE__, :hide)
  end

  def toggle_mode() do
    GenServer.cast(__MODULE__, :toggle_mode)
  end

  def visible? do
    GenServer.call(__MODULE__, :is_visible?)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      display_pid: nil,
      last_render: nil,
      display_mode: :summary
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:show, mode}, state) do
    if state.display_pid do
      # Just update the mode if already visible
      {:noreply, %{state | display_mode: mode}}
    else
      # Start the update timer
      timer_ref = :timer.send_interval(@update_interval, :update_display)

      # Initial render
      send(self(), :update_display)

      {:noreply, %{state | timer_ref: timer_ref, display_pid: self(), display_mode: mode}}
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

    {:noreply, %{state | timer_ref: nil, display_pid: nil}}
  end

  @impl true
  def handle_cast(:toggle_mode, state) do
    new_mode = if state.display_mode == :summary, do: :detailed, else: :summary
    {:noreply, %{state | display_mode: new_mode}}
  end

  @impl true
  def handle_call(:is_visible?, _from, state) do
    {:reply, state.display_pid != nil, state}
  end

  @impl true
  def handle_info(:update_display, state) do
    # Get cache statistics
    stats = ResourceCache.get_stats()

    # Get cached resources for detailed view
    resources =
      if state.display_mode == :detailed do
        ResourceCache.list_resources()
      else
        []
      end

    # Render the display
    render_cache_display(state.display_mode, stats, resources)

    {:noreply, %{state | last_render: {stats, resources}}}
  end

  # Private Functions

  defp render_cache_display(mode, stats, resources) do
    # Clear from cursor to end of screen
    IO.write("\e[J")

    # Build the UI based on mode
    ui =
      case mode do
        :summary -> build_summary_ui(stats)
        :detailed -> build_detailed_ui(stats, resources)
      end

    Owl.IO.puts(ui)
  end

  defp build_summary_ui(stats) do
    stats_content =
      [
        Owl.Data.tag("Resource Cache Status", :cyan),
        "\n\n",
        build_stats_table(stats)
      ]
      |> Enum.join("")

    [
      Owl.Box.new(
        stats_content,
        title: "Cache Summary",
        border_style: :solid_rounded,
        padding: 1
      ),
      "\n",
      Owl.Data.tag("Press 'd' for detailed view, 'h' to hide", :light_black)
    ]
    |> Enum.join("")
  end

  defp build_detailed_ui(stats, resources) do
    [
      build_summary_ui(stats),
      "\n",
      build_resources_table(resources),
      "\n",
      Owl.Data.tag("Press 's' for summary view, 'h' to hide", :light_black)
    ]
    |> Enum.join("\n")
  end

  defp build_stats_table(stats) do
    rows = [
      ["Total Resources:", to_string(stats.total_resources)],
      ["Cache Size:", format_bytes(stats.total_size)],
      ["Hit Rate:", format_percentage(stats.hit_rate)],
      ["Avg Response Time:", format_duration(stats.avg_response_time)],
      ["Memory Usage:", format_bytes(stats.memory_usage)],
      ["Last Cleanup:", format_time_ago(stats.last_cleanup)]
    ]

    Owl.Table.new(
      rows: rows,
      headers: ["Metric", "Value"],
      border_style: :none
    )
    |> Owl.Data.to_chardata()
  end

  defp build_resources_table(resources) do
    if resources == [] do
      Owl.Data.tag("No cached resources", :light_black)
    else
      # Take only the most recent resources
      recent_resources =
        resources
        |> Enum.sort_by(& &1.last_accessed, {:desc, DateTime})
        |> Enum.take(@max_resources_shown)

      rows =
        Enum.map(recent_resources, fn resource ->
          [
            truncate_uri(resource.uri, 40),
            resource.server_name,
            format_bytes(resource.size),
            format_time_ago(resource.cached_at),
            format_time_ago(resource.last_accessed),
            to_string(resource.hit_count)
          ]
        end)

      table =
        Owl.Table.new(
          rows: rows,
          headers: ["Resource", "Server", "Size", "Cached", "Last Access", "Hits"],
          border_style: :solid
        )

      count_info =
        if length(resources) > @max_resources_shown do
          "\n" <>
            IO.iodata_to_binary(
              Owl.Data.tag("Showing #{@max_resources_shown} of #{length(resources)} resources", :light_black)
            )
        else
          ""
        end

      [
        Owl.Data.tag("Cached Resources:", :cyan),
        "\n",
        Owl.Data.to_chardata(table),
        count_info
      ]
      |> Enum.join("")
    end
  end

  defp format_bytes(nil), do: "0 B"
  defp format_bytes(bytes) when bytes < 1_024, do: "#{bytes} B"

  defp format_bytes(bytes) when bytes < 1_024 * 1_024 do
    kb = Float.round(bytes / 1_024, 1)
    "#{kb} KB"
  end

  defp format_bytes(bytes) do
    mb = Float.round(bytes / (1_024 * 1_024), 2)
    "#{mb} MB"
  end

  defp format_percentage(nil), do: "0%"

  defp format_percentage(rate) when is_float(rate) do
    "#{round(rate * 100)}%"
  end

  defp format_percentage(rate), do: "#{rate}%"

  defp format_duration(nil), do: "N/A"
  defp format_duration(ms) when ms < 1_000, do: "#{ms}ms"

  defp format_duration(ms) do
    seconds = Float.round(ms / 1_000, 1)
    "#{seconds}s"
  end

  defp format_time_ago(nil), do: "Never"

  defp format_time_ago(%DateTime{} = time) do
    diff = DateTime.diff(DateTime.utc_now(), time, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3_600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3_600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp truncate_uri(uri, max_length) do
    if String.length(uri) > max_length do
      String.slice(uri, 0, max_length - 3) <> "..."
    else
      uri
    end
  end

  defp clear_display() do
    # Clear from cursor to end of screen
    IO.write("\e[J")
  end
end
