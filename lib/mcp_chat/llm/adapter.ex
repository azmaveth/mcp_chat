defmodule MCPChat.LLM.Adapter do
  @moduledoc """
  Behaviour for LLM backend adapters.
  """

  @type message :: %{
          role: String.t(),
          content: String.t()
        }

  @type options :: keyword()

  @type response :: %{
          content: String.t(),
          finish_reason: String.t() | nil,
          usage: map() | nil
        }

  @type stream_chunk :: %{
          delta: String.t(),
          finish_reason: String.t() | nil
        }

  @doc """
  Send a chat completion request to the LLM.
  """
  @callback chat(messages :: [message()], options :: options()) ::
              {:ok, response()} | {:error, term()}

  @doc """
  Send a streaming chat completion request to the LLM.
  Returns a stream of chunks.
  """
  @callback stream_chat(messages :: [message()], options :: options()) ::
              {:ok, Enumerable.t()} | {:error, term()}

  @doc """
  Check if the adapter is properly configured and ready to use.
  """
  @callback configured?() :: boolean()

  @doc """
  Get the default model for this adapter.
  """
  @callback default_model() :: String.t()

  @doc """
  List available models for this adapter.
  """
  @callback list_models() :: {:ok, [String.t()]} | {:error, term()}
end
