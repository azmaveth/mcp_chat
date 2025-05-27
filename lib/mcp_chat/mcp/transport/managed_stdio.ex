defmodule MCPChat.MCP.Transport.ManagedStdio do
  @moduledoc """
  ExMCP.Transport implementation that works with StdioProcessManager.

  This transport connects to an MCP server running as a managed OS process,
  handling the stdio communication through the process manager.
  """

  @behaviour ExMCP.Transport

  require Logger

  defstruct [:process_manager, :buffer, :receiver_pid]

  @impl ExMCP.Transport
  def connect(opts) do
    process_manager = Keyword.fetch!(opts, :process_manager)

    # Create a receiver process to handle async messages
    receiver_pid = spawn_link(__MODULE__, :receiver_loop, [self(), process_manager])

    # Register the receiver as the client for the process manager
    :ok = MCPChat.MCP.StdioProcessManager.set_client(process_manager, receiver_pid)

    state = %__MODULE__{
      process_manager: process_manager,
      buffer: "",
      receiver_pid: receiver_pid
    }

    {:ok, state}
  end

  @impl ExMCP.Transport
  def send_message(message, state) do
    # Message should already be JSON-encoded, just add newline
    data = message <> "\n"

    case MCPChat.MCP.StdioProcessManager.send_data(state.process_manager, data) do
      :ok ->
        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to send data to stdio process: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl ExMCP.Transport
  def receive_message(state) do
    # Block waiting for a complete message from the receiver process
    receive do
      {:complete_message, message} ->
        {:ok, message, state}

      {:stdio_exit, status} ->
        {:error, {:process_exit, status}}

      {:stdio_crash, reason} ->
        {:error, {:process_crash, reason}}
    end
  end

  @impl ExMCP.Transport
  def close(state) do
    # Stop the receiver process
    if state.receiver_pid && Process.alive?(state.receiver_pid) do
      Process.exit(state.receiver_pid, :shutdown)
    end

    # Stop the managed process
    MCPChat.MCP.StdioProcessManager.stop_process(state.process_manager)
    :ok
  end

  @impl ExMCP.Transport
  def connected?(state) do
    case MCPChat.MCP.StdioProcessManager.get_status(state.process_manager) do
      {:ok, %{running: true}} -> true
      _ -> false
    end
  end

  # Receiver process that handles async messages from StdioProcessManager
  @doc false
  def receiver_loop(parent, process_manager, buffer \\ "") do
    receive do
      {:stdio_data, data} ->
        # Append new data to buffer
        new_buffer = buffer <> data

        # Process complete messages (newline-delimited JSON)
        {messages, remaining_buffer} = extract_messages(new_buffer)

        # Send each complete message to the parent
        Enum.each(messages, fn message ->
          send(parent, {:complete_message, message})
        end)

        receiver_loop(parent, process_manager, remaining_buffer)

      {:stdio_exit, status} ->
        send(parent, {:stdio_exit, status})

      # Exit the receiver loop

      {:stdio_crash, reason} ->
        send(parent, {:stdio_crash, reason})
        # Exit the receiver loop
    end
  end

  defp extract_messages(buffer) do
    lines = String.split(buffer, "\n")

    case lines do
      [] ->
        {[], ""}

      [single] ->
        # No newline found, keep buffering
        {[], single}

      multiple ->
        # Last element might be incomplete
        {complete, [maybe_incomplete]} = Enum.split(multiple, -1)

        messages =
          complete
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(&validate_json/1)
          |> Enum.reject(&is_nil/1)

        {messages, maybe_incomplete}
    end
  end

  defp validate_json(line) do
    # Just validate it's valid JSON, don't decode
    case Jason.decode(line) do
      {:ok, _} ->
        line

      {:error, reason} ->
        Logger.error("Received invalid JSON from stdio: #{inspect(reason)}, line: #{inspect(line)}")
        nil
    end
  end
end
