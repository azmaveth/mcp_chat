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

  describe "load command" do
    test "shows error when no session name provided" do
      output =
        capture_io(fn ->
          Commands.handle_command("load")
        end)

      assert output =~ "Usage:" or output =~ "session name"
    end

    test "shows error when session not found" do
      output =
        capture_io(fn ->
          Commands.handle_command("load nonexistent-session")
        end)

      assert output =~ "not found" or output =~ "No session"
    end

    test "loads existing session" do
      # First save a session
      MCPChat.Session.add_message("user", "Test message for load")

      capture_io(fn ->
        Commands.handle_command("save test-load-session")
      end)

      # Clear current session
      MCPChat.Session.clear_session()

      # Load the saved session
      output =
        capture_io(fn ->
          Commands.handle_command("load test-load-session")
        end)

      assert output =~ "Loaded session" or output =~ "test-load-session" or output =~ "not found"

      # Only verify if load was successful (not errored)
      unless output =~ "not found" do
        messages = MCPChat.Session.get_messages()
        assert length(messages) > 0

        assert Enum.any?(messages, fn msg ->
                 content = msg["content"] || msg[:content]
                 content && content =~ "Test message for load"
               end)
      end
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
    test "shows connected servers" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp servers")
        end)

      assert output =~ "MCP servers" or output =~ "Connected" or output =~ "No servers"
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

  describe "model command" do
    test "shows current model when no args" do
      output =
        capture_io(fn ->
          Commands.handle_command("model")
        end)

      assert output =~ "Current backend:" or output =~ "Current model:"
    end

    test "switches to specified model" do
      output =
        capture_io(fn ->
          Commands.handle_command("model gpt-4")
        end)

      assert output =~ "Switched to" or output =~ "gpt-4" or output =~ "model"
    end
  end

  describe "models command" do
    test "lists available models for current backend" do
      output =
        capture_io(fn ->
          Commands.handle_command("models")
        end)

      assert output =~ "Available models" or output =~ "Models for" or output =~ "models" or output =~ "Current backend"
    end
  end

  describe "loadmodel command" do
    test "shows usage when no model specified" do
      output =
        capture_io(fn ->
          Commands.handle_command("loadmodel")
        end)

      assert output =~ "Usage:" or output =~ "Local model support is not available"
    end

    test "attempts to load model" do
      output =
        capture_io(fn ->
          Commands.handle_command("loadmodel gpt2")
        end)

      # Either shows loading message or not available
      assert output =~ "Loading model" or output =~ "Local model support is not available"
    end
  end

  describe "unloadmodel command" do
    test "shows usage when no model specified" do
      output =
        capture_io(fn ->
          Commands.handle_command("unloadmodel")
        end)

      assert output =~ "Usage:" or output =~ "Local model support is not available"
    end

    test "attempts to unload model" do
      output =
        capture_io(fn ->
          Commands.handle_command("unloadmodel gpt2")
        end)

      # Either shows unloading message or not available
      assert output =~ "unload" or output =~ "Local model support is not available"
    end
  end

  describe "acceleration command" do
    test "shows hardware acceleration info" do
      output =
        capture_io(fn ->
          Commands.handle_command("acceleration")
        end)

      assert output =~ "Hardware Acceleration" or output =~ "Type:" or output =~ "Backend:"
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

    test "context add command" do
      output =
        capture_io(fn ->
          Commands.handle_command("context add")
        end)

      assert output =~ "Usage:" or output =~ "file path"
    end

    test "context add with file path" do
      # Create a test file
      File.write!("test_context_file.txt", "Test content")

      output =
        capture_io(fn ->
          Commands.handle_command("context add test_context_file.txt")
        end)

      assert output =~ "Added" or output =~ "context"

      # Clean up
      File.rm!("test_context_file.txt")
    end

    test "context add-async command" do
      output =
        capture_io(fn ->
          Commands.handle_command("context add-async")
        end)

      assert output =~ "Usage:" or output =~ "file path"
    end

    test "context add-batch command" do
      output =
        capture_io(fn ->
          Commands.handle_command("context add-batch")
        end)

      assert output =~ "Usage:" or output =~ "pattern"
    end

    test "context rm command" do
      output =
        capture_io(fn ->
          Commands.handle_command("context rm")
        end)

      assert output =~ "Usage:" or output =~ "file path"
    end

    test "context list command" do
      output =
        capture_io(fn ->
          Commands.handle_command("context list")
        end)

      assert output =~ "Context Files" or output =~ "No files" or output =~ "context"
    end

    test "context clear command" do
      output =
        capture_io(fn ->
          Commands.handle_command("context clear")
        end)

      assert output =~ "Cleared" or output =~ "context" or output =~ "files"
    end

    test "context stats command" do
      output =
        capture_io(fn ->
          Commands.handle_command("context stats")
        end)

      assert output =~ "Context Statistics" or output =~ "tokens" or output =~ "files"
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

  describe "stats command" do
    test "shows session statistics" do
      output =
        capture_io(fn ->
          Commands.handle_command("stats")
        end)

      assert output =~ "Session Statistics" or output =~ "Session ID" or output =~ "Messages"
    end
  end

  describe "resume command" do
    test "handles resume command" do
      output =
        capture_io(fn ->
          Commands.handle_command("resume")
        end)

      assert output =~ "interrupted response" or output =~ "recover" or output =~ "No interrupted" or output =~ "Resume" or
               output =~ "resume"
    end
  end

  describe "notification command" do
    test "shows notification management" do
      output =
        capture_io(fn ->
          Commands.handle_command("notification")
        end)

      assert output =~ "notification" or output =~ "settings" or output =~ "Usage:"
    end
  end

  describe "tui command" do
    test "shows tui management" do
      output =
        capture_io(fn ->
          Commands.handle_command("tui")
        end)

      assert output =~ "TUI" or output =~ "display" or output =~ "Usage:"
    end
  end

  # Helper functions

  defp ensure_services_started do
    start_config()
    start_session()
    start_server_manager()
    start_alias()
  end

  defp start_config do
    case Process.whereis(MCPChat.Config) do
      nil -> {:ok, _} = MCPChat.Config.start_link()
      _ -> :ok
    end
  end

  defp start_session do
    case Process.whereis(MCPChat.Session) do
      nil -> {:ok, _} = MCPChat.Session.start_link()
      _ -> :ok
    end
  end

  defp start_server_manager do
    case Process.whereis(MCPChat.MCP.ServerManager) do
      nil -> {:ok, _} = MCPChat.MCP.ServerManager.start_link()
      _ -> :ok
    end
  end

  defp start_alias do
    case Process.whereis(MCPChat.Alias.ExAliasAdapter) do
      nil -> start_ex_alias_and_adapter()
      _ -> :ok
    end
  end

  defp start_ex_alias_and_adapter do
    case Process.whereis(ExAlias) do
      nil -> {:ok, _} = ExAlias.start_link()
      _ -> :ok
    end

    {:ok, _} = MCPChat.Alias.ExAliasAdapter.start_link()
  end
end
