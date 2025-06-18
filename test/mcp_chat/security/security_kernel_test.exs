defmodule MCPChat.Security.SecurityKernelTest do
  @moduledoc """
  Unit tests for the SecurityKernel GenServer.

  Tests the central security authority including capability management,
  permission validation, delegation handling, and system-wide security
  operations.
  """

  use ExUnit.Case, async: false

  alias MCPChat.Security.{SecurityKernel, Capability}

  @test_timeout 5000

  setup do
    # Start a fresh SecurityKernel for each test
    {:ok, pid} = SecurityKernel.start_link([])

    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end
    end)

    %{kernel_pid: pid}
  end

  describe "SecurityKernel initialization" do
    test "starts with empty state", %{kernel_pid: _pid} do
      stats = SecurityKernel.get_security_stats()

      assert stats.total_capabilities == 0
      assert stats.active_capabilities == 0
      assert stats.total_principals == 0
      assert stats.delegation_relationships == 0
      assert is_map(stats.performance_stats)
    end

    test "loads security policies on startup", %{kernel_pid: _pid} do
      stats = SecurityKernel.get_security_stats()

      # Should have some default policies loaded
      assert is_map(stats)
    end
  end

  describe "capability request handling" do
    test "creates and stores filesystem capability", %{kernel_pid: _pid} do
      resource_type = :filesystem
      constraints = %{paths: ["/tmp"], operations: [:read, :write]}
      principal_id = "test_principal"

      assert {:ok, capability} = SecurityKernel.request_capability(resource_type, constraints, principal_id)

      # Verify capability properties
      assert capability.resource_type == resource_type
      assert capability.constraints == constraints
      assert capability.principal_id == principal_id
      assert is_binary(capability.id)
      assert capability.delegation_depth == 0

      # Verify it's stored in the kernel
      {:ok, capabilities} = SecurityKernel.list_capabilities(principal_id)
      assert length(capabilities) == 1
      assert hd(capabilities).id == capability.id
    end

    test "creates MCP tool capability", %{kernel_pid: _pid} do
      constraints = %{allowed_tools: ["calculator"], operations: [:execute]}

      assert {:ok, capability} = SecurityKernel.request_capability(:mcp_tool, constraints, "test")

      assert capability.resource_type == :mcp_tool
      assert capability.constraints.allowed_tools == ["calculator"]
    end

    test "applies security policies during capability creation", %{kernel_pid: _pid} do
      # Request capability with path not in default policy
      constraints = %{paths: ["/etc"], operations: [:read]}

      # This should be rejected by the default path restriction policy
      assert {:error, :path_not_allowed} = SecurityKernel.request_capability(:filesystem, constraints, "test")
    end

    test "allows valid paths per security policy", %{kernel_pid: _pid} do
      # Request capability with allowed path
      constraints = %{paths: ["/tmp"], operations: [:read]}

      assert {:ok, _capability} = SecurityKernel.request_capability(:filesystem, constraints, "test")
    end

    test "rejects invalid operations per security policy", %{kernel_pid: _pid} do
      # Request capability with operation not in default policy
      constraints = %{paths: ["/tmp"], operations: [:delete]}

      assert {:error, :operation_not_allowed} = SecurityKernel.request_capability(:filesystem, constraints, "test")
    end
  end

  describe "capability validation" do
    test "validates existing capability successfully", %{kernel_pid: _pid} do
      {:ok, capability} = SecurityKernel.request_capability(:filesystem, %{paths: ["/tmp"]}, "test")

      assert :ok = SecurityKernel.validate_capability(capability, :read, "/tmp/test.txt")
    end

    test "rejects validation for non-existent capability", %{kernel_pid: _pid} do
      # Create a capability but don't store it in kernel
      {:ok, fake_capability} = Capability.create(:filesystem, %{paths: ["/tmp"]}, "test")

      assert {:error, :capability_not_found} =
               SecurityKernel.validate_capability(fake_capability, :read, "/tmp/test.txt")
    end

    test "rejects validation for tampered capability", %{kernel_pid: _pid} do
      {:ok, capability} = SecurityKernel.request_capability(:filesystem, %{paths: ["/tmp"]}, "test")

      # Tamper with the capability
      tampered_capability = %{capability | signature: "invalid_signature"}

      assert {:error, :capability_signature_mismatch} =
               SecurityKernel.validate_capability(tampered_capability, :read, "/tmp/test.txt")
    end

    test "rejects validation for expired capability", %{kernel_pid: _pid} do
      # Create capability that expires immediately
      past_time = DateTime.add(DateTime.utc_now(), -1, :second)
      constraints = %{paths: ["/tmp"], expires_at: past_time}

      {:ok, capability} = SecurityKernel.request_capability(:filesystem, constraints, "test")

      assert {:error, :capability_expired} = SecurityKernel.validate_capability(capability, :read, "/tmp/test.txt")
    end

    test "updates performance statistics on validation", %{kernel_pid: _pid} do
      {:ok, capability} = SecurityKernel.request_capability(:filesystem, %{paths: ["/tmp"]}, "test")

      initial_stats = SecurityKernel.get_security_stats()
      initial_validated = initial_stats.performance_stats.capabilities_validated

      SecurityKernel.validate_capability(capability, :read, "/tmp/test.txt")

      updated_stats = SecurityKernel.get_security_stats()
      updated_validated = updated_stats.performance_stats.capabilities_validated

      assert updated_validated == initial_validated + 1
    end
  end

  describe "capability delegation" do
    test "successfully delegates capability with additional constraints", %{kernel_pid: _pid} do
      # Create parent capability
      parent_constraints = %{paths: ["/tmp", "/var/tmp"], operations: [:read, :write]}
      {:ok, parent} = SecurityKernel.request_capability(:filesystem, parent_constraints, "parent")

      # Delegate with more restrictive constraints
      additional_constraints = %{operations: [:read]}

      assert {:ok, delegated} = SecurityKernel.delegate_capability(parent, "child", additional_constraints)

      # Verify delegation properties
      assert delegated.principal_id == "child"
      assert delegated.parent_id == parent.id
      assert delegated.delegation_depth == 1

      # Verify delegated capability is stored
      {:ok, child_capabilities} = SecurityKernel.list_capabilities("child")
      assert length(child_capabilities) == 1
      assert hd(child_capabilities).id == delegated.id
    end

    test "prevents delegation of non-existent capability", %{kernel_pid: _pid} do
      {:ok, fake_capability} = Capability.create(:filesystem, %{paths: ["/tmp"]}, "test")

      assert {:error, :capability_not_found} = SecurityKernel.delegate_capability(fake_capability, "child", %{})
    end

    test "prevents delegation beyond max_delegations limit", %{kernel_pid: _pid} do
      constraints = %{paths: ["/tmp"], max_delegations: 0}
      {:ok, capability} = SecurityKernel.request_capability(:filesystem, constraints, "parent")

      assert {:error, :delegation_not_allowed} = SecurityKernel.delegate_capability(capability, "child", %{})
    end

    test "tracks delegation relationships", %{kernel_pid: _pid} do
      {:ok, parent} = SecurityKernel.request_capability(:filesystem, %{paths: ["/tmp"]}, "parent")
      {:ok, _child} = SecurityKernel.delegate_capability(parent, "child", %{})

      stats = SecurityKernel.get_security_stats()
      assert stats.delegation_relationships == 1
    end
  end

  describe "capability revocation" do
    test "revokes capability and all delegated children", %{kernel_pid: _pid} do
      # Create delegation chain
      {:ok, parent} = SecurityKernel.request_capability(:filesystem, %{paths: ["/tmp"]}, "parent")
      {:ok, child1} = SecurityKernel.delegate_capability(parent, "child1", %{})
      {:ok, child2} = SecurityKernel.delegate_capability(child1, "child2", %{})

      # Revoke parent capability
      assert :ok = SecurityKernel.revoke_capability(parent, "test_revocation")

      # All capabilities should be marked as revoked
      # Note: The test would need to be enhanced to verify this fully
      # since we can't easily inspect internal state in this test structure
      stats = SecurityKernel.get_security_stats()
      assert stats.performance_stats.capabilities_revoked >= 3
    end

    test "handles revocation of non-existent capability", %{kernel_pid: _pid} do
      {:ok, fake_capability} = Capability.create(:filesystem, %{paths: ["/tmp"]}, "test")

      assert {:error, :capability_not_found} = SecurityKernel.revoke_capability(fake_capability, "test")
    end
  end

  describe "permission checking" do
    test "grants permission when principal has valid capability", %{kernel_pid: _pid} do
      principal_id = "test_principal"

      {:ok, _capability} =
        SecurityKernel.request_capability(:filesystem, %{paths: ["/tmp"], operations: [:read]}, principal_id)

      assert :ok = SecurityKernel.check_permission(principal_id, :filesystem, :read, "/tmp/test.txt")
    end

    test "denies permission when principal lacks capability", %{kernel_pid: _pid} do
      principal_id = "no_caps_principal"

      assert {:error, :permission_denied} =
               SecurityKernel.check_permission(principal_id, :filesystem, :read, "/tmp/test.txt")
    end

    test "denies permission when capability doesn't match resource", %{kernel_pid: _pid} do
      principal_id = "test_principal"

      {:ok, _capability} =
        SecurityKernel.request_capability(:filesystem, %{paths: ["/tmp"], operations: [:read]}, principal_id)

      # Try to access different path
      assert {:error, :permission_denied} =
               SecurityKernel.check_permission(principal_id, :filesystem, :read, "/home/test.txt")
    end

    test "handles multiple capabilities for same principal", %{kernel_pid: _pid} do
      principal_id = "multi_cap_principal"

      # Create multiple capabilities
      {:ok, _cap1} =
        SecurityKernel.request_capability(:filesystem, %{paths: ["/tmp"], operations: [:read]}, principal_id)

      {:ok, _cap2} = SecurityKernel.request_capability(:mcp_tool, %{allowed_tools: ["calculator"]}, principal_id)

      # Should be able to use both
      assert :ok = SecurityKernel.check_permission(principal_id, :filesystem, :read, "/tmp/test.txt")
      assert :ok = SecurityKernel.check_permission(principal_id, :mcp_tool, :execute, "calculator")
    end
  end

  describe "capability listing" do
    test "lists capabilities for principal", %{kernel_pid: _pid} do
      principal_id = "test_principal"

      # Create multiple capabilities
      {:ok, cap1} = SecurityKernel.request_capability(:filesystem, %{paths: ["/tmp"]}, principal_id)
      {:ok, cap2} = SecurityKernel.request_capability(:mcp_tool, %{allowed_tools: ["calc"]}, principal_id)

      {:ok, capabilities} = SecurityKernel.list_capabilities(principal_id)

      assert length(capabilities) == 2
      capability_ids = Enum.map(capabilities, & &1.id)
      assert cap1.id in capability_ids
      assert cap2.id in capability_ids
    end

    test "returns empty list for principal with no capabilities", %{kernel_pid: _pid} do
      {:ok, capabilities} = SecurityKernel.list_capabilities("no_caps_principal")

      assert capabilities == []
    end

    test "excludes revoked capabilities from listing", %{kernel_pid: _pid} do
      principal_id = "test_principal"

      {:ok, cap1} = SecurityKernel.request_capability(:filesystem, %{paths: ["/tmp"]}, principal_id)
      {:ok, cap2} = SecurityKernel.request_capability(:mcp_tool, %{allowed_tools: ["calc"]}, principal_id)

      # Revoke one capability
      SecurityKernel.revoke_capability(cap1, "test")

      {:ok, capabilities} = SecurityKernel.list_capabilities(principal_id)

      # Should only return non-revoked capabilities
      assert length(capabilities) == 1
      assert hd(capabilities).id == cap2.id
    end
  end

  describe "system statistics and monitoring" do
    test "tracks capability creation statistics", %{kernel_pid: _pid} do
      initial_stats = SecurityKernel.get_security_stats()
      initial_created = initial_stats.performance_stats.capabilities_created

      SecurityKernel.request_capability(:filesystem, %{paths: ["/tmp"]}, "test1")
      SecurityKernel.request_capability(:mcp_tool, %{allowed_tools: ["calc"]}, "test2")

      updated_stats = SecurityKernel.get_security_stats()
      updated_created = updated_stats.performance_stats.capabilities_created

      assert updated_created == initial_created + 2
    end

    test "tracks delegation statistics", %{kernel_pid: _pid} do
      {:ok, parent} = SecurityKernel.request_capability(:filesystem, %{paths: ["/tmp"]}, "parent")

      initial_stats = SecurityKernel.get_security_stats()
      initial_delegated = initial_stats.performance_stats.capabilities_delegated

      SecurityKernel.delegate_capability(parent, "child", %{})

      updated_stats = SecurityKernel.get_security_stats()
      updated_delegated = updated_stats.performance_stats.capabilities_delegated

      assert updated_delegated == initial_delegated + 1
    end

    test "tracks validation failure statistics", %{kernel_pid: _pid} do
      {:ok, capability} =
        SecurityKernel.request_capability(:filesystem, %{paths: ["/tmp"], operations: [:read]}, "test")

      initial_stats = SecurityKernel.get_security_stats()
      initial_failures = initial_stats.performance_stats.validation_failures

      # Cause a validation failure
      # Write not allowed
      SecurityKernel.validate_capability(capability, :write, "/tmp/test.txt")

      updated_stats = SecurityKernel.get_security_stats()
      updated_failures = updated_stats.performance_stats.validation_failures

      assert updated_failures == initial_failures + 1
    end

    test "provides comprehensive system statistics", %{kernel_pid: _pid} do
      # Create some test data
      {:ok, cap1} = SecurityKernel.request_capability(:filesystem, %{paths: ["/tmp"]}, "principal1")
      {:ok, _cap2} = SecurityKernel.request_capability(:mcp_tool, %{allowed_tools: ["calc"]}, "principal2")
      {:ok, _delegated} = SecurityKernel.delegate_capability(cap1, "child", %{})

      stats = SecurityKernel.get_security_stats()

      # Verify all expected fields are present
      assert is_integer(stats.total_capabilities)
      assert is_integer(stats.active_capabilities)
      assert is_integer(stats.total_principals)
      assert is_integer(stats.delegation_relationships)
      assert is_integer(stats.audit_buffer_size)
      assert %DateTime{} = stats.last_cleanup
      assert is_map(stats.performance_stats)

      # Verify some expected values
      assert stats.total_capabilities >= 3
      assert stats.total_principals >= 2
      assert stats.delegation_relationships >= 1
    end
  end

  describe "cleanup operations" do
    test "cleans up expired capabilities automatically", %{kernel_pid: _pid} do
      # Create capability that expires quickly
      past_time = DateTime.add(DateTime.utc_now(), -1, :second)
      constraints = %{paths: ["/tmp"], expires_at: past_time}

      {:ok, _expired_cap} = SecurityKernel.request_capability(:filesystem, constraints, "test")

      initial_stats = SecurityKernel.get_security_stats()
      initial_total = initial_stats.total_capabilities

      # Trigger cleanup
      SecurityKernel.cleanup_expired_capabilities()

      updated_stats = SecurityKernel.get_security_stats()
      updated_total = updated_stats.total_capabilities

      # Expired capability should be removed
      assert updated_total < initial_total
    end

    test "preserves non-expired capabilities during cleanup", %{kernel_pid: _pid} do
      # Create non-expired capability
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)
      constraints = %{paths: ["/tmp"], expires_at: future_time}

      {:ok, valid_cap} = SecurityKernel.request_capability(:filesystem, constraints, "test")

      # Trigger cleanup
      SecurityKernel.cleanup_expired_capabilities()

      # Capability should still be valid
      assert :ok = SecurityKernel.validate_capability(valid_cap, :read, "/tmp/test.txt")
    end
  end

  describe "concurrent operations" do
    test "handles concurrent capability requests", %{kernel_pid: _pid} do
      # Create multiple concurrent requests
      tasks =
        Enum.map(1..20, fn i ->
          Task.async(fn ->
            SecurityKernel.request_capability(:filesystem, %{paths: ["/tmp/#{i}"]}, "concurrent_test_#{i}")
          end)
        end)

      results = Task.await_many(tasks, @test_timeout)

      # All requests should succeed
      assert Enum.all?(results, fn
               {:ok, _capability} -> true
               _ -> false
             end)

      # Verify all capabilities are tracked
      stats = SecurityKernel.get_security_stats()
      assert stats.total_capabilities >= 20
    end

    test "handles concurrent validation requests", %{kernel_pid: _pid} do
      # Create a capability
      {:ok, capability} =
        SecurityKernel.request_capability(:filesystem, %{paths: ["/tmp"], operations: [:read]}, "test")

      # Create multiple concurrent validation requests
      tasks =
        Enum.map(1..50, fn i ->
          Task.async(fn ->
            SecurityKernel.validate_capability(capability, :read, "/tmp/test#{i}.txt")
          end)
        end)

      results = Task.await_many(tasks, @test_timeout)

      # All validations should succeed
      assert Enum.all?(results, fn result -> result == :ok end)
    end
  end
end
