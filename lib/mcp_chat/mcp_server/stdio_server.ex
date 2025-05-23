defmodule MCPChat.MCPServer.StdioServer do
  @moduledoc """
  MCP server that communicates via stdio (stdin/stdout).
  """
  use GenServer

  alias MCPChat.MCPServer.Handler
  # alias MCPChat.MCP.Protocol

  require Logger

  defstruct [:buffer, :state]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start() do
    GenServer.call(__MODULE__, :start)
  end

  def stop() do
    GenServer.call(__MODULE__, :stop)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      buffer: "",
      state: :ready
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:start, _from, state) do
    # Start reading from stdin
    Task.start_link(&read_loop/0)
    Logger.info("MCP stdio server started")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:stop, _from, state) do
    Logger.info("MCP stdio server stopping")
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info({:stdin, data}, state) do
    # Append data to buffer
    buffer = state.buffer <> data

    # Process complete lines
    {lines, remaining} = split_lines(buffer)

    # Process each complete JSON-RPC message
    new_state = Enum.reduce(lines, state.state, &process_request(&1, &2))

    {:noreply, %{state | buffer: remaining, state: new_state}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private functions

  defp read_loop() do
    case IO.gets("") do
      :eof ->
        Logger.info("EOF received, stopping server")
        GenServer.stop(__MODULE__)

      {:error, reason} ->
        Logger.error("Error reading stdin: #{inspect(reason)}")
        GenServer.stop(__MODULE__)

      data ->
        send(__MODULE__, {:stdin, data})
        read_loop()
    end
  end

  defp split_lines(data) do
    lines = String.split(data, "\n")

    case List.last(lines) do
      "" ->
        # Data ended with newline, all lines are complete
        {Enum.drop(lines, -1), ""}

      incomplete ->
        # Last line is incomplete
        {Enum.drop(lines, -1), incomplete}
    end
  end

  defp process_request("", state), do: state

  defp process_request(line, state) do
    case Jason.decode(line) do
      {:ok, %{"jsonrpc" => "2.0", "method" => method, "params" => params, "id" => id}} ->
        # Request with ID
        handle_request(method, params, id, state)

      {:ok, %{"jsonrpc" => "2.0", "method" => method, "params" => params}} ->
        # Notification (no ID)
        handle_notification(method, params, state)

      {:ok, %{"jsonrpc" => "2.0", "method" => method, "id" => id}} ->
        # Request with no params
        handle_request(method, %{}, id, state)

      {:error, reason} ->
        Logger.error("Failed to parse JSON-RPC request: #{inspect(reason)}")
        Logger.error("Raw line: #{line}")
        state
    end
  end

  defp handle_request(method, params, id, state) do
    case Handler.handle_request(method, params, state) do
      {:ok, result, new_state} ->
        response = %{
          jsonrpc: "2.0",
          result: result,
          id: id
        }

        send_response(response)
        new_state

      {:error, error, new_state} ->
        response = %{
          jsonrpc: "2.0",
          error: error,
          id: id
        }

        send_response(response)
        new_state
    end
  end

  defp handle_notification(method, params, state) do
    case Handler.handle_notification(method, params, state) do
      {:ok, new_state} -> new_state
      _ -> state
    end
  end

  defp send_response(response) do
    json = Jason.encode!(response)
    IO.puts(json)
  end
end
