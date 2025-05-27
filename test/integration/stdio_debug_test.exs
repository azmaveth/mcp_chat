defmodule MCPChat.StdioDebugTest do
  use ExUnit.Case, async: false

  alias MCPChat.MCP.StdioProcessManager

  @moduletag :debug

  test "debug stdio communication" do
    # Create a minimal echo server for testing
    test_script = Path.join(System.tmp_dir!(), "debug_echo_server.exs")

    File.write!(test_script, """
    # Simple echo server
    defmodule EchoServer do
      def loop() do
        case IO.gets("") do
          :eof -> :ok
          {:error, _} -> :ok
          line ->
            IO.puts("ECHO: " <> String.trim(line))
            loop()
        end
      end
    end

    EchoServer.loop()
    """)

    # Start process manager
    opts = [
      command: "elixir",
      args: [test_script],
      env: []
    ]

    {:ok, manager} = StdioProcessManager.start_link(opts)
    :ok = StdioProcessManager.set_client(manager, self())

    # Start the process
    {:ok, _port} = StdioProcessManager.start_process(manager)

    # Send test data
    :ok = StdioProcessManager.send_data(manager, "Hello, World!\n")

    # Should receive echo
    assert_receive {:stdio_data, data}, 2000
    IO.puts("Received: #{inspect(data)}")

    # Clean up
    StdioProcessManager.stop_process(manager)
    File.rm!(test_script)
  end

  test "test MCP initialization sequence" do
    # Create a minimal MCP server that logs everything
    test_script = Path.join(System.tmp_dir!(), "debug_mcp_server.exs")

    File.write!(test_script, ~S"""
    # Debug MCP server
    defmodule DebugMCPServer do
      def loop(msg_count \\ 1) do
        case IO.gets("") do
          :eof ->
            IO.puts(:stderr, "Received EOF")
            :ok
          {:error, reason} ->
            IO.puts(:stderr, "Error reading: #{inspect(reason)}")
            :ok
          line ->
            IO.puts(:stderr, "Received[#{msg_count}]: #{String.trim(line)}")

            # Try to parse as JSON and respond appropriately
            case Jason.decode(String.trim(line)) do
              {:ok, %{"method" => "initialize", "id" => id}} ->
                response = %{
                  "jsonrpc" => "2.0",
                  "id" => id,
                  "result" => %{
                    "protocolVersion" => "2024-11-05",
                    "capabilities" => %{"tools" => %{}},
                    "serverInfo" => %{"name" => "debug-server", "version" => "1.0.0"}
                  }
                }
                json = Jason.encode!(response)
                IO.puts(:stderr, "Sending: #{json}")
                IO.puts(json)

              {:ok, msg} ->
                IO.puts(:stderr, "Parsed message: #{inspect(msg)}")

              {:error, reason} ->
                IO.puts(:stderr, "Failed to parse JSON: #{inspect(reason)}")
            end

            loop(msg_count + 1)
        end
      end
    end

    # Simple JSON encoding if Jason not available
    if Code.ensure_loaded?(Jason) do
      DebugMCPServer.loop()
    else
      IO.puts(:stderr, "Jason not available, using simple protocol")
      IO.puts(~s({"error":"Jason not available"}))
    end
    """)

    # Start the server directly to see output
    config = %{
      "name" => "debug-mcp-server",
      "command" => "elixir -e 'Code.require_file(\"#{test_script}\")'",
      "env" => %{}
    }

    # Just start the wrapper and see what happens
    {:ok, wrapper} = MCPChat.MCP.ServerWrapper.start_link(config)

    # Give it time to initialize
    Process.sleep(1_000)

    # Try to get status
    status = MCPChat.MCP.ServerWrapper.get_status(wrapper)
    IO.puts("Status: #{inspect(status)}")

    # Clean up
    GenServer.stop(wrapper)
    File.rm!(test_script)
  end
end
