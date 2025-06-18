defmodule MCPChat.CostTracking.CostCalculator do
  @moduledoc """
  Precise cost calculation for different LLM providers and models.

  This module maintains up-to-date pricing information for various
  providers and calculates exact costs based on token usage.
  """

  require Logger

  # Pricing data (as of 2025-01-18)
  # Prices are per 1,000 tokens unless specified otherwise

  @anthropic_pricing %{
    "claude-3-haiku-20240307" => %{
      # $0.25 per 1K input tokens
      input: 0.00025,
      # $1.25 per 1K output tokens
      output: 0.00125
    },
    "claude-3-sonnet-20240229" => %{
      # $3.00 per 1K input tokens
      input: 0.003,
      # $15.00 per 1K output tokens
      output: 0.015
    },
    "claude-3-opus-20240229" => %{
      # $15.00 per 1K input tokens
      input: 0.015,
      # $75.00 per 1K output tokens
      output: 0.075
    },
    "claude-3-5-sonnet-20241022" => %{
      # $3.00 per 1K input tokens
      input: 0.003,
      # $15.00 per 1K output tokens
      output: 0.015
    },
    "claude-3-5-haiku-20241022" => %{
      # $1.00 per 1K input tokens
      input: 0.001,
      # $5.00 per 1K output tokens
      output: 0.005
    }
  }

  @openai_pricing %{
    "gpt-4" => %{
      # $30.00 per 1K input tokens
      input: 0.03,
      # $60.00 per 1K output tokens
      output: 0.06
    },
    "gpt-4-turbo" => %{
      # $10.00 per 1K input tokens
      input: 0.01,
      # $30.00 per 1K output tokens
      output: 0.03
    },
    "gpt-4o" => %{
      # $2.50 per 1K input tokens
      input: 0.0025,
      # $10.00 per 1K output tokens
      output: 0.01
    },
    "gpt-4o-mini" => %{
      # $0.15 per 1K input tokens
      input: 0.00015,
      # $0.60 per 1K output tokens
      output: 0.0006
    },
    "gpt-3.5-turbo" => %{
      # $0.50 per 1K input tokens
      input: 0.0005,
      # $1.50 per 1K output tokens
      output: 0.0015
    },
    "o1-preview" => %{
      # $15.00 per 1K input tokens
      input: 0.015,
      # $60.00 per 1K output tokens
      output: 0.06
    },
    "o1-mini" => %{
      # $3.00 per 1K input tokens
      input: 0.003,
      # $12.00 per 1K output tokens
      output: 0.012
    }
  }

  @gemini_pricing %{
    "gemini-1.5-pro" => %{
      # $3.50 per 1K input tokens
      input: 0.0035,
      # $10.50 per 1K output tokens
      output: 0.0105
    },
    "gemini-1.5-flash" => %{
      # $0.35 per 1K input tokens
      input: 0.00035,
      # $1.05 per 1K output tokens
      output: 0.00105
    },
    "gemini-2.0-flash-exp" => %{
      # $0.35 per 1K input tokens (estimated)
      input: 0.00035,
      # $1.05 per 1K output tokens (estimated)
      output: 0.00105
    }
  }

  @aws_bedrock_pricing %{
    "anthropic.claude-3-haiku-20240307-v1:0" => %{
      input: 0.00025,
      output: 0.00125
    },
    "anthropic.claude-3-sonnet-20240229-v1:0" => %{
      input: 0.003,
      output: 0.015
    },
    "anthropic.claude-3-opus-20240229-v1:0" => %{
      input: 0.015,
      output: 0.075
    },
    "anthropic.claude-3-5-sonnet-20241022-v2:0" => %{
      input: 0.003,
      output: 0.015
    }
  }

  @ollama_pricing %{
    # Ollama is typically free for self-hosted models
    # but we can track compute costs if desired
    default: %{
      input: 0.0,
      output: 0.0,
      # Estimated compute cost
      compute_cost_per_hour: 0.10
    }
  }

  @local_model_pricing %{
    # Local models have no API costs but may have compute costs
    default: %{
      input: 0.0,
      output: 0.0,
      # Lower compute cost estimate
      compute_cost_per_hour: 0.05
    }
  }

  @doc """
  Calculate the cost for a specific LLM interaction.
  """
  def calculate_cost(provider, model, prompt_tokens, completion_tokens, opts \\ []) do
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())

    case get_model_pricing(provider, model) do
      {:ok, pricing} ->
        input_cost = prompt_tokens / 1000.0 * pricing.input
        output_cost = completion_tokens / 1000.0 * pricing.output
        total_cost = input_cost + output_cost

        cost_data = %{
          provider: provider,
          model: model,
          prompt_tokens: prompt_tokens,
          completion_tokens: completion_tokens,
          total_tokens: prompt_tokens + completion_tokens,
          input_cost: input_cost,
          output_cost: output_cost,
          cost: total_cost,
          pricing_version: get_pricing_version(),
          timestamp: timestamp,
          currency: "USD"
        }

        {:ok, cost_data}

      {:error, reason} ->
        # Fallback to estimated cost
        Logger.warning("Unknown model pricing", provider: provider, model: model, reason: reason)
        estimated_cost = estimate_unknown_model_cost(prompt_tokens, completion_tokens)

        cost_data = %{
          provider: provider,
          model: model,
          prompt_tokens: prompt_tokens,
          completion_tokens: completion_tokens,
          total_tokens: prompt_tokens + completion_tokens,
          # Assume 40% input cost
          input_cost: estimated_cost * 0.4,
          # Assume 60% output cost
          output_cost: estimated_cost * 0.6,
          cost: estimated_cost,
          pricing_version: "estimated",
          timestamp: timestamp,
          currency: "USD",
          estimated: true
        }

        {:ok, cost_data}
    end
  end

  @doc """
  Calculate cost for a batch of interactions.
  """
  def calculate_batch_cost(interactions) do
    total_cost = 0.0
    total_tokens = 0
    batch_details = []

    {final_cost, final_tokens, final_details} =
      Enum.reduce(interactions, {total_cost, total_tokens, batch_details}, fn interaction,
                                                                              {acc_cost, acc_tokens, acc_details} ->
        case calculate_cost(
               interaction.provider,
               interaction.model,
               interaction.prompt_tokens,
               interaction.completion_tokens,
               timestamp: interaction.timestamp
             ) do
          {:ok, cost_data} ->
            {
              acc_cost + cost_data.cost,
              acc_tokens + cost_data.total_tokens,
              [cost_data | acc_details]
            }

          {:error, _reason} ->
            # Skip failed calculations but log them
            Logger.warning("Failed to calculate cost for interaction", interaction: interaction)
            {acc_cost, acc_tokens, acc_details}
        end
      end)

    %{
      total_cost: final_cost,
      total_tokens: final_tokens,
      interaction_count: length(final_details),
      details: Enum.reverse(final_details),
      calculated_at: DateTime.utc_now()
    }
  end

  @doc """
  Get pricing information for a model.
  """
  def get_model_pricing(provider, model) do
    pricing_map =
      case normalize_provider(provider) do
        :anthropic -> @anthropic_pricing
        :openai -> @openai_pricing
        :gemini -> @gemini_pricing
        :aws_bedrock -> @aws_bedrock_pricing
        :ollama -> @ollama_pricing
        :local -> @local_model_pricing
        _ -> %{}
      end

    case Map.get(pricing_map, model) do
      nil ->
        # Try default pricing for provider
        case Map.get(pricing_map, "default") do
          nil -> {:error, :pricing_not_found}
          default_pricing -> {:ok, default_pricing}
        end

      pricing ->
        {:ok, pricing}
    end
  end

  @doc """
  Get estimated cost range for a model.
  """
  def get_cost_estimate_range(provider, model, token_count) do
    case get_model_pricing(provider, model) do
      {:ok, pricing} ->
        # Assume 70% input, 30% output for estimation
        input_tokens = round(token_count * 0.7)
        output_tokens = round(token_count * 0.3)

        min_cost = calculate_cost(provider, model, input_tokens, output_tokens)
        max_cost = calculate_cost(provider, model, output_tokens, input_tokens)

        case {min_cost, max_cost} do
          {{:ok, min_data}, {:ok, max_data}} ->
            {:ok,
             %{
               min_cost: min_data.cost,
               max_cost: max_data.cost,
               estimated_cost: (min_data.cost + max_data.cost) / 2
             }}

          _ ->
            {:error, :calculation_failed}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Compare costs across different models for the same token usage.
  """
  def compare_model_costs(token_usage, models_to_compare) do
    %{prompt_tokens: prompt_tokens, completion_tokens: completion_tokens} = token_usage

    comparisons =
      Enum.map(models_to_compare, fn {provider, model} ->
        case calculate_cost(provider, model, prompt_tokens, completion_tokens) do
          {:ok, cost_data} ->
            %{
              provider: provider,
              model: model,
              cost: cost_data.cost,
              cost_per_token: cost_data.cost / cost_data.total_tokens,
              cost_breakdown: %{
                input_cost: cost_data.input_cost,
                output_cost: cost_data.output_cost
              }
            }

          {:error, _reason} ->
            %{
              provider: provider,
              model: model,
              cost: nil,
              error: "Pricing not available"
            }
        end
      end)

    # Sort by cost (lowest first)
    sorted_comparisons =
      Enum.sort_by(comparisons, fn comparison ->
        comparison[:cost] || 999.99
      end)

    %{
      token_usage: token_usage,
      comparisons: sorted_comparisons,
      cheapest: List.first(sorted_comparisons),
      most_expensive: List.last(sorted_comparisons),
      compared_at: DateTime.utc_now()
    }
  end

  @doc """
  Get all available models with their pricing.
  """
  def get_all_model_pricing do
    all_pricing = %{
      anthropic: @anthropic_pricing,
      openai: @openai_pricing,
      gemini: @gemini_pricing,
      aws_bedrock: @aws_bedrock_pricing,
      ollama: @ollama_pricing,
      local: @local_model_pricing
    }

    # Flatten into a single list with provider information
    Enum.flat_map(all_pricing, fn {provider, models} ->
      Enum.map(models, fn {model, pricing} ->
        %{
          provider: provider,
          model: model,
          input_price_per_1k: pricing.input,
          output_price_per_1k: pricing.output,
          avg_price_per_1k: (pricing.input + pricing.output) / 2
        }
      end)
    end)
    |> Enum.sort_by(& &1.avg_price_per_1k)
  end

  @doc """
  Calculate monthly cost projection based on usage pattern.
  """
  def project_monthly_cost(daily_usage_stats) do
    %{
      daily_cost: daily_cost,
      daily_tokens: daily_tokens,
      daily_interactions: daily_interactions
    } = daily_usage_stats

    # Project for 30 days
    monthly_projection = %{
      projected_cost: daily_cost * 30,
      projected_tokens: daily_tokens * 30,
      projected_interactions: daily_interactions * 30,
      daily_average: daily_cost,
      cost_per_interaction: if(daily_interactions > 0, do: daily_cost / daily_interactions, else: 0),
      cost_per_token: if(daily_tokens > 0, do: daily_cost / daily_tokens, else: 0)
    }

    # Add confidence level based on data quality
    confidence =
      cond do
        daily_interactions >= 10 -> :high
        daily_interactions >= 3 -> :medium
        daily_interactions >= 1 -> :low
        true -> :very_low
      end

    Map.put(monthly_projection, :confidence, confidence)
  end

  # Private functions

  defp normalize_provider(provider) when is_binary(provider) do
    provider
    |> String.downcase()
    |> String.to_atom()
  end

  defp normalize_provider(provider) when is_atom(provider), do: provider

  defp estimate_unknown_model_cost(prompt_tokens, completion_tokens) do
    # Use average pricing across known models for estimation
    total_tokens = prompt_tokens + completion_tokens

    # Conservative estimate: $0.002 per 1K tokens (average rate)
    estimated_cost_per_1k = 0.002
    total_tokens / 1000.0 * estimated_cost_per_1k
  end

  defp get_pricing_version do
    # Version identifier for pricing data
    "2025-01-18"
  end

  @doc """
  Update pricing for a specific model (for dynamic pricing updates).
  """
  def update_model_pricing(provider, model, new_pricing) do
    # In a production system, this would update a database or external service
    # For now, we'll log the update
    Logger.info("Pricing update requested",
      provider: provider,
      model: model,
      new_pricing: new_pricing
    )

    # This would typically update external pricing storage
    {:ok, "Pricing update logged - manual code update required"}
  end

  @doc """
  Validate pricing data structure.
  """
  def validate_pricing(pricing) do
    required_fields = [:input, :output]

    case pricing do
      %{} = p when is_map(p) ->
        missing_fields = required_fields -- Map.keys(p)

        if Enum.empty?(missing_fields) do
          if is_number(p.input) and is_number(p.output) and p.input >= 0 and p.output >= 0 do
            :ok
          else
            {:error, "Input and output prices must be non-negative numbers"}
          end
        else
          {:error, "Missing required fields: #{inspect(missing_fields)}"}
        end

      _ ->
        {:error, "Pricing must be a map"}
    end
  end
end
