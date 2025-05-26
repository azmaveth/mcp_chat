defmodule BeamIntegration.AgentServer do
  @moduledoc """
  A GenServer that manages an MCP Chat instance and handles requests from other processes.
  """
  use GenServer
  require Logger
  
  # Client API
  
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  def query(server \\ __MODULE__, prompt, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    GenServer.call(server, {:query, prompt, opts}, timeout)
  end
  
  def query_async(server \\ __MODULE__, prompt, reply_to, opts \\ []) do
    GenServer.cast(server, {:query_async, prompt, reply_to, opts})
  end
  
  def get_state(server \\ __MODULE__) do
    GenServer.call(server, :get_state)
  end
  
  def add_context_file(server \\ __MODULE__, file_path) do
    GenServer.call(server, {:add_context_file, file_path})
  end
  
  def switch_model(server \\ __MODULE__, backend, model) do
    GenServer.call(server, {:switch_model, backend, model})
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    # Initialize MCP Chat session
    session = MCPChat.Session.new()
    
    # Apply any initial configuration
    backend = Keyword.get(opts, :backend, "ollama")
    model = Keyword.get(opts, :model, "llama3.2:3b")
    
    session = 
      session
      |> MCPChat.Session.set_backend(backend)
      |> MCPChat.Session.set_model(model)
    
    state = %{
      session: session,
      pending_queries: %{},
      query_counter: 0,
      opts: opts
    }
    
    Logger.info("AgentServer started with backend: #{backend}, model: #{model}")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:query, prompt, opts}, _from, state) do
    # Synchronous query
    case run_query(prompt, state.session, opts) do
      {:ok, response, new_session} ->
        {:reply, {:ok, response}, %{state | session: new_session}}
      
      {:error, reason} = error ->
        Logger.error("Query failed: #{inspect(reason)}")
        {:reply, error, state}
    end
  end
  
  def handle_call(:get_state, _from, state) do
    info = %{
      backend: state.session.backend,
      model: state.session.model,
      pending_queries: map_size(state.pending_queries),
      message_count: length(state.session.messages)
    }
    {:reply, info, state}
  end
  
  def handle_call({:add_context_file, file_path}, _from, state) do
    case File.read(file_path) do
      {:ok, content} ->
        new_session = MCPChat.Session.add_context_file(state.session, file_path, content)
        {:reply, :ok, %{state | session: new_session}}
      
      {:error, reason} = error ->
        {:reply, error, state}
    end
  end
  
  def handle_call({:switch_model, backend, model}, _from, state) do
    new_session = 
      state.session
      |> MCPChat.Session.set_backend(backend)
      |> MCPChat.Session.set_model(model)
    
    Logger.info("Switched to backend: #{backend}, model: #{model}")
    {:reply, :ok, %{state | session: new_session}}
  end
  
  @impl true
  def handle_cast({:query_async, prompt, reply_to, opts}, state) do
    # Spawn a task to handle the query asynchronously
    query_id = state.query_counter + 1
    
    task = Task.async(fn ->
      run_query(prompt, state.session, opts)
    end)
    
    new_state = %{state | 
      pending_queries: Map.put(state.pending_queries, task.ref, {query_id, reply_to}),
      query_counter: query_id
    }
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Handle Task completion
    case Map.pop(state.pending_queries, ref) do
      {{query_id, reply_to}, pending_queries} ->
        # Clean up the task
        Process.demonitor(ref, [:flush])
        
        # Send result to the original requester
        case result do
          {:ok, response, new_session} ->
            send(reply_to, {:mcp_response, query_id, {:ok, response}})
            {:noreply, %{state | session: new_session, pending_queries: pending_queries}}
          
          {:error, reason} ->
            send(reply_to, {:mcp_response, query_id, {:error, reason}})
            {:noreply, %{state | pending_queries: pending_queries}}
        end
      
      {nil, _} ->
        # Unknown task reference
        {:noreply, state}
    end
  end
  
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Handle task failure
    case Map.pop(state.pending_queries, ref) do
      {{query_id, reply_to}, pending_queries} ->
        send(reply_to, {:mcp_response, query_id, {:error, {:task_failed, reason}}})
        {:noreply, %{state | pending_queries: pending_queries}}
      
      {nil, _} ->
        {:noreply, state}
    end
  end
  
  # Private Functions
  
  defp run_query(prompt, session, opts) do
    try do
      # Add the user message
      session_with_prompt = MCPChat.Session.add_message(session, %{
        role: "user",
        content: prompt
      })
      
      # Get completion from LLM
      case MCPChat.LLM.get_completion(session_with_prompt, opts) do
        {:ok, response} ->
          # Add assistant response to session
          final_session = MCPChat.Session.add_message(session_with_prompt, %{
            role: "assistant",
            content: response
          })
          
          {:ok, response, final_session}
        
        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e ->
        {:error, {:exception, Exception.format(:error, e, __STACKTRACE__)}}
    end
  end
end