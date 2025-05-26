#!/usr/bin/env elixir

# End-to-End Test Runner for MCP Chat
#
# This script runs comprehensive end-to-end tests using Ollama as the backend.
# Prerequisites:
# - Ollama must be running (http://localhost:11_434)
# - At least one model installed (e.g., ollama pull nomic-embed-text)
# - Python 3 installed for demo MCP servers
#
# Usage:
#   ./test/run_e2e_tests.exs [options]
#
# Options:
#   --all              Run all E2E tests (default)
#   --comprehensive    Run only comprehensive tests
#   --realtime         Run only real-time feature tests
#   --advanced         Run only advanced scenario tests
#   --quick            Run a quick smoke test
#   --setup            Install requirements and pull Ollama model

defmodule E2ETestRunner do
  @ollama_url "http://localhost:11_434"
  @required_model "nomic-embed-text:latest"
  @demo_servers_path Path.expand("../examples/demo_servers", __DIR__)

  def main(args) do
    case parse_args(args) do
      {:setup} ->
        setup_environment()

      {:run, test_suite} ->
        check_prerequisites() |> run_tests(test_suite)

      {:help} ->
        print_help()
    end
  end

  defp parse_args([]), do: {:run, :all}
  defp parse_args(["--all"]), do: {:run, :all}
  defp parse_args(["--comprehensive"]), do: {:run, :comprehensive}
  defp parse_args(["--realtime"]), do: {:run, :realtime}
  defp parse_args(["--advanced"]), do: {:run, :advanced}
  defp parse_args(["--quick"]), do: {:run, :quick}
  defp parse_args(["--setup"]), do: {:setup}
  defp parse_args(["--help"]), do: {:help}
  defp parse_args(_), do: {:help}

  defp print_help() do
    IO.puts("""
    MCP Chat E2E Test Runner

    Usage: ./test/run_e2e_tests.exs [options]

    Options:
      --all              Run all E2E tests (default)
      --comprehensive    Run only comprehensive tests
      --realtime         Run only real-time feature tests
      --advanced         Run only advanced scenario tests
      --quick            Run a quick smoke test
      --setup            Install requirements and pull Ollama model
      --help             Show this help message

    Prerequisites:
      - Ollama running at #{@ollama_url}
      - Model installed: #{@required_model}
      - Python 3 for demo MCP servers
    """)
  end

  defp setup_environment() do
    IO.puts("🔧 Setting up E2E test environment...\n")

    # Check and install Python requirements
    IO.puts("📦 Installing Python requirements for demo servers...")

    case System.cmd("pip3", ["install", "-r", Path.join(@demo_servers_path, "requirements.txt")]) do
      {output, 0} ->
        IO.puts("✅ Python requirements installed")

      {error, _} ->
        IO.puts("⚠️  Failed to install Python requirements: #{error}")
    end

    # Check and pull Ollama model
    IO.puts("\n🤖 Checking Ollama model...")

    case check_ollama_model() do
      :exists ->
        IO.puts("✅ Model #{@required_model} already installed")

      :missing ->
        IO.puts("📥 Pulling #{@required_model}...")

        case System.cmd("ollama", ["pull", @required_model]) do
          {_, 0} ->
            IO.puts("✅ Model installed successfully")

          {error, _} ->
            IO.puts("❌ Failed to pull model: #{error}")
        end
    end

    IO.puts("\n✨ Setup complete!")
  end

  defp check_prerequisites() do
    IO.puts("🔍 Checking prerequisites...\n")

    errors = []

    # Check Ollama
    errors =
      case check_ollama() do
        :ok ->
          IO.puts("✅ Ollama is running")
          errors

        {:error, reason} ->
          IO.puts("❌ Ollama check failed: #{reason}")
          ["Ollama: #{reason}" | errors]
      end

    # Check Ollama model
    errors =
      case check_ollama_model() do
        :exists ->
          IO.puts("✅ Required model installed: #{@required_model}")
          errors

        :missing ->
          IO.puts("❌ Model not installed: #{@required_model}")
          IO.puts("   Run: ollama pull #{@required_model}")
          ["Model: #{@required_model} not installed" | errors]
      end

    # Check Python
    errors =
      case System.cmd("python3", ["--version"]) do
        {version, 0} ->
          IO.puts("✅ Python 3 available: #{String.trim(version)}")
          errors

        _ ->
          IO.puts("⚠️  Python 3 not found (some tests will be limited)")
          errors
      end

    # Check demo servers
    if File.exists?(@demo_servers_path) do
      IO.puts("✅ Demo servers found")
    else
      IO.puts("⚠️  Demo servers not found at #{@demo_servers_path}")
      errors = ["Demo servers missing" | errors]
    end

    IO.puts("")

    if errors == [] do
      :ok
    else
      {:error, errors}
    end
  end

  defp check_ollama() do
    case HTTPoison.get("#{@ollama_url}/api/tags") do
      {:ok, %{status_code: 200}} ->
        :ok

      {:ok, %{status_code: code}} ->
        {:error, "Ollama returned status #{code}"}

      {:error, %{reason: reason}} ->
        {:error, "Cannot connect to Ollama: #{reason}"}
    end
  end

  defp check_ollama_model() do
    case HTTPoison.get("#{@ollama_url}/api/tags") do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"models" => models}} ->
            if Enum.any?(models, &(&1["name"] == @required_model)) do
              :exists
            else
              :missing
            end

          _ ->
            :missing
        end

      _ ->
        :missing
    end
  end

  defp run_tests(:ok, test_suite) do
    IO.puts("🚀 Running E2E tests...\n")

    test_files =
      case test_suite do
        :all ->
          [
            "test/integration/comprehensive_e2e_test.exs",
            "test/integration/realtime_features_e2e_test.exs",
            "test/integration/advanced_scenarios_e2e_test.exs"
          ]

        :comprehensive ->
          ["test/integration/comprehensive_e2e_test.exs"]

        :realtime ->
          ["test/integration/realtime_features_e2e_test.exs"]

        :advanced ->
          ["test/integration/advanced_scenarios_e2e_test.exs"]

        :quick ->
          IO.puts("Running quick smoke test...")
          run_smoke_test()
          return
      end

    # Run the test files
    Enum.each(test_files, fn file ->
      IO.puts("\n📄 Running #{Path.basename(file)}...")
      System.cmd("mix", ["test", file, "--color"], into: IO.stream(:stdio, :line))
    end)

    IO.puts("\n✅ E2E tests completed!")
  end

  defp run_tests({:error, errors}, _) do
    IO.puts("❌ Cannot run tests due to missing prerequisites:\n")

    Enum.each(errors, fn error ->
      IO.puts("  - #{error}")
    end)

    IO.puts("\nRun with --setup to install requirements")
    System.halt(1)
  end

  defp run_smoke_test() do
    # Quick test to verify basic functionality
    IO.puts("1. Testing Ollama connection...")

    # Ensure application is started
    Application.ensure_all_started(:mcp_chat)

    # Test Ollama
    config = %{
      "provider" => "ollama",
      "base_url" => @ollama_url,
      "model" => @required_model
    }

    case MCPChat.LLM.ExLLMAdapter.init(config) do
      {:ok, client} ->
        IO.puts("✅ Ollama client initialized")

        messages = [%{role: "user", content: "Say 'test passed' if you can read this"}]

        case MCPChat.LLM.ExLLMAdapter.complete(client, messages, %{}) do
          {:ok, response} ->
            if String.contains?(String.downcase(response), "test passed") do
              IO.puts("✅ Ollama response received")
            else
              IO.puts("⚠️  Unexpected response: #{response}")
            end

          {:error, reason} ->
            IO.puts("❌ Failed to get response: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("❌ Failed to initialize client: #{inspect(reason)}")
    end

    IO.puts("\n2. Testing MCP server startup...")

    # Try to start a simple server
    config = %{
      "name" => "test_time",
      "command" => "python3",
      "args" => [Path.join(@demo_servers_path, "time_server.py")]
    }

    case MCPChat.MCP.ServerManager.start_server(config) do
      {:ok, _} ->
        IO.puts("✅ MCP server started")
        Process.sleep(1_000)

        case MCPChat.MCP.ServerManager.list_tools("test_time") do
          {:ok, tools} when length(tools) > 0 ->
            IO.puts("✅ MCP tools available: #{length(tools)} tools")

          _ ->
            IO.puts("⚠️  No tools found")
        end

        MCPChat.MCP.ServerManager.stop_server("test_time")

      {:error, reason} ->
        IO.puts("⚠️  Failed to start MCP server: #{inspect(reason)}")
    end

    IO.puts("\n✅ Smoke test completed!")
  end
end

# Run the script
E2ETestRunner.main(System.argv())
