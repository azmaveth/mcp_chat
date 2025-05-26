defmodule MCPChat.SimpleE2ETest do
  use ExUnit.Case, async: false

  @moduledoc """
  Simple E2E test to verify basic Ollama functionality.
  """

  require Logger

  @ollama_url "http://localhost:11_434"
  @test_timeout 60_000

  setup_all do
    # Set up environment
    System.put_env("OLLAMA_API_BASE", @ollama_url)
    Application.put_env(:ex_llm, :ollama_base_url, @ollama_url)

    # Check for available models
    case ExLLM.list_models(:ollama, config_provider: ExLLM.ConfigProvider.Env) do
      {:ok, models} when models != [] ->
        model_names = Enum.map(models, & &1.id)

        # Use the first available model
        test_model = hd(model_names)
        Logger.info("Simple E2E: Using model #{test_model}")

        {:ok, %{model: test_model}}

      _ ->
        Logger.error("Simple E2E: No models available")
        :ignore
    end
  end

  describe "Basic Ollama Integration" do
    @tag timeout: @test_timeout
    test "simple chat request", %{model: model} do
      messages = [%{role: "user", content: "Say exactly: Hello World"}]

      result =
        ExLLM.chat(:ollama, messages,
          model: model,
          temperature: 0.1,
          max_tokens: 50,
          config_provider: ExLLM.ConfigProvider.Env
        )

      case result do
        {:ok, response} ->
          assert response.content != nil
          assert String.length(response.content) > 0
          Logger.info("Response: #{response.content}")

        {:error, reason} ->
          Logger.error("Chat failed: #{inspect(reason)}")
          flunk("Chat request failed: #{inspect(reason)}")
      end
    end

    @tag timeout: @test_timeout
    test "list models", %{model: _model} do
      case ExLLM.list_models(:ollama, config_provider: ExLLM.ConfigProvider.Env) do
        {:ok, models} ->
          assert is_list(models)
          assert length(models) > 0

          Enum.each(models, fn model ->
            assert model.id != nil
            Logger.info("Available model: #{model.id}")
          end)

        {:error, reason} ->
          flunk("Failed to list models: #{inspect(reason)}")
      end
    end
  end
end
