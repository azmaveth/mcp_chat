defmodule MCPChat.MCP.BuiltinResourcesTest do
  use ExUnit.Case
  alias MCPChat.MCP.BuiltinResources

  alias MCPChat.MCP.BuiltinResourcesTest

  setup do
    # Ensure Config is started for the config resource test
    case Process.whereis(MCPChat.Config) do
      nil -> {:ok, _} = MCPChat.Config.start_link()
      _ -> :ok
    end

    :ok
  end

  describe "list_resources/0" do
    test "returns all built-in resources" do
      resources = BuiltinResources.list_resources()

      assert is_list(resources)
      assert length(resources) > 0

      # Check all resources have required fields
      for resource <- resources do
        assert Map.has_key?(resource, :uri)
        assert Map.has_key?(resource, :name)
        assert Map.has_key?(resource, :description)
        assert Map.has_key?(resource, :mimeType)
      end

      # Check some expected resources exist
      resource_names = Enum.map(resources, & &1.name)
      assert "MCP Chat Documentation" in resource_names
      assert "Command Reference" in resource_names
      assert "Version Information" in resource_names
    end
  end

  describe "read_resource/1" do
    test "reads documentation resource" do
      {:ok, content} = BuiltinResources.read_resource("mcp-chat://docs/readme")

      assert is_binary(content)
      assert content =~ "MCP Chat"
      assert content =~ "Quick Reference"
    end

    test "reads commands resource" do
      {:ok, content} = BuiltinResources.read_resource("mcp-chat://docs/commands")

      assert is_binary(content)
      assert content =~ "Command Reference"
      assert content =~ "/help"
    end

    test "reads version resource" do
      {:ok, content} = BuiltinResources.read_resource("mcp-chat://info/version")

      assert is_binary(content)
      assert content =~ "MCP Chat"
      assert content =~ "MCP Chat v"
    end

    test "reads config resource" do
      {:ok, content} = BuiltinResources.read_resource("mcp-chat://info/config")

      assert is_binary(content)
      # Should be valid JSON
      assert {:ok, _} = Jason.decode(content)
    end

    test "returns error for unknown resource" do
      assert {:error, "Resource not found"} =
               BuiltinResources.read_resource("unknown://resource")
    end
  end

  describe "list_prompts/0" do
    test "returns all built-in prompts" do
      prompts = BuiltinResources.list_prompts()

      assert is_list(prompts)
      assert length(prompts) > 0

      # Check all prompts have required fields
      for prompt <- prompts do
        assert Map.has_key?(prompt, :name)
        assert Map.has_key?(prompt, :description)
      end

      # Check some expected prompts exist
      prompt_names = Enum.map(prompts, & &1.name)
      assert "getting_started" in prompt_names
      assert "demo" in prompt_names
      assert "troubleshoot" in prompt_names
    end
  end

  describe "get_prompt/1" do
    test "gets getting_started prompt" do
      {:ok, prompt} = BuiltinResources.get_prompt("getting_started")

      assert Map.has_key?(prompt, :name)
      assert Map.has_key?(prompt, :template)
      assert Map.has_key?(prompt, :arguments)

      assert prompt.name == "getting_started"
      assert is_binary(prompt.template)
      assert is_list(prompt.arguments)
    end

    test "gets demo prompt" do
      {:ok, prompt} = BuiltinResources.get_prompt("demo")

      assert prompt.name == "demo"
      assert prompt.template =~ "demonstrate"
      assert is_list(prompt.arguments)
    end

    test "returns error for unknown prompt" do
      assert {:error, "Prompt not found"} =
               BuiltinResources.get_prompt("unknown_prompt")
    end
  end
end
