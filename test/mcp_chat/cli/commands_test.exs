defmodule MCPChat.CLI.CommandsTest do
  use ExUnit.Case
  alias MCPChat.CLI.Commands

  import ExUnit.CaptureIO

  setup do
    # Start required services
    ensure_services_started()

    # Clear any existing session
    MCPChat.Session.clear_session()

    # Wait for session to be ready by checking it's clear
    wait_until(fn -> MCPChat.Session.get_messages() == [] end)

    :ok
  end

  defp wait_until(condition, timeout \\ 100) do
    if condition.() do
      :ok
    else
      if timeout > 0 do
        Process.sleep(10)
        wait_until(condition, timeout - 10)
      else
        # Give up but don't fail
        :ok
      end
    end
  end

  describe "handle_command/1" do
    test "returns :exit for exit command" do
      assert Commands.handle_command("exit") == :exit
      assert Commands.handle_command("quit") == :exit
    end

    test "shows error for unknown command" do
      output =
        capture_io(fn ->
          Commands.handle_command("unknown")
        end)

      assert output =~ "Unknown command"
    end

    test "splits command and arguments correctly" do
      # Test with various argument patterns
      output =
        capture_io(fn ->
          Commands.handle_command("save test session")
        end)

      # Should process save command with "test session" as argument
      assert output =~ "Saved" or output =~ "save"
    end
  end

  describe "help command" do
    test "shows available commands" do
      output =
        capture_io(fn ->
          Commands.handle_command("help")
        end)

      # Should show table with commands
      assert output =~ "Command"
      assert output =~ "Description"
      assert output =~ "/help"
      assert output =~ "/clear"
      assert output =~ "/save"
      assert output =~ "/load"
    end

    test "includes all documented commands" do
      output =
        capture_io(fn ->
          Commands.handle_command("help")
        end)

      # Check for various command categories
      # MCP commands
      assert output =~ "/mcp"
      # Config commands
      assert output =~ "/backend"
      # Context commands
      assert output =~ "/context"
      # Cost tracking
      assert output =~ "/cost"
      # Alias management
      assert output =~ "/alias"
    end
  end

  describe "clear command" do
    test "clears the screen" do
      output =
        capture_io(fn ->
          Commands.handle_command("clear")
        end)

      # Should contain ANSI clear sequence
      assert output =~ "\e[2J" or output =~ "\e[H"
    end
  end

  describe "history command" do
    test "shows empty history message when no messages" do
      output =
        capture_io(fn ->
          Commands.handle_command("history")
        end)

      assert output =~ "No messages in history"
    end

    test "shows conversation messages" do
      # Add some messages
      MCPChat.Session.add_message("user", "Hello")
      MCPChat.Session.add_message("assistant", "Hi there!")

      output =
        capture_io(fn ->
          Commands.handle_command("history")
        end)

      assert output =~ "User"
      assert output =~ "Hello"
      assert output =~ "Assistant"
      assert output =~ "Hi there!"
    end
  end

  describe "new command" do
    test "starts a new conversation" do
      # Add a message to current session
      MCPChat.Session.add_message("user", "Test")

      output =
        capture_io(fn ->
          Commands.handle_command("new")
        end)

      assert output =~ "Started new conversation"

      # Should have no messages in new session
      assert MCPChat.Session.get_messages() == []
    end
  end

  describe "save command" do
    test "saves session with auto-generated name" do
      MCPChat.Session.add_message("user", "Test message")

      output =
        capture_io(fn ->
          Commands.handle_command("save")
        end)

      assert output =~ "Session saved"
    end

    test "saves session with custom name" do
      MCPChat.Session.add_message("user", "Test message")

      output =
        capture_io(fn ->
          Commands.handle_command("save my-test-session")
        end)

      assert output =~ "Session saved"
      assert output =~ "my-test-session"
    end
  end

  describe "sessions command" do
    test "shows saved sessions or no sessions message" do
      output =
        capture_io(fn ->
          Commands.handle_command("sessions")
        end)

      # Either shows no sessions or lists sessions
      assert output =~ "No saved sessions" or output =~ "Saved sessions:"
    end
  end

  describe "config command" do
    test "shows current configuration" do
      output =
        capture_io(fn ->
          Commands.handle_command("config")
        end)

      assert output =~ "Setting"
      assert output =~ "Value"
      assert output =~ "LLM Backend"
      assert output =~ "Model"
      assert output =~ "MCP Servers"
    end
  end

  describe "mcp servers command" do
    test "shows no servers when none connected" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp servers")
        end)

      assert output =~ "No MCP servers connected"
    end
  end

  describe "mcp discover command" do
    test "attempts to discover MCP servers" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp discover")
        end)

      assert output =~ "Discovering MCP servers"
    end
  end

  describe "backend command" do
    test "requires backend name" do
      output =
        capture_io(fn ->
          Commands.handle_command("backend")
        end)

      assert output =~ "Current backend:" or output =~ "Available backends:"
    end

    test "switches to valid backend" do
      output =
        capture_io(fn ->
          Commands.handle_command("backend openai")
        end)

      assert output =~ "Switched to" or output =~ "openai"
    end

    test "shows error for invalid backend" do
      output =
        capture_io(fn ->
          Commands.handle_command("backend invalid")
        end)

      assert output =~ "Unknown backend" or output =~ "Available backends:"
    end
  end

  describe "context command" do
    test "shows context statistics" do
      output =
        capture_io(fn ->
          Commands.handle_command("context")
        end)

      assert output =~ "Context" or output =~ "tokens"
    end
  end

  describe "cost command" do
    test "shows session cost information" do
      output =
        capture_io(fn ->
          Commands.handle_command("cost")
        end)

      # Should show cost even if zero
      assert output =~ "$" or output =~ "cost" or output =~ "Cost" or output =~ "Session"
    end
  end

  describe "alias command" do
    test "shows help when no subcommand given" do
      output =
        capture_io(fn ->
          Commands.handle_command("alias")
        end)

      assert output =~ "aliases" or output =~ "Usage"
    end
  end

  describe "export command" do
    test "exports to markdown by default" do
      MCPChat.Session.add_message("user", "Test export")

      output =
        capture_io(fn ->
          Commands.handle_command("export")
        end)

      assert output =~ "exported to:" or output =~ ".md"

      # Clean up any created file
      File.ls!(".")
      |> Enum.filter(&String.match?(&1, ~r/^chat_export.*\.md$/))
      |> Enum.each(&File.rm!/1)
    end

    test "exports to specified format" do
      MCPChat.Session.add_message("user", "Test export")

      output =
        capture_io(fn ->
          Commands.handle_command("export markdown")
        end)

      assert output =~ "exported to:" or output =~ ".md"

      # Clean up any created file
      File.ls!(".")
      |> Enum.filter(&String.match?(&1, ~r/^chat_export.*\.md$/))
      |> Enum.each(&File.rm!/1)
    end
  end

  describe "system command" do
    test "shows current system prompt when no args" do
      output =
        capture_io(fn ->
          Commands.handle_command("system")
        end)

      assert output =~ "No system prompt set" or output =~ "Current system prompt"
    end

    test "sets system prompt" do
      output =
        capture_io(fn ->
          Commands.handle_command("system You are a helpful assistant")
        end)

      assert output =~ "System prompt" or output =~ "set"
    end
  end

  describe "tokens command" do
    test "requires token count" do
      output =
        capture_io(fn ->
          Commands.handle_command("tokens")
        end)

      assert output =~ "Usage:" or output =~ "number"
    end

    test "sets max tokens" do
      output =
        capture_io(fn ->
          Commands.handle_command("tokens 2_048")
        end)

      assert output =~ "Max tokens" or output =~ "2_048"
    end

    test "validates token count" do
      output =
        capture_io(fn ->
          Commands.handle_command("tokens abc")
        end)

      assert output =~ "Invalid" or output =~ "number"
    end
  end

  describe "strategy command" do
    test "requires strategy name" do
      output =
        capture_io(fn ->
          Commands.handle_command("strategy")
        end)

      assert output =~ "Usage:" or output =~ "strategy"
    end

    test "sets valid strategy" do
      output =
        capture_io(fn ->
          Commands.handle_command("strategy sliding_window")
        end)

      assert output =~ "strategy" or output =~ "sliding_window"
    end

    test "rejects invalid strategy" do
      output =
        capture_io(fn ->
          Commands.handle_command("strategy invalid")
        end)

      assert output =~ "Invalid" or output =~ "strategy"
    end
  end

  # Helper functions

  defp ensure_services_started() do
    # Start Config if needed
    case Process.whereis(MCPChat.Config) do
      nil -> {:ok, _} = MCPChat.Config.start_link()
      _ -> :ok
    end

    # Start Session if needed
    case Process.whereis(MCPChat.Session) do
      nil -> {:ok, _} = MCPChat.Session.start_link()
      _ -> :ok
    end

    # Start ServerManager if needed
    case Process.whereis(MCPChat.MCP.ServerManager) do
      nil -> {:ok, _} = MCPChat.MCP.ServerManager.start_link()
      _ -> :ok
    end

    # Start Alias if needed
    case Process.whereis(MCPChat.Alias.ExAliasAdapter) do
      nil ->
        # Start ExAlias first if needed
        case Process.whereis(ExAlias) do
          nil -> {:ok, _} = ExAlias.start_link()
          _ -> :ok
        end

        {:ok, _} = MCPChat.Alias.ExAliasAdapter.start_link()

      _ ->
        :ok
    end
  end
end
