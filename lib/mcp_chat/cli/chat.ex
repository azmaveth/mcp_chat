defmodule MCPChat.CLI.Chat do
  @moduledoc """
  Main chat interface for the MCP client.
  """

  alias MCPChat.{Session, Config}
  alias MCPChat.CLI.{Commands, Renderer}
  # alias MCPChat.LLM

  def start() do
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

  defp chat_loop() do
    # Print newline before prompt for spacing
    IO.write("\n")
    prompt = Renderer.format_prompt()

    case MCPChat.CLI.ExReadlineAdapter.read_line(prompt) do
      :eof ->
        Renderer.show_goodbye()
        :ok

      input ->
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

      _ ->
        :continue
    end
  end

  defp process_input(message) do
    # Add user message to session
    Session.add_message("user", message)

    # Show thinking indicator
    Renderer.show_thinking()

    # Get LLM response
    case get_llm_response(message) do
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

  defp get_llm_response(_message) do
    session = Session.get_current_session()
    # Get messages with context management
    messages = Session.get_messages_for_llm()

    # Get the appropriate LLM adapter
    adapter = get_llm_adapter(session.llm_backend)

    # Build options from session context
    options = [{:provider, session.llm_backend}]
    options = if session.context[:model], do: [{:model, session.context[:model]} | options], else: options

    options =
      if session.context[:system_prompt],
        do: [{:system_prompt, session.context[:system_prompt]} | options],
        else: options

    # Check if adapter is configured
    if adapter.configured?(session.llm_backend) do
      # Check if streaming is enabled
      response =
        if Config.get([:ui, :streaming]) != false do
          stream_response(adapter, messages, options)
        else
          adapter.chat(messages, options)
        end

      # Track token usage if we got a successful response
      case response do
        {:ok, content} ->
          Session.track_token_usage(messages, content)
          {:ok, content}

        error ->
          error
      end
    else
      backend_name = session.llm_backend

      env_var =
        case backend_name do
          "openai" -> "OPENAI_API_KEY"
          "bedrock" -> "AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
          "gemini" -> "GOOGLE_API_KEY"
          _ -> "ANTHROPIC_API_KEY"
        end

      {:error,
       "LLM backend '#{backend_name}' not configured. Please set your API key in ~/.config/mcp_chat/config.toml or set the #{env_var} environment variable"}
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

  defp stream_with_enhanced_consumer(stream, options) do
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
        # Get the partial response that was already shown
        case Session.get_last_recovery_id() do
          nil ->
            # Just add the continuation as a new message
            Session.add_message("assistant", continuation)

          recovery_id ->
            # Get the partial content and combine
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

      {:error, reason} ->
        Renderer.show_error("Failed to process resumed stream: #{inspect(reason)}")
    end
  end
end
