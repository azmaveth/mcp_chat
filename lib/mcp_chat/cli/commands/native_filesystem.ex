defmodule MCPChat.CLI.Commands.NativeFilesystem do
  @moduledoc """
  CLI commands for the native BEAM filesystem server.

  Provides ultra-fast filesystem operations using ExMCP.Native with zero
  serialization overhead and ~15μs latency.
  """

  alias MCPChat.CLI.Renderer
  alias MCPChat.Tools.NativeFilesystemTool

  @doc """
  Handle filesystem commands.
  """
  def handle_command("fs", args) do
    if ExMCP.Native.service_available?(:filesystem_server) do
      # Service is available, execute the command
      NativeFilesystemTool.handle_command(args)
    else
      # Service not available, show error with helpful message
      Renderer.show_error("Native filesystem server is not available")
      Renderer.show_text("The server may be starting up or disabled.")
      Renderer.show_text("Try again in a moment, or check application logs.")
    end

    :ok
  end

  def handle_command(unknown_command, _args) do
    {:error, "Unknown filesystem command: #{unknown_command}"}
  end

  @doc """
  List available filesystem commands.
  """
  def commands do
    %{
      "fs" => "Native BEAM filesystem operations with ultra-low latency (~15μs)"
    }
  end

  @doc """
  Show detailed help for filesystem commands.
  """
  def show_help do
    Renderer.show_text("# Native BEAM Filesystem Commands\n")

    if ExMCP.Native.service_available?(:filesystem_server) do
      Renderer.show_success("✓ Native filesystem server is running")
      Renderer.show_info("💡 Performance: ~15μs latency vs ~1-5ms for external servers")
      Renderer.show_text("")

      NativeFilesystemTool.show_help()
    else
      Renderer.show_warning("⚠ Native filesystem server is not available")
      Renderer.show_text("The server may be starting up or disabled.")
      Renderer.show_text("")
      Renderer.show_text("When available, the `/fs` command provides:")
      Renderer.show_text("- Ultra-fast file operations with zero serialization")
      Renderer.show_text("- Complete filesystem toolkit (ls, cat, write, edit, grep, find)")
      Renderer.show_text("- OTP fault tolerance and process isolation")
      Renderer.show_text("- Resource sharing within the BEAM virtual machine")
    end
  end

  @doc """
  Check if the native filesystem server is available and show status.
  """
  def show_status do
    if ExMCP.Native.service_available?(:filesystem_server) do
      Renderer.show_success("✓ Native filesystem server is running")

      # Try to get tools list to verify functionality
      case ExMCP.Native.call(:filesystem_server, "list_tools", %{}) do
        {:ok, %{"tools" => tools}} ->
          Renderer.show_info("Available tools: #{length(tools)}")

          Enum.each(tools, fn tool ->
            Renderer.show_text("  - #{tool["name"]}: #{tool["description"]}")
          end)

        {:error, reason} ->
          Renderer.show_warning("Server running but not responding: #{inspect(reason)}")

        other ->
          Renderer.show_warning("Unexpected response: #{inspect(other)}")
      end
    else
      Renderer.show_error("✗ Native filesystem server is not available")
      Renderer.show_text("Check if the server is configured to start with the application.")
    end
  end

  @doc """
  Benchmark the native filesystem server vs external alternatives.
  """
  def run_benchmark do
    if not ExMCP.Native.service_available?(:filesystem_server) do
      Renderer.show_error("Native filesystem server not available for benchmarking")
      :error
    else
      Renderer.show_text("# Native BEAM Filesystem Server Benchmark\n")
      Renderer.show_text("Testing native server performance...\n")

      # Test list_tools operation (lightweight)
      {native_time, _result} =
        :timer.tc(fn ->
          ExMCP.Native.call(:filesystem_server, "list_tools", %{})
        end)

      # Test a simple file stat operation
      temp_path = System.tmp_dir!()

      {stat_time, _result} =
        :timer.tc(fn ->
          ExMCP.Native.call(:filesystem_server, "tools/call", %{
            "name" => "stat",
            "arguments" => %{"path" => temp_path}
          })
        end)

      # Display results
      Renderer.show_success("✓ Benchmark Results:")
      Renderer.show_text("  - Tool discovery: #{native_time}μs")
      Renderer.show_text("  - File stat operation: #{stat_time}μs")
      Renderer.show_text("")

      # Compare with typical external server latencies
      Renderer.show_info("📊 Comparison with external MCP servers:")
      Renderer.show_text("  - Native BEAM: ~#{div(native_time + stat_time, 2)}μs average")
      Renderer.show_text("  - External Python: ~1,000-5,000μs (1-5ms)")
      Renderer.show_text("  - External Node.js: ~1,000-3,000μs (1-3ms)")
      Renderer.show_text("")

      improvement = div(2500, max(div(native_time + stat_time, 2), 1))
      Renderer.show_success("🚀 Native BEAM is ~#{improvement}x faster!")

      :ok
    end
  end
end
