defmodule MCPChat.Memory.StoreSupervisor do
  @moduledoc """
  Dynamic supervisor for MessageStore processes.
  Each session gets its own MessageStore for memory management.
  """

  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a new message store for a session.
  """
  def start_message_store(session_id, opts \\ []) do
    spec = {MCPChat.Memory.MessageStore, Keyword.merge([session_id: session_id], opts)}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Stop a message store for a session.
  """
  def stop_message_store(session_id) do
    store_name = :"message_store_#{session_id}"

    case Process.whereis(store_name) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  @doc """
  List all active message stores.
  """
  def list_stores() do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} -> pid end)
    |> Enum.filter(&is_pid/1)
  end
end
