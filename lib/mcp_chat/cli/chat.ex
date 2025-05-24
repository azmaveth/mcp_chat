defmodule MCPChat.CLI.Chat do
  @moduledoc """
  Main chat interface for the MCP client.
  """

  alias MCPChat.{Session, Config}
  alias MCPChat.CLI.{Commands, Renderer}
  # alias MCPChat.LLM

  def start() do
    Renderer.clear_screen()
    Renderer.show_welcome()

    # Set up command completion
    MCPChat.CLI.LineEditor.set_completion_fn(&Commands.get_completions/1)

    # Start the chat loop
    chat_loop()
  end

  defp chat_loop() do
    # Print newline before prompt for spacing
    IO.write("\n")
    prompt = Renderer.format_prompt()

    case MCPChat.CLI.LineEditor.read_line(prompt) do
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
    options = []
    options = if session.context[:model], do: [{:model, session.context[:model]} | options], else: options

    options =
      if session.context[:system_prompt],
        do: [{:system_prompt, session.context[:system_prompt]} | options],
        else: options

    # Check if adapter is configured
    if not adapter.configured?() do
      backend_name = session.llm_backend

      env_var =
        case backend_name do
          "openai" -> "OPENAI_API_KEY"
          _ -> "ANTHROPIC_API_KEY"
        end

      {:error,
       "LLM backend '#{backend_name}' not configured. Please set your API key in ~/.config/mcp_chat/config.toml or set the #{env_var} environment variable"}
    else
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
    end
  end

  defp get_llm_adapter("anthropic"), do: MCPChat.LLM.Anthropic
  defp get_llm_adapter("openai"), do: MCPChat.LLM.OpenAI
  defp get_llm_adapter("local"), do: MCPChat.LLM.Local
  defp get_llm_adapter("ollama"), do: MCPChat.LLM.Ollama
  defp get_llm_adapter(_), do: MCPChat.LLM.Anthropic

  defp stream_response(adapter, messages, options) do
    case adapter.stream_chat(messages, options) do
      {:ok, stream} ->
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

      error ->
        error
    end
  end
end
