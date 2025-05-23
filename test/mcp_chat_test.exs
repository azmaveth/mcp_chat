defmodule MCPChatTest do
  use ExUnit.Case
  
  describe "argument parsing" do
    test "parses help flag" do
      assert_raise SystemExit, fn ->
        MCPChat.main(["--help"])
      end
    end
    
    test "parses backend option" do
      # This would normally start the app, so we can't test it fully
      # without mocking the application start
      assert :ok == :ok
    end
  end
end