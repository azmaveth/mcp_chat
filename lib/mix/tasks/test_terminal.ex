defmodule Mix.Tasks.TestTerminal do
  @moduledoc """
  Mix task for testing terminal detection in Mix task context.

  This task helps debug terminal/TTY detection issues when running
  MCP Chat through Mix tasks vs direct execution.
  """

  use Mix.Task

  @shortdoc "Test terminal detection in Mix task context"

  @impl Mix.Task
  def run(_args) do
    IO.puts("=== Terminal Detection Test (Mix Task) ===")
    IO.puts("Running in context: #{inspect(self())}")
    IO.puts("")

    test_iex_status()
    test_io_options()
    test_environment()
    test_tty_command()
    test_io_columns()
    test_detection_logic()
  end

  defp test_iex_status() do
    IO.puts("IEx loaded?: #{Code.ensure_loaded?(IEx)}")
    IO.puts("IEx started?: #{Code.ensure_loaded?(IEx) and IEx.started?()}")
    IO.puts("")
  end

  defp test_io_options() do
    IO.puts("Checking :io.getopts(:standard_io)...")

    case :io.getopts(:standard_io) do
      opts when is_list(opts) ->
        show_io_options(opts)

      other ->
        IO.puts("Got: #{inspect(other)}")
        IO.puts("Would use: simple (fallback)")
    end

    IO.puts("")
  end

  defp show_io_options(opts) do
    IO.puts("Got options: #{inspect(opts)}")
    terminal = Keyword.get(opts, :terminal, :undefined)
    IO.puts("Terminal option: #{inspect(terminal)}")
    IO.puts("Would use: #{if terminal in [:ebadf, false], do: "simple", else: "advanced"}")
  end

  defp test_environment() do
    IO.puts("Mix loaded?: #{Code.ensure_loaded?(Mix)}")
    IO.puts("Mix env: #{if Code.ensure_loaded?(Mix), do: Mix.env(), else: "N/A"}")
    IO.puts("")
  end

  defp test_tty_command() do
    IO.puts("Testing tty command:")

    case System.cmd("tty", [], stderr_to_stdout: true) do
      {output, 0} ->
        show_tty_success(output)

      {output, code} ->
        IO.puts("  Failed with code #{code}: #{inspect(output)}")
    end
  end

  defp show_tty_success(output) do
    trimmed_output = String.trim(output)
    IO.puts("  Output: #{inspect(trimmed_output)}")
    IO.puts("  Is TTY: #{not String.contains?(output, "not a tty")}")
  end

  defp test_io_columns() do
    IO.puts("\nTesting :io.columns():")

    case :io.columns() do
      {:ok, columns} -> IO.puts("  Success! Columns: #{columns}")
      error -> IO.puts("  Failed: #{inspect(error)}")
    end
  end

  defp test_detection_logic() do
    result = detect_best_implementation()
    IO.puts("\nFinal detection result: #{result}")
  end

  defp detect_best_implementation() do
    if iex_running?() do
      :simple
    else
      detect_from_io_options()
    end
  end

  defp iex_running?() do
    Code.ensure_loaded?(IEx) and IEx.started?()
  end

  defp detect_from_io_options() do
    case :io.getopts(:standard_io) do
      opts when is_list(opts) ->
        handle_io_options(opts)

      _ ->
        :simple
    end
  end

  defp handle_io_options(opts) do
    terminal = Keyword.get(opts, :terminal, :undefined)

    if terminal in [:ebadf, false] do
      handle_limited_terminal()
    else
      :advanced
    end
  end

  defp handle_limited_terminal() do
    if mix_with_tty?() do
      :advanced
    else
      :simple
    end
  end

  defp mix_with_tty?() do
    Code.ensure_loaded?(Mix) and is_tty?()
  end

  # Check if we're connected to a real TTY
  defp is_tty?() do
    # Try to detect if stdin/stdout are connected to a terminal
    case System.cmd("tty", [], stderr_to_stdout: true) do
      {output, 0} ->
        # tty command succeeded, we have a terminal
        not String.contains?(output, "not a tty")

      _ ->
        # Fallback: check if we can interact with the terminal
        check_terminal_interaction()
    end
  rescue
    _ -> false
  end

  defp check_terminal_interaction() do
    # Alternative method: try to get terminal size
    case :io.columns() do
      {:ok, _columns} -> true
      _ -> false
    end
  end
end
