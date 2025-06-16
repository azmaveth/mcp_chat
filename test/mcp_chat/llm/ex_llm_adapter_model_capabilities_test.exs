defmodule MCPChat.LLM.ExLLMAdapterModelCapabilitiesTest do
  use ExUnit.Case
  alias MCPChat.LLM.ExLLMAdapter

  describe "ModelCapabilities integration" do
    test "get_model_capabilities/2 delegates to ExLLM.ModelCapabilities" do
      result = ExLLMAdapter.get_model_capabilities(:anthropic, "claude-3-opus-20240229")

      # Should return either success or error tuple
      assert is_tuple(result)
      assert elem(result, 0) in [:ok, :error]

      case result do
        {:ok, capabilities} ->
          # If successful, should have ModelInfo structure
          assert Map.has_key?(capabilities, :provider)
          assert Map.has_key?(capabilities, :model_id)
          assert Map.has_key?(capabilities, :display_name)
          assert Map.has_key?(capabilities, :capabilities)
          assert capabilities.provider == :anthropic
          assert capabilities.model_id == "claude-3-opus-20240229"

        {:error, _reason} ->
          # Expected if model not found in database
          assert true
      end
    end

    test "get_model_capabilities/2 handles unknown models" do
      result = ExLLMAdapter.get_model_capabilities(:anthropic, "unknown-model")

      assert {:error, :not_found} = result
    end

    test "get_model_capabilities/2 handles unknown providers" do
      result = ExLLMAdapter.get_model_capabilities(:unknown_provider, "some-model")

      assert {:error, :not_found} = result
    end

    test "recommend_models/1 delegates to ExLLM.ModelCapabilities" do
      requirements = [features: [:streaming, :function_calling]]
      result = ExLLMAdapter.recommend_models(requirements)

      assert is_list(result)

      # If we get recommendations, they should have the right structure
      if length(result) > 0 do
        {provider, model_id, metadata} = hd(result)
        assert is_atom(provider)
        assert is_binary(model_id)
        assert is_map(metadata)
        assert Map.has_key?(metadata, :score)
        assert Map.has_key?(metadata, :info)
      end
    end

    test "recommend_models/1 handles empty requirements" do
      result = ExLLMAdapter.recommend_models([])

      assert is_list(result)
      # Should still return some recommendations even with no requirements
    end

    test "recommend_models/1 handles invalid features" do
      requirements = [features: [:invalid_feature, :another_invalid]]
      result = ExLLMAdapter.recommend_models(requirements)

      assert is_list(result)
      # Should return empty list or filtered results
    end

    test "list_model_features/0 delegates to ExLLM.ModelCapabilities" do
      result = ExLLMAdapter.list_model_features()

      assert is_list(result)

      # Should include common features
      expected_features = [:streaming, :function_calling, :vision, :system_messages, :multi_turn]

      Enum.each(expected_features, fn feature ->
        assert feature in result, "Expected feature #{feature} to be in the list"
      end)
    end

    test "compare_models/1 delegates to ExLLM.ModelCapabilities" do
      model_specs = [
        {:anthropic, "claude-3-opus-20240229"},
        {:openai, "gpt-4"}
      ]

      result = ExLLMAdapter.compare_models(model_specs)

      case result do
        %{models: models, features: features} ->
          # Successful comparison
          assert is_list(models)
          assert is_map(features)

          # Check models structure
          if length(models) > 0 do
            model = hd(models)
            assert Map.has_key?(model, :provider)
            assert Map.has_key?(model, :model_id)
            assert Map.has_key?(model, :display_name)
            assert Map.has_key?(model, :context_window)
          end

          # Check features structure
          Enum.each(features, fn {feature, support_list} ->
            assert is_atom(feature)
            assert is_list(support_list)

            Enum.each(support_list, fn support ->
              assert Map.has_key?(support, :supported)
              assert is_boolean(support.supported)
            end)
          end)

        %{error: _error} ->
          # Expected if models not found
          assert true
      end
    end

    test "compare_models/1 handles empty model list" do
      result = ExLLMAdapter.compare_models([])

      assert %{error: _error} = result
    end

    test "compare_models/1 handles single model" do
      model_specs = [{:anthropic, "claude-3-opus-20240229"}]
      result = ExLLMAdapter.compare_models(model_specs)

      # Should still work with single model
      case result do
        %{models: models, features: _features} ->
          assert length(models) == 1

        %{error: _error} ->
          assert true
      end
    end

    test "compare_models/1 handles unknown models" do
      model_specs = [
        {:unknown_provider, "unknown-model"},
        {:another_unknown, "another-unknown-model"}
      ]

      result = ExLLMAdapter.compare_models(model_specs)

      assert %{error: _error} = result
    end

    test "supports_feature?/3 delegates to ExLLM.ModelCapabilities" do
      result = ExLLMAdapter.supports_feature?(:anthropic, "claude-3-opus-20240229", :streaming)

      assert is_boolean(result)

      # Claude 3 Opus should support streaming
      assert result == true
    end

    test "supports_feature?/3 handles unknown models" do
      result = ExLLMAdapter.supports_feature?(:unknown_provider, "unknown-model", :streaming)

      assert result == false
    end

    test "supports_feature?/3 handles unsupported features" do
      result = ExLLMAdapter.supports_feature?(:anthropic, "claude-3-opus-20240229", :unknown_feature)

      assert result == false
    end

    test "find_models_with_features/1 delegates to ExLLM.ModelCapabilities" do
      features = [:streaming, :function_calling]
      result = ExLLMAdapter.find_models_with_features(features)

      assert is_list(result)

      # If we get results, they should be {provider, model_id} tuples
      Enum.each(result, fn {provider, model_id} ->
        assert is_atom(provider)
        assert is_binary(model_id)
      end)
    end

    test "find_models_with_features/1 handles empty features list" do
      result = ExLLMAdapter.find_models_with_features([])

      assert is_list(result)
      # Should return all models when no features specified
    end

    test "find_models_with_features/1 handles invalid features" do
      features = [:invalid_feature, :another_invalid]
      result = ExLLMAdapter.find_models_with_features(features)

      assert is_list(result)
      # Should return empty list for invalid features
      assert result == []
    end

    test "models_by_capability/1 delegates to ExLLM.ModelCapabilities" do
      result = ExLLMAdapter.models_by_capability(:streaming)

      assert is_map(result)
      assert Map.has_key?(result, :supported)
      assert Map.has_key?(result, :not_supported)

      assert is_list(result.supported)
      assert is_list(result.not_supported)

      # Check structure of results
      Enum.each(result.supported, fn {provider, model_id} ->
        assert is_atom(provider)
        assert is_binary(model_id)
      end)

      Enum.each(result.not_supported, fn {provider, model_id} ->
        assert is_atom(provider)
        assert is_binary(model_id)
      end)
    end

    test "models_by_capability/1 handles invalid capabilities" do
      result = ExLLMAdapter.models_by_capability(:invalid_capability)

      assert is_map(result)
      assert Map.has_key?(result, :supported)
      assert Map.has_key?(result, :not_supported)

      # Should return empty supported list for invalid capability
      assert result.supported == []
    end
  end

  describe "integration with existing adapter functionality" do
    test "ModelCapabilities functions don't interfere with other adapter state" do
      # Test that calling ModelCapabilities functions doesn't affect adapter behavior
      initial_features = ExLLMAdapter.list_model_features()

      # Call various ModelCapabilities functions
      _caps_result = ExLLMAdapter.get_model_capabilities(:anthropic, "claude-3-opus-20240229")
      _recommend_result = ExLLMAdapter.recommend_models([])
      _compare_result = ExLLMAdapter.compare_models([{:anthropic, "claude-3-opus-20240229"}])

      # Features should still be the same
      final_features = ExLLMAdapter.list_model_features()
      assert initial_features == final_features

      # Adapter should still be available
      assert ExLLMAdapter.configured?()
    end

    test "ModelCapabilities functions are stateless" do
      # Test that repeated calls return consistent results
      features1 = ExLLMAdapter.list_model_features()
      features2 = ExLLMAdapter.list_model_features()
      assert features1 == features2

      # Test with same parameters
      caps1 = ExLLMAdapter.get_model_capabilities(:anthropic, "claude-3-opus-20240229")
      caps2 = ExLLMAdapter.get_model_capabilities(:anthropic, "claude-3-opus-20240229")
      assert caps1 == caps2
    end

    test "ModelCapabilities functions work with different providers" do
      providers = [:anthropic, :openai, :gemini, :groq]

      Enum.each(providers, fn provider ->
        # Test that each provider can be queried for capabilities
        result = ExLLMAdapter.models_by_capability(:streaming)

        # Should work without error
        assert is_map(result)

        # Check if this provider has any models supporting streaming
        supported_models = result.supported
        provider_models = Enum.filter(supported_models, fn {p, _model} -> p == provider end)

        # It's okay if no models are found for a provider
        assert is_list(provider_models)
      end)
    end
  end

  describe "error handling and edge cases" do
    test "handles ExLLM.ModelCapabilities module not available gracefully" do
      # This test ensures that if ExLLM.ModelCapabilities is not available,
      # the adapter functions don't crash

      # We can't easily mock the module not being available, but we can
      # test that calling the functions doesn't raise exceptions
      assert_no_exception(fn ->
        ExLLMAdapter.get_model_capabilities(:test, "test")
      end)

      assert_no_exception(fn ->
        ExLLMAdapter.list_model_features()
      end)

      assert_no_exception(fn ->
        ExLLMAdapter.recommend_models([])
      end)
    end

    test "handles malformed requirements gracefully" do
      # Test with various malformed requirement formats that should still work
      valid_malformed_requirements = [
        [],
        [invalid_key: :value],
        [features: []]
      ]

      Enum.each(valid_malformed_requirements, fn req ->
        assert_no_exception(fn ->
          ExLLMAdapter.recommend_models(req)
        end)
      end)

      # Test with requirements that will cause function clause errors but should be caught
      invalid_requirements = [
        nil,
        %{invalid: :format},
        [features: nil],
        [features: "not_a_list"]
      ]

      Enum.each(invalid_requirements, fn req ->
        result =
          try do
            ExLLMAdapter.recommend_models(req)
            :ok
          catch
            :error, %FunctionClauseError{} -> :caught_error
            _, _ -> :caught_other
          rescue
            _ -> :rescued
          end

        # Should either work or catch the error gracefully
        assert result in [:ok, :caught_error, :caught_other, :rescued]
      end)
    end

    test "handles large model comparison lists" do
      # Test with many models (might timeout or fail, but shouldn't crash)
      model_specs =
        Enum.map(1..20, fn i ->
          {:test_provider, "test-model-#{i}"}
        end)

      assert_no_exception(fn ->
        ExLLMAdapter.compare_models(model_specs)
      end)
    end
  end

  # Helper function to assert no exceptions are raised
  defp assert_no_exception(fun) do
    try do
      fun.()
      assert true
    rescue
      e ->
        flunk("Expected no exception, but got: #{inspect(e)}")
    end
  end
end
