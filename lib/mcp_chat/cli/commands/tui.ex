defmodule MCPChat.CLI.Commands.TUI do
  @moduledoc """
  Command module for controlling the TUI (Text User Interface) displays.
  """

  use MCPChat.CLI.Commands.Base

  alias MCPChat.UI.TUIManager
  alias MCPChat.CLI.Renderer

  @impl true
  def commands() do
    %{
      "tui" => "Control TUI displays (progress and cache)"
    }
  end

  @impl true
  def handle_command("tui", args) do
    case String.split(args || "", " ", trim: true) do
      ["show", "progress"] ->
        TUIManager.show_progress()
        Renderer.show_success("Progress display enabled")
        :ok

      ["show", "cache"] ->
        TUIManager.show_cache(:summary)
        Renderer.show_success("Cache display enabled (summary mode)")
        :ok

      ["show", "cache", "full"] ->
        TUIManager.show_cache(:detailed)
        Renderer.show_success("Cache display enabled (detailed mode)")
        :ok

      ["show", "both"] ->
        TUIManager.show_both()
        Renderer.show_success("Both displays enabled")
        :ok

      ["hide"] ->
        TUIManager.hide_all()
        Renderer.show_success("All displays hidden")
        :ok

      ["toggle"] ->
        TUIManager.toggle_display()
        Renderer.show_success("Display toggled")
        :ok

      ["status"] ->
        status = TUIManager.status()

        Renderer.show_info("TUI Status:")
        Renderer.show_info("  Active Display: #{status.active_display}")
        Renderer.show_info("  Layout Mode: #{status.layout_mode}")
        Renderer.show_info("  Progress Visible: #{status.progress_visible}")
        Renderer.show_info("  Cache Visible: #{status.cache_visible}")

        :ok

      _ ->
        show_usage()
        :ok
    end
  end

  defp show_usage() do
    usage = """
    Usage: /tui <subcommand>

    Subcommands:
      show progress    - Show progress display
      show cache       - Show cache display (summary)
      show cache full  - Show cache display (detailed)
      show both        - Show both displays
      hide             - Hide all displays
      toggle           - Cycle through display modes
      status           - Show current display status

    Keyboard shortcuts (when TUI is active):
      p - Show progress
      c - Show cache
      b - Show both
      h - Hide all
      d - Detailed cache view
      s - Summary cache view
      l - Toggle layout mode
    """

    Renderer.show_info(usage)
  end
end
