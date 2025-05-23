defmodule MCPChat.CostTest do
  use ExUnit.Case
  alias MCPChat.{Cost, Session}

  describe "calculate_session_cost/2" do
    test "calculates cost for Anthropic Claude model" do
      session = %Session{
        llm_backend: "anthropic",
        context: %{model: "claude-3-haiku-20_240_307"}
      }

      token_usage = %{input_tokens: 1_000, output_tokens: 500}

      cost_info = Cost.calculate_session_cost(session, token_usage)

      assert cost_info.backend == "anthropic"
      assert cost_info.model == "claude-3-haiku-20_240_307"
      assert cost_info.input_tokens == 1_000
      assert cost_info.output_tokens == 500
      assert cost_info.total_tokens == 1_500

      # Haiku pricing: $0.25/1M input, $1.25/1M output
      assert cost_info.input_cost == 0.00_025
      assert cost_info.output_cost == 0.000_625
      assert cost_info.total_cost == 0.000_875
    end

    test "calculates cost for OpenAI GPT model" do
      session = %Session{
        llm_backend: "openai",
        context: %{model: "gpt-3.5-turbo"}
      }

      token_usage = %{input_tokens: 2_000, output_tokens: 1_000}

      cost_info = Cost.calculate_session_cost(session, token_usage)

      assert cost_info.backend == "openai"
      assert cost_info.model == "gpt-3.5-turbo"

      # GPT-3.5 pricing: $0.50/1M input, $1.50/1M output
      assert cost_info.input_cost == 0.001
      assert cost_info.output_cost == 0.0_015
      assert cost_info.total_cost == 0.0_025
    end

    test "handles unknown model" do
      session = %Session{
        llm_backend: "unknown",
        context: %{model: "unknown-model"}
      }

      token_usage = %{input_tokens: 1_000, output_tokens: 500}

      cost_info = Cost.calculate_session_cost(session, token_usage)

      assert cost_info.error =~ "No pricing data available"
      assert cost_info.backend == "unknown"
      assert cost_info.model == "unknown-model"
    end
  end

  describe "track_token_usage/2" do
    test "tracks token usage for messages" do
      input_messages = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there"}
      ]

      response_content = "This is a response"

      usage = Cost.track_token_usage(input_messages, response_content)

      assert usage.input_tokens > 0
      assert usage.output_tokens > 0
      assert %DateTime{} = usage.timestamp
    end
  end

  describe "format_cost/1" do
    test "formats very small costs in cents" do
      assert Cost.format_cost(0.00_001) == "$0.001¢"
      assert Cost.format_cost(0.0_005) == "$0.050¢"
      assert Cost.format_cost(0.009) == "$0.900¢"
    end

    test "formats small costs with 4 decimals" do
      assert Cost.format_cost(0.01) == "$0.0_100"
      assert Cost.format_cost(0.1_234) == "$0.1_234"
      assert Cost.format_cost(0.9_999) == "$0.9_999"
    end

    test "formats larger costs with 2 decimals" do
      assert Cost.format_cost(1.0) == "$1.00"
      assert Cost.format_cost(15.5) == "$15.50"
      assert Cost.format_cost(999.99) == "$999.99"
    end
  end

  describe "get_pricing/2" do
    test "returns pricing for known models" do
      pricing = Cost.get_pricing("anthropic", "claude-3-haiku-20_240_307")
      assert pricing.input == 0.25
      assert pricing.output == 1.25
    end

    test "returns nil for unknown models" do
      assert is_nil(Cost.get_pricing("unknown", "model"))
    end
  end

  describe "list_pricing/0" do
    test "returns all available pricing" do
      pricing_list = Cost.list_pricing()

      assert is_list(pricing_list)
      assert length(pricing_list) > 0

      # Check structure
      first = hd(pricing_list)
      assert Map.has_key?(first, :backend)
      assert Map.has_key?(first, :model)
      assert Map.has_key?(first, :input_per_1m)
      assert Map.has_key?(first, :output_per_1m)
    end
  end
end
