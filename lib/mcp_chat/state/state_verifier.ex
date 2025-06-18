defmodule MCPChat.State.StateVerifier do
  @moduledoc """
  State verification system for data integrity checks.

  Provides comprehensive verification of system state across all components.
  """

  require Logger

  @doc """
  Verify the integrity of the entire system state.

  Returns {result, errors} where result is :ok or :error,
  and errors is a list of validation issues found.
  """
  def verify_system_state do
    Logger.info("Starting system state verification")

    checks = [
      {"Security State", &verify_security_state/0},
      {"Agent State", &verify_agent_state/0},
      {"Session State", &verify_session_state/0},
      {"Config State", &verify_config_state/0},
      {"Process Health", &verify_process_health/0},
      {"Memory Consistency", &verify_memory_consistency/0}
    ]

    {_results, errors} = run_verification_checks(checks)

    overall_result = if Enum.empty?(errors), do: :ok, else: :error

    Logger.info("State verification completed: #{overall_result}, #{length(errors)} errors")
    {overall_result, errors}
  end

  @doc """
  Verify security state integrity.
  """
  def verify_security_state do
    try do
      case GenServer.call(MCPChat.Security.SecurityKernel, :verify_state, 10_000) do
        {:ok, verification_report} ->
          validate_security_report(verification_report)

        {:error, reason} ->
          [{:security_kernel_error, reason}]

        :timeout ->
          [{:security_kernel_timeout, "Verification timed out"}]
      end
    rescue
      error ->
        [{:security_verification_error, error}]
    catch
      :exit, reason ->
        [{:security_kernel_unavailable, reason}]
    end
  end

  @doc """
  Verify agent state integrity.
  """
  def verify_agent_state do
    try do
      case GenServer.call(MCPChat.Agents.AgentSupervisor, :verify_state, 10_000) do
        {:ok, verification_report} ->
          validate_agent_report(verification_report)

        {:error, reason} ->
          [{:agent_supervisor_error, reason}]

        :timeout ->
          [{:agent_supervisor_timeout, "Verification timed out"}]
      end
    rescue
      error ->
        [{:agent_verification_error, error}]
    catch
      :exit, reason ->
        [{:agent_supervisor_unavailable, reason}]
    end
  end

  @doc """
  Verify session state integrity.
  """
  def verify_session_state do
    try do
      case GenServer.call(MCPChat.Agents.SessionManager, :verify_state, 10_000) do
        {:ok, verification_report} ->
          validate_session_report(verification_report)

        {:error, reason} ->
          [{:session_manager_error, reason}]

        :timeout ->
          [{:session_manager_timeout, "Verification timed out"}]
      end
    rescue
      error ->
        [{:session_verification_error, error}]
    catch
      :exit, reason ->
        [{:session_manager_unavailable, reason}]
    end
  end

  @doc """
  Verify configuration state integrity.
  """
  def verify_config_state do
    try do
      case GenServer.call(MCPChat.Config, :verify_state, 10_000) do
        {:ok, verification_report} ->
          validate_config_report(verification_report)

        {:error, reason} ->
          [{:config_error, reason}]

        :timeout ->
          [{:config_timeout, "Verification timed out"}]
      end
    rescue
      error ->
        [{:config_verification_error, error}]
    catch
      :exit, reason ->
        [{:config_unavailable, reason}]
    end
  end

  @doc """
  Verify process health across the system.
  """
  def verify_process_health do
    required_processes = [
      MCPChat.Security.SecurityKernel,
      MCPChat.Security.AuditLogger,
      MCPChat.Agents.AgentSupervisor,
      MCPChat.Config,
      MCPChat.PubSub
    ]

    errors =
      required_processes
      |> Enum.filter(fn process -> not process_healthy?(process) end)
      |> Enum.map(fn process -> {:process_unhealthy, process} end)

    errors
  end

  @doc """
  Verify memory consistency across components.
  """
  def verify_memory_consistency do
    errors = []

    # Check ETS table consistency
    errors = check_ets_tables() ++ errors

    # Check GenServer memory usage
    errors = check_genserver_memory() ++ errors

    # Check for memory leaks
    errors = check_memory_leaks() ++ errors

    errors
  end

  # Private verification functions

  defp run_verification_checks(checks) do
    results =
      Enum.map(checks, fn {name, check_fn} ->
        Logger.debug("Running verification check: #{name}")

        try do
          errors = check_fn.()
          {name, {:ok, errors}}
        rescue
          error ->
            Logger.warning("Verification check #{name} failed: #{inspect(error)}")
            {name, {:error, error}}
        end
      end)

    # Collect all errors
    all_errors =
      results
      |> Enum.flat_map(fn
        {_name, {:ok, errors}} -> errors
        {name, {:error, error}} -> [{:check_failed, name, error}]
      end)

    {results, all_errors}
  end

  defp validate_security_report(report) when is_map(report) do
    errors = []

    # Check capability count consistency
    errors =
      if Map.get(report, :capability_count, 0) < 0 do
        [{:invalid_capability_count, report.capability_count} | errors]
      else
        errors
      end

    # Check for orphaned capabilities
    errors =
      if Map.get(report, :orphaned_capabilities, []) != [] do
        [{:orphaned_capabilities, length(report.orphaned_capabilities)} | errors]
      else
        errors
      end

    # Check signature consistency
    errors =
      if Map.get(report, :invalid_signatures, []) != [] do
        [{:invalid_signatures, length(report.invalid_signatures)} | errors]
      else
        errors
      end

    errors
  end

  defp validate_security_report(_), do: [{:invalid_security_report, "Report is not a map"}]

  defp validate_agent_report(report) when is_map(report) do
    errors = []

    # Check agent count consistency
    errors =
      if Map.get(report, :agent_count, 0) < 0 do
        [{:invalid_agent_count, report.agent_count} | errors]
      else
        errors
      end

    # Check for zombie agents
    errors =
      if Map.get(report, :zombie_agents, []) != [] do
        [{:zombie_agents, length(report.zombie_agents)} | errors]
      else
        errors
      end

    # Check memory usage
    total_memory = Map.get(report, :total_memory, 0)
    # 100MB threshold
    errors =
      if total_memory > 100_000_000 do
        [{:high_agent_memory, total_memory} | errors]
      else
        errors
      end

    errors
  end

  defp validate_agent_report(_), do: [{:invalid_agent_report, "Report is not a map"}]

  defp validate_session_report(report) when is_map(report) do
    errors = []

    # Check session count
    session_count = Map.get(report, :session_count, 0)

    errors =
      if session_count < 0 do
        [{:invalid_session_count, session_count} | errors]
      else
        errors
      end

    # Check for corrupted sessions
    errors =
      if Map.get(report, :corrupted_sessions, []) != [] do
        [{:corrupted_sessions, length(report.corrupted_sessions)} | errors]
      else
        errors
      end

    # Check message consistency
    errors =
      if Map.get(report, :message_inconsistencies, []) != [] do
        [{:message_inconsistencies, length(report.message_inconsistencies)} | errors]
      else
        errors
      end

    errors
  end

  defp validate_session_report(_), do: [{:invalid_session_report, "Report is not a map"}]

  defp validate_config_report(report) when is_map(report) do
    errors = []

    # Check required configuration keys
    required_keys = [:llm, :mcp, :ui]

    missing_keys =
      Enum.filter(required_keys, fn key ->
        not Map.has_key?(report, key) or is_nil(report[key])
      end)

    errors =
      if not Enum.empty?(missing_keys) do
        [{:missing_config_keys, missing_keys} | errors]
      else
        errors
      end

    # Check configuration validity
    errors =
      if Map.get(report, :invalid_configs, []) != [] do
        [{:invalid_configs, report.invalid_configs} | errors]
      else
        errors
      end

    errors
  end

  defp validate_config_report(_), do: [{:invalid_config_report, "Report is not a map"}]

  defp process_healthy?(process_name) do
    case Process.whereis(process_name) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end

  defp check_ets_tables do
    errors = []

    # Check security tables
    security_tables = [:security_capabilities, :security_revocations, :security_metrics]
    errors = check_ets_table_health(security_tables, "security") ++ errors

    # Check agent tables
    agent_tables = [:agent_registry, :agent_metrics]
    errors = check_ets_table_health(agent_tables, "agent") ++ errors

    errors
  end

  defp check_ets_table_health(table_names, category) do
    Enum.flat_map(table_names, fn table_name ->
      case :ets.info(table_name) do
        :undefined ->
          [{:missing_ets_table, category, table_name}]

        info when is_list(info) ->
          size = Keyword.get(info, :size, 0)
          memory = Keyword.get(info, :memory, 0)

          cond do
            size > 100_000 ->
              [{:large_ets_table, category, table_name, size}]

            # 50MB
            memory > 50_000_000 ->
              [{:high_ets_memory, category, table_name, memory}]

            true ->
              []
          end

        _ ->
          [{:ets_table_error, category, table_name}]
      end
    end)
  end

  defp check_genserver_memory do
    important_processes = [
      MCPChat.Security.SecurityKernel,
      MCPChat.Security.AuditLogger,
      MCPChat.Agents.AgentSupervisor,
      MCPChat.Config
    ]

    Enum.flat_map(important_processes, fn process ->
      case Process.whereis(process) do
        nil ->
          []

        pid ->
          case Process.info(pid, :memory) do
            # 50MB
            {:memory, memory} when memory > 50_000_000 ->
              [{:high_process_memory, process, memory}]

            {:memory, _} ->
              []

            nil ->
              [{:process_memory_unavailable, process}]
          end
      end
    end)
  end

  defp check_memory_leaks do
    # Simple heuristic: check system memory usage
    case :erlang.memory() do
      memory_info when is_list(memory_info) ->
        total = Keyword.get(memory_info, :total, 0)
        processes = Keyword.get(memory_info, :processes, 0)

        cond do
          # 1GB
          total > 1_000_000_000 ->
            [{:high_system_memory, total}]

          # 500MB
          processes > 500_000_000 ->
            [{:high_process_memory_total, processes}]

          true ->
            []
        end

      _ ->
        [{:memory_info_unavailable, "Could not retrieve memory information"}]
    end
  end
end
