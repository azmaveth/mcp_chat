defmodule MCPChat.State.RecoveryManager do
  @moduledoc """
  Recovery Manager for state persistence and disaster recovery.

  Implements hot standby, cold recovery, partial recovery, and data verification
  strategies for the MCP Chat application state.
  """

  use GenServer
  require Logger

  alias MCPChat.State.{RecoveryStrategies, StateVerifier}

  @default_config %{
    hot_standby_enabled: false,
    # 5 minutes
    backup_interval: 300_000,
    # 15 minutes
    verification_interval: 900_000,
    # Keep 24 backups (2 hours at 5 min intervals)
    max_backup_count: 24,
    backup_directory: "~/.config/mcp_chat/backups",
    standby_nodes: [],
    recovery_timeout: 30_000
  }

  defstruct [
    :config,
    :backup_timer,
    :verification_timer,
    :standby_nodes,
    :last_backup_time,
    :last_verification_time,
    :verification_errors
  ]

  @doc """
  Start the Recovery Manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Trigger immediate hot standby sync.
  """
  def sync_standby do
    GenServer.call(__MODULE__, :sync_standby)
  end

  @doc """
  Trigger immediate backup.
  """
  def backup_now do
    GenServer.call(__MODULE__, :backup_now)
  end

  @doc """
  Perform cold recovery from backup.
  """
  def cold_recovery(backup_id \\ :latest) do
    GenServer.call(__MODULE__, {:cold_recovery, backup_id}, 60_000)
  end

  @doc """
  Perform partial recovery for specific components.
  """
  def partial_recovery(components) when is_list(components) do
    GenServer.call(__MODULE__, {:partial_recovery, components}, 30_000)
  end

  @doc """
  Verify system state integrity.
  """
  def verify_state do
    GenServer.call(__MODULE__, :verify_state, 30_000)
  end

  @doc """
  Get recovery status and statistics.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  List available backups.
  """
  def list_backups do
    GenServer.call(__MODULE__, :list_backups)
  end

  # GenServer callbacks

  def init(opts) do
    config = build_config(opts)

    # Ensure backup directory exists
    backup_dir = Path.expand(config.backup_directory)
    File.mkdir_p!(backup_dir)

    # Schedule periodic operations
    backup_timer = schedule_backup(config.backup_interval)
    verification_timer = schedule_verification(config.verification_interval)

    state = %__MODULE__{
      config: config,
      backup_timer: backup_timer,
      verification_timer: verification_timer,
      standby_nodes: config.standby_nodes,
      verification_errors: []
    }

    Logger.info("Recovery Manager started with config: #{inspect(config)}")
    {:ok, state}
  end

  def handle_call(:sync_standby, _from, state) do
    result = perform_standby_sync(state)
    {:reply, result, state}
  end

  def handle_call(:backup_now, _from, state) do
    result = perform_backup(state)
    new_state = %{state | last_backup_time: System.system_time(:millisecond)}
    {:reply, result, new_state}
  end

  def handle_call({:cold_recovery, backup_id}, _from, state) do
    result = RecoveryStrategies.cold_recovery(backup_id, state.config)
    {:reply, result, state}
  end

  def handle_call({:partial_recovery, components}, _from, state) do
    result = RecoveryStrategies.partial_recovery(components, state.config)
    {:reply, result, state}
  end

  def handle_call(:verify_state, _from, state) do
    {result, errors} = StateVerifier.verify_system_state()
    new_state = %{state | last_verification_time: System.system_time(:millisecond), verification_errors: errors}
    {:reply, result, new_state}
  end

  def handle_call(:get_status, _from, state) do
    status = %{
      last_backup: state.last_backup_time,
      last_verification: state.last_verification_time,
      verification_errors: length(state.verification_errors),
      standby_nodes: state.standby_nodes,
      config: state.config
    }

    {:reply, status, state}
  end

  def handle_call(:list_backups, _from, state) do
    backups = list_backup_files(state.config.backup_directory)
    {:reply, backups, state}
  end

  def handle_info(:perform_backup, state) do
    perform_backup(state)
    cleanup_old_backups(state.config)

    # Reschedule
    timer = schedule_backup(state.config.backup_interval)
    new_state = %{state | backup_timer: timer, last_backup_time: System.system_time(:millisecond)}

    {:noreply, new_state}
  end

  def handle_info(:perform_verification, state) do
    {_result, errors} = StateVerifier.verify_system_state()

    # Log verification results
    if Enum.empty?(errors) do
      Logger.info("State verification passed")
    else
      Logger.warning("State verification found errors: #{inspect(errors)}")
    end

    # Reschedule
    timer = schedule_verification(state.config.verification_interval)

    new_state = %{
      state
      | verification_timer: timer,
        last_verification_time: System.system_time(:millisecond),
        verification_errors: errors
    }

    {:noreply, new_state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp build_config(opts) do
    user_config = Keyword.get(opts, :config, %{})
    Map.merge(@default_config, user_config)
  end

  defp schedule_backup(interval) do
    Process.send_after(self(), :perform_backup, interval)
  end

  defp schedule_verification(interval) do
    Process.send_after(self(), :perform_verification, interval)
  end

  defp perform_backup(state) do
    try do
      timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)

      backup_file =
        Path.join([
          Path.expand(state.config.backup_directory),
          "backup_#{timestamp}.json"
        ])

      # Collect state from all major components
      backup_data = %{
        timestamp: timestamp,
        security_state: collect_security_state(),
        agent_state: collect_agent_state(),
        session_state: collect_session_state(),
        config_state: collect_config_state(),
        metadata: %{
          version: Application.spec(:mcp_chat, :vsn),
          node: Node.self(),
          system_time: System.system_time(:millisecond)
        }
      }

      # Write backup file
      json_data = Jason.encode!(backup_data, pretty: true)
      File.write!(backup_file, json_data)

      Logger.info("Backup created: #{backup_file}")
      {:ok, backup_file}
    rescue
      error ->
        Logger.error("Backup failed: #{inspect(error)}")
        {:error, error}
    end
  end

  defp perform_standby_sync(state) do
    if state.config.hot_standby_enabled and not Enum.empty?(state.standby_nodes) do
      results =
        Enum.map(state.standby_nodes, fn node ->
          try do
            :rpc.call(node, __MODULE__, :receive_standby_sync, [collect_sync_data()], 10_000)
          catch
            :exit, reason ->
              Logger.warning("Failed to sync with standby node #{node}: #{inspect(reason)}")
              {:error, reason}
          end
        end)

      success_count = Enum.count(results, &match?({:ok, _}, &1))
      Logger.info("Standby sync: #{success_count}/#{length(state.standby_nodes)} nodes updated")

      {:ok, %{synced: success_count, total: length(state.standby_nodes), results: results}}
    else
      {:ok, :disabled}
    end
  end

  defp collect_security_state do
    try do
      case GenServer.call(MCPChat.Security.SecurityKernel, :get_state_snapshot, 5000) do
        {:ok, state} -> state
        _ -> %{}
      end
    rescue
      _ -> %{}
    end
  end

  defp collect_agent_state do
    try do
      case GenServer.call(MCPChat.Agents.AgentSupervisor, :get_state_snapshot, 5000) do
        {:ok, state} -> state
        _ -> %{}
      end
    rescue
      _ -> %{}
    end
  end

  defp collect_session_state do
    try do
      case GenServer.call(MCPChat.Agents.SessionManager, :get_state_snapshot, 5000) do
        {:ok, state} -> state
        _ -> %{}
      end
    rescue
      _ -> %{}
    end
  end

  defp collect_config_state do
    try do
      case GenServer.call(MCPChat.Config, :get_state_snapshot, 5000) do
        {:ok, state} -> state
        _ -> %{}
      end
    rescue
      _ -> %{}
    end
  end

  defp collect_sync_data do
    %{
      security_state: collect_security_state(),
      agent_state: collect_agent_state(),
      session_state: collect_session_state(),
      sync_timestamp: System.system_time(:millisecond)
    }
  end

  defp cleanup_old_backups(config) do
    backup_dir = Path.expand(config.backup_directory)

    case File.ls(backup_dir) do
      {:ok, files} ->
        backup_files =
          files
          |> Enum.filter(&String.starts_with?(&1, "backup_"))
          |> Enum.map(&Path.join(backup_dir, &1))
          |> Enum.sort_by(&File.stat!(&1).mtime, :desc)

        # Keep only the most recent backups
        files_to_delete = Enum.drop(backup_files, config.max_backup_count)

        Enum.each(files_to_delete, fn file ->
          File.rm(file)
          Logger.debug("Deleted old backup: #{file}")
        end)

      {:error, reason} ->
        Logger.warning("Could not list backup directory: #{inspect(reason)}")
    end
  end

  defp list_backup_files(backup_dir) do
    expanded_dir = Path.expand(backup_dir)

    case File.ls(expanded_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.starts_with?(&1, "backup_"))
        |> Enum.map(fn file ->
          file_path = Path.join(expanded_dir, file)
          stat = File.stat!(file_path)

          %{
            id: Path.basename(file, ".json"),
            file: file_path,
            size: stat.size,
            created: stat.mtime,
            readable: File.exists?(file_path)
          }
        end)
        |> Enum.sort_by(& &1.created, :desc)

      {:error, reason} ->
        Logger.warning("Could not list backups: #{inspect(reason)}")
        []
    end
  end

  @doc """
  Receive standby sync data from primary node.
  This function is called via RPC on standby nodes.
  """
  def receive_standby_sync(sync_data) do
    try do
      # Apply sync data to local state
      RecoveryStrategies.apply_standby_sync(sync_data)
      {:ok, :synced}
    rescue
      error ->
        Logger.error("Failed to apply standby sync: #{inspect(error)}")
        {:error, error}
    end
  end
end
