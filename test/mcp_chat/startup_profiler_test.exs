defmodule MCPChat.StartupProfilerTest do
  use ExUnit.Case
  import ExUnit.CaptureIO
  alias MCPChat.StartupProfiler

  setup do
    # Clean up any existing profiling data
    :persistent_term.erase({StartupProfiler, :config_loading, :start}, :not_found)
    :persistent_term.erase({StartupProfiler, :config_loading, :end}, :not_found)
    :ok
  end

  describe "enabled?/0" do
    test "returns true when environment variable is set" do
      System.put_env("MCP_CHAT_STARTUP_PROFILING", "true")
      assert StartupProfiler.enabled?()
      System.delete_env("MCP_CHAT_STARTUP_PROFILING")
    end

    test "returns false when environment variable is not set" do
      System.delete_env("MCP_CHAT_STARTUP_PROFILING")
      refute StartupProfiler.enabled?()
    end
  end

  describe "start_phase/1" do
    test "stores start time when enabled" do
      System.put_env("MCP_CHAT_STARTUP_PROFILING", "true")

      StartupProfiler.start_phase(:config_loading)

      assert is_integer(:persistent_term.get({StartupProfiler, :config_loading, :start}))

      System.delete_env("MCP_CHAT_STARTUP_PROFILING")
    end

    test "does nothing when disabled" do
      System.delete_env("MCP_CHAT_STARTUP_PROFILING")

      StartupProfiler.start_phase(:config_loading)

      assert :not_found == :persistent_term.get({StartupProfiler, :config_loading, :start}, :not_found)
    end

    test "rejects invalid phase names" do
      System.put_env("MCP_CHAT_STARTUP_PROFILING", "true")

      # Should not crash but also not store anything
      StartupProfiler.start_phase(:invalid_phase)

      assert :not_found == :persistent_term.get({StartupProfiler, :invalid_phase, :start}, :not_found)

      System.delete_env("MCP_CHAT_STARTUP_PROFILING")
    end
  end

  describe "end_phase/1" do
    test "stores end time when enabled and start exists" do
      System.put_env("MCP_CHAT_STARTUP_PROFILING", "true")

      StartupProfiler.start_phase(:config_loading)
      Process.sleep(10)
      StartupProfiler.end_phase(:config_loading)

      assert is_integer(:persistent_term.get({StartupProfiler, :config_loading, :end}))

      System.delete_env("MCP_CHAT_STARTUP_PROFILING")
    end

    test "does nothing when disabled" do
      System.delete_env("MCP_CHAT_STARTUP_PROFILING")

      StartupProfiler.end_phase(:config_loading)

      assert :not_found == :persistent_term.get({StartupProfiler, :config_loading, :end}, :not_found)
    end
  end

  describe "get_timings/0" do
    test "returns empty map when disabled" do
      System.delete_env("MCP_CHAT_STARTUP_PROFILING")

      assert %{} == StartupProfiler.get_timings()
    end

    test "returns timings for completed phases" do
      System.put_env("MCP_CHAT_STARTUP_PROFILING", "true")

      # Complete a phase
      StartupProfiler.start_phase(:config_loading)
      Process.sleep(10)
      StartupProfiler.end_phase(:config_loading)

      # Start but don't complete another
      StartupProfiler.start_phase(:supervision_tree)

      timings = StartupProfiler.get_timings()

      assert Map.has_key?(timings, :config_loading)
      assert timings.config_loading > 0
      refute Map.has_key?(timings, :supervision_tree)

      System.delete_env("MCP_CHAT_STARTUP_PROFILING")
    end

    test "calculates total time correctly" do
      System.put_env("MCP_CHAT_STARTUP_PROFILING", "true")

      StartupProfiler.start_phase(:config_loading)
      Process.sleep(10)
      StartupProfiler.end_phase(:config_loading)

      StartupProfiler.start_phase(:supervision_tree)
      Process.sleep(10)
      StartupProfiler.end_phase(:supervision_tree)

      timings = StartupProfiler.get_timings()

      assert Map.has_key?(timings, :total)
      assert timings.total >= timings.config_loading + timings.supervision_tree

      System.delete_env("MCP_CHAT_STARTUP_PROFILING")
    end
  end

  describe "print_timings/0" do
    test "prints formatted output when enabled" do
      System.put_env("MCP_CHAT_STARTUP_PROFILING", "true")

      StartupProfiler.start_phase(:config_loading)
      Process.sleep(10)
      StartupProfiler.end_phase(:config_loading)

      output =
        capture_io(fn ->
          StartupProfiler.print_timings()
        end)

      assert output =~ "Startup Profile"
      assert output =~ "config_loading"
      assert output =~ "ms"

      System.delete_env("MCP_CHAT_STARTUP_PROFILING")
    end

    test "prints nothing when disabled" do
      System.delete_env("MCP_CHAT_STARTUP_PROFILING")

      output =
        capture_io(fn ->
          StartupProfiler.print_timings()
        end)

      assert output == ""
    end
  end
end
