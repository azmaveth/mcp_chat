defmodule MCPChat.LLM.GeminiTest do
  use ExUnit.Case
  alias MCPChat.LLM.Gemini

  describe "basic functionality" do
    test "configured? returns false when no API key" do
      # This test assumes no Google API key is set in the test environment
      refute Gemini.configured?()
    end

    test "default_model returns expected model" do
      assert Gemini.default_model() == "gemini-pro"
    end

    test "list_models returns expected format" do
      assert {:ok, models} = Gemini.list_models()
      assert is_list(models)
      assert length(models) > 0

      # Check if models have the expected structure
      Enum.each(models, fn model ->
        assert is_map(model)
        assert Map.has_key?(model, :id)
        assert Map.has_key?(model, :name)
        assert Map.has_key?(model, :supports_vision)
        assert Map.has_key?(model, :max_tokens)
      end)

      # Check specific models exist
      model_ids = Enum.map(models, & &1.id)
      assert "gemini-pro" in model_ids
      assert "gemini-pro-vision" in model_ids
    end
  end
end
