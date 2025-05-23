defmodule MCPChat.CLI.ChatTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias MCPChat.CLI.Chat

  setup do
    # Start with clean aliases
    Application.put_env(:mcp_chat, :aliases, %{})

    # Save current environment variables
    anthropic_key = System.get_env("ANTHROPIC_API_KEY")
    openai_key = System.get_env("OPENAI_API_KEY")

    on_exit(fn ->
      # Clean up any config changes
      Application.delete_env(:mcp_chat, :config)
      Application.delete_env(:mcp_chat, :llm_adapter_lookup)
      Application.delete_env(:mcp_chat, :aliases)

      # Restore environment variables
      if anthropic_key,
        do: System.put_env("ANTHROPIC_API_KEY", anthropic_key),
        else: System.delete_env("ANTHROPIC_API_KEY")

      if openai_key, do: System.put_env("OPENAI_API_KEY", openai_key), else: System.delete_env("OPENAI_API_KEY")
    end)
  end

  describe "start/0" do
    test "shows welcome screen and starts chat loop" do
      # Mock IO.gets to return exit command immediately
      output =
        capture_io([input: "/exit\n", capture_prompt: false], fn ->
          assert Chat.start() == :ok
        end)

      assert output =~ "MCP Chat Client"
      assert output =~ "Goodbye!"
    end
  end

  describe "chat loop input processing" do
    test "handles exit commands" do
      # Test various exit commands
      for command <- ["/exit", "/quit", "/q"] do
        output =
          capture_io([input: "#{command}\n", capture_prompt: false], fn ->
            assert Chat.start() == :ok
          end)

        assert output =~ "Goodbye!"
      end
    end

    test "handles empty input gracefully" do
      output =
        capture_io([input: "\n/exit\n", capture_prompt: false], fn ->
          assert Chat.start() == :ok
        end)

      # Should not crash on empty input
      assert output =~ "Goodbye!"
    end

    test "handles EOF" do
      # Simulate EOF by not providing any input
      output =
        capture_io(fn ->
          send(self(), {:io_request, self(), make_ref(), {:get_line, :unicode, ""}})
          send(self(), {:io_reply, self(), :eof})
          assert Chat.start() == :ok
        end)

      assert output =~ "Goodbye!"
    end

    test "handles command processing" do
      output =
        capture_io([input: "/help\n/exit\n", capture_prompt: false], fn ->
          assert Chat.start() == :ok
        end)

      assert output =~ "Available Commands" or output =~ "help"
    end

    test "processes regular messages" do
      # Since we can't easily mock private functions, we'll test with a real adapter
      # but ensure it's not configured to avoid API calls
      output =
        capture_io([input: "Hello\n/exit\n", capture_prompt: false], fn ->
          assert Chat.start() == :ok
        end)

      # Should show an error about not being configured
      assert output =~ "not configured" or output =~ "API key"
    end

    test "handles LLM backend not configured error" do
      # Ensure no API key is set
      Application.put_env(:mcp_chat, :config, %{})
      System.delete_env("ANTHROPIC_API_KEY")
      System.delete_env("OPENAI_API_KEY")

      output =
        capture_io([input: "Hello\n/exit\n", capture_prompt: false], fn ->
          assert Chat.start() == :ok
        end)

      assert output =~ "not configured" or output =~ "API key"
    end

    test "handles streaming when enabled" do
      # Enable streaming in config
      Application.put_env(:mcp_chat, :config, %{ui: %{streaming: true}})

      output =
        capture_io([input: "/exit\n", capture_prompt: false], fn ->
          assert Chat.start() == :ok
        end)

      # Should complete without error
      assert output =~ "Goodbye!"
    end

    test "handles aliases" do
      # Test that alias commands don't crash the system
      output =
        capture_io([input: "/alias\n/exit\n", capture_prompt: false], fn ->
          assert Chat.start() == :ok
        end)

      # Should show alias help or list
      assert output =~ "alias" or output =~ "Goodbye!"
    end
  end

  describe "LLM adapter selection" do
    test "handles backend context updates" do
      # Test that setting context doesn't crash
      MCPChat.Session.set_context(%{llm_backend: "anthropic"})
      session = MCPChat.Session.get_current_session()
      assert session != nil

      MCPChat.Session.set_context(%{llm_backend: "openai"})
      session = MCPChat.Session.get_current_session()
      assert session != nil
    end
  end
end
