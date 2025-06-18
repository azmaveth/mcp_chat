defmodule MCPChat.CLI.Commands.Recovery do
  @moduledoc """
  Recovery and backup management commands.

  Provides commands for state persistence, backup management, and recovery operations.
  """

  alias MCPChat.State.RecoveryManager

  @doc """
  Handle recovery-related commands.
  """
  def handle_command(["backup"], _session) do
    case RecoveryManager.backup_now() do
      {:ok, backup_file} ->
        backup_name = Path.basename(backup_file)
        {:ok, "✅ Backup created: #{backup_name}"}

      {:error, reason} ->
        {:error, "❌ Backup failed: #{inspect(reason)}"}
    end
  end

  def handle_command(["backup", "list"], _session) do
    backups = RecoveryManager.list_backups()

    if Enum.empty?(backups) do
      {:ok, "📁 No backups found"}
    else
      header = "📁 Available Backups:\n\n"

      backup_list =
        backups
        |> Enum.with_index(1)
        |> Enum.map(fn {backup, index} ->
          created = format_timestamp(backup.created)
          size = format_file_size(backup.size)
          "#{index}. #{backup.id}\n   Created: #{created}\n   Size: #{size}"
        end)
        |> Enum.join("\n\n")

      {:ok, header <> backup_list}
    end
  end

  def handle_command(["backup", "status"], _session) do
    status = RecoveryManager.get_status()

    last_backup = format_optional_timestamp(status.last_backup)
    last_verification = format_optional_timestamp(status.last_verification)
    error_count = status.verification_errors

    status_text = """
    📊 Recovery System Status:

    🔄 Last Backup: #{last_backup}
    ✅ Last Verification: #{last_verification}
    ⚠️  Verification Errors: #{error_count}
    🌐 Standby Nodes: #{length(status.standby_nodes)}
    ⚙️  Hot Standby: #{if status.config.hot_standby_enabled, do: "Enabled", else: "Disabled"}
    """

    {:ok, status_text}
  end

  def handle_command(["verify"], _session) do
    {:ok, "🔍 Running state verification..."}

    case RecoveryManager.verify_state() do
      {:ok, []} ->
        {:ok, "✅ State verification passed - no errors found"}

      {:ok, errors} ->
        error_summary = format_verification_errors(errors)
        {:error, "⚠️ State verification found issues:\n\n#{error_summary}"}

      {:error, errors} ->
        error_summary = format_verification_errors(errors)
        {:error, "❌ State verification failed:\n\n#{error_summary}"}
    end
  end

  def handle_command(["recover", "cold"], _session) do
    {:ok, "🔄 Starting cold recovery from latest backup..."}

    case RecoveryManager.cold_recovery(:latest) do
      {:ok, report} ->
        success_msg = format_recovery_report(report)
        {:ok, "✅ Cold recovery completed:\n\n#{success_msg}"}

      {:error, reason} ->
        {:error, "❌ Cold recovery failed: #{inspect(reason)}"}
    end
  end

  def handle_command(["recover", "cold", backup_id], _session) do
    {:ok, "🔄 Starting cold recovery from backup: #{backup_id}..."}

    case RecoveryManager.cold_recovery(backup_id) do
      {:ok, report} ->
        success_msg = format_recovery_report(report)
        {:ok, "✅ Cold recovery completed:\n\n#{success_msg}"}

      {:error, reason} ->
        {:error, "❌ Cold recovery failed: #{inspect(reason)}"}
    end
  end

  def handle_command(["recover", "partial" | components], _session) do
    component_atoms = Enum.map(components, &String.to_existing_atom/1)

    {:ok, "🔄 Starting partial recovery for: #{Enum.join(components, ", ")}..."}

    case RecoveryManager.partial_recovery(component_atoms) do
      {:ok, report} ->
        success_msg = format_partial_recovery_report(report)
        {:ok, "✅ Partial recovery completed:\n\n#{success_msg}"}

      {:error, reason} ->
        {:error, "❌ Partial recovery failed: #{inspect(reason)}"}
    end
  end

  def handle_command(["standby", "sync"], _session) do
    case RecoveryManager.sync_standby() do
      {:ok, :disabled} ->
        {:ok, "ℹ️ Hot standby is disabled"}

      {:ok, %{synced: synced, total: total}} ->
        {:ok, "✅ Standby sync completed: #{synced}/#{total} nodes updated"}

      {:error, reason} ->
        {:error, "❌ Standby sync failed: #{inspect(reason)}"}
    end
  end

  def handle_command(["help"], _session) do
    help_text = """
    🔧 Recovery System Commands:

    📦 Backup Management:
      /recovery backup                    - Create immediate backup
      /recovery backup list               - List available backups
      /recovery backup status             - Show backup system status

    🔍 System Verification:
      /recovery verify                    - Verify system state integrity

    🔄 Recovery Operations:
      /recovery recover cold              - Cold recovery from latest backup
      /recovery recover cold <backup_id>  - Cold recovery from specific backup
      /recovery recover partial <components> - Partial recovery (security, agents, sessions, config)

    🌐 Standby Management:
      /recovery standby sync              - Sync with hot standby nodes

    📚 Examples:
      /recovery backup
      /recovery verify
      /recovery recover cold
      /recovery recover partial security agents
      /recovery standby sync
    """

    {:ok, help_text}
  end

  def handle_command(args, _session) do
    {:error, "❌ Unknown recovery command: #{Enum.join(args, " ")}\n\nUse `/recovery help` for available commands."}
  end

  # Private helper functions

  defp format_timestamp(timestamp) when is_integer(timestamp) do
    timestamp
    |> DateTime.from_unix!(:second)
    |> DateTime.to_string()
  end

  defp format_timestamp({{year, month, day}, {hour, minute, second}}) do
    "#{year}-#{pad_number(month)}-#{pad_number(day)} #{pad_number(hour)}:#{pad_number(minute)}:#{pad_number(second)}"
  end

  defp format_timestamp(_), do: "Unknown"

  defp format_optional_timestamp(nil), do: "Never"

  defp format_optional_timestamp(timestamp) do
    timestamp
    |> DateTime.from_unix!(:millisecond)
    |> DateTime.to_string()
  end

  defp format_file_size(size) when size < 1024, do: "#{size} B"
  defp format_file_size(size) when size < 1024 * 1024, do: "#{Float.round(size / 1024, 1)} KB"
  defp format_file_size(size), do: "#{Float.round(size / (1024 * 1024), 1)} MB"

  defp format_verification_errors(errors) do
    errors
    |> Enum.map(fn
      {type, details} when is_atom(type) ->
        "• #{type}: #{inspect(details)}"

      error ->
        "• #{inspect(error)}"
    end)
    |> Enum.join("\n")
  end

  defp format_recovery_report(report) do
    """
    📁 Backup: #{Path.basename(report.backup_file)}
    🕒 Recovery Time: #{DateTime.to_string(report.recovery_time)}
    ✅ Components Restored: #{length(report.components_restored)}
    📊 Success Rate: #{report.success_count}/#{report.success_count + report.failure_count}

    🔧 Components:
    #{format_component_results(report.results)}
    """
  end

  defp format_partial_recovery_report(report) do
    """
    📁 Backup: #{Path.basename(report.backup_file)}
    🕒 Recovery Time: #{DateTime.to_string(report.recovery_time)}
    🎯 Components: #{Enum.join(report.components, ", ")}

    🔧 Results:
    #{format_component_results(report.results)}
    """
  end

  defp format_component_results(results) do
    results
    |> Enum.map(fn
      {component, {:ok, _}} ->
        "  ✅ #{component}: Restored successfully"

      {component, {:error, reason}} ->
        "  ❌ #{component}: Failed (#{inspect(reason)})"
    end)
    |> Enum.join("\n")
  end

  defp pad_number(num) when num < 10, do: "0#{num}"
  defp pad_number(num), do: "#{num}"
end
