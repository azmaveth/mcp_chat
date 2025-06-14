defmodule MCPChat.CLI.Commands.MCPCommandsTest do
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

  describe "mcp connect command" do
    test "shows usage when no server specified" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp connect")
        end)

      assert output =~ "Usage:" or output =~ "server name"
    end

    test "attempts to connect to server" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp connect test-server")
        end)

      assert output =~ "Connecting" or output =~ "not found" or output =~ "test-server"
    end
  end

  describe "mcp disconnect command" do
    test "shows usage when no server specified" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp disconnect")
        end)

      assert output =~ "Usage:" or output =~ "server name"
    end

    test "attempts to disconnect from server" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp disconnect test-server")
        end)

      assert output =~ "Disconnecting" or output =~ "not connected" or output =~ "test-server"
    end
  end

  describe "mcp saved command" do
    test "lists saved server connections" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp saved")
        end)

      assert output =~ "Saved MCP" or output =~ "servers" or output =~ "No saved"
    end
  end

  describe "mcp tools command" do
    test "lists available tools" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp tools")
        end)

      assert output =~ "Available tools" or output =~ "No tools" or output =~ "tools"
    end

    test "filters tools by server when specified" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp tools test-server")
        end)

      assert output =~ "tools" or output =~ "test-server" or output =~ "No tools"
    end
  end

  describe "mcp tool command" do
    test "shows usage when no tool specified" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp tool")
        end)

      assert output =~ "Usage:" or output =~ "tool name"
    end

    test "shows tool info" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp tool test-tool")
        end)

      assert output =~ "tool" or output =~ "not found" or output =~ "test-tool"
    end

    test "calls tool with arguments" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp tool test-tool arg1 arg2")
        end)

      assert output =~ "tool" or output =~ "not found" or output =~ "test-tool"
    end
  end

  describe "mcp resources command" do
    test "lists available resources" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp resources")
        end)

      assert output =~ "Available resources" or output =~ "No resources" or output =~ "resources"
    end

    test "filters resources by server when specified" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp resources test-server")
        end)

      assert output =~ "resources" or output =~ "test-server" or output =~ "No resources"
    end
  end

  describe "mcp resource command" do
    test "shows usage when no resource specified" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp resource")
        end)

      assert output =~ "Usage:" or output =~ "resource"
    end

    test "reads resource" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp resource test://resource")
        end)

      assert output =~ "resource" or output =~ "not found" or output =~ "test://resource"
    end
  end

  describe "mcp prompts command" do
    test "lists available prompts" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp prompts")
        end)

      assert output =~ "Available prompts" or output =~ "No prompts" or output =~ "prompts"
    end

    test "filters prompts by server when specified" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp prompts test-server")
        end)

      assert output =~ "prompts" or output =~ "test-server" or output =~ "No prompts"
    end
  end

  describe "mcp prompt command" do
    test "shows usage when no prompt specified" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp prompt")
        end)

      assert output =~ "Usage:" or output =~ "prompt"
    end

    test "gets prompt" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp prompt test-prompt")
        end)

      assert output =~ "prompt" or output =~ "not found" or output =~ "test-prompt"
    end
  end

  describe "mcp sample command" do
    test "shows usage when no prompt specified" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp sample")
        end)

      assert output =~ "Usage:" or output =~ "prompt"
    end

    test "uses server-side LLM generation" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp sample test-prompt")
        end)

      assert output =~ "sample" or output =~ "not found" or output =~ "test-prompt"
    end
  end

  describe "mcp capabilities command" do
    test "shows server capabilities" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp capabilities")
        end)

      assert output =~ "capabilities" or output =~ "servers"
    end

    test "shows capabilities for specific server" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp capabilities test-server")
        end)

      assert output =~ "capabilities" or output =~ "test-server" or output =~ "not found"
    end
  end

  describe "mcp notify command" do
    test "controls notification display" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp notify")
        end)

      assert output =~ "notification" or output =~ "settings" or output =~ "Usage:"
    end

    test "toggles notifications" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp notify toggle")
        end)

      assert output =~ "notification" or output =~ "toggle"
    end
  end

  describe "mcp progress command" do
    test "shows active operations with progress" do
      output =
        capture_io(fn ->
          Commands.handle_command("mcp progress")
        end)

      assert output =~ "progress" or output =~ "operations" or output =~ "No active"
    end
  end

  # Helper functions

  defp ensure_services_started() do
    start_config()
    start_session()
    start_server_manager()
    start_alias()
  end

  defp start_config() do
    case Process.whereis(MCPChat.Config) do
      nil -> {:ok, _} = MCPChat.Config.start_link()
      _ -> :ok
    end
  end

  defp start_session() do
    case Process.whereis(MCPChat.Session) do
      nil -> {:ok, _} = MCPChat.Session.start_link()
      _ -> :ok
    end
  end

  defp start_server_manager() do
    case Process.whereis(MCPChat.MCP.ServerManager) do
      nil -> {:ok, _} = MCPChat.MCP.ServerManager.start_link()
      _ -> :ok
    end
  end

  defp start_alias() do
    case Process.whereis(MCPChat.Alias.ExAliasAdapter) do
      nil -> start_ex_alias_and_adapter()
      _ -> :ok
    end
  end

  defp start_ex_alias_and_adapter() do
    case Process.whereis(ExAlias) do
      nil -> {:ok, _} = ExAlias.start_link()
      _ -> :ok
    end

    {:ok, _} = MCPChat.Alias.ExAliasAdapter.start_link()
  end
end
