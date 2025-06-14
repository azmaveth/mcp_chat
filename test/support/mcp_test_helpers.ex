defmodule MCPChat.MCPTestHelpers do
  @moduledoc """
  Helper functions for testing MCP integration.

  Provides utilities for starting MCP servers as external processes
  and connecting clients to them, following the proper MCP architecture.
  """

  require Logger

  @doc """
  Starts an MCP server as an external process and connects a client to it.

  This follows the correct MCP architecture where:
  1. Servers are external processes (OS processes)
  2. Clients connect to servers via transports (stdio, SSE, etc.)
  3. Communication happens through the MCP protocol, not direct function calls

  ## Options
  - `:transport` - Transport type (:stdio or :sse), defaults to :stdio
  - `:timeout` - Connection timeout in ms, defaults to 5_000

  ## Example

      config = %{
        "command" => "elixir",
        "args" => ["test/support/demo_time_server.exs"],
        "env" => %{}
      }

      MCPTestHelpers.with_mcp_server("test-server", config, fn client_name ->
        {:ok, tools} = MCPChat.MCP.ServerManager.get_tools(client_name)
        assert length(tools) > 0
      end)
  """
  def with_mcp_server(name, config, opts \\ [], fun) do
    # Start the server process
    server_result = start_server_process(config)

    case server_result do
      {:ok, server_port} ->
        # Give server time to initialize
        Process.sleep(500)

        # Connect a client to the server
        client_config =
          Map.merge(config, %{
            "name" => name,
            "transport" => Keyword.get(opts, :transport, :stdio)
          })

        # Start client connection through ServerManager
        {:ok, _client} = MCPChat.MCP.ServerManager.start_server(client_config)

        # Wait for client to connect and initialize
        timeout = Keyword.get(opts, :timeout, 5_000)
        wait_for_client_ready(name, timeout)

        try do
          # Execute the test function
          fun.(name)
        after
          # Cleanup
          stop_mcp_server(name)
          if is_port(server_port), do: Port.close(server_port)
        end

      {:error, reason} ->
        raise "Failed to start MCP server: #{inspect(reason)}"
    end
  end

  @doc """
  Starts an MCP server process using the command from config.
  Returns {:ok, port} or {:error, reason}.
  """
  def start_server_process(config) do
    command = config["command"]
    args = config["args"] || []
    env = config["env"] || %{}

    # Convert env map to list of {"KEY", "VALUE"} tuples
    env_list = Enum.map(env, fn {k, v} -> {to_string(k), to_string(v)} end)

    try do
      port =
        Port.open({:spawn_executable, to_charlist(command)}, [
          :binary,
          :exit_status,
          args: Enum.map(args, &to_charlist/1),
          env: env_list
        ])

      {:ok, port}
    rescue
      e -> {:error, e}
    end
  end

  @doc """
  Stops an MCP server by name through the ServerManager.
  """
  def stop_mcp_server(name) do
    MCPChat.MCP.ServerManager.stop_server(name)
  end

  @doc """
  Waits for a client to be ready by checking if it can list tools.
  """
  def wait_for_client_ready(name, timeout \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    wait_until_ready(name, deadline)
  end

  defp wait_until_ready(name, deadline) do
    case MCPChat.MCP.ServerManager.get_tools(name) do
      {:ok, _tools} ->
        :ok

      {:error, _reason} ->
        now = System.monotonic_time(:millisecond)

        if now < deadline do
          Process.sleep(100)
          wait_until_ready(name, deadline)
        else
          raise "Timeout waiting for MCP client #{name} to be ready"
        end
    end
  end

  @doc """
  Creates an MCP server using BEAM transport for in-process testing.
  This is useful for tests that don't need to test the stdio protocol.

  ## Example

      MCPTestHelpers.with_beam_mcp_server("test-server", TestHandler, fn client_name ->
        {:ok, result} = MCPChat.MCP.ServerManager.call_tool(
          client_name,
          "test_tool",
          %{}
        )
      end)
  """
  def with_beam_mcp_server(name, handler_module, fun) do
    # Start server with BEAM transport
    {:ok, server} =
      ExMCP.Server.start_link(
        transport: :beam,
        handler: handler_module,
        name: {:local, :"#{name}_server"}
      )

    # Connect client with BEAM transport
    client_config = %{
      "name" => name,
      "transport" => :beam,
      "server_name" => :"#{name}_server"
    }

    {:ok, _client} = MCPChat.MCP.ServerManager.start_server(client_config)

    # Wait for initialization
    wait_for_client_ready(name)

    try do
      fun.(name)
    after
      MCPChat.MCP.ServerManager.stop_server(name)
      GenServer.stop(server)
    end
  end

  @doc """
  Creates a simple mock MCP server handler for testing.

  ## Example

      handler = MCPTestHelpers.create_mock_handler(%{
        tools: [
          %{
            "name" => "test_tool",
            "description" => "A test tool",
            "inputSchema" => %{"type" => "object"}
          }
        ],
        tool_results: %{
          "test_tool" => fn _args -> %{"result" => "success"} end
        }
      })

      MCPTestHelpers.with_beam_mcp_server("test", handler, fn name ->
        # Test code
      end)
  """
  def create_mock_handler(config \\ %{}) do
    handler_config = build_handler_config(config)

    # Return a function that creates the handler with config
    fn ->
      {:ok, _pid} = GenServer.start_link(MCPChat.MCPTestHelpers.MCPTestHandler, handler_config)
    end
  end

  defp build_handler_config(config) do
    %{
      tools: Map.get(config, :tools, []),
      tool_results: Map.get(config, :tool_results, %{}),
      resources: Map.get(config, :resources, []),
      prompts: Map.get(config, :prompts, [])
    }
  end
end

# Define the test handler module at the module level
defmodule MCPChat.MCPTestHelpers.MCPTestHandler do
  @moduledoc false
  use ExMCP.Server.Handler

  def init(config), do: {:ok, config}

  @impl true
  def handle_initialize(_params, state) do
    {:ok,
     %{
       "serverInfo" => %{
         "name" => "test-server",
         "version" => "1.0.0"
       },
       "capabilities" => %{
         "tools" => %{},
         "resources" => %{},
         "prompts" => %{}
       }
     }, state}
  end

  @impl true
  def handle_list_tools(_params, state) do
    {:ok, %{"tools" => state.tools}, state}
  end

  @impl true
  def handle_call_tool(name, arguments, state) do
    case Map.get(state.tool_results, name) do
      nil ->
        {:error,
         %{
           "code" => -32_601,
           "message" => "Tool not found: #{name}"
         }, state}

      fun when is_function(fun) ->
        result = fun.(arguments)
        {:ok, %{"content" => [result]}, state}

      result ->
        {:ok, %{"content" => [result]}, state}
    end
  end

  @impl true
  def handle_list_resources(_params, state) do
    {:ok, %{"resources" => Map.get(state, :resources, [])}, state}
  end

  @impl true
  def handle_list_prompts(_params, state) do
    {:ok, %{"prompts" => Map.get(state, :prompts, [])}, state}
  end
end
