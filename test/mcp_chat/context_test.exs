defmodule MCPChat.ContextTest do
  use ExUnit.Case
  alias MCPChat.Context

  describe "estimate_tokens/1" do
    test "estimates tokens for simple text" do
      # "Hello world" = 2 words * 1.3 = 2.6 ≈ 3
      assert Context.estimate_tokens("Hello world") == 3
      # "This is a test message" = 5 words * 1.3 = 6.5 ≈ 7
      assert Context.estimate_tokens("This is a test message") == 7
    end

    test "estimates tokens for text with punctuation" do
      # "Hello, world!" = 2 words * 1.3 + 2 punctuation * 0.5 = 2.6 + 1 = 3.6 ≈ 4
      assert Context.estimate_tokens("Hello, world!") == 4
      # "What's up?" = 2 words * 1.3 + 2 punctuation * 0.5 = 2.6 + 1 = 3.6 ≈ 4
      assert Context.estimate_tokens("What's up?") == 4
    end

    test "estimates tokens for empty string" do
      # Empty string splits to empty list, length 0 * 1.3 = 0
      assert Context.estimate_tokens("") == 0
    end

    test "estimates tokens for message map" do
      message = %{content: "Hello world", role: "user"}
      # Same as text: 2 words * 1.3 = 2.6 ≈ 3
      assert Context.estimate_tokens(message) == 3
    end

    test "estimates tokens for list of messages" do
      messages = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there"}
      ]

      # "Hello" = 1 word * 1.3 = 1.3 ≈ 1 + 3 = 4
      # "Hi there" = 2 words * 1.3 = 2.6 ≈ 3 + 3 = 6
      # Total: 4 + 6 = 10
      assert Context.estimate_tokens(messages) == 10
    end
  end

  describe "get_context_stats/2" do
    test "calculates context statistics" do
      messages = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there"}
      ]

      stats = Context.get_context_stats(messages, 1_000)

      assert stats.message_count == 2
      # Same calculation as above
      assert stats.estimated_tokens == 10
      assert stats.max_tokens == 1_000
      assert stats.tokens_used_percentage == 1.0
      # 1_000 - 10 - 500 reserve
      assert stats.tokens_remaining == 490
    end

    test "handles empty messages" do
      stats = Context.get_context_stats([], 4_096)

      assert stats.message_count == 0
      assert stats.estimated_tokens == 0
      # 4_096 - 500 reserve
      assert stats.tokens_remaining == 3_596
    end
  end

  describe "prepare_messages/2" do
    test "returns messages as-is when under token limit" do
      messages = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi"}
      ]

      result = Context.prepare_messages(messages, max_tokens: 1_000)
      assert result == messages
    end

    test "adds system prompt when provided" do
      messages = [
        %{role: "user", content: "Hello"}
      ]

      result =
        Context.prepare_messages(messages,
          system_prompt: "You are helpful",
          max_tokens: 1_000
        )

      assert length(result) == 2
      assert hd(result).role == "system"
      assert hd(result).content == "You are helpful"
    end

    test "truncates messages with sliding window strategy" do
      # Create many messages that exceed token limit
      messages =
        for i <- 1..50 do
          %{role: "user", content: "This is message number #{i} with some additional content to make it longer"}
        end

      result =
        Context.prepare_messages(messages,
          # Need to be larger than reserve tokens (500)
          max_tokens: 1_000,
          strategy: :sliding_window
        )

      # Should have fewer messages
      assert length(result) < length(messages)
      # Should keep the most recent messages
      assert length(result) > 0
      assert List.last(result).content =~ "message number"
    end

    test "applies smart truncation strategy" do
      messages =
        for i <- 1..20 do
          role = if rem(i, 2) == 1, do: "user", else: "assistant"
          %{role: role, content: "Message #{i}"}
        end

      result =
        Context.prepare_messages(messages,
          # Need to be large enough to trigger smart truncation
          max_tokens: 800,
          strategy: :smart
        )

      # Should keep first few and recent messages
      assert length(result) < length(messages)
      # Should have a truncation notice
      assert Enum.any?(result, fn msg ->
               msg.role == "system" && String.contains?(msg.content, "omitted")
             end)
    end
  end

  describe "build_context_config/1" do
    test "builds default config" do
      config = Context.build_context_config()

      assert config.max_tokens == 4_096
      assert config.strategy == :sliding_window
      assert config.temperature == 0.7
      assert is_nil(config.system_prompt)
    end

    test "builds config with custom options" do
      config =
        Context.build_context_config(
          max_tokens: 8_192,
          system_prompt: "Be concise",
          strategy: :smart,
          temperature: 0.5
        )

      assert config.max_tokens == 8_192
      assert config.system_prompt == "Be concise"
      assert config.strategy == :smart
      assert config.temperature == 0.5
    end
  end
end
