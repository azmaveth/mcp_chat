defmodule MCPChat.MCP.NotificationIntegrationTest do
  use ExUnit.Case

  alias MCPChat.MCP.Handlers.ProgressHandler
  alias MCPChat.MCP.{NotificationRegistry, ProgressTracker}

  alias MCPChat.MCP.NotificationIntegrationTest

  describe "notification system integration" do
    test "progress notifications update tracker" do
      # Ensure services are started
      assert Process.whereis(NotificationRegistry) != nil
      assert Process.whereis(ProgressTracker) != nil

      # Start an operation
      {:ok, token} = ProgressTracker.start_operation("test_server", "test_tool", 100)

      # Simulate a progress notification
      NotificationRegistry.dispatch_notification(
        "test_server",
        "notifications/progress",
        %{
          "progressToken" => token,
          "progress" => 50,
          "total" => 100
        }
      )

      # Give it time to process
      Process.sleep(100)

      # Check that progress was updated
      operation = ProgressTracker.get_operation(token)
      assert operation != nil
      assert operation.progress == 50
      assert operation.total == 100
    end

    test "change notifications are logged" do
      # This test just verifies notifications don't crash
      notifications = [
        {"server1", "notifications/tools/list_changed", %{}},
        {"server2", "notifications/resources/list_changed", %{}},
        {"server1", "notifications/resources/updated", %{"uri" => "file:///test.txt"}},
        {"server3", "notifications/prompts/list_changed", %{}}
      ]

      Enum.each(notifications, fn {server, method, params} ->
        # Should not crash
        NotificationRegistry.dispatch_notification(server, method, params)
      end)

      # Give time to process
      Process.sleep(100)

      # If we get here, notifications were handled without crashing
      assert true
    end
  end
end
