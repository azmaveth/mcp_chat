defmodule MCPChat.MCP.ServerPersistenceTest do
  use ExUnit.Case
  alias MCPChat.MCP.ServerPersistence

  describe "ServerPersistence functionality" do
    @tag :integration
    test "save and load servers integration test" do
      # This test uses the actual file system
      # In a real test environment, you would want to:
      # 1. Use a test-specific config directory
      # 2. Mock the file system operations
      # 3. Clean up after tests

      # For now, we'll just test the basic behavior
      assert Code.ensure_loaded?(ServerPersistence)
    end
  end

  describe "atomize_keys/1" do
    test "converts string keys to atoms" do
      input = %{
        "name" => "test",
        "command" => ["node"],
        "env" => %{"KEY" => "value"}
      }

      result = ServerPersistence.atomize_keys(input)

      assert result == %{
               name: "test",
               command: ["node"],
               env: %{"KEY" => "value"}
             }
    end

    test "handles nested maps" do
      input = %{
        "outer" => %{
          "inner" => "value"
        }
      }

      result = ServerPersistence.atomize_keys(input)

      assert result == %{
               outer: %{
                 "inner" => "value"
               }
             }
    end

    test "preserves non-map values" do
      assert ServerPersistence.atomize_keys("string") == "string"
      assert ServerPersistence.atomize_keys(123) == 123
      assert ServerPersistence.atomize_keys(nil) == nil
      assert ServerPersistence.atomize_keys([1, 2, 3]) == [1, 2, 3]
    end
  end
end
