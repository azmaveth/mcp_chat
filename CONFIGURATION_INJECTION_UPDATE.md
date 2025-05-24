# Configuration Injection Update Summary

## Overview
Updated all LLM adapter modules to support configuration injection similar to the Anthropic adapter. This allows for dynamic configuration at runtime through a `config_provider` option.

## Changes Made

### 1. OpenAI Adapter (`lib/mcp_chat/llm/openai.ex`)
- Added module documentation about configuration injection
- Updated `chat/2` and `stream_chat/2` to accept `config_provider` option
- Updated `get_config/1`, `get_api_key/1`, and `get_base_url/1` to accept config_provider parameter
- Updated `configured?/0` and `default_model/0` to use MCPChat.ConfigProvider.Default
- Updated `fetch_models_from_api/0` to use the default config provider

### 2. Ollama Adapter (`lib/mcp_chat/llm/ollama.ex`)
- Added module documentation about configuration injection
- Updated `chat/2` and `stream_chat/2` to accept `config_provider` option
- Updated `get_config/1`, `get_base_url/1`, and `get_default_model/1` to accept config_provider parameter
- Updated `configured?/0`, `default_model/0`, and `list_models/0` to use MCPChat.ConfigProvider.Default
- Updated `check_ollama_status/0` to use the default config provider

### 3. Bedrock Adapter (`lib/mcp_chat/llm/bedrock.ex`)
- Added module documentation about configuration injection
- Updated `chat/2` and `stream_chat/2` to accept `config_provider` option
- Updated `get_config/1`, `get_aws_credentials/1`, `get_bedrock_client/1`, and `get_model_id/2` to accept config_provider parameter
- Updated `configured?/0`, `default_model/0`, and `list_models/0` to use MCPChat.ConfigProvider.Default

### 4. Gemini Adapter (`lib/mcp_chat/llm/gemini.ex`)
- Added module documentation about configuration injection
- Updated `chat/2` and `stream_chat/2` to accept `config_provider` option
- Updated `get_config/1` and `get_api_key/1` to accept config_provider parameter
- Updated `configured?/0` and `default_model/0` to use MCPChat.ConfigProvider.Default

## Usage Example

All adapters now support the same configuration injection pattern:

```elixir
# Using default configuration
MCPChat.LLM.OpenAI.chat(messages)

# Using custom configuration provider
custom_provider = %{
  get_config: fn [:llm, :openai] -> 
    %{
      api_key: "custom-key",
      model: "gpt-4",
      base_url: "https://custom-endpoint.com"
    }
  end
}

MCPChat.LLM.OpenAI.chat(messages, config_provider: custom_provider)
```

## Implementation Details

1. **Default Behavior**: When no `config_provider` is specified, the adapters use `MCPChat.ConfigProvider.Default`, which maintains backward compatibility.

2. **Config Provider Interface**: The config provider must implement a `get_config/1` function that accepts a path (e.g., `[:llm, :openai]`) and returns a configuration map.

3. **Consistent Pattern**: All adapters follow the same pattern:
   - Extract `config_provider` from options with default to `MCPChat.ConfigProvider.Default`
   - Pass `config_provider` to all configuration-related functions
   - Handle both the default provider and custom providers in `get_config/1`

This update ensures all LLM adapters have consistent configuration injection capabilities, making them more flexible and testable.