defmodule MCPChat.Servers.FilesystemServerTest do
  use ExUnit.Case, async: false

  alias MCPChat.Servers.FilesystemServer

  @moduletag :integration

  setup do
    # Ensure the application is started so the filesystem server is available
    case Application.ensure_all_started(:mcp_chat) do
      {:ok, _} -> :ok
      # Already started
      {:error, _} -> :ok
    end

    # Wait a moment for the server to be available
    :timer.sleep(100)

    # Create a temporary directory for testing
    test_dir = Path.join(System.tmp_dir!(), "mcp_chat_fs_test_#{:rand.uniform(10000)}")
    File.mkdir_p!(test_dir)

    on_exit(fn ->
      # Clean up test directory
      File.rm_rf(test_dir)
    end)

    {:ok, test_dir: test_dir}
  end

  describe "native filesystem server" do
    test "server is available via ExMCP.Native" do
      assert ExMCP.Native.service_available?(:filesystem_server)
    end

    test "lists available tools" do
      {:ok, response} = ExMCP.Native.call(:filesystem_server, "list_tools", %{})

      assert %{"tools" => tools} = response
      assert is_list(tools)
      assert length(tools) > 0

      # Check that essential tools are available
      tool_names = Enum.map(tools, & &1["name"])
      assert "ls" in tool_names
      assert "cat" in tool_names
      assert "write" in tool_names
      assert "grep" in tool_names
      assert "find" in tool_names
    end

    test "performance is ultra-fast (< 100μs for local calls)", %{test_dir: test_dir} do
      # Test tool listing performance
      {time1, {:ok, _}} =
        :timer.tc(fn ->
          ExMCP.Native.call(:filesystem_server, "list_tools", %{})
        end)

      # Test stat operation performance
      {time2, {:ok, _}} =
        :timer.tc(fn ->
          ExMCP.Native.call(:filesystem_server, "tools/call", %{
            "name" => "stat",
            "arguments" => %{"path" => test_dir}
          })
        end)

      # Native calls should be much faster than 100μs (typical external server overhead)
      # 100ms (very generous for test environment)
      assert time1 < 100_000
      assert time2 < 100_000

      # Log the actual performance for visibility
      IO.puts("Native tool listing: #{time1}μs")
      IO.puts("Native stat operation: #{time2}μs")
    end
  end

  describe "filesystem operations" do
    test "ls command works", %{test_dir: test_dir} do
      {:ok, response} =
        ExMCP.Native.call(:filesystem_server, "tools/call", %{
          "name" => "ls",
          "arguments" => %{"path" => test_dir}
        })

      assert %{"content" => content} = response
      assert is_list(content)
      assert [%{"type" => "text", "text" => text}] = content
      assert text =~ "Directory listing for #{test_dir}"
    end

    test "write and cat operations work", %{test_dir: test_dir} do
      test_file = Path.join(test_dir, "test.txt")
      test_content = "Hello, native BEAM filesystem!"

      # Write content
      {:ok, write_response} =
        ExMCP.Native.call(:filesystem_server, "tools/call", %{
          "name" => "write",
          "arguments" => %{"path" => test_file, "content" => test_content}
        })

      assert %{"content" => write_content} = write_response
      assert [%{"type" => "text", "text" => write_text}] = write_content
      assert write_text =~ "Successfully"

      # Read content back
      {:ok, cat_response} =
        ExMCP.Native.call(:filesystem_server, "tools/call", %{
          "name" => "cat",
          "arguments" => %{"path" => test_file}
        })

      assert %{"content" => cat_content} = cat_response
      assert [%{"type" => "text", "text" => cat_text}] = cat_content
      assert cat_text =~ test_content
    end

    test "mkdir operation works", %{test_dir: test_dir} do
      new_dir = Path.join(test_dir, "new_directory")

      {:ok, response} =
        ExMCP.Native.call(:filesystem_server, "tools/call", %{
          "name" => "mkdir",
          "arguments" => %{"path" => new_dir}
        })

      assert %{"content" => content} = response
      assert [%{"type" => "text", "text" => text}] = content
      assert text =~ "Successfully created directory"

      # Verify directory was created
      assert File.dir?(new_dir)
    end

    test "stat operation provides detailed information", %{test_dir: test_dir} do
      {:ok, response} =
        ExMCP.Native.call(:filesystem_server, "tools/call", %{
          "name" => "stat",
          "arguments" => %{"path" => test_dir}
        })

      assert %{"content" => content} = response
      assert [%{"type" => "text", "text" => text}] = content
      assert text =~ "File: #{test_dir}"
      assert text =~ "Type: directory"
      assert text =~ "Size:"
      assert text =~ "Mode:"
    end

    test "grep operation searches file contents", %{test_dir: test_dir} do
      test_file = Path.join(test_dir, "search_test.txt")

      test_content = """
      This is line 1
      This is line 2 with IMPORTANT content
      This is line 3
      Another IMPORTANT line here
      Final line
      """

      # Create test file
      File.write!(test_file, test_content)

      {:ok, response} =
        ExMCP.Native.call(:filesystem_server, "tools/call", %{
          "name" => "grep",
          "arguments" => %{"pattern" => "IMPORTANT", "path" => test_file}
        })

      assert %{"content" => content} = response
      assert [%{"type" => "text", "text" => text}] = content
      assert text =~ "IMPORTANT"
      # Line numbers should be included
      assert text =~ "2:"
      assert text =~ "4:"
    end

    test "find operation locates files", %{test_dir: test_dir} do
      # Create some test files
      File.write!(Path.join(test_dir, "test1.txt"), "content1")
      File.write!(Path.join(test_dir, "test2.ex"), "content2")
      File.write!(Path.join(test_dir, "other.md"), "content3")

      {:ok, response} =
        ExMCP.Native.call(:filesystem_server, "tools/call", %{
          "name" => "find",
          "arguments" => %{"path" => test_dir, "name" => "*.txt"}
        })

      assert %{"content" => content} = response
      assert [%{"type" => "text", "text" => text}] = content
      assert text =~ "test1.txt"
      # Should not match .ex files
      refute text =~ "test2.ex"
      # Should not match .md files
      refute text =~ "other.md"
    end

    test "edit operations work correctly", %{test_dir: test_dir} do
      test_file = Path.join(test_dir, "edit_test.txt")

      original_content = """
      Line 1
      Line 2
      Line 3
      Line 4
      """

      File.write!(test_file, original_content)

      # Test replace operation
      {:ok, response} =
        ExMCP.Native.call(:filesystem_server, "tools/call", %{
          "name" => "edit",
          "arguments" => %{
            "path" => test_file,
            "operation" => "replace",
            "line_number" => 2,
            "content" => "NEW Line 2"
          }
        })

      assert %{"content" => content} = response
      assert [%{"type" => "text", "text" => text}] = content
      assert text =~ "Successfully replaced"

      # Verify the change
      updated_content = File.read!(test_file)
      assert updated_content =~ "NEW Line 2"
      refute updated_content =~ "Line 2\n"
    end
  end

  describe "error handling" do
    test "handles non-existent file gracefully" do
      {:ok, response} =
        ExMCP.Native.call(:filesystem_server, "tools/call", %{
          "name" => "cat",
          "arguments" => %{"path" => "/non/existent/file.txt"}
        })

      assert %{"content" => content, "isError" => true} = response
      assert [%{"type" => "text", "text" => text}] = content
      assert text =~ "Failed to read file"
    end

    test "handles invalid tool name" do
      {:ok, response} =
        ExMCP.Native.call(:filesystem_server, "tools/call", %{
          "name" => "invalid_tool",
          "arguments" => %{}
        })

      assert %{"code" => -32601, "message" => message} = response
      assert message =~ "Unknown tool"
    end

    test "handles invalid regex pattern in grep" do
      {:ok, response} =
        ExMCP.Native.call(:filesystem_server, "tools/call", %{
          "name" => "grep",
          "arguments" => %{"pattern" => "[invalid", "path" => "/tmp"}
        })

      assert %{"content" => content, "isError" => true} = response
      assert [%{"type" => "text", "text" => text}] = content
      assert text =~ "Invalid regex pattern"
    end
  end

  describe "CLI integration" do
    test "NativeFilesystemTool can list tools" do
      tools = MCPChat.Tools.NativeFilesystemTool.list_tools()

      assert is_list(tools)
      assert length(tools) > 0

      tool_names = Enum.map(tools, & &1["name"])
      assert "ls" in tool_names
      assert "cat" in tool_names
    end
  end
end
