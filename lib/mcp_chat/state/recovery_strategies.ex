defmodule MCPChat.State.RecoveryStrategies do
  @moduledoc """
  Implementation of recovery strategies for state persistence.

  Provides hot standby, cold recovery, and partial recovery capabilities.
  """

  require Logger

  @doc """
  Perform cold recovery from a backup file.

  ## Parameters
  - backup_id: :latest or specific backup ID
  - config: Recovery configuration

  ## Returns
  - {:ok, recovery_report} on success
  - {:error, reason} on failure
  """
  def cold_recovery(backup_id, config) do
    Logger.info("Starting cold recovery with backup_id: #{inspect(backup_id)}")

    with {:ok, backup_file} <- find_backup_file(backup_id, config),
         {:ok, backup_data} <- load_backup_data(backup_file),
         {:ok, _verification} <- verify_backup_integrity(backup_data),
         {:ok, recovery_plan} <- create_recovery_plan(backup_data),
         {:ok, results} <- execute_recovery_plan(recovery_plan) do
      recovery_report = %{
        backup_id: backup_id,
        backup_file: backup_file,
        recovery_time: DateTime.utc_now(),
        components_restored: Map.keys(results),
        success_count: count_successful_recoveries(results),
        failure_count: count_failed_recoveries(results),
        results: results
      }

      Logger.info("Cold recovery completed successfully")
      {:ok, recovery_report}
    else
      {:error, reason} = error ->
        Logger.error("Cold recovery failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Perform partial recovery for specific components.

  ## Parameters
  - components: List of component atoms [:security, :agents, :sessions, :config]
  - config: Recovery configuration

  ## Returns
  - {:ok, recovery_report} on success
  - {:error, reason} on failure
  """
  def partial_recovery(components, config) do
    Logger.info("Starting partial recovery for components: #{inspect(components)}")

    with {:ok, backup_file} <- find_backup_file(:latest, config),
         {:ok, backup_data} <- load_backup_data(backup_file),
         {:ok, filtered_data} <- filter_backup_data(backup_data, components),
         {:ok, recovery_plan} <- create_partial_recovery_plan(filtered_data, components),
         {:ok, results} <- execute_recovery_plan(recovery_plan) do
      recovery_report = %{
        components: components,
        backup_file: backup_file,
        recovery_time: DateTime.utc_now(),
        results: results
      }

      Logger.info("Partial recovery completed for #{length(components)} components")
      {:ok, recovery_report}
    else
      {:error, reason} = error ->
        Logger.error("Partial recovery failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Apply standby sync data to current node.
  Used for hot standby synchronization.
  """
  def apply_standby_sync(sync_data) do
    Logger.debug("Applying standby sync data")

    results = %{
      security: apply_security_sync(sync_data[:security_state]),
      agents: apply_agent_sync(sync_data[:agent_state]),
      sessions: apply_session_sync(sync_data[:session_state])
    }

    success_count = Enum.count(results, fn {_k, v} -> v == :ok end)

    if success_count == map_size(results) do
      Logger.info("Standby sync applied successfully")
      {:ok, results}
    else
      Logger.warning("Standby sync partially failed: #{inspect(results)}")
      {:partial, results}
    end
  end

  # Private functions

  defp find_backup_file(:latest, config) do
    backup_dir = Path.expand(config.backup_directory)

    case File.ls(backup_dir) do
      {:ok, files} ->
        latest_backup =
          files
          |> Enum.filter(&String.starts_with?(&1, "backup_"))
          |> Enum.map(&Path.join(backup_dir, &1))
          |> Enum.max_by(&File.stat!(&1).mtime, fn -> nil end)

        if latest_backup do
          {:ok, latest_backup}
        else
          {:error, :no_backups_found}
        end

      {:error, reason} ->
        {:error, {:backup_directory_error, reason}}
    end
  end

  defp find_backup_file(backup_id, config) when is_binary(backup_id) do
    backup_file =
      Path.join([
        Path.expand(config.backup_directory),
        "backup_#{backup_id}.json"
      ])

    if File.exists?(backup_file) do
      {:ok, backup_file}
    else
      {:error, {:backup_not_found, backup_id}}
    end
  end

  defp load_backup_data(backup_file) do
    case File.read(backup_file) do
      {:ok, json_content} ->
        case Jason.decode(json_content) do
          {:ok, data} -> {:ok, data}
          {:error, reason} -> {:error, {:json_decode_error, reason}}
        end

      {:error, reason} ->
        {:error, {:file_read_error, reason}}
    end
  end

  defp verify_backup_integrity(backup_data) do
    required_fields = ["timestamp", "metadata", "security_state", "agent_state", "session_state"]

    missing_fields =
      Enum.filter(required_fields, fn field ->
        not Map.has_key?(backup_data, field)
      end)

    if Enum.empty?(missing_fields) do
      # Additional integrity checks
      with {:ok, _} <- verify_timestamp_validity(backup_data["timestamp"]),
           {:ok, _} <- verify_metadata_integrity(backup_data["metadata"]) do
        {:ok, :verified}
      end
    else
      {:error, {:missing_fields, missing_fields}}
    end
  end

  defp verify_timestamp_validity(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _} ->
        # Check if backup is not too old (default: 7 days)
        age_days = DateTime.diff(DateTime.utc_now(), dt, :day)

        if age_days <= 7 do
          {:ok, dt}
        else
          {:error, {:backup_too_old, age_days}}
        end

      {:error, reason} ->
        {:error, {:invalid_timestamp, reason}}
    end
  end

  defp verify_metadata_integrity(metadata) do
    required_metadata = ["version", "node", "system_time"]

    missing_metadata =
      Enum.filter(required_metadata, fn field ->
        not Map.has_key?(metadata, field)
      end)

    if Enum.empty?(missing_metadata) do
      {:ok, metadata}
    else
      {:error, {:missing_metadata, missing_metadata}}
    end
  end

  defp create_recovery_plan(backup_data) do
    plan = %{
      security: %{
        component: :security,
        data: backup_data["security_state"],
        recovery_function: &recover_security_state/1,
        priority: 1
      },
      config: %{
        component: :config,
        data: backup_data["config_state"],
        recovery_function: &recover_config_state/1,
        priority: 2
      },
      agents: %{
        component: :agents,
        data: backup_data["agent_state"],
        recovery_function: &recover_agent_state/1,
        priority: 3
      },
      sessions: %{
        component: :sessions,
        data: backup_data["session_state"],
        recovery_function: &recover_session_state/1,
        priority: 4
      }
    }

    {:ok, plan}
  end

  defp filter_backup_data(backup_data, components) do
    component_mapping = %{
      security: "security_state",
      agents: "agent_state",
      sessions: "session_state",
      config: "config_state"
    }

    filtered_data =
      components
      |> Enum.map(fn component ->
        field = component_mapping[component]
        {component, backup_data[field]}
      end)
      |> Enum.into(%{})

    {:ok, filtered_data}
  end

  defp create_partial_recovery_plan(filtered_data, components) do
    recovery_functions = %{
      security: &recover_security_state/1,
      agents: &recover_agent_state/1,
      sessions: &recover_session_state/1,
      config: &recover_config_state/1
    }

    plan =
      components
      |> Enum.with_index(1)
      |> Enum.map(fn {component, priority} ->
        {component,
         %{
           component: component,
           data: filtered_data[component],
           recovery_function: recovery_functions[component],
           priority: priority
         }}
      end)
      |> Enum.into(%{})

    {:ok, plan}
  end

  defp execute_recovery_plan(recovery_plan) do
    # Sort by priority and execute in order
    sorted_steps =
      recovery_plan
      |> Enum.sort_by(fn {_k, v} -> v.priority end)

    results =
      Enum.reduce_while(sorted_steps, %{}, fn {component, step}, acc ->
        Logger.info("Recovering component: #{component}")

        case execute_recovery_step(step) do
          {:ok, result} ->
            {:cont, Map.put(acc, component, {:ok, result})}

          {:error, reason} = error ->
            Logger.error("Recovery failed for #{component}: #{inspect(reason)}")
            {:halt, Map.put(acc, component, error)}
        end
      end)

    {:ok, results}
  end

  defp execute_recovery_step(%{recovery_function: recovery_fn, data: data}) do
    try do
      recovery_fn.(data)
    rescue
      error ->
        {:error, {:recovery_function_error, error}}
    end
  end

  defp recover_security_state(data) when is_map(data) and map_size(data) > 0 do
    try do
      case GenServer.call(MCPChat.Security.SecurityKernel, {:restore_state, data}, 10_000) do
        :ok -> {:ok, :restored}
        {:error, reason} -> {:error, reason}
      end
    catch
      :exit, reason -> {:error, {:process_error, reason}}
    end
  end

  defp recover_security_state(_), do: {:ok, :no_data}

  defp recover_agent_state(data) when is_map(data) and map_size(data) > 0 do
    try do
      case GenServer.call(MCPChat.Agents.AgentSupervisor, {:restore_state, data}, 10_000) do
        :ok -> {:ok, :restored}
        {:error, reason} -> {:error, reason}
      end
    catch
      :exit, reason -> {:error, {:process_error, reason}}
    end
  end

  defp recover_agent_state(_), do: {:ok, :no_data}

  defp recover_session_state(data) when is_map(data) and map_size(data) > 0 do
    try do
      case GenServer.call(MCPChat.Agents.SessionManager, {:restore_state, data}, 10_000) do
        :ok -> {:ok, :restored}
        {:error, reason} -> {:error, reason}
      end
    catch
      :exit, reason -> {:error, {:process_error, reason}}
    end
  end

  defp recover_session_state(_), do: {:ok, :no_data}

  defp recover_config_state(data) when is_map(data) and map_size(data) > 0 do
    try do
      case GenServer.call(MCPChat.Config, {:restore_state, data}, 10_000) do
        :ok -> {:ok, :restored}
        {:error, reason} -> {:error, reason}
      end
    catch
      :exit, reason -> {:error, {:process_error, reason}}
    end
  end

  defp recover_config_state(_), do: {:ok, :no_data}

  defp apply_security_sync(state_data) when is_map(state_data) do
    try do
      GenServer.call(MCPChat.Security.SecurityKernel, {:sync_state, state_data}, 5000)
      :ok
    catch
      :exit, _reason -> :error
    end
  end

  defp apply_security_sync(_), do: :ok

  defp apply_agent_sync(state_data) when is_map(state_data) do
    try do
      GenServer.call(MCPChat.Agents.AgentSupervisor, {:sync_state, state_data}, 5000)
      :ok
    catch
      :exit, _reason -> :error
    end
  end

  defp apply_agent_sync(_), do: :ok

  defp apply_session_sync(state_data) when is_map(state_data) do
    try do
      GenServer.call(MCPChat.Agents.SessionManager, {:sync_state, state_data}, 5000)
      :ok
    catch
      :exit, _reason -> :error
    end
  end

  defp apply_session_sync(_), do: :ok

  defp count_successful_recoveries(results) do
    Enum.count(results, fn {_k, v} -> match?({:ok, _}, v) end)
  end

  defp count_failed_recoveries(results) do
    Enum.count(results, fn {_k, v} -> match?({:error, _}, v) end)
  end
end
