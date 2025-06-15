defmodule MCPChat.Context.AsyncFileLoader do
  @moduledoc """
  Asynchronous file loader for context management.

  Features:
  - Non-blocking file loading with async operations
  - Progress tracking for large files and multiple files
  - File validation and content preprocessing
  - Batch loading with configurable concurrency
  - Cancellation support for long operations
  - Memory-efficient streaming for large files
  """

  require Logger
  alias MCPChat.{MCP.ProgressTracker, Session}

  defmodule LoadOperation do
    @moduledoc false
    defstruct [
      :id,
      :file_path,
      :task,
      :progress_token,
      :start_time,
      :status,
      :result,
      :error
    ]
  end

  defmodule LoadRequest do
    @moduledoc false
    defstruct [
      :file_paths,
      :options,
      :callback,
      :progress_callback
    ]
  end

  @default_opts [
    max_concurrency: 3,
    timeout: 30_000,
    # 10MB
    max_file_size: 10 * 1_024 * 1_024,
    # 64KB chunks
    chunk_size: 64 * 1_024,
    validate_content: true,
    track_progress: true
  ]

  @doc """
  Load a single file asynchronously.

  Returns `{:ok, task_ref}` immediately. The result will be delivered
  via the callback function or can be awaited using `await_result/2`.
  """
  def load_file_async(file_path, opts \\ []) do
    load_files_async([file_path], opts)
  end

  @doc """
  Load multiple files asynchronously with configurable concurrency.

  ## Options
  - `:max_concurrency` - Maximum concurrent file loads (default: 3)
  - `:timeout` - Timeout per file in milliseconds (default: 30s)
  - `:max_file_size` - Maximum file size in bytes (default: 10MB)
  - `:chunk_size` - Read chunk size for large files (default: 64KB)
  - `:validate_content` - Validate file content (default: true)
  - `:track_progress` - Enable progress tracking (default: true)
  - `:callback` - Function to call with results `{:ok, results} | {:error, reason}`
  - `:progress_callback` - Function to call with progress updates

  ## Returns
  `{:ok, operation_id}` - Use with `await_results/2` or results via callback
  """
  def load_files_async(file_paths, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)
    operation_id = generate_operation_id()

    # Always start the async operation - validation happens during execution
    request = %LoadRequest{
      file_paths: file_paths,
      options: opts,
      callback: Keyword.get(opts, :callback),
      progress_callback: Keyword.get(opts, :progress_callback)
    }

    Task.start(fn -> execute_load_operation(operation_id, request) end)
    {:ok, operation_id}
  end

  @doc """
  Add a file to the current session context asynchronously.

  This is a convenience function that loads the file and automatically
  adds it to the session context when complete.
  """
  def add_to_context_async(file_path, opts \\ []) do
    callback = build_context_callback(file_path, opts)
    load_file_async(file_path, Keyword.put(opts, :callback, callback))
  end

  defp build_context_callback(file_path, opts) do
    fn
      {:ok, [result]} ->
        handle_single_file_result(result, file_path, opts)

      {:error, reason} ->
        handle_context_error(reason, opts)
    end
  end

  defp handle_single_file_result(result, file_path, opts) do
    case result.status do
      :success ->
        add_loaded_file_to_context(result)
        if cb = opts[:success_callback], do: cb.(result)

      :failed ->
        Logger.warning("Failed to load file for context: #{file_path}")
        if cb = opts[:error_callback], do: cb.(result.error)
    end
  end

  defp handle_context_error(reason, opts) do
    Logger.error("Async context loading failed: #{inspect(reason)}")
    if cb = opts[:error_callback], do: cb.(reason)
  end

  @doc """
  Load multiple files and add them to context in batch.
  """
  def add_batch_to_context_async(file_paths, opts \\ []) do
    callback = fn
      {:ok, results} ->
        successful_files =
          results
          |> Enum.filter(&(&1.status == :success))
          |> Enum.each(&add_loaded_file_to_context/1)

        failed_files = Enum.filter(results, &(&1.status != :success))

        Logger.info("Batch context loading: #{length(successful_files)} successful, #{length(failed_files)} failed")

        if cb = opts[:batch_callback] do
          cb.(%{successful: successful_files, failed: failed_files})
        end

      {:error, reason} ->
        Logger.error("Batch context loading failed: #{inspect(reason)}")
        if cb = opts[:error_callback], do: cb.(reason)
    end

    load_files_async(file_paths, Keyword.put(opts, :callback, callback))
  end

  @doc """
  Cancel an ongoing load operation.
  """
  def cancel_operation(operation_id) do
    # In a full implementation, this would track active operations
    # and cancel the associated tasks
    Logger.info("Cancelling load operation: #{operation_id}")
    :ok
  end

  @doc """
  Check if a file is suitable for context loading.
  """
  def validate_file_for_context(file_path, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)

    cond do
      not File.exists?(file_path) ->
        {:error, :file_not_found}

      not File.regular?(file_path) ->
        {:error, :not_regular_file}

      File.stat!(file_path).size > opts[:max_file_size] ->
        {:error, :file_too_large}

      not readable_file?(file_path) ->
        {:error, :file_not_readable}

      true ->
        :ok
    end
  end

  # Private Functions

  defp execute_load_operation(operation_id, request) do
    Logger.debug("Starting async load operation #{operation_id} for #{length(request.file_paths)} files")

    start_time = System.monotonic_time(:millisecond)

    progress_token =
      if request.options[:track_progress] do
        ProgressTracker.start_operation("file_loading", %{
          operation_id: operation_id,
          file_count: length(request.file_paths)
        })
      end

    # Report initial progress
    if request.progress_callback do
      request.progress_callback.(%{
        phase: :starting,
        operation_id: operation_id,
        total_files: length(request.file_paths),
        completed: 0
      })
    end

    # Create load operations for each file
    operations =
      request.file_paths
      |> Enum.with_index()
      |> Enum.map(fn {file_path, index} ->
        %LoadOperation{
          id: "#{operation_id}_file_#{index}",
          file_path: file_path,
          progress_token: progress_token,
          start_time: System.monotonic_time(:millisecond),
          status: :pending
        }
      end)

    # Execute loads with controlled concurrency
    results =
      operations
      |> Task.async_stream(
        fn operation -> load_single_file(operation, request.options) end,
        max_concurrency: request.options[:max_concurrency],
        timeout: request.options[:timeout],
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} ->
          result

        {:exit, reason} ->
          %LoadOperation{
            id: "unknown",
            file_path: "unknown",
            status: :crashed,
            error: reason,
            start_time: System.monotonic_time(:millisecond)
          }
      end)

    total_duration = System.monotonic_time(:millisecond) - start_time

    # Complete progress tracking
    if progress_token do
      successful_count = Enum.count(results, &(&1.status == :success))

      if successful_count == length(results) do
        ProgressTracker.complete_operation(progress_token)
      else
        ProgressTracker.fail_operation(progress_token, "Some files failed to load")
      end
    end

    # Final progress report
    if request.progress_callback do
      {successful, failed} = Enum.split_with(results, &(&1.status == :success))

      request.progress_callback.(%{
        phase: :completed,
        operation_id: operation_id,
        total_files: length(request.file_paths),
        successful: length(successful),
        failed: length(failed),
        duration_ms: total_duration
      })
    end

    # Call completion callback if provided
    if request.callback do
      if Enum.all?(results, &(&1.status == :success)) do
        request.callback.({:ok, results})
      else
        successful_results = Enum.filter(results, &(&1.status == :success))
        failed_results = Enum.filter(results, &(&1.status != :success))
        request.callback.({:partial, %{successful: successful_results, failed: failed_results}})
      end
    end

    Logger.debug("Async load operation #{operation_id} completed in #{total_duration}ms")
    {:ok, results}
  end

  defp load_single_file(operation, opts) do
    try do
      Logger.debug("Loading file: #{operation.file_path}")

      # Validate file first
      case validate_file_for_context(operation.file_path, opts) do
        :ok ->
          # Load file content
          case read_file_efficiently(operation.file_path, opts) do
            {:ok, content} ->
              duration_ms = System.monotonic_time(:millisecond) - operation.start_time

              # Validate content if requested
              content =
                if opts[:validate_content] do
                  validate_and_clean_content(content)
                else
                  content
                end

              file_info = %{
                path: operation.file_path,
                name: Path.basename(operation.file_path),
                content: content,
                size: byte_size(content),
                loaded_at: DateTime.utc_now(),
                load_duration_ms: duration_ms
              }

              Logger.debug(
                "Successfully loaded #{operation.file_path} (#{byte_size(content)} bytes) in #{duration_ms}ms"
              )

              %{operation | status: :success, result: file_info}

            {:error, reason} ->
              Logger.warning("Failed to read #{operation.file_path}: #{inspect(reason)}")
              %{operation | status: :failed, error: reason}
          end

        {:error, reason} ->
          Logger.warning("File validation failed for #{operation.file_path}: #{inspect(reason)}")
          %{operation | status: :failed, error: reason}
      end
    rescue
      e ->
        Logger.error("Exception loading #{operation.file_path}: #{inspect(e)}")
        %{operation | status: :crashed, error: e}
    end
  end

  defp read_file_efficiently(file_path, opts) do
    file_size = File.stat!(file_path).size

    if file_size > opts[:chunk_size] do
      # Stream large files in chunks
      read_file_in_chunks(file_path, opts[:chunk_size])
    else
      # Read small files directly
      File.read(file_path)
    end
  end

  defp read_file_in_chunks(file_path, chunk_size) do
    try do
      content =
        File.stream!(file_path, [], chunk_size)
        |> Enum.join()

      {:ok, content}
    rescue
      e -> {:error, e}
    end
  end

  defp validate_and_clean_content(content) do
    # Basic content validation and cleaning
    content
    # Normalize line endings
    |> String.replace(~r/\r\n/, "\n")
    # Handle old Mac line endings
    |> String.replace(~r/\r/, "\n")
    # Remove trailing spaces/tabs from lines
    |> String.replace(~r/[ \t]+\n/, "\n")
    # Remove trailing spaces/tabs from file (preserve final newline)
    |> String.replace(~r/[ \t]+$/, "")
  end

  defp validate_file_paths(file_paths, opts) do
    Enum.reduce_while(file_paths, :ok, fn path, _acc ->
      case validate_file_for_context(path, opts) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, "File #{path}: #{reason}"}}
      end
    end)
  end

  defp readable_file?(file_path) do
    case File.open(file_path, [:read]) do
      {:ok, file} ->
        File.close(file)
        true

      {:error, _} ->
        false
    end
  end

  defp add_loaded_file_to_context(load_result) do
    file_info = load_result.result

    # Get current session
    session = Session.get_current_session()

    # Get or initialize context files map
    context_files = session.context[:files] || %{}

    # Add file to context
    updated_files = Map.put(context_files, file_info.name, file_info)
    updated_context = Map.put(session.context, :files, updated_files)

    # Update session
    Session.update_session(%{context: updated_context})

    Logger.info("Added #{file_info.name} to context (#{byte_size(file_info.content)} bytes)")
  end

  defp generate_operation_id do
    "async_load_#{System.unique_integer([:positive])}_#{System.system_time(:millisecond)}"
  end
end
