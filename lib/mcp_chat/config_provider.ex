defmodule MCPChat.ConfigProvider do
  @moduledoc """
  Behaviour for configuration providers and a default implementation.

  This allows modules to receive configuration through dependency injection
  rather than directly accessing MCPChat.Config, making them more portable
  and testable.
  """

  @doc """
  Gets configuration value for a given key or path.
  """
  @callback get(key :: atom() | [atom()]) :: any()

  @doc """
  Gets all configuration.
  """
  @callback get_all() :: map()

  defmodule Default do
    @moduledoc """
    Default implementation that delegates to MCPChat.Config.
    Used by the main application.
    """
    @behaviour MCPChat.ConfigProvider

    @impl true
    def get(key) do
      MCPChat.Config.get(key)
    end

    @impl true
    def get_all do
      MCPChat.Config.get_all()
    end
  end

  defmodule Static do
    @moduledoc """
    Static configuration provider for testing and library usage.

    Usage:
        config = %{llm: %{default: "openai", openai: %{api_key: "test"}}}
        {:ok, provider} = MCPChat.ConfigProvider.Static.start_link(config)
        MCPChat.LLM.OpenAI.chat(messages, config_provider: provider)
    """
    use Agent

    def start_link(config) do
      Agent.start_link(fn -> config end)
    end

    def get(provider, key) when is_atom(key) do
      Agent.get(provider, &Map.get(&1, key))
    end

    def get(provider, [head | tail]) when is_atom(head) do
      Agent.get(provider, fn config ->
        get_in(config, [head | tail])
      end)
    end

    def get_all(provider) do
      Agent.get(provider, & &1)
    end
  end
end
