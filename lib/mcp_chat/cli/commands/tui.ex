defmodule MCPChat.CLI.Commands.TUI do
  @moduledoc """
  Command module for controlling the TUI (Text User Interface) displays.
  """

  use MCPChat.CLI.Commands.Base

  alias MCPChat.CLI.Renderer
  alias MCPChat.UI.TUIManager

  @impl true
  def commands do
    %{
      "tui" => "Control TUI displays (progress and cache)"
    }
  end

  @impl true
  def handle_command("tui", args) do
    args_str = normalize_args(args)
    command_parts = String.split(args_str, " ", trim: true)
    execute_tui_command(command_parts)
  end

  defp normalize_args(args) do
    case args do
      list when is_list(list) -> Enum.join(list, " ")
      str when is_binary(str) -> str
      _ -> ""
    end
  end

  defp execute_tui_command(["show", "progress"]) do
    TUIManager.show_progress()
    Renderer.show_success("Progress display enabled")
    :ok
  end

  defp execute_tui_command(["show", "cache"]) do
    TUIManager.show_cache(:summary)
    Renderer.show_success("Cache display enabled (summary mode)")
    :ok
  end

  defp execute_tui_command(["show", "cache", "full"]) do
    TUIManager.show_cache(:detailed)
    Renderer.show_success("Cache display enabled (detailed mode)")
    :ok
  end

  defp execute_tui_command(["show", "both"]) do
    TUIManager.show_both()
    Renderer.show_success("Both displays enabled")
    :ok
  end

  defp execute_tui_command(["hide"]) do
    TUIManager.hide_all()
    Renderer.show_success("All displays hidden")
    :ok
  end

  defp execute_tui_command(["toggle"]) do
    TUIManager.toggle_display()
    Renderer.show_success("Display toggled")
    :ok
  end

  defp execute_tui_command(["status"]) do
    show_tui_status()
    :ok
  end

  defp execute_tui_command(_) do
    show_usage()
    :ok
  end

  defp show_tui_status do
    status = TUIManager.status()

    Renderer.show_info("TUI Status:")
    Renderer.show_info("  Active Display: #{status.active_display}")
    Renderer.show_info("  Layout Mode: #{status.layout_mode}")
    Renderer.show_info("  Progress Visible: #{status.progress_visible}")
    Renderer.show_info("  Cache Visible: #{status.cache_visible}")
  end

  defp show_usage do
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
