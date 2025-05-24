defmodule MCPChat.ManualRefactoringTest do
  use ExUnit.Case

  setup_all do
    # Start required processes
    {:ok, _} = MCPChat.Session.start_link()
    {:ok, _} = MCPChat.Alias.start_link()
    :ok
  end

  describe "refactored command modules" do
    test "session commands" do
      assert :ok = MCPChat.CLI.Commands.handle_command("new", [])
      assert :ok = MCPChat.CLI.Commands.handle_command("sessions", [])
      assert :ok = MCPChat.CLI.Commands.handle_command("history", [])
    end

    test "utility commands" do
      assert :ok = MCPChat.CLI.Commands.handle_command("help", [])
      assert :ok = MCPChat.CLI.Commands.handle_command("clear", [])
      assert :ok = MCPChat.CLI.Commands.handle_command("config", [])
      assert :ok = MCPChat.CLI.Commands.handle_command("cost", [])
    end

    test "LLM commands" do
      assert :ok = MCPChat.CLI.Commands.handle_command("backend", [])
      assert :ok = MCPChat.CLI.Commands.handle_command("models", [])
      assert :ok = MCPChat.CLI.Commands.handle_command("acceleration", [])
    end

    test "MCP commands" do
      assert :ok = MCPChat.CLI.Commands.handle_command("servers", [])
      assert :ok = MCPChat.CLI.Commands.handle_command("discover", [])
      assert :ok = MCPChat.CLI.Commands.handle_command("tools", [])
      assert :ok = MCPChat.CLI.Commands.handle_command("resources", [])
      assert :ok = MCPChat.CLI.Commands.handle_command("prompts", [])
    end

    test "context commands" do
      assert :ok = MCPChat.CLI.Commands.handle_command("context", [])
      assert :ok = MCPChat.CLI.Commands.handle_command("tokens", ["4_096"])
      assert :ok = MCPChat.CLI.Commands.handle_command("strategy", ["sliding_window"])
    end

    test "alias commands" do
      assert :ok = MCPChat.CLI.Commands.handle_command("alias", ["list"])
    end

    test "unknown commands return error" do
      assert {:error, _} = MCPChat.CLI.Commands.handle_command("unknown_command", [])
    end
  end
end
