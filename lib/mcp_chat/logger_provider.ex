defmodule MCPChat.LoggerProvider do
  @moduledoc """
  Behaviour for configurable logging providers.

  This enables dependency injection of logging functionality,
  making the modules more testable and suitable for library usage
  where consumers may want to use their own logging systems.

  ## Example

      # Use default provider (uses Elixir Logger when available)
      MCPChat.LoggerProvider.Default.info("Starting process")

      # Use noop provider for silent operation
      MCPChat.LoggerProvider.Noop.info("This won't be logged")

      # Use custom provider
      {:ok, provider} = MCPChat.LoggerProvider.Custom.start_link(&MyApp.log/2)
      MCPChat.LoggerProvider.Custom.info(provider, "Custom logging")
  """

  @type log_level :: :debug | :info | :warning | :error
  @type message :: String.t() | iodata()
  @type metadata :: keyword()

  @doc """
  Log a debug message.
  """
  @callback debug(message(), metadata()) :: :ok

  @doc """
  Log an info message.
  """
  @callback info(message(), metadata()) :: :ok

  @doc """
  Log a warning message.
  """
  @callback warning(message(), metadata()) :: :ok

  @doc """
  Log an error message.
  """
  @callback error(message(), metadata()) :: :ok

  defmodule Default do
    @moduledoc """
    Default logger provider that uses Elixir's Logger when available.
    Falls back to IO.puts if Logger is not available.
    """
    @behaviour MCPChat.LoggerProvider

    require Logger

    @impl true
    def debug(message, metadata \\ []) do
      log(:debug, message, metadata)
    end

    @impl true
    def info(message, metadata \\ []) do
      log(:info, message, metadata)
    end

    @impl true
    def warning(message, metadata \\ []) do
      log(:warning, message, metadata)
    end

    @impl true
    def error(message, metadata \\ []) do
      log(:error, message, metadata)
    end

    defp log(level, message, metadata) do
      if Code.ensure_loaded?(Logger) do
        # Use the appropriate Logger function based on level
        case level do
          :debug -> Logger.debug(message, metadata)
          :info -> Logger.info(message, metadata)
          :warning -> Logger.warning(message, metadata)
          :error -> Logger.error(message, metadata)
        end
      else
        formatted_message = "[#{String.upcase(to_string(level))}] #{message}"
        formatted_message = if metadata != [], do: "#{formatted_message} #{inspect(metadata)}", else: formatted_message
        IO.puts(formatted_message)
      end

      :ok
    end
  end

  defmodule Noop do
    @moduledoc """
    No-op logger provider for silent operation.
    Useful for testing or when logging should be completely disabled.
    """
    @behaviour MCPChat.LoggerProvider

    @impl true
    def debug(_message, _metadata \\ []), do: :ok

    @impl true
    def info(_message, _metadata \\ []), do: :ok

    @impl true
    def warning(_message, _metadata \\ []), do: :ok

    @impl true
    def error(_message, _metadata \\ []), do: :ok
  end

  defmodule Custom do
    @moduledoc """
    Custom logger provider for external logging systems.

    Usage:
        # With a simple function
        {:ok, provider} = MCPChat.LoggerProvider.Custom.start_link(fn level, message ->
          MyLogger.log(level, message)
        end)

        # With a more complex function that handles metadata
        {:ok, provider} = MCPChat.LoggerProvider.Custom.start_link(fn level, message, metadata ->
          MyLogger.log(level, message, metadata)
        end)
    """
    use Agent

    def start_link(log_fun) when is_function(log_fun) do
      arity = Function.info(log_fun)[:arity]

      if arity in [2, 3] do
        Agent.start_link(fn -> {log_fun, arity} end)
      else
        {:error, :invalid_log_function_arity}
      end
    end

    def debug(provider, message, metadata \\ []) do
      log(provider, :debug, message, metadata)
    end

    def info(provider, message, metadata \\ []) do
      log(provider, :info, message, metadata)
    end

    def warning(provider, message, metadata \\ []) do
      log(provider, :warning, message, metadata)
    end

    def error(provider, message, metadata \\ []) do
      log(provider, :error, message, metadata)
    end

    defp log(provider, level, message, metadata) do
      Agent.get(provider, fn {log_fun, arity} ->
        case arity do
          2 -> log_fun.(level, message)
          3 -> log_fun.(level, message, metadata)
        end
      end)

      :ok
    end
  end
end
