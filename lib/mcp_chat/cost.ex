defmodule MCPChat.Cost do
  @moduledoc """
  Cost calculation for LLM API usage.

  Tracks token usage and calculates costs based on provider pricing.

  Can be used with configuration injection for library usage:

      # With default config
      MCPChat.Cost.calculate_session_cost(session, token_usage)

      # With injected config
      MCPChat.Cost.calculate_session_cost(session, token_usage, config_provider: my_config)
  """

  # Pricing per 1M tokens (as of January 2_025)
  # credo:disable-for-next-line Credo.Check.Readability.LargeNumbers
  @pricing %{
    "anthropic" => %{
      # Model names contain dates in YYYYMMDD format - do not add underscores
      "claude-3-5-sonnet-20241022" => %{input: 3.00, output: 15.00},
      "claude-3-5-haiku-20241022" => %{input: 1.00, output: 5.00},
      "claude-3-opus-20240229" => %{input: 15.00, output: 75.00},
      "claude-3-sonnet-20240229" => %{input: 3.00, output: 15.00},
      "claude-3-haiku-20240307" => %{input: 0.25, output: 1.25},
      # Claude 4 models
      "claude-sonnet-4-20250514" => %{input: 3.00, output: 15.00},
      "claude-4" => %{input: 3.00, output: 15.00}
    },
    "openai" => %{
      "gpt-4-turbo" => %{input: 10.00, output: 30.00},
      "gpt-4-turbo-preview" => %{input: 10.00, output: 30.00},
      "gpt-4" => %{input: 30.00, output: 60.00},
      "gpt-4-32k" => %{input: 60.00, output: 120.00},
      "gpt-3.5-turbo" => %{input: 0.50, output: 1.50},
      "gpt-3.5-turbo-16k" => %{input: 3.00, output: 4.00},
      "gpt-4o" => %{input: 5.00, output: 15.00},
      "gpt-4o-mini" => %{input: 0.15, output: 0.60}
    },
    "bedrock" => %{
      # Anthropic via Bedrock (slightly different pricing)
      "claude-instant-v1" => %{input: 0.80, output: 2.40},
      "claude-v2" => %{input: 8.00, output: 24.00},
      "claude-v2.1" => %{input: 8.00, output: 24.00},
      "claude-3-sonnet" => %{input: 3.00, output: 15.00},
      "claude-3-haiku" => %{input: 0.25, output: 1.25},
      # Amazon Titan
      "titan-lite" => %{input: 0.30, output: 0.40},
      "titan-express" => %{input: 1.30, output: 1.70},
      # Meta Llama 2
      "llama2-13b" => %{input: 0.75, output: 1.00},
      "llama2-70b" => %{input: 1.95, output: 2.56},
      # Cohere
      "command" => %{input: 1.50, output: 2.00},
      "command-light" => %{input: 0.30, output: 0.60},
      # AI21 Jurassic
      "jurassic-2-mid" => %{input: 1.25, output: 1.25},
      "jurassic-2-ultra" => %{input: 18.80, output: 18.80},
      # Mistral
      "mistral-7b" => %{input: 0.20, output: 0.26},
      "mixtral-8x7b" => %{input: 0.45, output: 0.70}
    },
    "gemini" => %{
      # Google Gemini pricing (as of Jan 2025)
      "gemini-pro" => %{input: 0.50, output: 1.50},
      "gemini-pro-vision" => %{input: 0.50, output: 1.50},
      "gemini-ultra" => %{input: 5.00, output: 15.00},
      "gemini-nano" => %{input: 0.10, output: 0.30}
    }
  }

  @doc """
  Calculate the cost for a session based on token usage.

  Returns a map with detailed cost breakdown.
  """
  def calculate_session_cost(session, token_usage, opts \\ []) do
    config_provider = Keyword.get(opts, :config_provider, MCPChat.ConfigProvider.Default)
    backend = session.llm_backend
    model = get_model_for_session(session, config_provider)

    pricing = get_pricing(backend, model)

    if pricing do
      input_cost = calculate_token_cost(token_usage.input_tokens, pricing.input)
      output_cost = calculate_token_cost(token_usage.output_tokens, pricing.output)
      total_cost = input_cost + output_cost

      %{
        backend: backend,
        model: model,
        input_tokens: token_usage.input_tokens,
        output_tokens: token_usage.output_tokens,
        total_tokens: token_usage.input_tokens + token_usage.output_tokens,
        input_cost: input_cost,
        output_cost: output_cost,
        total_cost: total_cost,
        currency: "USD",
        pricing: pricing
      }
    else
      %{
        error: "No pricing data available for #{backend}/#{model}",
        backend: backend,
        model: model
      }
    end
  end

  @doc """
  Track token usage for a message exchange.

  Estimates tokens for input and output messages.
  """
  def track_token_usage(input_messages, response_content) do
    input_tokens = MCPChat.Context.estimate_tokens(input_messages)
    output_tokens = MCPChat.Context.estimate_tokens(response_content)

    %{
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Get pricing for a specific backend and model.
  """
  def get_pricing(backend, model) do
    @pricing
    |> Map.get(backend, %{})
    |> Map.get(model)
  end

  @doc """
  Format cost for display.
  """
  def format_cost(cost_in_dollars) do
    cond do
      cost_in_dollars < 0.01 ->
        # Show in cents if less than 1 cent
        cents = cost_in_dollars * 100
        "$#{:erlang.float_to_binary(cents, decimals: 3)}¢"

      cost_in_dollars < 1.0 ->
        # Show with 4 decimal places if less than $1
        "$#{:erlang.float_to_binary(cost_in_dollars, decimals: 4)}"

      true ->
        # Show with 2 decimal places for larger amounts
        "$#{:erlang.float_to_binary(cost_in_dollars, decimals: 2)}"
    end
  end

  @doc """
  Get a summary of available models and their pricing.
  """
  def list_pricing do
    for {backend, models} <- @pricing,
        {model, prices} <- models do
      %{
        backend: backend,
        model: model,
        input_per_1m: prices.input,
        output_per_1m: prices.output
      }
    end
    |> Enum.sort_by(&{&1.backend, &1.model})
  end

  # Private functions

  defp calculate_token_cost(tokens, price_per_million) do
    # Convert to cost (price is per million tokens)
    tokens / 1_000_000 * price_per_million
  end

  defp get_model_for_session(session, config_provider) do
    # Check if model is stored in context, otherwise use config default
    model = session.context[:model]

    if model do
      model
    else
      # Get default model from config based on backend
      case session.llm_backend do
        "anthropic" ->
          get_config_value(config_provider, [:llm, :anthropic, :model]) || "claude-sonnet-4-20_250_514"

        "openai" ->
          get_config_value(config_provider, [:llm, :openai, :model]) || "gpt-4-turbo"

        _ ->
          nil
      end
    end
  end

  defp get_config_value(config_provider, path) do
    case config_provider do
      MCPChat.ConfigProvider.Default ->
        MCPChat.Config.get(path)

      provider when is_pid(provider) ->
        # Static provider (Agent pid)
        MCPChat.ConfigProvider.Static.get(provider, path)

      provider ->
        # Custom provider module
        provider.get(path)
    end
  end
end
