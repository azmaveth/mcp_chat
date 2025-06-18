defmodule MCPChat.CostTracking.CostCalculatorTest do
  use ExUnit.Case, async: true

  alias MCPChat.CostTracking.CostCalculator

  describe "cost calculation" do
    test "calculates cost for Claude models correctly" do
      # Test Claude 3.5 Sonnet
      {:ok, cost_data} =
        CostCalculator.calculate_cost(
          :anthropic,
          "claude-3-5-sonnet-20241022",
          # prompt tokens
          1000,
          # completion tokens
          500
        )

      # Pricing: $3.00 per 1K input, $15.00 per 1K output
      # $3.00
      assert cost_data.input_cost == 3.0 * (1000 / 1000.0)
      # $7.50
      assert cost_data.output_cost == 15.0 * (500 / 1000.0)
      # $10.50 total
      assert cost_data.cost == 10.5
      assert cost_data.provider == :anthropic
      assert cost_data.model == "claude-3-5-sonnet-20241022"
      assert cost_data.total_tokens == 1500
    end

    test "calculates cost for OpenAI models correctly" do
      # Test GPT-4o mini
      {:ok, cost_data} =
        CostCalculator.calculate_cost(
          :openai,
          "gpt-4o-mini",
          # prompt tokens
          2000,
          # completion tokens
          1000
        )

      # Pricing: $0.15 per 1K input, $0.60 per 1K output
      # $0.30
      assert cost_data.input_cost == 0.15 * (2000 / 1000.0)
      # $0.60
      assert cost_data.output_cost == 0.60 * (1000 / 1000.0)
      # $0.90 total
      assert cost_data.cost == 0.90
    end

    test "calculates cost for Gemini models correctly" do
      # Test Gemini 1.5 Flash
      {:ok, cost_data} =
        CostCalculator.calculate_cost(
          :gemini,
          "gemini-1.5-flash",
          # prompt tokens
          1500,
          # completion tokens
          800
        )

      # Pricing: $0.35 per 1K input, $1.05 per 1K output
      # $0.525
      assert cost_data.input_cost == 0.35 * (1500 / 1000.0)
      # $0.84
      assert cost_data.output_cost == 1.05 * (800 / 1000.0)
      # $1.365 total
      assert cost_data.cost == 1.365
    end

    test "handles unknown models with estimation" do
      {:ok, cost_data} =
        CostCalculator.calculate_cost(
          :unknown_provider,
          "unknown-model",
          1000,
          500
        )

      assert cost_data.estimated == true
      assert is_number(cost_data.cost)
      assert cost_data.cost > 0
    end

    test "handles Ollama models (free)" do
      {:ok, cost_data} =
        CostCalculator.calculate_cost(
          :ollama,
          "llama3.2",
          1000,
          500
        )

      assert cost_data.input_cost == 0.0
      assert cost_data.output_cost == 0.0
      assert cost_data.cost == 0.0
    end
  end

  describe "batch cost calculation" do
    test "calculates cost for multiple interactions" do
      interactions = [
        %{
          provider: :anthropic,
          model: "claude-3-haiku-20240307",
          prompt_tokens: 100,
          completion_tokens: 50,
          timestamp: DateTime.utc_now()
        },
        %{
          provider: :openai,
          model: "gpt-4o-mini",
          prompt_tokens: 200,
          completion_tokens: 100,
          timestamp: DateTime.utc_now()
        }
      ]

      batch_result = CostCalculator.calculate_batch_cost(interactions)

      assert batch_result.interaction_count == 2
      assert is_number(batch_result.total_cost)
      assert batch_result.total_cost > 0
      # 100+50+200+100
      assert batch_result.total_tokens == 450
      assert length(batch_result.details) == 2
    end
  end

  describe "cost comparison" do
    test "compares costs across different models" do
      token_usage = %{prompt_tokens: 1000, completion_tokens: 500}

      models_to_compare = [
        {:anthropic, "claude-3-haiku-20240307"},
        {:openai, "gpt-4o-mini"},
        {:gemini, "gemini-1.5-flash"}
      ]

      comparison = CostCalculator.compare_model_costs(token_usage, models_to_compare)

      assert length(comparison.comparisons) == 3
      assert comparison.cheapest.cost <= comparison.most_expensive.cost

      # All models should have valid costs
      Enum.each(comparison.comparisons, fn comp ->
        assert is_number(comp.cost)
        assert comp.cost >= 0
      end)
    end
  end

  describe "cost estimation" do
    test "provides cost estimate ranges" do
      {:ok, estimate} =
        CostCalculator.get_cost_estimate_range(
          :anthropic,
          "claude-3-5-sonnet-20241022",
          1000
        )

      assert is_number(estimate.min_cost)
      assert is_number(estimate.max_cost)
      assert is_number(estimate.estimated_cost)
      assert estimate.min_cost <= estimate.estimated_cost
      assert estimate.estimated_cost <= estimate.max_cost
    end

    test "handles unknown models in estimation" do
      result =
        CostCalculator.get_cost_estimate_range(
          :unknown_provider,
          "unknown-model",
          1000
        )

      assert {:error, :pricing_not_found} = result
    end
  end

  describe "pricing information" do
    test "gets model pricing information" do
      {:ok, pricing} = CostCalculator.get_model_pricing(:anthropic, "claude-3-haiku-20240307")

      assert is_number(pricing.input)
      assert is_number(pricing.output)
      assert pricing.input >= 0
      assert pricing.output >= 0
    end

    test "returns error for unknown model pricing" do
      result = CostCalculator.get_model_pricing(:unknown, "unknown-model")
      assert {:error, :pricing_not_found} = result
    end

    test "lists all available model pricing" do
      all_pricing = CostCalculator.get_all_model_pricing()

      assert is_list(all_pricing)
      assert length(all_pricing) > 0

      # Check structure of pricing entries
      first_entry = List.first(all_pricing)
      assert Map.has_key?(first_entry, :provider)
      assert Map.has_key?(first_entry, :model)
      assert Map.has_key?(first_entry, :input_price_per_1k)
      assert Map.has_key?(first_entry, :output_price_per_1k)
    end
  end

  describe "monthly projections" do
    test "projects monthly costs from daily usage" do
      daily_stats = %{
        daily_cost: 2.50,
        daily_tokens: 10000,
        daily_interactions: 25
      }

      projection = CostCalculator.project_monthly_cost(daily_stats)

      # $75.00
      assert projection.projected_cost == 2.50 * 30
      assert projection.projected_tokens == 10000 * 30
      assert projection.projected_interactions == 25 * 30
      assert projection.daily_average == 2.50
      assert projection.cost_per_interaction == 2.50 / 25
      # 25 interactions is high confidence
      assert projection.confidence == :high
    end

    test "assigns appropriate confidence levels" do
      # High confidence (10+ interactions)
      high_confidence =
        CostCalculator.project_monthly_cost(%{
          daily_cost: 1.0,
          daily_tokens: 1000,
          daily_interactions: 15
        })

      assert high_confidence.confidence == :high

      # Medium confidence (3-9 interactions)
      medium_confidence =
        CostCalculator.project_monthly_cost(%{
          daily_cost: 1.0,
          daily_tokens: 1000,
          daily_interactions: 5
        })

      assert medium_confidence.confidence == :medium

      # Low confidence (1-2 interactions)
      low_confidence =
        CostCalculator.project_monthly_cost(%{
          daily_cost: 1.0,
          daily_tokens: 1000,
          daily_interactions: 2
        })

      assert low_confidence.confidence == :low

      # Very low confidence (0 interactions)
      very_low_confidence =
        CostCalculator.project_monthly_cost(%{
          daily_cost: 0.0,
          daily_tokens: 0,
          daily_interactions: 0
        })

      assert very_low_confidence.confidence == :very_low
    end
  end

  describe "pricing validation" do
    test "validates correct pricing structure" do
      valid_pricing = %{input: 0.001, output: 0.002}
      assert :ok = CostCalculator.validate_pricing(valid_pricing)
    end

    test "rejects invalid pricing structures" do
      # Missing fields
      assert {:error, _} = CostCalculator.validate_pricing(%{input: 0.001})
      assert {:error, _} = CostCalculator.validate_pricing(%{output: 0.002})

      # Negative prices
      assert {:error, _} = CostCalculator.validate_pricing(%{input: -0.001, output: 0.002})
      assert {:error, _} = CostCalculator.validate_pricing(%{input: 0.001, output: -0.002})

      # Non-numeric values
      assert {:error, _} = CostCalculator.validate_pricing(%{input: "invalid", output: 0.002})
      assert {:error, _} = CostCalculator.validate_pricing(%{input: 0.001, output: "invalid"})

      # Not a map
      assert {:error, _} = CostCalculator.validate_pricing("not a map")
      assert {:error, _} = CostCalculator.validate_pricing(nil)
    end
  end
end
