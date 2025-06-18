defmodule MCPChat.Security.CapabilityTest do
  @moduledoc """
  Unit tests for the Capability module.

  Tests capability creation, validation, delegation logic, constraint
  inheritance, expiration handling, and security properties.
  """

  use ExUnit.Case, async: true

  alias MCPChat.Security.Capability

  describe "capability creation" do
    test "creates valid capability with required fields" do
      resource_type = :filesystem
      constraints = %{paths: ["/tmp"], operations: [:read, :write]}
      principal_id = "test_principal"

      assert {:ok, capability} = Capability.create(resource_type, constraints, principal_id)

      # Verify required fields
      assert capability.resource_type == resource_type
      assert capability.constraints == constraints
      assert capability.principal_id == principal_id
      assert is_binary(capability.id)
      assert is_binary(capability.signature)
      assert %DateTime{} = capability.issued_at
      assert capability.delegation_depth == 0
      assert capability.revoked == false
      assert capability.parent_id == nil
    end

    test "creates capability with expiration constraint" do
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)
      constraints = %{expires_at: expires_at}

      assert {:ok, capability} = Capability.create(:filesystem, constraints, "test")

      assert capability.expires_at == expires_at
      assert capability.constraints.expires_at == expires_at
    end

    test "creates delegated capability with parent reference" do
      parent_id = "parent_capability_123"

      assert {:ok, capability} = Capability.create(:filesystem, %{}, "test", parent_id)

      assert capability.parent_id == parent_id
      assert capability.delegation_depth == 1
    end

    test "generates unique capability IDs" do
      {:ok, cap1} = Capability.create(:filesystem, %{}, "test1")
      {:ok, cap2} = Capability.create(:filesystem, %{}, "test2")

      assert cap1.id != cap2.id
      # 16 bytes hex encoded
      assert String.length(cap1.id) == 32
      assert String.length(cap2.id) == 32
    end
  end

  describe "capability validation" do
    test "validates well-formed capability" do
      {:ok, capability} = Capability.create(:filesystem, %{paths: ["/tmp"]}, "test")

      assert :ok = Capability.validate(capability)
      assert Capability.valid?(capability)
    end

    test "rejects capability with invalid signature" do
      {:ok, capability} = Capability.create(:filesystem, %{}, "test")
      tampered_capability = %{capability | signature: "invalid_signature"}

      assert {:error, :invalid_signature} = Capability.validate(tampered_capability)
      assert not Capability.valid?(tampered_capability)
    end

    test "rejects capability with missing signature" do
      {:ok, capability} = Capability.create(:filesystem, %{}, "test")
      no_sig_capability = %{capability | signature: nil}

      assert {:error, :missing_signature} = Capability.validate(no_sig_capability)
    end

    test "rejects expired capability" do
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      constraints = %{expires_at: past_time}

      {:ok, capability} = Capability.create(:filesystem, constraints, "test")

      assert {:error, :capability_expired} = Capability.validate(capability)
      assert Capability.expired?(capability)
      assert not Capability.valid?(capability)
    end

    test "validates capability with future expiration" do
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)
      constraints = %{expires_at: future_time}

      {:ok, capability} = Capability.create(:filesystem, constraints, "test")

      assert :ok = Capability.validate(capability)
      assert not Capability.expired?(capability)
      assert Capability.valid?(capability)
    end

    test "rejects malformed capability structure" do
      malformed = %Capability{
        # Invalid
        id: nil,
        resource_type: :filesystem,
        constraints: %{},
        principal_id: "test",
        issued_at: DateTime.utc_now(),
        delegation_depth: 0,
        revoked: false,
        signature: "test"
      }

      assert {:error, :invalid_capability_structure} = Capability.validate(malformed)
    end
  end

  describe "capability expiration" do
    test "expired? returns false for capability without expiration" do
      {:ok, capability} = Capability.create(:filesystem, %{}, "test")

      assert not Capability.expired?(capability)
    end

    test "expired? returns true for past expiration time" do
      past_time = DateTime.add(DateTime.utc_now(), -1, :second)

      capability = %Capability{expires_at: past_time}

      assert Capability.expired?(capability)
    end

    test "expired? returns false for future expiration time" do
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)

      capability = %Capability{expires_at: future_time}

      assert not Capability.expired?(capability)
    end
  end

  describe "capability delegation" do
    test "creates delegated capability with inherited constraints" do
      parent_constraints = %{
        paths: ["/tmp", "/var/tmp"],
        operations: [:read, :write, :execute]
      }

      {:ok, parent} = Capability.create(:filesystem, parent_constraints, "parent")

      additional_constraints = %{
        # More restrictive
        operations: [:read],
        max_delegations: 1
      }

      assert {:ok, delegated} = Capability.delegate(parent, "child", additional_constraints)

      # Verify delegation properties
      assert delegated.principal_id == "child"
      assert delegated.parent_id == parent.id
      assert delegated.delegation_depth == parent.delegation_depth + 1
      assert delegated.resource_type == parent.resource_type

      # Verify constraint inheritance (intersection)
      assert delegated.constraints.operations == [:read]
      assert delegated.constraints.max_delegations == 1

      # Parent paths should be inherited
      assert "/tmp" in delegated.constraints.paths
      assert "/var/tmp" in delegated.constraints.paths
    end

    test "delegation fails for revoked capability" do
      {:ok, capability} = Capability.create(:filesystem, %{}, "test")
      revoked_capability = Capability.revoke(capability)

      assert {:error, :delegation_not_allowed} = Capability.delegate(revoked_capability, "child", %{})
    end

    test "delegation respects max_delegations constraint" do
      constraints = %{max_delegations: 0}
      {:ok, capability} = Capability.create(:filesystem, constraints, "test")

      assert not Capability.delegatable?(capability)
      assert {:error, :delegation_not_allowed} = Capability.delegate(capability, "child", %{})
    end

    test "delegation with unlimited delegations" do
      constraints = %{max_delegations: :unlimited}
      {:ok, capability} = Capability.create(:filesystem, constraints, "test")

      assert Capability.delegatable?(capability)
      assert {:ok, _delegated} = Capability.delegate(capability, "child", %{})
    end

    test "delegation applies expiration intersection" do
      parent_expires = DateTime.add(DateTime.utc_now(), 3600, :second)
      # Earlier
      child_expires = DateTime.add(DateTime.utc_now(), 1800, :second)

      parent_constraints = %{expires_at: parent_expires}
      additional_constraints = %{expires_at: child_expires}

      {:ok, parent} = Capability.create(:filesystem, parent_constraints, "parent")
      {:ok, delegated} = Capability.delegate(parent, "child", additional_constraints)

      # Should use the earlier expiration time
      assert delegated.expires_at == child_expires
    end

    test "delegation applies path intersection" do
      parent_constraints = %{paths: ["/tmp", "/var/tmp", "/opt"]}
      # Partial overlap
      additional_constraints = %{paths: ["/tmp", "/home"]}

      {:ok, parent} = Capability.create(:filesystem, parent_constraints, "parent")
      {:ok, delegated} = Capability.delegate(parent, "child", additional_constraints)

      # Should only include intersecting paths
      assert delegated.constraints.paths == ["/tmp"]
    end
  end

  describe "capability revocation" do
    test "revoke marks capability as revoked" do
      {:ok, capability} = Capability.create(:filesystem, %{}, "test")

      assert not capability.revoked

      revoked_capability = Capability.revoke(capability)

      assert revoked_capability.revoked
      assert not Capability.valid?(revoked_capability)
    end
  end

  describe "permission checking" do
    test "permits? allows valid operations" do
      constraints = %{
        paths: ["/tmp"],
        operations: [:read, :write]
      }

      {:ok, capability} = Capability.create(:filesystem, constraints, "test")

      assert :ok = Capability.permits?(capability, :read, "/tmp/test.txt")
      assert :ok = Capability.permits?(capability, :write, "/tmp/test.txt")
    end

    test "permits? denies invalid operations" do
      constraints = %{
        paths: ["/tmp"],
        operations: [:read]
      }

      {:ok, capability} = Capability.create(:filesystem, constraints, "test")

      assert {:error, :operation_not_permitted} = Capability.permits?(capability, :write, "/tmp/test.txt")
      assert {:error, :operation_not_permitted} = Capability.permits?(capability, :execute, "/tmp/test.txt")
    end

    test "permits? denies access to restricted paths" do
      constraints = %{
        paths: ["/tmp"],
        operations: [:read, :write]
      }

      {:ok, capability} = Capability.create(:filesystem, constraints, "test")

      assert {:error, :resource_not_permitted} = Capability.permits?(capability, :read, "/home/test.txt")
      assert {:error, :resource_not_permitted} = Capability.permits?(capability, :read, "/etc/passwd")
    end

    test "permits? allows access without operation constraints" do
      # No operations specified
      constraints = %{paths: ["/tmp"]}

      {:ok, capability} = Capability.create(:filesystem, constraints, "test")

      # Should allow any operation when no operation constraints
      assert :ok = Capability.permits?(capability, :read, "/tmp/test.txt")
      assert :ok = Capability.permits?(capability, :write, "/tmp/test.txt")
      assert :ok = Capability.permits?(capability, :execute, "/tmp/test.txt")
    end

    test "permits? allows access without path constraints" do
      # No paths specified
      constraints = %{operations: [:read]}

      {:ok, capability} = Capability.create(:filesystem, constraints, "test")

      # Should allow any path when no path constraints
      assert :ok = Capability.permits?(capability, :read, "/tmp/test.txt")
      assert :ok = Capability.permits?(capability, :read, "/home/test.txt")
    end
  end

  describe "capability summary and utilities" do
    test "to_summary provides readable representation" do
      {:ok, capability} = Capability.create(:filesystem, %{}, "test_principal")

      summary = Capability.to_summary(capability)

      assert summary =~ "filesystem"
      assert summary =~ "test_principal"
      assert summary =~ String.slice(capability.id, 0, 8)
    end

    test "delegatable? checks delegation constraints" do
      # Unlimited delegations
      {:ok, cap1} = Capability.create(:filesystem, %{max_delegations: :unlimited}, "test")
      assert Capability.delegatable?(cap1)

      # Limited delegations
      {:ok, cap2} = Capability.create(:filesystem, %{max_delegations: 2}, "test")
      assert Capability.delegatable?(cap2)

      # No delegations allowed
      {:ok, cap3} = Capability.create(:filesystem, %{max_delegations: 0}, "test")
      assert not Capability.delegatable?(cap3)
    end
  end

  describe "constraint validation" do
    test "validates expires_at constraint" do
      valid_time = DateTime.utc_now()
      invalid_time = "not_a_datetime"

      # Valid constraint
      {:ok, _cap} = Capability.create(:filesystem, %{expires_at: valid_time}, "test")

      # Invalid constraint should be rejected during validation
      constraints = %{expires_at: invalid_time}
      {:ok, capability} = Capability.create(:filesystem, constraints, "test")

      # The capability is created but validation should fail
      assert {:error, :invalid_expires_at_constraint} = Capability.validate(capability)
    end

    test "validates operations constraint" do
      # Valid operations
      valid_ops = [:read, :write, :execute]
      {:ok, _cap} = Capability.create(:filesystem, %{operations: valid_ops}, "test")

      # Invalid operations format
      invalid_ops = "not_a_list"
      constraints = %{operations: invalid_ops}
      {:ok, capability} = Capability.create(:filesystem, constraints, "test")

      assert {:error, :invalid_operations_constraint} = Capability.validate(capability)
    end

    test "validates paths constraint" do
      # Valid paths
      valid_paths = ["/tmp", "/var/tmp"]
      {:ok, _cap} = Capability.create(:filesystem, %{paths: valid_paths}, "test")

      # Invalid paths format
      # Should be a list
      invalid_paths = "/tmp"
      constraints = %{paths: invalid_paths}
      {:ok, capability} = Capability.create(:filesystem, constraints, "test")

      assert {:error, :invalid_paths_constraint} = Capability.validate(capability)
    end

    test "validates max_delegations constraint" do
      # Valid max_delegations
      {:ok, _cap1} = Capability.create(:filesystem, %{max_delegations: 5}, "test")
      {:ok, _cap2} = Capability.create(:filesystem, %{max_delegations: :unlimited}, "test")
      {:ok, _cap3} = Capability.create(:filesystem, %{max_delegations: 0}, "test")

      # Invalid max_delegations
      invalid_max = -1
      constraints = %{max_delegations: invalid_max}
      {:ok, capability} = Capability.create(:filesystem, constraints, "test")

      assert {:error, :invalid_max_delegations_constraint} = Capability.validate(capability)
    end

    test "allows unknown constraints for extensibility" do
      # Unknown constraints should be allowed
      unknown_constraints = %{custom_constraint: "value", another_one: 123}

      {:ok, capability} = Capability.create(:filesystem, unknown_constraints, "test")
      assert :ok = Capability.validate(capability)
    end
  end
end
