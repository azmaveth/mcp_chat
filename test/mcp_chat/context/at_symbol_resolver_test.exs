defmodule MCPChat.Context.AtSymbolResolverTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  alias MCPChat.Context.{AtSymbolResolver, AtSymbolParser}

  describe "resolve_reference/2 for files" do
    test "resolves existing text file" do
      # Create a temporary file
      file_path = System.tmp_dir!() |> Path.join("test_file.txt")
      File.write!(file_path, "Hello, World!")

      reference = %{
        type: :file,
        identifier: file_path,
        full_match: "@file:#{file_path}",
        start_pos: 0,
        end_pos: String.length("@file:#{file_path}")
      }

      result = AtSymbolResolver.resolve_reference(reference)

      assert result.content == "Hello, World!"
      assert result.error == nil
      assert result.metadata.size == 13

      # Clean up
      File.rm(file_path)
    end

    test "handles missing file" do
      reference = %{
        type: :file,
        identifier: "/nonexistent/file.txt",
        full_match: "@file:/nonexistent/file.txt",
        start_pos: 0,
        end_pos: 26
      }

      result = AtSymbolResolver.resolve_reference(reference)

      assert result.content == nil
      assert result.error == "File not found"
    end

    test "handles file too large" do
      # Create a large temporary file
      file_path = System.tmp_dir!() |> Path.join("large_file.txt")
      # 2MB
      large_content = String.duplicate("x", 2 * 1_024 * 1_024)
      File.write!(file_path, large_content)

      reference = %{
        type: :file,
        identifier: file_path,
        full_match: "@file:#{file_path}",
        start_pos: 0,
        end_pos: String.length("@file:#{file_path}")
      }

      result = AtSymbolResolver.resolve_reference(reference, max_file_size: 1_024 * 1_024)

      assert result.content == nil
      assert String.contains?(result.error, "File too large")

      # Clean up
      File.rm(file_path)
    end
  end

  describe "resolve_reference/2 for URLs" do
    @tag :external_network
    test "resolves HTTP URL" do
      reference = %{
        type: :url,
        identifier: "https://httpbin.org/get",
        full_match: "@url:https://httpbin.org/get",
        start_pos: 0,
        end_pos: 29
      }

      result = AtSymbolResolver.resolve_reference(reference, http_timeout: 15_000)

      # Should get JSON response
      assert result.content != nil
      assert result.error == nil
      assert result.metadata.status == 200
    end

    test "handles invalid URL" do
      reference = %{
        type: :url,
        identifier: "not-a-url",
        full_match: "@url:not-a-url",
        start_pos: 0,
        end_pos: 14
      }

      result = AtSymbolResolver.resolve_reference(reference)

      assert result.content == nil
      assert result.error != nil
    end
  end

  describe "resolve_reference/2 for MCP resources" do
    test "handles missing MCP server" do
      reference = %{
        type: :resource,
        identifier: "nonexistent_resource",
        full_match: "@resource:nonexistent_resource",
        start_pos: 0,
        end_pos: 30
      }

      # Should handle gracefully when MCP not available
      result = AtSymbolResolver.resolve_reference(reference)

      assert result.content == nil
      assert result.error != nil
    end
  end

  describe "resolve_all/2" do
    test "resolves multiple references" do
      # Create test files
      file1_path = System.tmp_dir!() |> Path.join("test1.txt")
      file2_path = System.tmp_dir!() |> Path.join("test2.txt")
      File.write!(file1_path, "Content 1")
      File.write!(file2_path, "Content 2")

      text = "Check @file:#{file1_path} and @file:#{file2_path}"

      result = AtSymbolResolver.resolve_all(text)

      assert result.resolved_text == "Check Content 1 and Content 2"
      assert length(result.results) == 2
      assert result.total_tokens > 0
      assert result.errors == []

      # Clean up
      File.rm(file1_path)
      File.rm(file2_path)
    end

    test "handles mixed success and failure" do
      # Create one file, reference another that doesn't exist
      file_path = System.tmp_dir!() |> Path.join("exists.txt")
      File.write!(file_path, "I exist")

      text = "Check @file:#{file_path} and @file:/missing.txt"

      result = AtSymbolResolver.resolve_all(text)

      assert String.contains?(result.resolved_text, "I exist")
      assert String.contains?(result.resolved_text, "[ERROR:")
      assert length(result.results) == 2
      assert length(result.errors) == 1

      # Clean up
      File.rm(file_path)
    end

    test "handles empty text" do
      result = AtSymbolResolver.resolve_all("")

      assert result.resolved_text == ""
      assert result.results == []
      assert result.total_tokens == 0
      assert result.errors == []
    end

    test "handles text without @ references" do
      text = "This is just normal text"
      result = AtSymbolResolver.resolve_all(text)

      assert result.resolved_text == text
      assert result.results == []
      assert result.total_tokens == 0
      assert result.errors == []
    end
  end

  describe "parse_tool_spec/1" do
    # This is a private function, so we'll test it via resolve_reference
    test "handles tool without arguments" do
      reference = %{
        type: :tool,
        identifier: "calculator",
        full_match: "@tool:calculator",
        start_pos: 0,
        end_pos: 16
      }

      # Should handle gracefully when MCP not available
      result = AtSymbolResolver.resolve_reference(reference)

      # We expect an error since no MCP servers are available
      assert result.content == nil
      assert result.error != nil
    end

    test "handles tool with arguments" do
      reference = %{
        type: :tool,
        identifier: "calculator:operation=add,a=5,b=3",
        full_match: "@tool:calculator:operation=add,a=5,b=3",
        start_pos: 0,
        end_pos: 37
      }

      # Should handle gracefully when MCP not available
      result = AtSymbolResolver.resolve_reference(reference)

      # We expect an error since no MCP servers are available
      assert result.content == nil
      assert result.error != nil
    end
  end

  describe "get_available_completions/1" do
    test "returns empty lists when no MCP servers available" do
      assert AtSymbolResolver.get_available_completions(:resource) == []
      assert AtSymbolResolver.get_available_completions(:prompt) == []
      assert AtSymbolResolver.get_available_completions(:tool) == []
      assert AtSymbolResolver.get_available_completions(:file) == []
      assert AtSymbolResolver.get_available_completions(:url) == []
    end
  end
end
