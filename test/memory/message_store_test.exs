defmodule MCPChat.Memory.MessageStoreTest do
  use ExUnit.Case, async: true

  alias MCPChat.Memory.MessageStore

  setup do
    # Start a test message store
    {:ok, pid} =
      MessageStore.start_link(
        session_id: "test_#{System.unique_integer([:positive])}",
        memory_limit: 5,
        page_size: 3
      )

    %{store: pid}
  end

  describe "add_message/2" do
    test "stores messages in memory cache", %{store: store} do
      # Add a few messages
      :ok = MessageStore.add_message(store, %{role: :user, content: "Hello"})
      :ok = MessageStore.add_message(store, %{role: :assistant, content: "Hi there!"})

      # Get recent messages
      {:ok, messages} = MessageStore.get_recent_messages(store)

      assert length(messages) == 2
      assert Enum.at(messages, 0).content == "Hello"
      assert Enum.at(messages, 1).content == "Hi there!"
    end

    test "respects memory limit", %{store: store} do
      # Add more messages than memory limit (5)
      for i <- 1..7 do
        :ok =
          MessageStore.add_message(store, %{
            role: :user,
            content: "Message #{i}"
          })
      end

      # Should only keep last 5 in memory
      {:ok, messages} = MessageStore.get_recent_messages(store)
      assert length(messages) == 5

      # Should have most recent messages
      assert Enum.at(messages, 0).content == "Message 3"
      assert Enum.at(messages, 4).content == "Message 7"
    end
  end

  describe "get_page/2" do
    test "returns paginated results", %{store: store} do
      # Add 10 messages
      for i <- 1..10 do
        :ok =
          MessageStore.add_message(store, %{
            role: :user,
            content: "Message #{i}"
          })
      end

      # Get first page (page size is 3)
      {:ok, page1} = MessageStore.get_page(store, 1)

      assert page1.page == 1
      # 10 messages / 3 per page
      assert page1.total_pages == 4
      assert page1.total_messages == 10
      assert page1.has_next == true
      assert page1.has_prev == false
      assert length(page1.messages) == 3
      assert Enum.at(page1.messages, 0).content == "Message 1"

      # Get second page
      {:ok, page2} = MessageStore.get_page(store, 2)

      assert page2.page == 2
      assert page2.has_next == true
      assert page2.has_prev == true
      assert Enum.at(page2.messages, 0).content == "Message 4"
    end
  end

  describe "get_stats/1" do
    test "returns memory statistics", %{store: store} do
      # Add some messages
      for i <- 1..3 do
        :ok =
          MessageStore.add_message(store, %{
            role: :user,
            content: "Message #{i}"
          })
      end

      {:ok, stats} = MessageStore.get_stats(store)

      assert stats.messages_in_memory == 3
      assert stats.total_messages == 3
      assert stats.memory_limit == 5
      assert %DateTime{} = stats.last_accessed
    end
  end

  describe "clear_session/2" do
    test "clears all messages", %{store: store} do
      # Add messages
      MessageStore.add_message(store, %{role: :user, content: "Test"})

      # Get session_id from stats
      {:ok, stats} = MessageStore.get_stats(store)
      session_id = stats.session_id

      # Clear session
      :ok = MessageStore.clear_session(store, session_id)

      # Verify cleared
      {:ok, messages} = MessageStore.get_recent_messages(store)
      assert messages == []

      {:ok, stats} = MessageStore.get_stats(store)
      assert stats.total_messages == 0
    end
  end
end
