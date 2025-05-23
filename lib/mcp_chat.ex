defmodule MCPChat do
  @moduledoc """
  MCP Chat Client - A CLI chat interface with MCP server support.
  """

  @doc """
  Start the chat client CLI.
  """
  def main(args \\ []) do
    case parse_args(args) do
      {:ok, opts} ->
        start_app(opts)

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end

  defp parse_args(args) do
    case OptionParser.parse(args,
           switches: [
             config: :string,
             backend: :string,
             help: :boolean
           ],
           aliases: [
             c: :config,
             b: :backend,
             h: :help
           ]
         ) do
      {opts, [], []} ->
        if opts[:help] do
          show_help()
          System.halt(0)
        else
          {:ok, opts}
        end

      {_, _, invalid} ->
        {:error, "Invalid arguments: #{inspect(invalid)}"}
    end
  end

  defp show_help() do
    IO.puts("""
    MCP Chat Client

    Usage: mcp_chat [options]

    Options:
      -c, --config PATH      Path to configuration file
      -b, --backend NAME     LLM backend to use (anthropic, openai, local)
      -h, --help            Show this help message
    """)
  end

  defp start_app(opts) do
    # Start the application
    {:ok, _} = Application.ensure_all_started(:mcp_chat)

    # Apply CLI options
    if opts[:backend] do
      MCPChat.Session.new_session(opts[:backend])
    end

    # Start the chat interface
    MCPChat.CLI.Chat.start()
  end
end
