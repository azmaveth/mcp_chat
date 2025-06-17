defmodule MCPChat.ApplicationTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Tests for the MCPChat.Application supervisor.
  """
  alias ExAliasAdapter
  alias ServerManager
  alias SSEServer
  alias StdioServer

  describe "start/2" do
    setup do
      # Stop all supervised processes if running
      stop_supervised_processes()

      on_exit(fn ->
        stop_supervised_processes()
      end)

      :ok
    end

    test "starts all required child processes" do
      # Start the application
      {:ok, pid} = MCPChat.Application.start(:normal, [])
      assert Process.alive?(pid)

      # Give processes time to start
      Process.sleep(500)

      # Verify core children are started
      assert Process.whereis(MCPChat.Config) != nil
      assert Process.whereis(MCPChat.PubSub) != nil

      # Verify agent architecture components
      assert Process.whereis(MCPChat.Agents.AgentSupervisor) != nil
      assert Process.whereis(MCPChat.Agents.SessionManager) != nil
      assert Process.whereis(MCPChat.Agents.AgentPool) != nil

      # Verify MCP components (ExAlias needs to start before ExAliasAdapter)
      assert Process.whereis(ExAlias) != nil
      # ExAliasAdapter may need more time to start
      Process.sleep(200)
      assert Process.whereis(ExAliasAdapter) != nil

      # Clean up
      Supervisor.stop(pid)
    end

    test "supervisor restarts crashed children" do
      # Start the application
      {:ok, sup_pid} = MCPChat.Application.start(:normal, [])
      Process.sleep(500)

      # Get the AgentSupervisor process (more critical than the legacy Session)
      agent_supervisor_pid = Process.whereis(MCPChat.Agents.AgentSupervisor)
      assert agent_supervisor_pid != nil

      # Monitor the process
      ref = Process.monitor(agent_supervisor_pid)

      # Kill the process
      Process.exit(agent_supervisor_pid, :kill)

      # Wait for the DOWN message
      assert_receive {:DOWN, ^ref, :process, ^agent_supervisor_pid, :killed}, 1_000

      # Give supervisor time to restart
      Process.sleep(100)

      # Verify it was restarted with a new PID
      new_agent_supervisor_pid = Process.whereis(MCPChat.Agents.AgentSupervisor)
      assert new_agent_supervisor_pid != nil
      assert new_agent_supervisor_pid != agent_supervisor_pid

      # Clean up
      Supervisor.stop(sup_pid)
    end

    test "supervisor uses one_for_one strategy" do
      # Start the application
      {:ok, sup_pid} = MCPChat.Application.start(:normal, [])
      Process.sleep(200)

      # Get PIDs of multiple children
      config_pid = Process.whereis(MCPChat.Config)
      session_manager_pid = Process.whereis(MCPChat.Agents.SessionManager)
      alias_pid = Process.whereis(ExAliasAdapter)

      assert config_pid != nil
      assert session_manager_pid != nil
      assert alias_pid != nil

      # Kill one child
      Process.exit(session_manager_pid, :kill)
      Process.sleep(100)

      # Verify only the killed child was restarted
      assert Process.whereis(MCPChat.Config) == config_pid
      assert Process.whereis(MCPChat.Agents.SessionManager) != session_manager_pid
      assert Process.whereis(ExAliasAdapter) == alias_pid

      # Clean up
      Supervisor.stop(sup_pid)
    end
  end

  describe "child specifications" do
    setup do
      stop_supervised_processes()
      on_exit(fn -> stop_supervised_processes() end)
      :ok
    end

    test "core children are properly specified" do
      # Start the application
      {:ok, sup_pid} = MCPChat.Application.start(:normal, [])
      Process.sleep(200)

      # Get supervisor children
      children = Supervisor.which_children(sup_pid)

      # Extract child IDs
      child_ids = Enum.map(children, fn {id, _, _, _} -> id end)

      # Verify core children are present
      assert MCPChat.Config in child_ids
      assert MCPChat.Agents.AgentSupervisor in child_ids
      assert ExAliasAdapter in child_ids
      assert ServerManager in child_ids

      # Clean up
      Supervisor.stop(sup_pid)
    end

    test "all children are workers" do
      # Start the application
      {:ok, sup_pid} = MCPChat.Application.start(:normal, [])
      Process.sleep(200)

      # Get supervisor children
      children = Supervisor.which_children(sup_pid)

      # Verify all are workers (not supervisors)
      Enum.each(children, fn {_id, _pid, type, _modules} ->
        assert type == :worker
      end)

      # Clean up
      Supervisor.stop(sup_pid)
    end
  end

  describe "supervisor behavior" do
    setup do
      stop_supervised_processes()
      on_exit(fn -> stop_supervised_processes() end)
      :ok
    end

    test "supervisor is named MCPChat.Supervisor" do
      {:ok, sup_pid} = MCPChat.Application.start(:normal, [])
      Process.sleep(100)

      # Verify the supervisor is registered with the correct name
      assert Process.whereis(MCPChat.Supervisor) == sup_pid

      # Clean up
      Supervisor.stop(sup_pid)
    end

    test "supervisor info shows correct strategy" do
      {:ok, sup_pid} = MCPChat.Application.start(:normal, [])
      Process.sleep(100)

      # Get supervisor info
      info = Supervisor.count_children(sup_pid)

      # Verify we have children
      # At least the 4 core children
      assert info[:active] >= 4
      assert info[:workers] >= 4

      # Clean up
      Supervisor.stop(sup_pid)
    end

    test "handles multiple restarts within threshold" do
      {:ok, sup_pid} = MCPChat.Application.start(:normal, [])
      Process.sleep(200)

      # Kill it multiple times
      for _i <- 1..3 do
        current_pid = Process.whereis(ExAliasAdapter)
        Process.exit(current_pid, :kill)
        Process.sleep(100)

        # Verify it was restarted
        new_pid = Process.whereis(ExAliasAdapter)
        assert new_pid != nil
        assert new_pid != current_pid
      end

      # Supervisor should still be running
      assert Process.alive?(sup_pid)

      # Clean up
      Supervisor.stop(sup_pid)
    end
  end

  describe "MCP server children" do
    setup do
      stop_supervised_processes()
      on_exit(fn -> stop_supervised_processes() end)
      :ok
    end

    test "mcp_server_children function behavior" do
      # We can't directly test the private function, but we can verify
      # that the application starts successfully with whatever config exists
      {:ok, sup_pid} = MCPChat.Application.start(:normal, [])
      Process.sleep(200)

      # The application should start successfully regardless of MCP server config
      assert Process.alive?(sup_pid)

      # Check if any MCP servers are running (depends on config)
      stdio_server = Process.whereis(StdioServer)
      sse_server = Process.whereis(SSEServer)

      # At least verify we can check for them without errors
      assert stdio_server == nil or Process.alive?(stdio_server)
      assert sse_server == nil or Process.alive?(sse_server)

      # Clean up
      Supervisor.stop(sup_pid)
    end
  end

  describe "error handling" do
    setup do
      stop_supervised_processes()
      on_exit(fn -> stop_supervised_processes() end)
      :ok
    end

    test "handles child start failures gracefully" do
      # This test verifies the supervisor can handle startup issues
      # We start the application multiple times to ensure cleanup works

      for _i <- 1..3 do
        stop_supervised_processes()

        {:ok, sup_pid} = MCPChat.Application.start(:normal, [])
        assert Process.alive?(sup_pid)

        Supervisor.stop(sup_pid)
        Process.sleep(100)
      end
    end
  end

  # Helper functions

  defp stop_supervised_processes do
    # Stop application supervisor if running
    case Process.whereis(MCPChat.Supervisor) do
      nil ->
        :ok

      pid ->
        try do
          Supervisor.stop(pid, :normal, 5_000)
        catch
          :exit, _ -> :ok
        end
    end

    # Stop individual processes if still running
    processes = [
      MCPChat.Config,
      MCPChat.Agents.AgentSupervisor,
      ExAliasAdapter,
      ServerManager,
      StdioServer,
      SSEServer
    ]

    Enum.each(processes, fn name ->
      case Process.whereis(name) do
        nil ->
          :ok

        pid ->
          try do
            GenServer.stop(pid, :normal, 5_000)
          catch
            :exit, _ -> :ok
          end
      end
    end)

    # Give processes time to fully stop
    Process.sleep(100)
  end
end
