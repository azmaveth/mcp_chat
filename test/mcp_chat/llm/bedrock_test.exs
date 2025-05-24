defmodule MCPChat.LLM.BedrockTest do
  use ExUnit.Case
  alias MCPChat.LLM.Bedrock

  describe "basic functionality" do
    test "configured? returns false when no credentials" do
      # This test assumes no AWS credentials are set in the test environment
      refute Bedrock.configured?()
    end

    test "default_model returns expected model" do
      assert Bedrock.default_model() == "claude-3-sonnet"
    end

    test "list_models returns expected format or credential error" do
      case Bedrock.list_models() do
        {:ok, models} ->
          assert is_list(models)

          # Check if models have the expected structure
          Enum.each(models, fn model ->
            assert is_map(model)
            assert Map.has_key?(model, :id)
            assert Map.has_key?(model, :name)
          end)

        {:error, "No AWS credentials found"} ->
          # This is expected when no credentials are configured
          assert true
      end
    end
  end
end
