defmodule MCPChat.CLI.Commands.Base do
  @moduledoc """
  Base behavior and common functionality for CLI commands.

  This module defines the contract that all command modules must implement
  and provides shared utilities for command handling.
  """

  alias MCPChat.CLI.Renderer

  @doc """
  Defines the behavior that command modules must implement.
  """
  @callback commands() :: map()
  @callback handle_command(command :: String.t(), args :: list()) :: :ok | {:error, String.t()}

  @doc """
  Common command validation and error handling.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour MCPChat.CLI.Commands.Base

      import MCPChat.CLI.Commands.Base

      require Logger
    end
  end

  @doc """
  Validates that required arguments are present.
  """
  def require_args(args, count, usage) when length(args) < count do
    {:error, "Usage: #{usage}"}
  end

  def require_args(args, _count, _usage), do: {:ok, args}

  @doc """
  Validates that at least one argument is present.
  """
  def require_arg([], usage), do: {:error, "Usage: #{usage}"}
  def require_arg(args, _usage), do: {:ok, args}

  @doc """
  Parses arguments into a string.
  """
  def parse_args([]), do: ""
  def parse_args([arg]), do: arg
  def parse_args(args) when is_list(args), do: Enum.join(args, " ")

  @doc """
  Displays an error message to the user.
  """
  def show_error(message) do
    Renderer.show_error(message)
    :ok
  end

  @doc """
  Displays a success message to the user.
  """
  def show_success(message) do
    Renderer.show_success(message)
    :ok
  end

  @doc """
  Displays an info message to the user.
  """
  def show_info(message) do
    Renderer.show_info(message)
    :ok
  end

  @doc """
  Displays a warning message to the user.
  """
  def show_warning(message) do
    Renderer.show_warning(message)
    :ok
  end

  @doc """
  Gets the current backend name with proper error handling.
  """
  def get_current_backend do
    MCPChat.Session.get_current_session()
    |> Map.get(:llm_backend, MCPChat.Config.get([:llm, :default]) || "anthropic")
  end

  @doc """
  Gets the current model with proper error handling.
  """
  def get_current_model do
    session = MCPChat.Session.get_current_session()
    backend = get_current_backend()

    model = Map.get(session, :model) || get_default_model(backend)
    {backend, model}
  end

  @doc """
  Gets the default model for a backend.
  """
  def get_default_model(backend) do
    get_configured_model(backend) || get_fallback_model(backend)
  end

  defp get_configured_model(backend) do
    case backend do
      "anthropic" -> MCPChat.Config.get([:llm, :anthropic, :model])
      "openai" -> MCPChat.Config.get([:llm, :openai, :model])
      "ollama" -> MCPChat.Config.get([:llm, :ollama, :model])
      "bedrock" -> MCPChat.Config.get([:llm, :bedrock, :model])
      "gemini" -> MCPChat.Config.get([:llm, :gemini, :model])
      _ -> nil
    end
  end

  defp get_fallback_model(backend) do
    case backend do
      "anthropic" -> "claude-3-5-sonnet-20241022"
      "openai" -> "gpt-4"
      "ollama" -> "llama2"
      "local" -> "microsoft/phi-2"
      "bedrock" -> "claude-3-5-sonnet-v2"
      "gemini" -> "gemini-pro"
      _ -> nil
    end
  end
end
