defmodule MCPChat.MCP.Transport.ManagedStdio do
  @moduledoc """
  ExMCP.Transport implementation that works with StdioProcessManager.

  This transport connects to an MCP server running as a managed OS process,
  handling the stdio communication through the process manager.
  """

  @behaviour ExMCP.Transport

  require Logger

  # The transport state no longer needs a buffer; it's managed in the receiver process.
  defstruct [:process_manager, :receiver_pid]

  @impl ExMCP.Transport
  def connect(opts) do
    process_manager = Keyword.fetch!(opts, :process_manager)

    # The receiver process is spawned and linked. It manages its own state
    # and no longer needs the parent PID for sending messages.
    receiver_pid = spawn_link(__MODULE__, :receiver_server_loop, [process_manager])

    # Register the receiver to get {:stdio_data, ...} messages.
    :ok = MCPChat.MCP.StdioProcessManager.set_client(process_manager, receiver_pid)

    state = %__MODULE__{
      process_manager: process_manager,
      receiver_pid: receiver_pid
    }

    {:ok, state}
  end

  @impl ExMCP.Transport
  def send_message(message, state) do
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
    # Request a message from the receiver server process and wait for a reply.
    ref = make_ref()
    send(state.receiver_pid, {:get_message, {self(), ref}})

    receive do
      {^ref, reply} ->
        case reply do
          {:complete_message, message} ->
            {:ok, message, state}

          {:stdio_exit, status} ->
            {:error, {:process_exit, status}}

          {:stdio_crash, reason} ->
            {:error, {:process_crash, reason}}
        end
    end
  end

  @impl ExMCP.Transport
  def close(state) do
    if state.receiver_pid && Process.alive?(state.receiver_pid) do
      Process.exit(state.receiver_pid, :shutdown)
    end

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

  # The receiver is now a server that queues messages and requests.
  @doc false
  def receiver_server_loop(process_manager) do
    state = %{
      buffer: "",
      messages: :queue.new(),
      requesters: :queue.new()
    }

    do_receiver_loop(process_manager, state)
  end

  defp do_receiver_loop(process_manager, state) do
    # If we have a buffered message and a waiting requester, fulfill the request.
    if !:queue.is_empty(state.messages) && !:queue.is_empty(state.requesters) do
      {{:value, msg}, remaining_messages} = :queue.out(state.messages)
      {{:value, {requester_pid, ref}}, remaining_requesters} = :queue.out(state.requesters)

      send(requester_pid, {ref, msg})

      do_receiver_loop(process_manager, %{
        state
        | messages: remaining_messages,
          requesters: remaining_requesters
      })
    else
      # Otherwise, wait for an incoming event.
      receive do
        {:stdio_data, data} ->
          new_buffer = state.buffer <> data
          {messages, remaining_buffer} = extract_messages(new_buffer)

          new_message_queue =
            Enum.reduce(messages, state.messages, fn msg, q ->
              :queue.in({:complete_message, msg}, q)
            end)

          do_receiver_loop(process_manager, %{
            state
            | buffer: remaining_buffer,
              messages: new_message_queue
          })

        {:get_message, {requester_pid, ref} = requester} ->
          new_requester_queue = :queue.in(requester, state.requesters)
          do_receiver_loop(process_manager, %{state | requesters: new_requester_queue})

        {:stdio_exit, status} ->
          for {pid, ref} <- :queue.to_list(state.requesters), do: send(pid, {ref, {:stdio_exit, status}})

        {:stdio_crash, reason} ->
          for {pid, ref} <- :queue.to_list(state.requesters), do: send(pid, {ref, {:stdio_crash, reason}})
      end
    end
  end

  defp extract_messages(buffer) do
    lines = String.split(buffer, "\n")

    case lines do
      [] ->
        {[], ""}

      [single] ->
        {[], single}

      multiple ->
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
    case Jason.decode(line) do
      {:ok, _} ->
        line

      {:error, reason} ->
        Logger.error("Received invalid JSON from stdio: #{inspect(reason)}, line: #{inspect(line)}")
        nil
    end
  end
end
