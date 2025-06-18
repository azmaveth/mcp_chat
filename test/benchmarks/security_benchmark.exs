defmodule MCPChat.SecurityBenchmark do
  @moduledoc """
  Performance benchmarks comparing Phase 1 (centralized) vs Phase 2 (token-based) security.

  Run with: mix run test/benchmarks/security_benchmark.exs
  """

  alias MCPChat.Security
  alias MCPChat.Security.{SecurityKernel, TokenIssuer, TokenValidator, KeyManager, RevocationCache}

  def run do
    # Ensure all services are started
    {:ok, _} = Application.ensure_all_started(:mcp_chat)

    IO.puts("\n🔐 Security Model Performance Benchmarks")
    IO.puts("=====================================\n")

    # Warm up
    warmup()

    # Run benchmarks
    benchmark_capability_creation()
    benchmark_capability_validation()
    benchmark_delegation()
    benchmark_revocation()
    benchmark_throughput()

    IO.puts("\n✅ Benchmarks complete!")
  end

  defp warmup do
    IO.puts("Warming up...")

    # Phase 1 warmup
    Security.set_token_mode(false)

    for _ <- 1..100 do
      {:ok, cap} = Security.request_capability(:filesystem, %{operations: [:read]}, "warmup")
      Security.validate_capability(cap, :read, "/tmp")
    end

    # Phase 2 warmup
    Security.set_token_mode(true)

    for _ <- 1..100 do
      {:ok, cap} = Security.request_capability(:filesystem, %{operations: [:read]}, "warmup")
      Security.validate_capability(cap, :read, "/tmp")
    end

    IO.puts("Warmup complete.\n")
  end

  defp benchmark_capability_creation do
    IO.puts("## Capability Creation")
    IO.puts("Creating 1000 capabilities...\n")

    # Phase 1 - Centralized
    Security.set_token_mode(false)

    phase1_time =
      :timer.tc(fn ->
        for i <- 1..1000 do
          Security.request_capability(
            :filesystem,
            %{operations: [:read, :write], paths: ["/tmp/bench_#{i}"]},
            "agent_#{i}"
          )
        end
      end)
      |> elem(0)

    # Phase 2 - Token-based
    Security.set_token_mode(true)

    phase2_time =
      :timer.tc(fn ->
        for i <- 1..1000 do
          Security.request_capability(
            :filesystem,
            %{operations: [:read, :write], paths: ["/tmp/bench_#{i}"]},
            "agent_#{i}"
          )
        end
      end)
      |> elem(0)

    print_comparison("Capability Creation", phase1_time, phase2_time, 1000)
  end

  defp benchmark_capability_validation do
    IO.puts("\n## Capability Validation")
    IO.puts("Validating 10,000 operations...\n")

    # Create capabilities for testing
    Security.set_token_mode(false)

    {:ok, phase1_cap} =
      Security.request_capability(
        :filesystem,
        %{operations: [:read, :write], resource: "/tmp/**"},
        "bench_agent"
      )

    Security.set_token_mode(true)

    {:ok, phase2_cap} =
      Security.request_capability(
        :filesystem,
        %{operations: [:read, :write], resource: "/tmp/**"},
        "bench_agent"
      )

    # Phase 1 - Centralized validation
    Security.set_token_mode(false)

    phase1_time =
      :timer.tc(fn ->
        for i <- 1..10_000 do
          Security.validate_capability(phase1_cap, :read, "/tmp/file_#{i}.txt")
        end
      end)
      |> elem(0)

    # Phase 2 - Local token validation
    Security.set_token_mode(true)

    phase2_time =
      :timer.tc(fn ->
        for i <- 1..10_000 do
          Security.validate_capability(phase2_cap, :read, "/tmp/file_#{i}.txt")
        end
      end)
      |> elem(0)

    print_comparison("Capability Validation", phase1_time, phase2_time, 10_000)
  end

  defp benchmark_delegation do
    IO.puts("\n## Capability Delegation")
    IO.puts("Delegating 500 capabilities...\n")

    # Create parent capabilities
    Security.set_token_mode(false)

    phase1_parents =
      for i <- 1..500 do
        {:ok, cap} =
          Security.request_capability(
            :network,
            %{operations: [:read, :write], resource: "https://api.example.com/**"},
            "parent_#{i}"
          )

        cap
      end

    Security.set_token_mode(true)

    phase2_parents =
      for i <- 1..500 do
        {:ok, cap} =
          Security.request_capability(
            :network,
            %{operations: [:read, :write], resource: "https://api.example.com/**"},
            "parent_#{i}"
          )

        cap
      end

    # Phase 1 - Centralized delegation
    Security.set_token_mode(false)

    phase1_time =
      :timer.tc(fn ->
        Enum.with_index(phase1_parents, fn cap, i ->
          Security.delegate_capability(cap, "child_#{i}", %{operations: [:read]})
        end)
      end)
      |> elem(0)

    # Phase 2 - Token-based delegation
    Security.set_token_mode(true)

    phase2_time =
      :timer.tc(fn ->
        Enum.with_index(phase2_parents, fn cap, i ->
          Security.delegate_capability(cap, "child_#{i}", %{operations: [:read]})
        end)
      end)
      |> elem(0)

    print_comparison("Capability Delegation", phase1_time, phase2_time, 500)
  end

  defp benchmark_revocation do
    IO.puts("\n## Capability Revocation")
    IO.puts("Revoking 1000 capabilities...\n")

    # Create capabilities to revoke
    Security.set_token_mode(false)

    phase1_caps =
      for i <- 1..1000 do
        {:ok, cap} = Security.request_capability(:process, %{operations: [:execute]}, "rev_#{i}")
        cap
      end

    Security.set_token_mode(true)

    phase2_caps =
      for i <- 1..1000 do
        {:ok, cap} = Security.request_capability(:process, %{operations: [:execute]}, "rev_#{i}")
        cap
      end

    # Phase 1 - Centralized revocation
    Security.set_token_mode(false)

    phase1_time =
      :timer.tc(fn ->
        Enum.each(phase1_caps, &Security.revoke_capability/1)
      end)
      |> elem(0)

    # Phase 2 - Token revocation
    Security.set_token_mode(true)

    phase2_time =
      :timer.tc(fn ->
        Enum.each(phase2_caps, &Security.revoke_capability/1)
      end)
      |> elem(0)

    print_comparison("Capability Revocation", phase1_time, phase2_time, 1000)
  end

  defp benchmark_throughput do
    IO.puts("\n## Throughput Test")
    IO.puts("Mixed operations for 10 seconds...\n")

    # Test duration
    # 10 seconds in milliseconds
    duration = 10_000

    # Phase 1 throughput
    Security.set_token_mode(false)
    phase1_ops = run_throughput_test(duration, false)

    # Phase 2 throughput
    Security.set_token_mode(true)
    phase2_ops = run_throughput_test(duration, true)

    IO.puts("Phase 1 (Centralized): #{phase1_ops} ops in #{duration}ms = #{phase1_ops * 1000 / duration} ops/sec")
    IO.puts("Phase 2 (Token-based): #{phase2_ops} ops in #{duration}ms = #{phase2_ops * 1000 / duration} ops/sec")
    IO.puts("Improvement: #{Float.round(phase2_ops / phase1_ops, 2)}x")
  end

  defp run_throughput_test(duration_ms, _token_mode) do
    start_time = System.monotonic_time(:millisecond)
    end_time = start_time + duration_ms
    ops = run_ops_until(end_time, 0)
    ops
  end

  defp run_ops_until(end_time, count) do
    if System.monotonic_time(:millisecond) >= end_time do
      count
    else
      # Mix of operations
      operation = rem(count, 4)

      case operation do
        0 ->
          # Create capability
          {:ok, _cap} =
            Security.request_capability(
              :filesystem,
              %{operations: [:read], resource: "/tmp/#{count}"},
              "agent_#{count}"
            )

        1 ->
          # Validate capability (reuse a created one)
          {:ok, cap} =
            Security.request_capability(
              :filesystem,
              %{operations: [:read], resource: "/tmp/**"},
              "validate_agent"
            )

          Security.validate_capability(cap, :read, "/tmp/file.txt")

        2 ->
          # Delegate capability
          {:ok, parent} =
            Security.request_capability(
              :network,
              %{operations: [:read, :write]},
              "parent_#{count}"
            )

          Security.delegate_capability(parent, "child_#{count}", %{operations: [:read]})

        3 ->
          # Revoke capability
          {:ok, cap} =
            Security.request_capability(
              :process,
              %{operations: [:execute]},
              "revoke_#{count}"
            )

          Security.revoke_capability(cap)
      end

      run_ops_until(end_time, count + 1)
    end
  end

  defp print_comparison(operation, phase1_us, phase2_us, count) do
    phase1_per_op = phase1_us / count
    phase2_per_op = phase2_us / count
    improvement = phase1_per_op / phase2_per_op

    IO.puts("Phase 1 (Centralized): #{format_time(phase1_us)} total, #{format_time(phase1_per_op)} per operation")
    IO.puts("Phase 2 (Token-based): #{format_time(phase2_us)} total, #{format_time(phase2_per_op)} per operation")
    IO.puts("Improvement: #{Float.round(improvement, 2)}x faster")

    cond do
      improvement >= 5.0 ->
        IO.puts("🚀 Significant performance improvement!")

      improvement >= 2.0 ->
        IO.puts("✨ Good performance improvement!")

      improvement >= 1.0 ->
        IO.puts("✓ Modest performance improvement")

      true ->
        IO.puts("⚠️  Performance regression detected")
    end
  end

  defp format_time(microseconds) when microseconds >= 1_000_000 do
    "#{Float.round(microseconds / 1_000_000, 2)}s"
  end

  defp format_time(microseconds) when microseconds >= 1_000 do
    "#{Float.round(microseconds / 1_000, 2)}ms"
  end

  defp format_time(microseconds) do
    "#{microseconds}μs"
  end
end

# Run the benchmarks
MCPChat.SecurityBenchmark.run()
