defmodule MCPChat.MCP.Handlers.ComprehensiveNotificationHandlerTest do
  use ExUnit.Case
  alias MCPChat.MCP.Handlers.ComprehensiveNotificationHandler

  alias MCPChat.MCP.Handlers.ComprehensiveNotificationHandlerTest

  setup do
    {:ok, handler} = ComprehensiveNotificationHandler.start_link(name: :test_handler)

    on_exit(fn ->
      GenServer.stop(handler)
    end)

    {:ok, handler: handler}
  end

  describe "handle_notification/3" do
    test "handles connection notifications", %{handler: handler} do
      # Server connected
      :ok =
        ComprehensiveNotificationHandler.handle_notification(
          handler,
          "test_server",
          %{"method" => "notifications/server/connected", "params" => %{}}
        )

      # Server disconnected
      :ok =
        ComprehensiveNotificationHandler.handle_notification(
          handler,
          "test_server",
          %{"method" => "notifications/server/disconnected", "params" => %{"reason" => "test"}}
        )

      # Server error
      :ok =
        ComprehensiveNotificationHandler.handle_notification(
          handler,
          "test_server",
          %{"method" => "notifications/server/error", "params" => %{"error" => "test error"}}
        )

      # Check history
      history = ComprehensiveNotificationHandler.get_history(handler)
      assert length(history) == 3
    end

    test "handles resource notifications", %{handler: handler} do
      notifications = [
        %{"method" => "notifications/resources/list_changed", "params" => %{}},
        %{"method" => "notifications/resources/updated", "params" => %{"uri" => "test://resource"}},
        %{"method" => "notifications/resource/added", "params" => %{"uri" => "test://new"}},
        %{"method" => "notifications/resource/removed", "params" => %{"uri" => "test://old"}}
      ]

      for notification <- notifications do
        :ok =
          ComprehensiveNotificationHandler.handle_notification(
            handler,
            "test_server",
            notification
          )
      end

      history = ComprehensiveNotificationHandler.get_history(handler)
      assert length(history) == 4
    end

    test "handles tool notifications", %{handler: handler} do
      notifications = [
        %{"method" => "notifications/tools/list_changed", "params" => %{}},
        %{"method" => "notifications/tool/added", "params" => %{"name" => "new_tool"}},
        %{"method" => "notifications/tool/removed", "params" => %{"name" => "old_tool"}}
      ]

      for notification <- notifications do
        :ok =
          ComprehensiveNotificationHandler.handle_notification(
            handler,
            "test_server",
            notification
          )
      end

      history = ComprehensiveNotificationHandler.get_history(handler)
      assert length(history) == 3
    end

    test "handles progress notifications", %{handler: handler} do
      token = "progress-123"

      # Progress start
      :ok =
        ComprehensiveNotificationHandler.handle_notification(
          handler,
          "test_server",
          %{
            "method" => "notifications/progress",
            "params" => %{
              "progressToken" => token,
              "progress" => 0,
              "total" => 100
            }
          }
        )

      # Progress update
      :ok =
        ComprehensiveNotificationHandler.handle_notification(
          handler,
          "test_server",
          %{
            "method" => "notifications/progress",
            "params" => %{
              "progressToken" => token,
              "progress" => 50,
              "total" => 100
            }
          }
        )

      history = ComprehensiveNotificationHandler.get_history(handler)
      assert length(history) == 2
    end
  end

  describe "configuration" do
    test "enable/disable notifications", %{handler: handler} do
      # Disable all
      :ok = ComprehensiveNotificationHandler.disable_all(handler)
      config = ComprehensiveNotificationHandler.get_config(handler)
      refute config.enabled

      # Enable all
      :ok = ComprehensiveNotificationHandler.enable_all(handler)
      config = ComprehensiveNotificationHandler.get_config(handler)
      assert config.enabled
    end

    test "configure categories", %{handler: handler} do
      # Disable specific category
      :ok =
        ComprehensiveNotificationHandler.configure_category(
          handler,
          :resource,
          enabled: false
        )

      config = ComprehensiveNotificationHandler.get_config(handler)
      refute config.categories.resource.enabled
    end

    test "respects category settings", %{handler: handler} do
      # Disable resource notifications
      :ok =
        ComprehensiveNotificationHandler.configure_category(
          handler,
          :resource,
          enabled: false
        )

      # Send resource notification
      :ok =
        ComprehensiveNotificationHandler.handle_notification(
          handler,
          "test_server",
          %{"method" => "notifications/resources/list_changed", "params" => %{}}
        )

      # Should not be in history
      history = ComprehensiveNotificationHandler.get_history(handler)
      assert Enum.empty?(history)
    end
  end

  describe "batching" do
    test "batches notifications when enabled", %{handler: handler} do
      # Enable batching for resources
      :ok =
        ComprehensiveNotificationHandler.configure_category(
          handler,
          :resource,
          batch_enabled: true,
          # 100ms
          batch_window: 100
        )

      # Send multiple notifications quickly
      for i <- 1..5 do
        ComprehensiveNotificationHandler.handle_notification(
          handler,
          "test_server",
          %{"method" => "notifications/resources/updated", "params" => %{"uri" => "test://#{i}"}}
        )
      end

      # Should not be processed yet
      history = ComprehensiveNotificationHandler.get_history(handler)
      assert Enum.empty?(history)

      # Wait for batch window
      Process.sleep(150)

      # Now should be batched as one event
      history = ComprehensiveNotificationHandler.get_history(handler, 10)
      assert length(history) == 1
      assert history |> hd() |> Map.get(:count) == 5
    end
  end

  describe "history management" do
    test "limits history size", %{handler: handler} do
      # Send many notifications
      for i <- 1..150 do
        ComprehensiveNotificationHandler.handle_notification(
          handler,
          "server#{i}",
          %{"method" => "notifications/server/connected", "params" => %{}}
        )
      end

      history = ComprehensiveNotificationHandler.get_history(handler, :all)
      # Default max
      assert length(history) == 100
    end

    test "clears history", %{handler: handler} do
      # Add some events
      ComprehensiveNotificationHandler.handle_notification(
        handler,
        "test_server",
        %{"method" => "notifications/server/connected", "params" => %{}}
      )

      # Clear
      :ok = ComprehensiveNotificationHandler.clear_history(handler)

      history = ComprehensiveNotificationHandler.get_history(handler)
      assert Enum.empty?(history)
    end

    test "filters history by limit", %{handler: handler} do
      # Add events
      for i <- 1..10 do
        ComprehensiveNotificationHandler.handle_notification(
          handler,
          "server#{i}",
          %{"method" => "notifications/server/connected", "params" => %{}}
        )
      end

      history = ComprehensiveNotificationHandler.get_history(handler, 5)
      assert length(history) == 5
    end
  end

  describe "send_test_notification/1" do
    test "sends test notifications for all categories", %{handler: handler} do
      :ok = ComprehensiveNotificationHandler.send_test_notification(handler)

      # Wait for processing
      Process.sleep(50)

      history = ComprehensiveNotificationHandler.get_history(handler)

      # Should have test notifications for each category
      categories = history |> Enum.map(& &1.type) |> Enum.uniq()
      assert :server_connected in categories
      assert :resources_list_changed in categories
      assert :tools_list_changed in categories
      assert :progress_start in categories
    end
  end
end
