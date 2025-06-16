defmodule MCPChat.CLI.Chat do
  @moduledoc """
  Main chat interface for the MCP client.
  """

  require Logger
  alias MCPChat.CLI.ExReadlineAdapter
  alias MCPChat.CLI.{Commands, Renderer}
  alias MCPChat.Context.AtSymbolResolver
  alias MCPChat.LLM.ExLLMAdapter
  alias MCPChat.{Config, Session}

  # alias MCPChat.LLM

  def start do
    start([])
  end

  def start(_opts) do
    Renderer.clear_screen()
    Renderer.show_welcome()

    # Emit telemetry event for session start
    session_id = generate_session_id()
    MCPChat.Telemetry.emit_session_started(session_id, %{startup_time: System.system_time(:millisecond)})

    # Set up command completion
    ExReadlineAdapter.set_completion_fn(&Commands.get_completions/1)

    # Start the chat loop
    start_time = System.monotonic_time(:millisecond)
    result = chat_loop()

    # Emit telemetry event for session end
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time
    MCPChat.Telemetry.emit_session_ended(session_id, duration, %{end_time: System.system_time(:millisecond)})

    result
  end

  defp chat_loop do
    # Print newline before prompt for spacing
    IO.write("\n")
    prompt = Renderer.format_prompt()

    case ExReadlineAdapter.read_line(prompt) do
      :eof ->
        Renderer.show_goodbye()
        :ok

      input ->
        # Debug output
        if System.get_env("MCP_DEBUG") == "1" do
          IO.puts("[DEBUG Chat] Got input: #{inspect(input)}")
          IO.puts("[DEBUG Chat] After trim: #{inspect(String.trim(input))}")
        end

        input = String.trim(input)

        case process_input(input) do
          :exit ->
            Renderer.show_goodbye()
            :ok

          :continue ->
            chat_loop()
        end
    end
  end

  defp process_input(""), do: :continue
  defp process_input("/exit"), do: :exit
  defp process_input("/quit"), do: :exit
  defp process_input("/q"), do: :exit

  defp process_input("/" <> command) do
    # Debug output
    if System.get_env("MCP_DEBUG") == "1" do
      IO.puts("[DEBUG] Processing command: #{inspect(command)}")
    end

    case Commands.handle_command(command) do
      {:message, text} ->
        # Alias returned a message to send
        process_input(text)

      {:resume_stream, stream} ->
        # Handle resumed stream
        handle_resumed_stream(stream)
        :continue

      :exit ->
        :exit

      result ->
        # Debug output
        if System.get_env("MCP_DEBUG") == "1" do
          IO.puts("[DEBUG] Command result: #{inspect(result)}")
        end

        :continue
    end
  end

  defp process_input(message) do
    # Process @ symbol references if any
    {processed_message, at_metadata} = process_at_symbols(message)

    # Add user message to session (original message for history)
    Session.add_message("user", message)

    # Display @ symbol processing results if any
    if at_metadata.total_tokens > 0 do
      display_at_symbol_info(at_metadata)
    end

    # Show thinking indicator
    Renderer.show_thinking()

    # Get LLM response using processed message
    case get_llm_response(processed_message) do
      {:ok, response_data} ->
        # response_data is now the full response map with content, usage, cost, etc.
        content = get_response_content(response_data)
        Session.add_message("assistant", content)

        # Track cost using full response for comprehensive tracking
        Session.track_cost(response_data)

        Renderer.show_assistant_message(content)

      {:error, reason} ->
        Renderer.show_error("Failed to get response: #{inspect(reason)}")

      response ->
        # Handle unexpected response format
        Renderer.show_error("Unexpected response: #{inspect(response)}")
    end

    :continue
  end

  defp get_llm_response(processed_message) do
    session = Session.get_current_session()
    messages = prepare_messages(session, processed_message)
    adapter = get_llm_adapter(session.llm_backend)
    options = build_llm_options(session)

    if adapter.configured?(session.llm_backend) do
      execute_llm_request(adapter, messages, options)
    else
      build_configuration_error(session.llm_backend)
    end
  end

  defp prepare_messages(session, processed_message) do
    base_messages = Session.get_messages_for_llm()
    replace_last_user_message(base_messages, processed_message)
  end

  defp build_llm_options(session) do
    options = [{:provider, session.llm_backend}]
    options = maybe_add_model_option(options, session)
    options = maybe_add_system_prompt_option(options, session)

    # Add context truncation settings
    context_config = Config.get([:context], %{})
    truncation_strategy = Map.get(context_config, "strategy", "smart")

    options =
      [
        truncate_context: true,
        truncation_strategy: String.to_atom(truncation_strategy)
      ] ++ options

    # Add max_tokens if configured
    if max_tokens = Map.get(context_config, "max_tokens") do
      [{:max_tokens, max_tokens} | options]
    else
      options
    end
  end

  defp maybe_add_model_option(options, session) do
    if session.context[:model] do
      [{:model, session.context[:model]} | options]
    else
      options
    end
  end

  defp maybe_add_system_prompt_option(options, session) do
    if session.context[:system_prompt] do
      [{:system_prompt, session.context[:system_prompt]} | options]
    else
      options
    end
  end

  defp execute_llm_request(adapter, messages, options) do
    response = choose_response_method(adapter, messages, options)
    handle_llm_response(response, messages)
  end

  defp choose_response_method(adapter, messages, options) do
    if Config.get([:ui, :streaming]) != false do
      stream_response(adapter, messages, options)
    else
      adapter.chat(messages, options)
    end
  end

  defp handle_llm_response(response, messages) do
    case response do
      {:ok, response_data} ->
        # response_data is the full response map from ExLLM adapter
        content = get_response_content(response_data)
        Session.track_token_usage(messages, content)
        # Return full response data instead of just content
        {:ok, response_data}

      error ->
        error
    end
  end

  # Helper function to extract content from response data
  defp get_response_content(response_data) when is_map(response_data) do
    Map.get(response_data, :content, "")
  end

  defp get_response_content(content) when is_binary(content) do
    content
  end

  defp get_response_content(_), do: ""

  defp build_configuration_error(backend_name) do
    env_var = get_env_var_for_backend(backend_name)

    {:error,
     "LLM backend '#{backend_name}' not configured. Please set your API key in ~/.config/mcp_chat/config.toml or set the #{env_var} environment variable"}
  end

  defp get_env_var_for_backend(backend_name) do
    case backend_name do
      "openai" -> "OPENAI_API_KEY"
      "bedrock" -> "AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
      "gemini" -> "GOOGLE_API_KEY"
      _ -> "ANTHROPIC_API_KEY"
    end
  end

  defp get_llm_adapter(_), do: ExLLMAdapter

  defp stream_response(adapter, messages, options) do
    # Add recovery options if enabled
    options = maybe_add_recovery_options(options)

    case adapter.stream_chat(messages, options) do
      {:ok, stream, recovery_id} ->
        handle_recoverable_stream(stream, recovery_id, options)

      {:ok, stream} ->
        handle_simple_stream(stream, options)

      error ->
        error
    end
  end

  defp handle_recoverable_stream(stream, recovery_id, options) do
    # Store recovery ID in session for potential resume
    Session.set_last_recovery_id(recovery_id)
    Logger.debug("Stream started with recovery ID: #{recovery_id}")

    result = execute_stream(stream, options)
    handle_stream_result(result, recovery_id)
  end

  defp handle_simple_stream(stream, options) do
    # No recovery ID - proceed normally
    Logger.debug("Stream started without recovery support")
    execute_stream(stream, options)
  end

  defp execute_stream(stream, options) do
    if Config.get(:streaming, :enhanced, true) do
      stream_with_enhanced_consumer(stream, options)
    else
      # Fallback to simple streaming
      stream_simple(stream)
    end
  end

  defp handle_stream_result(result, recovery_id) do
    case result do
      {:ok, response} ->
        Session.clear_last_recovery_id()
        Logger.debug("Stream completed successfully, cleared recovery ID")
        {:ok, response}

      {:error, :interrupted} ->
        # Keep recovery ID for resume
        Logger.info("Stream interrupted, recovery ID preserved: #{recovery_id}")
        show_resume_hint()
        result

      {:error, reason} = error ->
        handle_stream_error(reason, recovery_id)
        error
    end
  end

  defp handle_stream_error(reason, recovery_id) do
    if recoverable_error?(reason) do
      Logger.info("Recoverable error occurred, recovery ID preserved: #{recovery_id}")
      show_resume_hint()
    else
      Session.clear_last_recovery_id()
      Logger.error("Non-recoverable error: #{inspect(reason)}")
    end
  end

  defp show_resume_hint do
    Renderer.show_info("\n💡 Use /resume to continue the interrupted response")
  end

  defp recoverable_error?(reason) do
    case reason do
      :timeout -> true
      :disconnected -> true
      {:network_error, _} -> true
      {:stream_error, _} -> true
      _ -> false
    end
  end

  defp maybe_add_recovery_options(options) do
    if Config.get([:streaming, :enable_recovery], true) do
      build_recovery_options(options)
    else
      options
    end
  end

  defp build_recovery_options(options) do
    recovery_opts = build_base_recovery_opts()
    recovery_opts = maybe_add_recovery_id(recovery_opts, options)
    recovery_opts = maybe_add_metrics_tracking(recovery_opts)

    Keyword.merge(options, recovery_opts)
  end

  defp build_base_recovery_opts do
    [
      enable_recovery: true,
      recovery_strategy: Config.get([:streaming, :recovery_strategy], :paragraph),
      recovery_storage: Config.get([:streaming, :recovery_storage], :memory),
      # 1 hour default
      recovery_ttl: Config.get([:streaming, :recovery_ttl], 3_600),
      # Save every 10 chunks
      recovery_checkpoint_interval: Config.get([:streaming, :recovery_checkpoint_interval], 10)
    ]
  end

  defp maybe_add_recovery_id(recovery_opts, options) do
    if Keyword.has_key?(options, :recovery_id) do
      recovery_opts
    else
      [{:recovery_id, generate_recovery_id()} | recovery_opts]
    end
  end

  defp maybe_add_metrics_tracking(recovery_opts) do
    if Config.get([:streaming, :track_metrics], false) do
      metrics_callback = create_metrics_callback()
      [{:track_metrics, true}, {:on_metrics, metrics_callback} | recovery_opts]
    else
      recovery_opts
    end
  end

  defp create_metrics_callback do
    fn metrics ->
      if Config.get([:debug, :log_streaming_metrics], false) do
        Logger.debug("ExLLM Streaming metrics: #{inspect(metrics)}")
      end
    end
  end

  defp generate_recovery_id do
    timestamp = :os.system_time(:millisecond)
    random = :rand.uniform(9_999)
    "mcp_chat_#{timestamp}_#{random}"
  end

  defp stream_with_enhanced_consumer(stream, options) do
    # Use ExLLM's enhanced streaming infrastructure directly
    # Since ExLLM.stream_chat now returns an enhanced stream with built-in
    # flow control, batching, and backpressure handling, we can consume it directly

    response =
      stream
      |> Enum.reduce("", fn chunk, acc ->
        # Display chunk immediately with ExLLM's optimized batching
        Renderer.show_stream_chunk(chunk.delta)
        acc <> chunk.delta
      end)

    Renderer.end_stream()
    {:ok, response}
  rescue
    e ->
      Logger.error("ExLLM enhanced streaming failed: #{Exception.message(e)}")
      # Fallback to simple streaming
      stream_simple(stream)
  end

  defp stream_simple(stream) do
    response =
      stream
      |> Enum.reduce("", fn chunk, acc ->
        Renderer.show_stream_chunk(chunk.delta)
        acc <> chunk.delta
      end)

    Renderer.end_stream()
    {:ok, response}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp handle_resumed_stream(stream) do
    # Process the resumed stream with recovery support
    result =
      if Config.get(:streaming, :enhanced, true) do
        stream_with_enhanced_consumer(stream, [])
      else
        stream_simple(stream)
      end

    case result do
      {:ok, continuation} ->
        handle_continuation_success(continuation)

      {:error, reason} ->
        Renderer.show_error("Failed to process resumed stream: #{inspect(reason)}")
    end
  end

  defp handle_continuation_success(continuation) do
    case Session.get_last_recovery_id() do
      nil ->
        # Just add the continuation as a new message
        Session.add_message("assistant", continuation)
        Renderer.show_assistant_message(continuation)

      recovery_id ->
        handle_recovery_continuation(recovery_id, continuation)
    end
  end

  defp handle_recovery_continuation(recovery_id, continuation) do
    case ExLLMAdapter.get_partial_response(recovery_id) do
      {:ok, chunks} ->
        partial_content = Enum.map_join(chunks, "", & &1.content)
        recovery_strategy = Config.get([:streaming, :recovery_strategy], :paragraph)

        full_response =
          case recovery_strategy do
            :exact ->
              # Continue from exact cutoff
              partial_content <> continuation

            :paragraph ->
              # Find last complete paragraph and continue from there
              last_paragraph_end = find_last_paragraph_end(partial_content)
              String.slice(partial_content, 0, last_paragraph_end) <> "\n\n" <> continuation

            :summarize ->
              # Include a summary marker
              partial_content <> "\n\n[Response resumed after interruption]\n\n" <> continuation

            _ ->
              partial_content <> continuation
          end

        Session.add_message("assistant", full_response)
        Renderer.show_assistant_message(full_response)
        Session.clear_last_recovery_id()
        Logger.info("Successfully resumed response with #{recovery_strategy} strategy")

      {:error, reason} ->
        # Fallback to just the continuation
        Logger.warn("Could not retrieve partial response: #{inspect(reason)}")
        Session.add_message("assistant", continuation)
        Renderer.show_assistant_message(continuation)
        Session.clear_last_recovery_id()
    end
  end

  defp find_last_paragraph_end(text) do
    # Find the last double newline or end of a sentence before that
    case Regex.scan(~r/\n\n|[.!?]\s*$/m, text, return: :index) do
      [] ->
        String.length(text)

      matches ->
        {last_pos, last_len} = List.last(matches) |> List.first()
        last_pos + last_len
    end
  end

  # @ Symbol Processing Functions

  defp process_at_symbols(message) do
    require Logger

    # Check if message contains @ symbols
    if String.contains?(message, "@") do
      Logger.debug("Processing @ symbols in message")

      # Get resolution options from config
      options = [
        max_file_size: Config.get([:context, :max_file_size], 1_024 * 1_024),
        http_timeout: Config.get([:context, :http_timeout], 10_000),
        mcp_timeout: Config.get([:context, :mcp_timeout], 30_000),
        validate_content: Config.get([:context, :validate_content], true)
      ]

      # Resolve @ symbols
      case AtSymbolResolver.resolve_all(message, options) do
        %{resolved_text: resolved_text} = metadata ->
          {resolved_text, metadata}

        error ->
          Logger.error("Failed to process @ symbols: #{inspect(error)}")
          {message, %{resolved_text: message, results: [], total_tokens: 0, errors: []}}
      end
    else
      # No @ symbols to process
      {message, %{resolved_text: message, results: [], total_tokens: 0, errors: []}}
    end
  end

  defp display_at_symbol_info(metadata) do
    if length(metadata.results) > 0 do
      display_reference_summary(metadata)
      display_each_reference(metadata.results)
      display_token_estimate(metadata)
      display_reference_errors(metadata)
      IO.puts("")
    end
  end

  defp display_reference_summary(metadata) do
    Renderer.show_info("📄 Included content from #{length(metadata.results)} @ references:")
  end

  defp display_each_reference(results) do
    Enum.each(results, &display_single_reference/1)
  end

  defp display_single_reference(result) do
    ref = result.reference
    icon = get_reference_icon(ref.type)

    case result.error do
      nil ->
        size_info = format_reference_size_info(result.metadata)
        Renderer.show_info("  #{icon} #{ref.type}:#{ref.identifier}#{size_info}")

      error ->
        Renderer.show_error("  #{icon} #{ref.type}:#{ref.identifier} - #{error}")
    end
  end

  defp format_reference_size_info(metadata) do
    case metadata do
      %{size: size} -> " (#{format_bytes(size)})"
      %{status: 200} -> " (web content)"
      _ -> ""
    end
  end

  defp display_token_estimate(metadata) do
    if metadata.total_tokens > 0 do
      Renderer.show_info("📊 Estimated tokens added: #{metadata.total_tokens}")
    end
  end

  defp display_reference_errors(metadata) do
    if length(metadata.errors) > 0 do
      Renderer.show_error("⚠️  #{length(metadata.errors)} @ references failed to resolve")
    end
  end

  defp get_reference_icon(:file), do: "📄"
  defp get_reference_icon(:url), do: "🌐"
  defp get_reference_icon(:resource), do: "📚"
  defp get_reference_icon(:prompt), do: "💬"
  defp get_reference_icon(:tool), do: "🔧"
  defp get_reference_icon(_), do: "❓"

  defp format_bytes(bytes) when bytes < 1_024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_024 * 1_024, do: "#{Float.round(bytes / 1_024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1_024 * 1_024), 1)} MB"

  defp replace_last_user_message(messages, processed_content) do
    # Find the last user message and replace its content
    messages
    |> Enum.reverse()
    |> case do
      [%{"role" => "user"} = last_msg | rest] ->
        updated_msg = %{last_msg | "content" => processed_content}
        [updated_msg | rest] |> Enum.reverse()

      other ->
        # No user message found, return as-is
        other
    end
  end

  defp generate_session_id do
    # Generate a unique session ID using timestamp and random bytes
    timestamp = System.system_time(:millisecond)
    random = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    "session_#{timestamp}_#{random}"
  end
end
