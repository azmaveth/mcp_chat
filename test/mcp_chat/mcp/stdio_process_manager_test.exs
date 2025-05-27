defmodule MCPChat.MCP.StdioProcessManagerTest do
  use ExUnit.Case, async: true
  alias MCPChat.MCP.StdioProcessManager

  @moduletag :integration

  describe "stdio process management" do
    test "starts and stops a simple echo process" do
      # Use a simple echo command for testing
      opts = [
        command: "cat",
        args: [],
        env: []
      ]

      {:ok, manager} = StdioProcessManager.start_link(opts)

      # Get initial status
      {:ok, status} = StdioProcessManager.get_status(manager)
      assert status.running == false

      # Start the process
      {:ok, _port} = StdioProcessManager.start_process(manager)

      # Verify it's running
      {:ok, status} = StdioProcessManager.get_status(manager)
      assert status.running == true

      # Set ourselves as the client to receive messages
      :ok = StdioProcessManager.set_client(manager, self())

      # Send some data
      :ok = StdioProcessManager.send_data(manager, "Hello, World!\n")

      # Should receive the echo back
      assert_receive {:stdio_data, "Hello, World!\n"}, 1_000

      # Stop the process
      :ok = StdioProcessManager.stop_process(manager)

      # Verify it's stopped
      {:ok, status} = StdioProcessManager.get_status(manager)
      assert status.running == false
    end

    test "handles process exit gracefully" do
      # Use a command that exits immediately
      opts = [
        command: "echo",
        args: ["test"],
        env: []
      ]

      {:ok, manager} = StdioProcessManager.start_link(opts)
      :ok = StdioProcessManager.set_client(manager, self())

      # Start the process
      {:ok, _port} = StdioProcessManager.start_process(manager)

      # Should receive the output and exit notification
      assert_receive {:stdio_data, "test\n"}, 1_000
      assert_receive {:stdio_exit, 0}, 1_000

      # Process should no longer be running
      {:ok, status} = StdioProcessManager.get_status(manager)
      assert status.running == false
    end

    test "handles invalid command" do
      opts = [
        command: "this_command_does_not_exist_12345",
        args: [],
        env: []
      ]

      {:ok, manager} = StdioProcessManager.start_link(opts)

      # Should fail to start
      assert {:error, _reason} = StdioProcessManager.start_process(manager)
    end

    test "cannot send data when process not started" do
      opts = [
        command: "cat",
        args: [],
        env: []
      ]

      {:ok, manager} = StdioProcessManager.start_link(opts)

      # Should fail to send data
      assert {:error, :not_started} = StdioProcessManager.send_data(manager, "test")
    end

    test "cannot start process twice" do
      opts = [
        command: "cat",
        args: [],
        env: []
      ]

      {:ok, manager} = StdioProcessManager.start_link(opts)

      # Start once
      {:ok, _port} = StdioProcessManager.start_process(manager)

      # Try to start again
      assert {:error, :already_started} = StdioProcessManager.start_process(manager)

      # Cleanup
      :ok = StdioProcessManager.stop_process(manager)
    end
  end
end
