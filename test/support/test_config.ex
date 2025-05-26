defmodule MCPChat.TestConfig do
  @moduledoc """
  Test configuration helpers for E2E tests.
  """

  def setup_test_config() do
    # Set up a minimal test configuration
    config = %{
      "llm" => %{
        "provider" => "ollama",
        "base_url" => "http://localhost:11_434",
        "temperature" => 0.1,
        "max_tokens" => 500
      },
      "mcp" => %{
        "servers" => %{}
      },
      "ui" => %{
        "prompt" => "test> ",
        "show_cost" => false,
        "show_tokens" => true
      },
      "session" => %{
        "autosave" => false,
        "context_limit" => 4_000
      }
    }

    # Apply config to application environment
    Application.put_env(:mcp_chat, :config, config)
    Application.put_env(:mcp_chat, :llm, config["llm"])
    Application.put_env(:mcp_chat, :mcp, config["mcp"])
    Application.put_env(:mcp_chat, :ui, config["ui"])
    Application.put_env(:mcp_chat, :session, config["session"])

    # Configure ex_llm
    Application.put_env(:ex_llm, :ollama_base_url, config["llm"]["base_url"])
    Application.put_env(:ex_llm, :default_provider, :ollama)

    :ok
  end

  def reset_config() do
    # Reset to default configuration
    Application.delete_env(:mcp_chat, :config)
    Application.delete_env(:mcp_chat, :llm)
    Application.delete_env(:mcp_chat, :mcp)
    Application.delete_env(:mcp_chat, :ui)
    Application.delete_env(:mcp_chat, :session)

    :ok
  end

  def set_llm_backend(provider, model) do
    config = Application.get_env(:mcp_chat, :llm, %{})
    updated_config = Map.merge(config, %{"provider" => provider, "model" => model})
    Application.put_env(:mcp_chat, :llm, updated_config)

    # Also update ex_llm config
    case provider do
      "ollama" ->
        Application.put_env(:ex_llm, :default_provider, :ollama)
        Application.put_env(:ex_llm, :default_model, model)

      "anthropic" ->
        Application.put_env(:ex_llm, :default_provider, :anthropic)
        Application.put_env(:ex_llm, :default_model, model)

      _ ->
        :ok
    end

    {:ok, updated_config}
  end
end
