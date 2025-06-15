defmodule MCPChat.MCP.ParallelConnectionManager do
  @moduledoc """
  Manages parallel MCP server connections for improved performance.

  Features:
  - Concurrent server initialization
  - Connection timeout handling
  - Progress tracking for parallel operations
  - Configurable concurrency limits
  - Error isolation per server
  """

  alias MCPChat.MCP.{LazyServerManager, ServerManager}

  require Logger

  defmodule ConnectionResult do
    @moduledoc false
    defstruct [:server_name, :config, :status, :pid, :error, :duration_ms]
  end

  @default_opts [
    max_concurrency: 10,
    # 30 seconds per server
    connection_timeout: 30_000,
    # 60 seconds total
    overall_timeout: 60_000,
    retry_attempts: 2
  ]

  @doc """
  Connects to multiple MCP servers in parallel.

  Options:
  - `:max_concurrency` - Maximum concurrent connections (default: 10)
  - `:connection_timeout` - Timeout per server connection (default: 30s)
  - `:overall_timeout` - Total timeout for all connections (default: 60s)
  - `:retry_attempts` - Number of retry attempts per server (default: 2)
  - `:progress_callback` - Function to call with progress updates

  Returns `{:ok, results}` where results is a list of ConnectionResult structs.
  """
  def connect_servers_parallel(servers, opts \\ []) do
    # Get configuration with fallbacks
    config =
      try do
        MCPChat.Config.get([:startup, :parallel]) || %{}
      rescue
        _ -> %{}
      end

    # Merge defaults, config, and opts (opts have highest priority)
    default_opts_with_config =
      Keyword.merge(@default_opts,
        max_concurrency: config[:max_concurrency] || @default_opts[:max_concurrency],
        connection_timeout: config[:connection_timeout] || @default_opts[:connection_timeout],
        show_progress: config[:show_progress] || false
      )

    opts = Keyword.merge(default_opts_with_config, opts)

    start_time = System.monotonic_time(:millisecond)
    progress_callback = Keyword.get(opts, :progress_callback)

    Logger.info("Starting parallel connection to #{length(servers)} MCP servers")

    # Report initial progress
    if progress_callback do
      progress_callback.(%{
        phase: :starting,
        total: length(servers),
        completed: 0,
        in_progress: 0
      })
    end

    # Use Task.async_stream for controlled concurrency
    tasks_stream =
      servers
      |> Enum.with_index()
      |> Task.async_stream(
        fn {{name, config}, index} ->
          connect_single_server(name, config, index, opts)
        end,
        max_concurrency: opts[:max_concurrency],
        timeout: opts[:overall_timeout],
        on_timeout: :kill_task
      )

    # Collect results with progress tracking
    results =
      tasks_stream
      |> Enum.with_index()
      |> Enum.map(fn
        {{:ok, result}, index} ->
          # Report progress if callback provided
          if progress_callback do
            progress_callback.(%{
              phase: :connecting,
              total: length(servers),
              completed: index + 1,
              current_server: result.server_name,
              elapsed_ms: System.monotonic_time(:millisecond) - start_time
            })
          end

          result

        {{:exit, reason}, index} ->
          Logger.error("Task #{index} exited: #{inspect(reason)}")

          %ConnectionResult{
            server_name: "task_#{index}",
            config: %{},
            status: :crashed,
            error: reason,
            duration_ms: 0
          }
      end)

    # Calculate summary statistics
    {successful, failed} = Enum.split_with(results, &(&1.status == :connected))

    total_duration = System.monotonic_time(:millisecond) - start_time

    Logger.info("""
    Parallel connection completed in #{total_duration}ms:
    - Successful: #{length(successful)}
    - Failed: #{length(failed)}
    - Concurrency: #{opts[:max_concurrency]}
    """)

    # Final progress report
    if progress_callback do
      progress_callback.(%{
        phase: :completed,
        total: length(servers),
        completed: length(successful),
        failed: length(failed),
        duration_ms: total_duration
      })
    end

    {:ok, results}
  end

  @doc """
  Connects to servers using the current connection mode (lazy/eager/background).

  This function respects the startup configuration but optimizes the connection
  process within each mode.
  """
  def connect_with_mode(servers, mode, opts \\ []) do
    case mode do
      :eager ->
        # Connect all servers immediately in parallel
        connect_servers_parallel(servers, opts)

      :background ->
        # Start parallel connections in a background task
        Task.start(fn ->
          # Small delay to let UI initialize
          Process.sleep(100)
          connect_servers_parallel(servers, opts)
        end)

        {:ok, []}

      :lazy ->
        # Don't connect now, but prepare for parallel connection on demand
        LazyServerManager.prepare_parallel_connections(servers, opts)
        {:ok, []}

      _ ->
        Logger.warning("Unknown connection mode: #{mode}, falling back to eager")
        connect_servers_parallel(servers, opts)
    end
  end

  # Private Functions

  defp connect_single_server(name, config, index, opts) do
    start_time = System.monotonic_time(:millisecond)

    try do
      Logger.debug("Starting connection to server '#{name}' (#{index + 1})")

      # Attempt connection with retries
      result =
        with_retries(opts[:retry_attempts], fn ->
          case ServerManager.Core.start_server(name, config) do
            {:ok, pid} ->
              # Wait for connection to be established
              wait_for_connection(pid, name, opts[:connection_timeout])

            {:error, reason} ->
              {:error, reason}
          end
        end)

      duration_ms = System.monotonic_time(:millisecond) - start_time

      case result do
        {:ok, pid} ->
          Logger.debug("Successfully connected to server '#{name}' in #{duration_ms}ms")

          %ConnectionResult{
            server_name: name,
            config: config,
            status: :connected,
            pid: pid,
            duration_ms: duration_ms
          }

        {:error, reason} ->
          Logger.warning("Failed to connect to server '#{name}': #{inspect(reason)}")

          %ConnectionResult{
            server_name: name,
            config: config,
            status: :failed,
            error: reason,
            duration_ms: duration_ms
          }
      end
    catch
      :exit, reason ->
        duration_ms = System.monotonic_time(:millisecond) - start_time
        Logger.error("Server '#{name}' connection crashed: #{inspect(reason)}")

        %ConnectionResult{
          server_name: name,
          config: config,
          status: :crashed,
          error: reason,
          duration_ms: duration_ms
        }
    end
  end

  defp wait_for_connection(pid, _name, timeout) do
    # Simple health check - try to get server info
    case GenServer.call(pid, :get_info, timeout) do
      {:ok, _info} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  defp with_retries(0, _fun), do: {:error, :max_retries_exceeded}

  defp with_retries(attempts, fun) when attempts > 0 do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, _reason} when attempts > 1 ->
        # Brief delay before retry
        Process.sleep(100)
        with_retries(attempts - 1, fun)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
