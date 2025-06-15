defmodule AtSymbolParserTest do
  use ExUnit.Case, async: true

  alias AtSymbolParser

  alias AtSymbolParserTest

  describe "parse/1" do
    test "parses single @ reference" do
      text = "Please review @file:src/main.ex for issues"

      result = AtSymbolParser.parse(text)

      assert length(result) == 1

      assert hd(result) == %{
               type: :file,
               identifier: "src/main.ex",
               full_match: "@file:src/main.ex",
               start_pos: 14,
               end_pos: 30
             }
    end

    test "parses multiple @ references" do
      text = "Compare @file:config.toml with @url:https://example.com/config"

      result = AtSymbolParser.parse(text)

      assert length(result) == 2
      assert Enum.at(result, 0).type == :file
      assert Enum.at(result, 0).identifier == "config.toml"
      assert Enum.at(result, 1).type == :url
      assert Enum.at(result, 1).identifier == "https://example.com/config"
    end

    test "handles short form @ references" do
      text = "Use @r:docs.md and @p:review_code and @t:calculator"

      result = AtSymbolParser.parse(text)

      assert length(result) == 3
      assert Enum.at(result, 0).type == :resource
      assert Enum.at(result, 1).type == :prompt
      assert Enum.at(result, 2).type == :tool
    end

    test "returns empty list for text without @ references" do
      text = "This is just normal text without any special symbols"

      result = AtSymbolParser.parse(text)

      assert result == []
    end

    test "ignores malformed @ references" do
      text = "This has @ symbol but no colon and @incomplete"

      result = AtSymbolParser.parse(text)

      assert result == []
    end

    test "handles complex identifiers" do
      text = "@file:/absolute/path/file.txt and @url:https://api.example.com/v1/resource?param=value"

      result = AtSymbolParser.parse(text)

      assert length(result) == 2
      assert Enum.at(result, 0).identifier == "/absolute/path/file.txt"
      assert Enum.at(result, 1).identifier == "https://api.example.com/v1/resource?param=value"
    end
  end

  describe "remove_references/3" do
    test "removes single reference" do
      text = "Please review @file:main.ex for issues"
      references = AtSymbolParser.parse(text)

      result = AtSymbolParser.remove_references(text, references)

      assert result == "Please review  for issues"
    end

    test "removes multiple references" do
      text = "Compare @file:a.txt with @file:b.txt"
      references = AtSymbolParser.parse(text)

      result = AtSymbolParser.remove_references(text, references)

      assert result == "Compare  with "
    end

    test "replaces references with placeholder" do
      text = "Please review @file:main.ex for issues"
      references = AtSymbolParser.parse(text)

      result = AtSymbolParser.remove_references(text, references, "[INCLUDED]")

      assert result == "Please review [INCLUDED] for issues"
    end
  end

  describe "extract_identifiers/2" do
    test "extracts identifiers for specific type" do
      text = "Use @file:a.txt and @resource:docs and @file:b.txt"
      references = AtSymbolParser.parse(text)

      file_ids = AtSymbolParser.extract_identifiers(references, :file)
      resource_ids = AtSymbolParser.extract_identifiers(references, :resource)

      assert file_ids == ["a.txt", "b.txt"]
      assert resource_ids == ["docs"]
    end

    test "returns unique identifiers" do
      text = "Use @file:test.txt and @file:test.txt again"
      references = AtSymbolParser.parse(text)

      file_ids = AtSymbolParser.extract_identifiers(references, :file)

      assert file_ids == ["test.txt"]
    end
  end

  describe "validate_reference/1" do
    test "validates correct reference" do
      result = AtSymbolParser.validate_reference("@file:test.txt")

      assert {:ok, reference} = result
      assert reference.type == :file
      assert reference.identifier == "test.txt"
    end

    test "rejects empty identifier" do
      result = AtSymbolParser.validate_reference("@file:")

      assert {:error, "Empty identifier in @ reference"} = result
    end

    test "rejects invalid file path" do
      result = AtSymbolParser.validate_reference("@file:invalid<path")

      assert {:error, "Invalid file path in @ reference"} = result
    end

    test "rejects invalid URL" do
      result = AtSymbolParser.validate_reference("@url:not-a-url")

      assert {:error, "Invalid URL in @ reference"} = result
    end

    test "rejects multiple references" do
      result = AtSymbolParser.validate_reference("@file:a.txt @file:b.txt")

      assert {:error, "Multiple @ references found, expected single reference"} = result
    end
  end

  describe "get_completion_suggestions/1" do
    test "suggests completions for partial @ symbols" do
      assert "@resource:" in AtSymbolParser.get_completion_suggestions("@r")
      assert "@r:" in AtSymbolParser.get_completion_suggestions("@r")
      assert "@prompt:" in AtSymbolParser.get_completion_suggestions("@p")
      assert "@tool:" in AtSymbolParser.get_completion_suggestions("@t")
    end

    test "suggests all types for bare @" do
      suggestions = AtSymbolParser.get_completion_suggestions("@")

      assert "@resource:" in suggestions
      assert "@prompt:" in suggestions
      assert "@tool:" in suggestions
      assert "@file:" in suggestions
      assert "@url:" in suggestions
    end

    test "returns empty list for non-@ text" do
      assert AtSymbolParser.get_completion_suggestions("normal text") == []
    end
  end
end
