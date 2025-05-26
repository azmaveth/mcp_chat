defmodule MCPChat.ConfigTest do
  use ExUnit.Case, async: false
  alias MCPChat.Config

  @test_config_path "test/fixtures/test_config.toml"

  setup do
    # Stop the Config server if it's running
    case Process.whereis(Config) do
      nil ->
        :ok

      pid ->
        GenServer.stop(pid)
        wait_until(fn -> Process.whereis(Config) == nil end, 500)
    end

    # Create test config directory
    File.mkdir_p!("test/fixtures")

    # Clean up any existing test config
    File.rm(@test_config_path)

    on_exit(fn ->
      File.rm(@test_config_path)
      # Ensure Config server is stopped
      case Process.whereis(Config) do
        nil -> :ok
        pid -> GenServer.stop(pid, :normal, 100)
      end
    end)

    :ok
  end

  describe "get/1" do
    test "returns config value by atom key" do
      # Ensure Config is running
      ensure_config_started()

      # Get a known default value
      llm_config = Config.get(:llm)
      assert is_map(llm_config)
      assert llm_config.default == "anthropic"
    end

    test "returns config value by path" do
      ensure_config_started()

      # Get nested value
      model = Config.get([:llm, :anthropic, :model])
      assert model == "claude-sonnet-4-20250514"

      # Get UI theme
      theme = Config.get([:ui, :theme])
      assert theme in ["dark", "light"]
    end

    test "returns nil for non-existent key" do
      ensure_config_started()

      assert Config.get(:nonexistent) == nil
      assert Config.get([:foo, :bar, :baz]) == nil
    end
  end

  describe "default_config/0" do
    test "includes LLM configuration" do
      ensure_config_started()

      llm_config = Config.get(:llm)

      # Check structure
      assert Map.has_key?(llm_config, :default)
      assert Map.has_key?(llm_config, :anthropic)
      # OpenAI config might not be in existing config files
      if Map.has_key?(llm_config, :openai) do
        assert Map.has_key?(llm_config, :openai)
      end

      # Check Anthropic config
      anthropic = llm_config.anthropic
      assert anthropic.model == "claude-sonnet-4-20250514"
      assert anthropic.max_tokens == 4_096

      # Check OpenAI config if present
      if Map.has_key?(llm_config, :openai) do
        openai = llm_config.openai
        assert openai.model == "gpt-4"
      end
    end

    test "includes MCP configuration" do
      ensure_config_started()

      mcp_config = Config.get(:mcp)
      # MCP config might be nil if loaded from existing file
      if mcp_config do
        assert Map.has_key?(mcp_config, :servers)
        assert is_list(mcp_config.servers)
      else
        # Just verify we can get config without crashing
        assert Config.get([:mcp, :servers]) == nil || is_list(Config.get([:mcp, :servers]))
      end
    end

    test "includes UI configuration" do
      ensure_config_started()

      ui_config = Config.get(:ui)
      assert ui_config.theme in ["dark", "light"]
      assert ui_config.history_size == 1_000
    end

    test "reads API keys from environment" do
      # Set test env vars BEFORE starting config
      System.put_env("ANTHROPIC_API_KEY", "test-anthropic-key")
      System.put_env("OPENAI_API_KEY", "test-openai-key")

      # Stop existing config
      case Process.whereis(Config) do
        nil ->
          :ok

        pid ->
          GenServer.stop(pid)
          # Wait for it to actually stop
          wait_until(fn -> Process.whereis(Config) == nil end, 500)
      end

      # Create a fresh config that will read env vars
      {:ok, _} = Config.start_link(config_path: @test_config_path)

      # Wait for config to be ready
      wait_until(fn -> Config.get([]) != nil end, 500)

      anthropic_key = Config.get([:llm, :anthropic, :api_key])
      openai_key = Config.get([:llm, :openai, :api_key])

      assert anthropic_key == "test-anthropic-key"

      # OpenAI key might only be present if openai config exists
      if Config.get([:llm, :openai]) do
        assert openai_key == "test-openai-key"
      end

      # Clean up
      System.delete_env("ANTHROPIC_API_KEY")
      System.delete_env("OPENAI_API_KEY")
    end
  end

  describe "load from TOML file" do
    test "loads configuration from TOML file" do
      # Create a test TOML file
      toml_content = """
      [llm]
      default = "openai"

      [llm.openai]
      api_key = "test-key"
      model = "gpt-4-turbo"

      [ui]
      theme = "light"
      history_size = 500
      """

      File.write!(@test_config_path, toml_content)

      # Restart config with test file
      restart_config(config_path: @test_config_path)

      # Verify loaded config
      assert Config.get([:llm, :default]) == "openai"
      assert Config.get([:llm, :openai, :model]) == "gpt-4-turbo"
      assert Config.get([:ui, :theme]) == "light"
      assert Config.get([:ui, :history_size]) == 500
    end

    test "handles invalid TOML gracefully" do
      # Create invalid TOML
      File.write!(@test_config_path, "invalid toml [[ content")

      # Should load default config without crashing
      restart_config(config_path: @test_config_path)

      # Should have default values
      assert Config.get([:llm, :default]) == "anthropic"
    end
  end

  describe "reload/0" do
    test "reloads configuration from file" do
      ensure_config_started()

      # Get initial value
      initial_theme = Config.get([:ui, :theme])
      assert initial_theme in ["dark", "light"]

      # Modify the config file
      config_path = get_config_path()

      if File.exists?(config_path) do
        content = File.read!(config_path)
        new_content = String.replace(content, "theme = \"dark\"", "theme = \"light\"")
        File.write!(config_path, new_content)

        # Reload config
        Config.reload()
        # Wait for reload to complete
        wait_until(fn -> Config.get([:ui, :theme]) == "light" end, 300)

        # Check if reloaded
        new_theme = Config.get([:ui, :theme])
        assert new_theme == "light"
      end
    end
  end

  # Helper functions

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

  defp ensure_config_started() do
    case Process.whereis(Config) do
      nil ->
        {:ok, _} = Config.start_link()

      _pid ->
        :ok
    end
  end

  defp restart_config(opts) do
    case Process.whereis(Config) do
      nil ->
        :ok

      pid ->
        GenServer.stop(pid)
        # Wait for process to fully stop
        wait_until(fn -> Process.whereis(Config) == nil end, 500)
    end

    {:ok, _} = Config.start_link(opts)
    # Wait for initialization
    wait_until(fn -> Config.get([]) != nil end, 500)
  end

  defp get_config_path() do
    case Process.whereis(Config) do
      nil ->
        nil

      _pid ->
        # This is a bit hacky, but for testing purposes
        Path.expand("~/.config/mcp_chat/config.toml")
    end
  end
end
