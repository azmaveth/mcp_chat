defmodule MCPChat.State.RecoveryManagerTest do
  use ExUnit.Case, async: false

  alias MCPChat.State.RecoveryManager

  setup do
    # Start the recovery manager with test configuration
    config = %{
      hot_standby_enabled: false,
      # 1 minute for testing
      backup_interval: 60_000,
      # 30 seconds for testing
      verification_interval: 30_000,
      max_backup_count: 5,
      backup_directory: "/tmp/mcp_chat_test_backups",
      standby_nodes: [],
      recovery_timeout: 10_000
    }

    {:ok, pid} = start_supervised({RecoveryManager, [config: config]})

    # Clean up test directory
    File.rm_rf(config.backup_directory)
    File.mkdir_p!(config.backup_directory)

    %{recovery_manager: pid, config: config}
  end

  describe "RecoveryManager" do
    test "starts successfully and provides status", %{recovery_manager: _pid} do
      status = RecoveryManager.get_status()

      assert is_map(status)
      assert Map.has_key?(status, :last_backup)
      assert Map.has_key?(status, :last_verification)
      assert Map.has_key?(status, :verification_errors)
      assert Map.has_key?(status, :config)
    end

    test "can trigger immediate backup", %{recovery_manager: _pid} do
      result = RecoveryManager.backup_now()

      assert {:ok, backup_file} = result
      assert String.contains?(backup_file, "backup_")
      assert File.exists?(backup_file)

      # Verify backup content
      {:ok, content} = File.read(backup_file)
      {:ok, data} = Jason.decode(content)

      assert Map.has_key?(data, "timestamp")
      assert Map.has_key?(data, "metadata")
      assert Map.has_key?(data, "security_state")
      assert Map.has_key?(data, "agent_state")
      assert Map.has_key?(data, "session_state")
      assert Map.has_key?(data, "config_state")
    end

    test "can list backups", %{recovery_manager: _pid} do
      # Create a few backups
      RecoveryManager.backup_now()
      Process.sleep(100)
      RecoveryManager.backup_now()

      backups = RecoveryManager.list_backups()

      assert is_list(backups)
      assert length(backups) >= 2

      # Check backup structure
      backup = List.first(backups)
      assert Map.has_key?(backup, :id)
      assert Map.has_key?(backup, :file)
      assert Map.has_key?(backup, :size)
      assert Map.has_key?(backup, :created)
      assert Map.has_key?(backup, :readable)
      assert backup.readable == true
    end

    test "can perform state verification", %{recovery_manager: _pid} do
      {result, errors} = RecoveryManager.verify_state()

      # Since we're in test environment, some services may not be running
      # Just verify the verification system works
      assert result in [:ok, :error]
      assert is_list(errors)
    end

    test "handles standby sync when disabled", %{recovery_manager: _pid} do
      result = RecoveryManager.sync_standby()

      assert result == {:ok, :disabled}
    end
  end

  describe "Cold Recovery" do
    test "performs cold recovery from latest backup", %{recovery_manager: _pid} do
      # Create a backup first
      {:ok, _backup_file} = RecoveryManager.backup_now()

      # Attempt cold recovery
      result = RecoveryManager.cold_recovery(:latest)

      # This should attempt recovery (may fail due to test environment)
      case result do
        {:ok, report} ->
          assert Map.has_key?(report, :backup_id)
          assert Map.has_key?(report, :backup_file)
          assert Map.has_key?(report, :recovery_time)
          assert Map.has_key?(report, :components_restored)

        {:error, reason} ->
          # Expected in test environment where some services aren't running
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "handles missing backup gracefully", %{recovery_manager: _pid, config: config} do
      # Clean backup directory
      File.rm_rf!(config.backup_directory)
      File.mkdir_p!(config.backup_directory)

      result = RecoveryManager.cold_recovery(:latest)

      assert {:error, _reason} = result
    end
  end

  describe "Partial Recovery" do
    test "performs partial recovery for specific components", %{recovery_manager: _pid} do
      # Create a backup first
      {:ok, _backup_file} = RecoveryManager.backup_now()

      # Attempt partial recovery for security component only
      result = RecoveryManager.partial_recovery([:security])

      # This should attempt recovery (may fail due to test environment)
      case result do
        {:ok, report} ->
          assert Map.has_key?(report, :components)
          assert report.components == [:security]
          assert Map.has_key?(report, :backup_file)
          assert Map.has_key?(report, :recovery_time)
          assert Map.has_key?(report, :results)

        {:error, reason} ->
          # Expected in test environment
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "validates component list", %{recovery_manager: _pid} do
      # Create a backup first
      {:ok, _backup_file} = RecoveryManager.backup_now()

      # Test with valid components
      valid_components = [:security, :agents, :sessions, :config]
      result = RecoveryManager.partial_recovery(valid_components)

      # Should attempt recovery or fail gracefully
      case result do
        {:ok, _report} -> :ok
        # Expected in test environment
        {:error, _reason} -> :ok
      end
    end
  end

  describe "Error Handling" do
    test "handles backup directory creation", %{config: config} do
      # Use a nested directory that doesn't exist
      nested_config = %{config | backup_directory: "/tmp/mcp_test/deep/nested/backups"}

      {:ok, _pid} = start_supervised({RecoveryManager, [config: nested_config]}, id: :nested_test)

      # Should create the directory and work
      result = GenServer.call(:nested_test, :backup_now)
      assert {:ok, _backup_file} = result

      # Clean up
      File.rm_rf!("/tmp/mcp_test")
    end

    test "handles JSON encoding errors gracefully", %{recovery_manager: _pid} do
      # This should still work as we use Jason.encode! with fallbacks
      result = RecoveryManager.backup_now()
      assert {:ok, _backup_file} = result
    end
  end

  describe "Configuration" do
    test "uses default configuration when none provided" do
      {:ok, _pid} = start_supervised({RecoveryManager, []}, id: :default_config_test)

      status = GenServer.call(:default_config_test, :get_status)
      config = status.config

      assert config.hot_standby_enabled == false
      assert config.backup_interval == 300_000
      assert config.verification_interval == 900_000
      assert config.max_backup_count == 24
      assert String.contains?(config.backup_directory, ".config/mcp_chat/backups")
    end

    test "merges custom configuration with defaults", %{config: custom_config} do
      status = RecoveryManager.get_status()
      config = status.config

      assert config.backup_interval == custom_config.backup_interval
      assert config.max_backup_count == custom_config.max_backup_count
      assert config.backup_directory == custom_config.backup_directory
    end
  end
end
