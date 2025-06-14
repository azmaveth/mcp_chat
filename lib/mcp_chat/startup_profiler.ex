defmodule MCPChat.StartupProfiler do
  @moduledoc """
  Profiles application startup time to identify bottlenecks.

  Usage:
    - Set MCP_CHAT_STARTUP_PROFILING=true environment variable
    - Start the application
    - View timing report in console
  """

  require Logger

  @phases [
    :config_loading,
    :supervision_tree,
    :mcp_servers,
    :llm_initialization,
    :ui_setup,
    :total
  ]

  def start_profiling() do
    if System.get_env("MCP_CHAT_STARTUP_PROFILING") == "true" do
      :persistent_term.put({__MODULE__, :enabled}, true)
      :persistent_term.put({__MODULE__, :timings}, %{})
      :persistent_term.put({__MODULE__, :start_time}, System.monotonic_time(:millisecond))
      Logger.info("[Startup Profiler] Profiling enabled")
    end
  end

  def start_phase(phase) when phase in @phases do
    if enabled?() do
      :persistent_term.put({__MODULE__, phase, :start}, System.monotonic_time(:millisecond))
    end
  end

  def end_phase(phase) when phase in @phases do
    if enabled?() do
      start_time = :persistent_term.get({__MODULE__, phase, :start}, nil)

      if start_time do
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        timings = :persistent_term.get({__MODULE__, :timings}, %{})
        :persistent_term.put({__MODULE__, :timings}, Map.put(timings, phase, duration))

        Logger.info("[Startup Profiler] #{phase} took #{duration}ms")
      end
    end
  end

  def report() do
    if enabled?() do
      total_start = :persistent_term.get({__MODULE__, :start_time}, 0)
      total_end = System.monotonic_time(:millisecond)
      total_duration = total_end - total_start

      timings = :persistent_term.get({__MODULE__, :timings}, %{})

      if map_size(timings) > 0 do
        timings = Map.put(timings, :total, total_duration)

        IO.puts("\n🚀 Startup Performance Report:")
        IO.puts("================================")
        IO.puts(format_timings(timings))
        IO.puts("================================\n")
      else
        IO.puts("\n⚠️  No startup timing data collected.")
        IO.puts("Phases tracked: #{inspect(@phases)}")
      end

      cleanup()
    else
      IO.puts("\n⚠️  Startup profiling is not enabled.")
      IO.puts("Set MCP_CHAT_STARTUP_PROFILING=true to enable.")
    end
  end

  defp enabled? do
    :persistent_term.get({__MODULE__, :enabled}, false)
  end

  defp format_timings(timings) do
    timings
    |> Enum.sort_by(fn {phase, _} -> phase_order(phase) end)
    |> Enum.map_join("\n", fn {phase, duration} ->
      percentage = if timings[:total], do: Float.round(duration / timings[:total] * 100, 1), else: 0
      "  #{format_phase(phase)} #{duration}ms (#{percentage}%)"
    end)
  end

  defp phase_order(phase) do
    case phase do
      :config_loading -> 1
      :supervision_tree -> 2
      :mcp_servers -> 3
      :llm_initialization -> 4
      :ui_setup -> 5
      :total -> 6
      _ -> 99
    end
  end

  defp format_phase(phase) do
    phase
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
    |> String.pad_trailing(20, ".")
  end

  defp cleanup() do
    @phases
    |> Enum.each(fn phase ->
      :persistent_term.erase({__MODULE__, phase, :start})
    end)

    :persistent_term.erase({__MODULE__, :enabled})
    :persistent_term.erase({__MODULE__, :timings})
    :persistent_term.erase({__MODULE__, :start_time})
  end
end
