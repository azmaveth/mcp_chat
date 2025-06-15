defmodule NotificationRegistryTest do
  use ExUnit.Case, async: true

  alias NotificationRegistry

  alias MCPChat.MCP.NotificationHandler
  alias NotificationRegistryTest
  # Test handler module
  defmodule TestHandler do
    @behaviour NotificationHandler

    def init(args) do
      {:ok, %{test_pid: args[:test_pid], calls: []}}
    end

    def handle_notification(server_name, type, params, state) do
      if state.test_pid do
        send(state.test_pid, {:notification, server_name, type, params})
      end

      new_state = %{state | calls: [{server_name, type, params} | state.calls]}
      {:ok, new_state}
    end
  end

  setup do
    # Use the existing registry or start a new one
    registry =
      case Process.whereis(NotificationRegistry) do
        nil ->
          {:ok, pid} = NotificationRegistry.start_link()
          pid

        pid ->
          # Clean up existing handlers
          handlers = NotificationRegistry.list_handlers()

          Enum.each(Map.keys(handlers), fn _type ->
            nil
            # Clear handlers between tests
          end)

          pid
      end

    {:ok, registry: registry}
  end

  describe "handler registration" do
    test "registers handler for notification types", %{registry: registry} do
      assert :ok =
               GenServer.call(
                 registry,
                 {:register_handler, TestHandler, [:progress, :tools_list_changed], [test_pid: self()]}
               )

      handlers = GenServer.call(registry, :list_handlers)
      assert Map.has_key?(handlers, :progress)
      assert Map.has_key?(handlers, :tools_list_changed)
      assert TestHandler in handlers[:progress]
      assert TestHandler in handlers[:tools_list_changed]
    end

    test "unregisters handler", %{registry: registry} do
      GenServer.call(registry, {:register_handler, TestHandler, [:progress], []})
      GenServer.call(registry, {:unregister_handler, TestHandler})

      handlers = GenServer.call(registry, :list_handlers)
      assert handlers == %{}
    end
  end

  describe "notification dispatch" do
    test "dispatches notifications to registered handlers", %{registry: registry} do
      GenServer.call(registry, {:register_handler, TestHandler, [:progress], [test_pid: self()]})

      GenServer.cast(registry, {:dispatch, "test_server", "notifications/progress", %{"progress" => 50}})

      assert_receive {:notification, "test_server", :progress, %{"progress" => 50}}
    end

    test "ignores notifications without handlers", %{registry: registry} do
      # Should not crash
      GenServer.cast(registry, {:dispatch, "test_server", "notifications/progress", %{}})

      # Give it time to process
      Process.sleep(10)

      # Registry should still be alive
      assert Process.alive?(registry)
    end

    test "handles multiple handlers for same notification", %{registry: registry} do
      GenServer.call(registry, {:register_handler, TestHandler, [:progress], [test_pid: self()]})

      # Register a second handler (same module but will create new state)
      defmodule SecondHandler do
        @behaviour NotificationHandler

        def init(args) do
          {:ok, %{test_pid: args[:test_pid]}}
        end

        def handle_notification(server_name, type, params, state) do
          if state.test_pid do
            send(state.test_pid, {:second_handler, server_name, type, params})
          end

          {:ok, state}
        end
      end

      GenServer.call(registry, {:register_handler, SecondHandler, [:progress], [test_pid: self()]})

      GenServer.cast(registry, {:dispatch, "test_server", "notifications/progress", %{"progress" => 75}})

      assert_receive {:notification, "test_server", :progress, %{"progress" => 75}}
      assert_receive {:second_handler, "test_server", :progress, %{"progress" => 75}}
    end
  end

  describe "error handling" do
    test "continues processing if handler fails", %{registry: registry} do
      defmodule FailingHandler do
        @behaviour NotificationHandler

        def init(_args), do: {:ok, %{}}

        def handle_notification(_server, _type, _params, state) do
          {:error, :intentional_failure, state}
        end
      end

      GenServer.call(registry, {:register_handler, FailingHandler, [:progress], []})
      GenServer.call(registry, {:register_handler, TestHandler, [:progress], [test_pid: self()]})

      GenServer.cast(registry, {:dispatch, "test_server", "notifications/progress", %{"progress" => 100}})

      # Second handler should still receive notification
      assert_receive {:notification, "test_server", :progress, %{"progress" => 100}}
    end
  end
end
