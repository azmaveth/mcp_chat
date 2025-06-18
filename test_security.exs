#!/usr/bin/env elixir

defmodule SecurityTestRunner do
  @moduledoc """
  Comprehensive test runner for the MCP Chat Security Model.
  
  This script runs all security-related tests including unit tests,
  integration tests, and supervision tests. It provides detailed
  reporting and ensures the security system is production-ready.
  
  Usage:
    ./test_security.exs                    # Run all security tests
    ./test_security.exs --unit             # Run only unit tests
    ./test_security.exs --integration      # Run only integration tests
    ./test_security.exs --supervision      # Run only supervision tests
    ./test_security.exs --verbose          # Verbose output
    ./test_security.exs --quick            # Quick test suite (subset)
  """

  @test_categories %{
    unit: [
      "test/mcp_chat/security/capability_test.exs",
      "test/mcp_chat/security/security_kernel_test.exs", 
      "test/mcp_chat/security/audit_logger_test.exs",
      "test/mcp_chat/security/mcp_security_adapter_test.exs"
    ],
    integration: [
      "test/integration/security_integration_test.exs"
    ],
    supervision: [
      "test/integration/security_supervision_test.exs"
    ]
  }

  @quick_tests [
    "test/mcp_chat/security/capability_test.exs",
    "test/integration/security_integration_test.exs"
  ]

  def main(args \\ []) do
    IO.puts("🔒 MCP Chat Security Model Test Runner")
    IO.puts("=====================================\n")
    
    case parse_args(args) do
      {:ok, options} ->
        run_tests(options)
      {:error, message} ->
        IO.puts("❌ Error: #{message}")
        print_help()
        System.halt(1)
    end
  end

  defp parse_args(args) do
    options = %{
      categories: [:unit, :integration, :supervision],
      verbose: false,
      quick: false
    }
    
    case parse_args(args, options) do
      {:ok, opts} -> {:ok, opts}
      {:error, msg} -> {:error, msg}
    end
  end

  defp parse_args([], options), do: {:ok, options}
  
  defp parse_args(["--unit" | rest], options) do
    parse_args(rest, %{options | categories: [:unit]})
  end
  
  defp parse_args(["--integration" | rest], options) do
    parse_args(rest, %{options | categories: [:integration]})
  end
  
  defp parse_args(["--supervision" | rest], options) do
    parse_args(rest, %{options | categories: [:supervision]})
  end
  
  defp parse_args(["--verbose" | rest], options) do
    parse_args(rest, %{options | verbose: true})
  end
  
  defp parse_args(["--quick" | rest], options) do
    parse_args(rest, %{options | quick: true})
  end
  
  defp parse_args(["--help" | _rest], _options) do
    print_help()
    System.halt(0)
  end
  
  defp parse_args([unknown | _rest], _options) do
    {:error, "Unknown option: #{unknown}"}
  end

  defp run_tests(options) do
    start_time = System.monotonic_time(:millisecond)
    
    # Ensure we're in the right directory
    ensure_in_project_root()
    
    # Setup test environment
    setup_test_environment()
    
    # Get test files to run
    test_files = get_test_files(options)
    
    IO.puts("📋 Test Plan:")
    IO.puts("  Categories: #{Enum.join(options.categories, ", ")}")
    IO.puts("  Files: #{length(test_files)} test files")
    IO.puts("  Quick mode: #{options.quick}")
    IO.puts("  Verbose: #{options.verbose}\n")
    
    # Run tests
    results = run_test_files(test_files, options)
    
    # Report results
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time
    
    report_results(results, duration)
    
    # Exit with appropriate code
    if Enum.all?(results, fn {_, status} -> status == :passed end) do
      IO.puts("\n✅ All security tests passed! The security model is ready for production.")
      System.halt(0)
    else
      IO.puts("\n❌ Some security tests failed. Please review the failures above.")
      System.halt(1)
    end
  end

  defp ensure_in_project_root do
    unless File.exists?("mix.exs") do
      IO.puts("❌ Error: Please run this script from the project root directory.")
      System.halt(1)
    end
  end

  defp setup_test_environment do
    # Set test-specific environment variables
    System.put_env("MIX_ENV", "test")
    
    # Ensure security is enabled for tests
    Application.put_env(:mcp_chat, :security_enabled, true)
    Application.put_env(:mcp_chat, :disable_security_for_tests, false)
    
    IO.puts("🔧 Test environment configured")
  end

  defp get_test_files(options) do
    if options.quick do
      @quick_tests
    else
      options.categories
      |> Enum.flat_map(&Map.get(@test_categories, &1, []))
      |> Enum.uniq()
    end
  end

  defp run_test_files(test_files, options) do
    IO.puts("🚀 Running security tests...\n")
    
    Enum.map(test_files, fn test_file ->
      IO.puts("📝 Running #{test_file}...")
      
      result = run_single_test_file(test_file, options)
      
      case result do
        :passed ->
          IO.puts("  ✅ PASSED\n")
        :failed ->
          IO.puts("  ❌ FAILED\n")
        :error ->
          IO.puts("  💥 ERROR\n")
      end
      
      {test_file, result}
    end)
  end

  defp run_single_test_file(test_file, options) do
    # Check if test file exists
    unless File.exists?(test_file) do
      IO.puts("  ⚠️  Test file not found: #{test_file}")
      :error
    else
      # Build mix test command
      cmd_args = ["test", test_file]
      cmd_args = if options.verbose, do: cmd_args ++ ["--trace"], else: cmd_args
      
      # Run the test
      case System.cmd("mix", cmd_args, stderr_to_stdout: true) do
        {output, 0} ->
          if options.verbose do
            IO.puts("  Output:")
            IO.puts(indent_output(output))
          end
          :passed
          
        {output, _exit_code} ->
          IO.puts("  Output:")
          IO.puts(indent_output(output))
          :failed
      end
    end
  rescue
    error ->
      IO.puts("  Exception: #{inspect(error)}")
      :error
  end

  defp indent_output(output) do
    output
    |> String.split("\n")
    |> Enum.map(fn line -> "    #{line}" end)
    |> Enum.join("\n")
  end

  defp report_results(results, duration) do
    IO.puts("\n📊 Security Test Results")
    IO.puts("========================")
    
    passed = Enum.count(results, fn {_, status} -> status == :passed end)
    failed = Enum.count(results, fn {_, status} -> status == :failed end)
    errors = Enum.count(results, fn {_, status} -> status == :error end)
    total = length(results)
    
    IO.puts("  Total tests: #{total}")
    IO.puts("  Passed: #{passed}")
    IO.puts("  Failed: #{failed}")
    IO.puts("  Errors: #{errors}")
    IO.puts("  Duration: #{duration}ms")
    
    if failed > 0 or errors > 0 do
      IO.puts("\n❌ Failed/Error Tests:")
      
      results
      |> Enum.filter(fn {_, status} -> status in [:failed, :error] end)
      |> Enum.each(fn {test_file, status} ->
        status_icon = if status == :failed, do: "❌", else: "💥"
        IO.puts("  #{status_icon} #{test_file}")
      end)
    end
    
    # Security coverage report
    IO.puts("\n🛡️  Security Coverage Report")
    IO.puts("============================")
    
    coverage_areas = [
      {"Capability Management", check_capability_coverage(results)},
      {"Permission Validation", check_permission_coverage(results)},
      {"Audit Logging", check_audit_coverage(results)},
      {"MCP Integration", check_mcp_coverage(results)},
      {"System Integration", check_system_coverage(results)}
    ]
    
    Enum.each(coverage_areas, fn {area, covered} ->
      status = if covered, do: "✅", else: "❌"
      IO.puts("  #{status} #{area}")
    end)
  end

  defp check_capability_coverage(results) do
    capability_tests = [
      "test/mcp_chat/security/capability_test.exs",
      "test/integration/security_integration_test.exs"
    ]
    
    Enum.any?(capability_tests, fn test ->
      Enum.any?(results, fn {file, status} -> 
        String.contains?(file, test) and status == :passed 
      end)
    end)
  end

  defp check_permission_coverage(results) do
    permission_tests = [
      "test/mcp_chat/security/security_kernel_test.exs",
      "test/integration/security_integration_test.exs"
    ]
    
    Enum.any?(permission_tests, fn test ->
      Enum.any?(results, fn {file, status} -> 
        String.contains?(file, test) and status == :passed 
      end)
    end)
  end

  defp check_audit_coverage(results) do
    Enum.any?(results, fn {file, status} -> 
      String.contains?(file, "audit_logger_test.exs") and status == :passed 
    end)
  end

  defp check_mcp_coverage(results) do
    Enum.any?(results, fn {file, status} -> 
      String.contains?(file, "mcp_security_adapter_test.exs") and status == :passed 
    end)
  end

  defp check_system_coverage(results) do
    Enum.any?(results, fn {file, status} -> 
      String.contains?(file, "security_supervision_test.exs") and status == :passed 
    end)
  end

  defp print_help do
    IO.puts("""
    🔒 MCP Chat Security Model Test Runner

    Usage:
      ./test_security.exs [options]

    Options:
      --unit          Run only unit tests
      --integration   Run only integration tests  
      --supervision   Run only supervision tests
      --verbose       Enable verbose output
      --quick         Run quick test suite (subset)
      --help          Show this help message

    Examples:
      ./test_security.exs                    # Run all security tests
      ./test_security.exs --unit --verbose   # Unit tests with verbose output
      ./test_security.exs --quick            # Quick smoke test

    Test Categories:
      Unit Tests:
        - Capability creation, validation, delegation
        - SecurityKernel GenServer functionality  
        - AuditLogger event handling
        - MCP Security Adapter operations

      Integration Tests:
        - End-to-end security workflows
        - Cross-module interactions
        - Error handling and edge cases

      Supervision Tests:
        - Component restart and recovery
        - Fault tolerance
        - System integration
    """)
  end
end

# Run if called directly
if __ENV__.file == :code.get_path() |> List.first() |> Path.basename() do
  SecurityTestRunner.main(System.argv())
end