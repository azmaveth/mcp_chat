defmodule MCPChat.CLI.Chat do
  @moduledoc """
  Main chat interface for the MCP client.
  """

  require Logger
  alias MCPChat.CLI.{Commands, Renderer}
  alias MCPChat.Context.AtSymbolResolver
  alias MCPChat.{Session, Config}

  # alias MCPChat.LLM

  def start do
    start([])
  end

  def start(_opts) do
    Renderer.clear_screen()
    Renderer.show_welcome()

    # Set up command completion
    MCPChat.CLI.ExReadlineAdapter.set_completion_fn(&Commands.get_completions/1)

    # Start the chat loop
    chat_loop()
  end

  defp chat_loop do
    # Print newline before prompt for spacing
    IO.write("\n")
    prompt = Renderer.format_prompt()

    case MCPChat.CLI.ExReadlineAdapter.read_line(prompt) do
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
      {:ok, response} ->
        Session.add_message("assistant", response)
        Renderer.show_assistant_message(response)

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
    maybe_add_system_prompt_option(options, session)
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
      {:ok, content} ->
        Session.track_token_usage(messages, content)
        {:ok, content}

      error ->
        error
    end
  end

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

  defp get_llm_adapter(_), do: MCPChat.LLM.ExLLMAdapter

  defp stream_response(adapter, messages, options) do
    # Add recovery options if enabled
    options = maybe_add_recovery_options(options)

    case adapter.stream_chat(messages, options) do
      {:ok, stream, recovery_id} ->
        # Store recovery ID in session for potential resume
        Session.set_last_recovery_id(recovery_id)

        # Use enhanced streaming if enabled
        result =
          if Config.get(:streaming, :enhanced, true) do
            stream_with_enhanced_consumer(stream, options)
          else
            # Fallback to simple streaming
            stream_simple(stream)
          end

        # Clear recovery ID on successful completion
        case result do
          {:ok, _response} ->
            Session.clear_last_recovery_id()
            result

          error ->
            error
        end

      {:ok, stream} ->
        # No recovery ID - proceed normally
        if Config.get(:streaming, :enhanced, true) do
          stream_with_enhanced_consumer(stream, options)
        else
          # Fallback to simple streaming
          stream_simple(stream)
        end

      error ->
        error
    end
  end

  defp maybe_add_recovery_options(options) do
    if Config.get([:streaming, :enable_recovery], true) do
      Keyword.merge(options,
        enable_recovery: true,
        recovery_strategy: Config.get([:streaming, :recovery_strategy], :paragraph)
      )
    else
      options
    end
  end

  defp stream_with_enhanced_consumer(stream, _options) do
    alias MCPChat.Streaming.EnhancedConsumer

    # Get streaming configuration
    config = [
      buffer_capacity: Config.get(:streaming, :buffer_capacity, 100),
      write_interval: Config.get(:streaming, :write_interval, 25),
      min_batch_size: Config.get(:streaming, :min_batch_size, 3),
      max_batch_size: Config.get(:streaming, :max_batch_size, 10)
    ]

    # Process with enhanced consumer
    case EnhancedConsumer.process_with_manager(stream, config) do
      {:ok, response, metrics} ->
        # Log metrics if debug mode
        if Config.get(:debug, :log_streaming_metrics, false) do
          Logger.debug("Streaming metrics: #{inspect(metrics)}")
        end

        {:ok, response}

      {:error, reason} ->
        Logger.error("Enhanced streaming failed: #{inspect(reason)}")
        # Fallback to simple streaming
        stream_simple(stream)
    end
  end

  defp stream_simple(stream) do
    try do
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
  end

  defp handle_resumed_stream(stream) do
    # Process the resumed stream
    case stream_simple(stream) do
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

      recovery_id ->
        handle_recovery_continuation(recovery_id, continuation)
    end
  end

  defp handle_recovery_continuation(recovery_id, continuation) do
    case MCPChat.LLM.ExLLMAdapter.get_partial_response(recovery_id) do
      {:ok, chunks} ->
        partial = chunks |> Enum.map_join(& &1.content, "")
        full_response = partial <> continuation
        Session.add_message("assistant", full_response)

      _ ->
        # Fallback to just the continuation
        Session.add_message("assistant", continuation)
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
end
