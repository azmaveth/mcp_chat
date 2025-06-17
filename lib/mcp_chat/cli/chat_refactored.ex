defmodule MCPChat.CLI.ChatRefactored do
  @moduledoc """
  Refactored chat interface that uses the agent architecture through the Gateway API.
  This module sends commands to agents and receives updates via Phoenix.PubSub.
  """

  require Logger
  alias MCPChat.CLI.{ExReadlineAdapter, Commands, Renderer, EventSubscriber}
  alias MCPChat.Context.AtSymbolResolver
  alias MCPChat.{Config, Gateway}

  @doc "Start the refactored chat interface"
  def start(opts \\ []) do
    Renderer.clear_screen()
    Renderer.show_welcome()

    # Create a session through the Gateway
    user_id = Keyword.get(opts, :user_id, "default_user")

    case Gateway.create_session(user_id, opts) do
      {:ok, session_id} ->
        Logger.info("Created session", session_id: session_id)

        # Subscribe to session events
        {:ok, _subscriber_pid} = EventSubscriber.subscribe_to_session(session_id)

        # Set up command completion
        ExReadlineAdapter.set_completion_fn(&Commands.get_completions/1)

        # Start the chat loop
        chat_loop(session_id)

        # Clean up
        EventSubscriber.unsubscribe_from_session(session_id)
        Gateway.destroy_session(session_id)

      {:error, reason} ->
        Renderer.show_error("Failed to create session: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp chat_loop(session_id) do
    # Print newline before prompt for spacing
    IO.write("\n")
    prompt = Renderer.format_prompt()

    case ExReadlineAdapter.read_line(prompt) do
      :eof ->
        Renderer.show_goodbye()
        :ok

      input ->
        input = String.trim(input)

        case process_input(session_id, input) do
          :exit ->
            Renderer.show_goodbye()
            :ok

          :continue ->
            chat_loop(session_id)
        end
    end
  end

  defp process_input(_session_id, ""), do: :continue
  defp process_input(_session_id, "/exit"), do: :exit
  defp process_input(_session_id, "/quit"), do: :exit
  defp process_input(_session_id, "/q"), do: :exit

  defp process_input(session_id, "/" <> command) do
    # Route command through Gateway
    case Gateway.execute_command(session_id, command) do
      {:message, text} ->
        # Command returned a message to send
        process_input(session_id, text)

      {:error, :session_not_found} ->
        Renderer.show_error("Session not found. Exiting.")
        :exit

      {:error, reason} ->
        Renderer.show_error("Command failed: #{inspect(reason)}")
        :continue

      _ ->
        :continue
    end
  end

  defp process_input(session_id, message) do
    # Process @ symbol references if any
    {processed_message, at_metadata} = process_at_symbols(message)

    # Display @ symbol processing results if any
    if at_metadata.total_tokens > 0 do
      display_at_symbol_info(at_metadata)
    end

    # Send message through Gateway
    case Gateway.send_message(session_id, message) do
      :ok ->
        # Set UI mode for streaming
        EventSubscriber.set_ui_mode(session_id, :streaming)

        # Show thinking indicator
        Renderer.show_thinking()

        # Get LLM response through agent architecture
        handle_llm_response(session_id, processed_message)

      {:error, :session_not_found} ->
        Renderer.show_error("Session not found. Exiting.")
        :exit

      {:error, reason} ->
        Renderer.show_error("Failed to send message: #{inspect(reason)}")
        :continue
    end
  end

  defp handle_llm_response(session_id, processed_message) do
    # Get session state to determine LLM backend
    case Gateway.get_session_state(session_id) do
      {:ok, session} ->
        # Execute LLM request through Gateway
        execute_llm_through_gateway(session_id, session, processed_message)

      {:error, reason} ->
        Renderer.show_error("Failed to get session state: #{inspect(reason)}")
    end

    :continue
  end

  defp execute_llm_through_gateway(session_id, session, processed_message) do
    # Prepare LLM execution options
    opts = build_llm_options(session)

    # This is where we'd integrate with the LLM through the agent architecture
    # For now, we'll use the existing LLM infrastructure but route through agents

    # Check if we should use streaming
    if Config.get([:ui, :streaming]) != false do
      handle_streaming_response(session_id, processed_message, opts)
    else
      handle_standard_response(session_id, processed_message, opts)
    end
  end

  defp handle_streaming_response(session_id, processed_message, opts) do
    # For streaming, we need to handle the response asynchronously
    # The actual streaming will be handled by the agent and updates
    # will come through PubSub events

    # Set up a temporary process to collect the streamed response
    parent = self()

    spawn(fn ->
      # Subscribe to completion events
      Phoenix.PubSub.subscribe(MCPChat.PubSub, "session:#{session_id}:llm_response")

      # Collect chunks until we get a completion signal
      response = collect_stream_chunks("")

      # Send the complete response back to the parent
      send(parent, {:llm_response_complete, response})
    end)

    # Wait for the response with a timeout
    receive do
      {:llm_response_complete, response} ->
        # Add to message history through Gateway
        Gateway.send_message(session_id, {:assistant_response, response})
        Renderer.end_stream()
    after
      # 1 minute timeout
      60_000 ->
        Renderer.show_error("Response timeout")
    end
  end

  defp handle_standard_response(session_id, processed_message, opts) do
    # For non-streaming responses, we can wait synchronously
    # This would be implemented as a call to the agent that handles LLM requests

    # For now, show a placeholder
    Renderer.show_info("[Standard response mode - to be implemented through agents]")
  end

  defp collect_stream_chunks(acc) do
    receive do
      {:llm_chunk, chunk} ->
        # Display the chunk
        Renderer.show_stream_chunk(chunk)
        collect_stream_chunks(acc <> chunk)

      :llm_complete ->
        acc
    after
      # 30 second timeout for individual chunks
      30_000 ->
        acc
    end
  end

  defp build_llm_options(session) do
    options = []

    # Add model if specified
    options =
      if session.context[:model] do
        [{:model, session.context[:model]} | options]
      else
        options
      end

    # Add system prompt if specified
    options =
      if session.context[:system_prompt] do
        [{:system_prompt, session.context[:system_prompt]} | options]
      else
        options
      end

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

  # @ Symbol Processing (reused from original)

  defp process_at_symbols(message) do
    if String.contains?(message, "@") do
      Logger.debug("Processing @ symbols in message")

      options = [
        max_file_size: Config.get([:context, :max_file_size], 1_024 * 1_024),
        http_timeout: Config.get([:context, :http_timeout], 10_000),
        mcp_timeout: Config.get([:context, :mcp_timeout], 30_000),
        validate_content: Config.get([:context, :validate_content], true)
      ]

      case AtSymbolResolver.resolve_all(message, options) do
        %{resolved_text: resolved_text} = metadata ->
          {resolved_text, metadata}

        error ->
          Logger.error("Failed to process @ symbols: #{inspect(error)}")
          {message, %{resolved_text: message, results: [], total_tokens: 0, errors: []}}
      end
    else
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
end
