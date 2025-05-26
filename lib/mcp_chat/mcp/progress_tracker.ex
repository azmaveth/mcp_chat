defmodule MCPChat.MCP.ProgressTracker do
  @moduledoc """
  Tracks progress of long-running MCP operations.
  Provides UI for monitoring active operations and their progress.
  """
  use GenServer
  require Logger

  defstruct operations: %{}, token_counter: 0

  # Operation structure
  defmodule Operation do
    defstruct [
      :token,
      :server,
      :tool,
      :started_at,
      :updated_at,
      :progress,
      :total,
      :status
    ]
  end

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts tracking a new operation.
  Returns a progress token.
  """
  def start_operation(server, tool, total \\ nil) do
    GenServer.call(__MODULE__, {:start_operation, server, tool, total})
  end

  @doc """
  Updates progress for an operation.
  """
  def update_progress(token, progress, total \\ nil) do
    GenServer.cast(__MODULE__, {:update_progress, token, progress, total})
  end

  @doc """
  Marks an operation as completed.
  """
  def complete_operation(token) do
    GenServer.cast(__MODULE__, {:complete_operation, token})
  end

  @doc """
  Marks an operation as failed.
  """
  def fail_operation(token, reason) do
    GenServer.cast(__MODULE__, {:fail_operation, token, reason})
  end

  @doc """
  Gets all active operations.
  """
  def list_operations() do
    GenServer.call(__MODULE__, :list_operations)
  end

  @doc """
  Gets a specific operation by token.
  """
  def get_operation(token) do
    GenServer.call(__MODULE__, {:get_operation, token})
  end

  @doc """
  Generates a unique progress token.
  """
  def generate_token() do
    GenServer.call(__MODULE__, :generate_token)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Clean up old operations periodically
    # 1 minute
    Process.send_after(self(), :cleanup, 60_000)

    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:start_operation, server, tool, total}, _from, state) do
    token = "op-#{state.token_counter + 1}-#{:erlang.unique_integer([:positive])}"

    operation = %Operation{
      token: token,
      server: server,
      tool: tool,
      started_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      progress: 0,
      total: total,
      status: :running
    }

    new_operations = Map.put(state.operations, token, operation)
    new_state = %{state | operations: new_operations, token_counter: state.token_counter + 1}

    Logger.info("Started tracking operation: #{token} for #{server}/#{tool}")

    {:reply, {:ok, token}, new_state}
  end

  def handle_call(:list_operations, _from, state) do
    active_ops =
      state.operations
      |> Map.values()
      |> Enum.filter(&(&1.status == :running))
      |> Enum.sort_by(& &1.started_at, {:desc, DateTime})

    {:reply, active_ops, state}
  end

  def handle_call({:get_operation, token}, _from, state) do
    operation = Map.get(state.operations, token)
    {:reply, operation, state}
  end

  def handle_call(:generate_token, _from, state) do
    token = "op-#{state.token_counter + 1}-#{:erlang.unique_integer([:positive])}"
    new_state = %{state | token_counter: state.token_counter + 1}
    {:reply, token, new_state}
  end

  @impl true
  def handle_cast({:update_progress, token, progress, total}, state) do
    case Map.get(state.operations, token) do
      nil ->
        {:noreply, state}

      operation ->
        updated_op = %{operation | progress: progress, total: total || operation.total, updated_at: DateTime.utc_now()}

        # Check if completed
        updated_op =
          if updated_op.total && updated_op.progress >= updated_op.total do
            %{updated_op | status: :completed}
          else
            updated_op
          end

        new_operations = Map.put(state.operations, token, updated_op)
        {:noreply, %{state | operations: new_operations}}
    end
  end

  def handle_cast({:complete_operation, token}, state) do
    case Map.get(state.operations, token) do
      nil ->
        {:noreply, state}

      operation ->
        updated_op = %{operation | status: :completed, updated_at: DateTime.utc_now()}

        new_operations = Map.put(state.operations, token, updated_op)
        {:noreply, %{state | operations: new_operations}}
    end
  end

  def handle_cast({:fail_operation, token, _reason}, state) do
    case Map.get(state.operations, token) do
      nil ->
        {:noreply, state}

      operation ->
        updated_op = %{operation | status: :failed, updated_at: DateTime.utc_now()}

        new_operations = Map.put(state.operations, token, updated_op)
        {:noreply, %{state | operations: new_operations}}
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Remove completed/failed operations older than 5 minutes
    cutoff = DateTime.add(DateTime.utc_now(), -300, :second)

    new_operations =
      state.operations
      |> Enum.filter(fn {_token, op} ->
        op.status == :running ||
          DateTime.compare(op.updated_at, cutoff) == :gt
      end)
      |> Enum.into(%{})

    # Schedule next cleanup
    Process.send_after(self(), :cleanup, 60_000)

    {:noreply, %{state | operations: new_operations}}
  end

  def handle_info({:progress_update, _server, token, progress, total}, state) do
    # Handle progress updates from notification handler
    handle_cast({:update_progress, token, progress, total}, state)
  end
end
