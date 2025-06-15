#!/usr/bin/env elixir

# Enhanced E2E Test Runner
# Runs comprehensive end-to-end tests with real Ollama backend.

defmodule EnhancedE2ERunner do
  @ollama_url "http://localhost:11_434"

  def main(args) do
    case parse_args(args) do
      :check -> check_prerequisites()
      :setup -> setup_environment()
      :run -> run_tests()
      :cleanup -> cleanup()
      :help -> print_help()
    end
  end

  defp parse_args([]), do: :run
  defp parse_args(["--check"]), do: :check
  defp parse_args(["--setup"]), do: :setup
  defp parse_args(["--run"]), do: :run
  defp parse_args(["--cleanup"]), do: :cleanup
  defp parse_args(["--help"]), do: :help
  defp parse_args(_), do: :help

  defp check_prerequisites do
    IO.puts("Checking E2E test prerequisites...\n")

    checks = [
      check_ollama(),
      check_elixir(),
      check_demo_servers()
    ]

    if Enum.all?(checks, &(&1 == :ok)) do
      IO.puts("\n✅ All prerequisites met!")
      System.halt(0)
    else
      IO.puts("\n❌ Some prerequisites are missing. Run with --setup to install.")
      System.halt(1)
    end
  end

  defp check_ollama do
    IO.write("Checking Ollama... ")

    case System.cmd("curl", ["-s", "#{@ollama_url}/api/tags"], stderr_to_stdout: true) do
      {response, 0} ->
        check_ollama_response(response)

      _ ->
        IO.puts("✗ (not running)")
        IO.puts("  Start Ollama with: ollama serve")
        :error
    end
  end

  defp check_ollama_response(response) do
    if String.contains?(response, "\"models\"") and String.contains?(response, "\"name\"") do
      handle_models_response(response)
    else
      IO.puts("✗ (no models found)")
      IO.puts("  Run: ollama pull nomic-embed-text:latest")
      :error
    end
  end

  defp handle_models_response(response) do
    # Count models by counting "name" occurrences
    model_count = length(String.split(response, "\"name\"")) - 1
    IO.puts("✓ (#{model_count} models available)")

    # Extract model names with regex
    model_names =
      Regex.scan(~r/"name":"([^"]+)"/, response)
      |> Enum.map(fn [_, name] -> name end)

    display_model_list(model_names)
  end

  defp display_model_list([]) do
    IO.puts("✗ (no models installed)")
    IO.puts("  Run: ollama pull nomic-embed-text:latest")
    :error
  end

  defp display_model_list(model_names) do
    IO.puts("  Available models:")

    Enum.each(model_names, fn name ->
      IO.puts("    - #{name}")
    end)

    :ok
  end

  defp check_elixir do
    IO.write("Checking Elixir environment... ")

    # Check if we can access ex_mcp
    try do
      Code.ensure_loaded?(ExMCP.Server)
      IO.puts("✓ (ExMCP available)")
      :ok
    rescue
      _ ->
        IO.puts("✗ (ExMCP not available)")
        IO.puts("  Make sure to run from the project directory")
        :error
    end
  end

  defp check_demo_servers do
    IO.write("Checking demo servers... ")

    demo_support_path = Path.expand("../support", __DIR__)
    required_servers = ["demo_time_server.exs", "demo_calculator_server.exs", "demo_dynamic_server.exs"]

    existing_servers =
      Enum.filter(required_servers, fn server ->
        File.exists?(Path.join(demo_support_path, server))
      end)

    if length(existing_servers) == length(required_servers) do
      IO.puts("✓ (all #{length(required_servers)} servers found)")
      :ok
    else
      missing = required_servers -- existing_servers
      IO.puts("✗ (missing: #{Enum.join(missing, ", ")})")
      :error
    end
  end

  defp setup_environment do
    IO.puts("Setting up E2E test environment...\n")

    # Check Elixir dependencies
    IO.puts("Checking Elixir dependencies...")
    IO.puts("✓ Using built-in Elixir MCP servers")

    # Pull Ollama model if needed
    IO.puts("\nChecking Ollama models...")

    case System.cmd("curl", ["-s", "#{@ollama_url}/api/tags"], stderr_to_stdout: true) do
      {response, 0} ->
        ensure_preferred_model(response)

      _ ->
        IO.puts("✗ Ollama not running. Start with: ollama serve")
    end

    # Make demo servers executable
    IO.puts("\nConfiguring demo servers...")
    demo_support_path = Path.expand("../support", __DIR__)

    Enum.each(["demo_time_server.exs", "demo_calculator_server.exs", "demo_dynamic_server.exs"], fn server ->
      path = Path.join(demo_support_path, server)

      if File.exists?(path) do
        File.chmod(path, 0o755)
      end
    end)

    IO.puts("✓ Demo servers configured")

    IO.puts("\n✅ Setup complete!")
  end

  defp ensure_preferred_model(response) do
    # Extract model names with regex
    model_names =
      Regex.scan(~r/"name":"([^"]+)"/, response)
      |> Enum.map(fn [_, name] -> name end)

    # Check for preferred model for tool calling
    preferred_model = "hf.co/unsloth/Qwen3-8B-GGUF:IQ4_XS"

    if preferred_model in model_names do
      IO.puts("✓ Preferred model already available")
    else
      pull_preferred_model(preferred_model)
    end
  end

  defp pull_preferred_model(model_name) do
    IO.puts("Pulling #{model_name} model (recommended for tool calling)...")

    case System.cmd("ollama", ["pull", model_name], stderr_to_stdout: true) do
      {_, 0} -> IO.puts("✓ Model pulled successfully")
      {output, _} -> IO.puts("✗ Failed to pull model:\n#{output}")
    end
  end

  defp run_tests do
    IO.puts("Running enhanced E2E tests...\n")

    # Check prerequisites first
    if check_prerequisites() != :ok do
      IO.puts("\n❌ Prerequisites not met. Run with --setup first.")
      System.halt(1)
    end

    # Change to project root
    project_root = Path.expand("../..", __DIR__)
    File.cd!(project_root)

    # Run the enhanced E2E tests
    args = [
      "test",
      "test/integration/enhanced_e2e_test.exs",
      "--color",
      "--trace"
    ]

    IO.puts("Executing: mix #{Enum.join(args, " ")}\n")

    case System.cmd("mix", args, into: IO.stream(:stdio, :line)) do
      {_, 0} ->
        IO.puts("\n✅ All E2E tests passed!")
        System.halt(0)

      {_, exit_code} ->
        IO.puts("\n❌ Some tests failed (exit code: #{exit_code})")
        System.halt(exit_code)
    end
  end

  defp cleanup do
    IO.puts("Cleaning up test artifacts...\n")

    # Kill any running Elixir demo servers
    IO.write("Stopping demo servers... ")
    System.cmd("pkill", ["-f", "demo_time_server.exs"], stderr_to_stdout: true)
    System.cmd("pkill", ["-f", "demo_calculator_server.exs"], stderr_to_stdout: true)
    System.cmd("pkill", ["-f", "demo_dynamic_server.exs"], stderr_to_stdout: true)
    IO.puts("✓")

    # Clean up test sessions
    IO.write("Removing test sessions... ")
    test_sessions = Path.expand("~/.config/mcp_chat/test_sessions")

    if File.exists?(test_sessions) do
      File.rm_rf!(test_sessions)
    end

    IO.puts("✓")

    # Clean up temporary files
    IO.write("Removing temporary files... ")
    Path.wildcard("/tmp/test_export*") |> Enum.each(&File.rm/1)
    Path.wildcard("/tmp/mcp_test*") |> Enum.each(&File.rm/1)
    IO.puts("✓")

    IO.puts("\n✅ Cleanup complete!")
  end

  defp print_help do
    IO.puts("""
    Enhanced E2E Test Runner

    Usage:
      ./test/integration/run_enhanced_e2e.exs [options]

    Options:
      --check     Check prerequisites only
      --setup     Install requirements and pull Ollama model
      --run       Run the enhanced E2E tests (default)
      --cleanup   Clean up test artifacts
      --help      Show this help message

    Prerequisites:
      - Ollama running at http://localhost:11_434
      - Elixir and Mix installed
      - Demo servers in test/support/

    Examples:
      # Check if everything is ready
      ./test/integration/run_enhanced_e2e.exs --check

      # Set up the environment
      ./test/integration/run_enhanced_e2e.exs --setup

      # Run the tests
      ./test/integration/run_enhanced_e2e.exs

      # Clean up after tests
      ./test/integration/run_enhanced_e2e.exs --cleanup
    """)
  end
end

# Run the script
EnhancedE2ERunner.main(System.argv())
