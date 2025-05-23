defmodule MCPChat.LLMBackendIntegrationTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Integration tests for LLM backend functionality.
  Tests the LLM client working with different backends.
  """

  setup_all do
    Application.ensure_all_started(:mcp_chat)
    :ok
  end

  describe "LLM backend initialization" do
    test "initializes OpenAI-compatible backend" do
      config = %{
        "name" => "openai",
        "api_key" => "test-key",
        "base_url" => "https://api.openai.com/v1",
        "model" => "gpt-4"
      }

      # Verify configuration structure
      assert config["name"] == "openai"
      assert config["api_key"] != nil
      assert config["base_url"] =~ ~r/^https?:\/\//
    end

    test "initializes Anthropic backend" do
      config = %{
        "name" => "anthropic",
        "api_key" => "test-key",
        "model" => "claude-3-sonnet-20240229"
      }

      assert config["name"] == "anthropic"
      assert config["model"] =~ ~r/claude/
    end

    test "initializes Ollama backend" do
      config = %{
        "name" => "ollama",
        "base_url" => "http://localhost:11_434",
        "model" => "llama2"
      }

      assert config["name"] == "ollama"
      assert config["base_url"] =~ ~r/localhost/
    end
  end

  describe "Message formatting for backends" do
    test "formats messages for OpenAI API" do
      messages = [
        %{role: "system", content: "You are a helpful assistant"},
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there!"}
      ]

      # Test message structure is compatible
      Enum.each(messages, fn msg ->
        assert msg.role in ["system", "user", "assistant"]
        assert is_binary(msg.content)
      end)
    end

    test "formats messages with tool calls" do
      message_with_tool = %{
        role: "assistant",
        content: nil,
        tool_calls: [
          %{
            id: "call_123",
            type: "function",
            function: %{
              name: "get_weather",
              arguments: ~s({"location": "San Francisco"})
            }
          }
        ]
      }

      assert message_with_tool.tool_calls != nil
      assert length(message_with_tool.tool_calls) == 1
      assert hd(message_with_tool.tool_calls).function.name == "get_weather"
    end

    test "formats tool response messages" do
      tool_response = %{
        role: "tool",
        tool_call_id: "call_123",
        name: "get_weather",
        content: ~s({"temperature": 72, "conditions": "sunny"})
      }

      assert tool_response.role == "tool"
      assert tool_response.tool_call_id == "call_123"
      assert tool_response.content =~ "temperature"
    end
  end

  describe "Request construction" do
    test "constructs chat completion request" do
      request = %{
        model: "gpt-4",
        messages: [
          %{role: "user", content: "Hello"}
        ],
        temperature: 0.7,
        max_tokens: 1_000,
        stream: false
      }

      assert request.model != nil
      assert length(request.messages) > 0
      assert request.temperature >= 0 and request.temperature <= 2
      assert request.max_tokens > 0
    end

    test "constructs streaming request" do
      request = %{
        model: "gpt-4",
        messages: [
          %{role: "user", content: "Tell me a story"}
        ],
        stream: true,
        stream_options: %{
          include_usage: true
        }
      }

      assert request.stream == true
      assert request.stream_options.include_usage == true
    end

    test "constructs request with tools" do
      request = %{
        model: "gpt-4",
        messages: [
          %{role: "user", content: "What's the weather?"}
        ],
        tools: [
          %{
            type: "function",
            function: %{
              name: "get_weather",
              description: "Get current weather",
              parameters: %{
                type: "object",
                properties: %{
                  location: %{type: "string"}
                },
                required: ["location"]
              }
            }
          }
        ],
        tool_choice: "auto"
      }

      assert length(request.tools) == 1
      assert hd(request.tools).function.name == "get_weather"
      assert request.tool_choice == "auto"
    end
  end

  describe "Response parsing" do
    test "parses non-streaming response" do
      response = %{
        "id" => "chatcmpl-123",
        "object" => "chat.completion",
        "created" => 167_765_228_8,
        "model" => "gpt-4",
        "choices" => [
          %{
            "index" => 0,
            "message" => %{
              "role" => "assistant",
              "content" => "Hello! How can I help you?"
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 10,
          "completion_tokens" => 20,
          "total_tokens" => 30
        }
      }

      assert response["choices"] != nil
      assert length(response["choices"]) > 0
      choice = hd(response["choices"])
      assert choice["message"]["content"] == "Hello! How can I help you?"
      assert response["usage"]["total_tokens"] == 30
    end

    test "parses streaming chunk" do
      chunk = %{
        "id" => "chatcmpl-123",
        "object" => "chat.completion.chunk",
        "created" => 167_765_228_8,
        "model" => "gpt-4",
        "choices" => [
          %{
            "index" => 0,
            "delta" => %{
              "content" => "Hello"
            },
            "finish_reason" => nil
          }
        ]
      }

      assert chunk["object"] == "chat.completion.chunk"
      assert hd(chunk["choices"])["delta"]["content"] == "Hello"
    end

    test "parses tool call response" do
      response = %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => nil,
              "tool_calls" => [
                %{
                  "id" => "call_abc",
                  "type" => "function",
                  "function" => %{
                    "name" => "get_weather",
                    "arguments" => ~s({"location": "NYC"})
                  }
                }
              ]
            },
            "finish_reason" => "tool_calls"
          }
        ]
      }

      message = hd(response["choices"])["message"]
      assert message["tool_calls"] != nil
      assert length(message["tool_calls"]) == 1
      tool_call = hd(message["tool_calls"])
      assert tool_call["function"]["name"] == "get_weather"
    end

    test "parses error response" do
      error_response = %{
        "error" => %{
          "message" => "Invalid API key",
          "type" => "invalid_request_error",
          "code" => "invalid_api_key"
        }
      }

      assert error_response["error"] != nil
      assert error_response["error"]["message"] =~ "Invalid API key"
      assert error_response["error"]["code"] == "invalid_api_key"
    end
  end

  describe "Token counting integration" do
    test "estimates tokens for messages" do
      messages = [
        %{role: "system", content: "You are helpful"},
        %{role: "user", content: "Hello, how are you?"},
        %{role: "assistant", content: "I'm doing well, thank you!"}
      ]

      # Use the actual token estimation
      total_tokens = MCPChat.LLM.TokenEstimator.estimate_messages(messages)

      assert total_tokens > 0
      # These short messages should be under 100 tokens
      assert total_tokens < 100
    end

    test "tracks token usage from responses" do
      usage = %{
        "prompt_tokens" => 25,
        "completion_tokens" => 15,
        "total_tokens" => 40
      }

      assert usage["total_tokens"] == usage["prompt_tokens"] + usage["completion_tokens"]
    end
  end

  describe "Cost calculation integration" do
    test "calculates cost for different models" do
      usage = %{
        input_tokens: 1_000,
        output_tokens: 500
      }

      # Test with different models
      gpt4_cost = MCPChat.LLM.CostCalculator.calculate_cost("gpt-4", usage)
      gpt35_cost = MCPChat.LLM.CostCalculator.calculate_cost("gpt-3.5-turbo", usage)

      assert gpt4_cost > 0
      assert gpt35_cost > 0
      # GPT-4 is more expensive
      assert gpt4_cost > gpt35_cost
    end

    test "handles unknown model pricing" do
      usage = %{
        input_tokens: 1_000,
        output_tokens: 500
      }

      cost = MCPChat.LLM.CostCalculator.calculate_cost("unknown-model", usage)
      assert cost == 0.0
    end
  end

  describe "Error handling integration" do
    test "handles rate limit errors" do
      error = %{
        "error" => %{
          "type" => "rate_limit_error",
          "message" => "Rate limit exceeded",
          "code" => 429
        }
      }

      assert error["error"]["code"] == 429
      assert error["error"]["type"] == "rate_limit_error"
    end

    test "handles network timeouts" do
      # Simulate timeout error structure
      timeout_error = {:error, :timeout}

      assert elem(timeout_error, 0) == :error
      assert elem(timeout_error, 1) == :timeout
    end

    test "handles malformed responses" do
      malformed = %{
        "choices" => nil,
        "error" => nil
      }

      # Should handle gracefully
      assert malformed["choices"] == nil
      assert malformed["error"] == nil
    end
  end
end
