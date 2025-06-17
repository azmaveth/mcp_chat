defmodule MCPChat.CLI.Base do
  @moduledoc """
  Base behavior and common functionality for CLI commands.

  This module defines the contract that all command modules must implement
  and provides shared utilities for command handling.
  """

  alias MCPChat.CLI.Renderer
  alias MCPChat.Session

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
      @behaviour MCPChat.CLI.Base

      import MCPChat.CLI.Base
      import MCPChat.CLI.Helpers

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
    Session.get_session_backend()
  end

  @doc """
  Gets the current model with proper error handling.
  """
  def get_current_model do
    backend = get_current_backend()
    model = Session.get_session_model() || get_default_model(backend)
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

  @doc """
  Handles operation results with consistent success/error messaging.

  ## Examples

      iex> handle_result({:ok, "Success"}, "Operation completed")
      # Shows success message

      iex> handle_result({:error, "Failed"}, "Operation completed")
      # Shows error message
  """
  def handle_result(result, success_msg, error_prefix \\ "Failed")

  def handle_result({:ok, _result}, success_msg, _error_prefix) do
    show_success(success_msg)
  end

  def handle_result({:error, reason}, _success_msg, error_prefix) do
    show_error("#{error_prefix}: #{inspect(reason)}")
  end

  @doc """
  Shows operation result with custom formatting for success values.
  """
  def show_operation_result(result, msg, format_fn \\ &inspect/1)

  def show_operation_result({:ok, result}, success_msg, format_fn) do
    formatted_result = format_fn.(result)
    show_success("#{success_msg}: #{formatted_result}")
  end

  def show_operation_result({:error, reason}, error_prefix, _format_fn) do
    show_error("#{error_prefix}: #{inspect(reason)}")
  end

  @doc """
  Executes a function with the current session, showing appropriate errors.
  """
  def with_current_session(fun) when is_function(fun, 1) do
    case Session.require_session() do
      {:ok, session} ->
        try do
          fun.(session)
        rescue
          error -> show_error("Error: #{inspect(error)}")
        end

      {:error, :no_active_session} ->
        show_error("No active session. Start a conversation first.")
    end
  end

  @doc """
  Gets session information for display, with fallbacks for missing data.
  """
  def get_session_info_for_display(keys) when is_list(keys) do
    Session.get_session_info(keys)
  end
end
