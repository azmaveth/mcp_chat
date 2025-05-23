defmodule MCPChat.MCPServer.SSEServer do
  @moduledoc """
  MCP server that communicates via Server-Sent Events (SSE) over HTTP.
  """
  use GenServer
  
  alias MCPChat.MCPServer.Handler
  
  require Logger

  defmodule Router do
    use Plug.Router
    
    plug Plug.Logger
    plug :match
    plug Plug.Parsers,
      parsers: [:json],
      pass: ["application/json"],
      json_decoder: Jason
    plug :dispatch

    # SSE endpoint for receiving messages
    get "/sse" do
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      |> put_resp_header("access-control-allow-origin", "*")
      |> send_chunked(200)
      |> handle_sse_connection()
    end

    # JSON-RPC endpoint for sending messages
    post "/message" do
      with {:ok, request} <- parse_request(conn.body_params),
           {:ok, response} <- MCPChat.MCPServer.SSEServer.process_message(request) do
        conn
        |> put_resp_content_type("application/json")
        |> put_resp_header("access-control-allow-origin", "*")
        |> send_resp(200, Jason.encode!(response))
      else
        {:error, reason} ->
          error_response = %{
            jsonrpc: "2.0",
            error: %{
              code: -32700,
              message: "Parse error: #{inspect(reason)}"
            },
            id: nil
          }
          
          conn
          |> put_resp_content_type("application/json")
          |> put_resp_header("access-control-allow-origin", "*")
          |> send_resp(400, Jason.encode!(error_response))
      end
    end

    # CORS preflight
    options _ do
      conn
      |> put_resp_header("access-control-allow-origin", "*")
      |> put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
      |> put_resp_header("access-control-allow-headers", "content-type")
      |> send_resp(204, "")
    end

    # Catch-all
    match _ do
      send_resp(conn, 404, "Not found")
    end

    # Private functions

    defp handle_sse_connection(conn) do
      # Register this connection with the SSE server
      {:ok, connection_id} = MCPChat.MCPServer.SSEServer.register_connection(conn)
      
      # Send initial connection event
      send_sse_event(conn, "connected", %{status: "ready", connection_id: connection_id})
      
      # Keep connection alive with a monitoring process
      Task.start_link(fn ->
        monitor_connection(conn, connection_id)
      end)
      
      conn
    end

    defp monitor_connection(conn, connection_id) do
      Process.sleep(30_000)
      
      case send_sse_event(conn, "ping", %{timestamp: DateTime.utc_now()}) do
        {:ok, conn} ->
          monitor_connection(conn, connection_id)
        {:error, _} ->
          MCPChat.MCPServer.SSEServer.unregister_connection(connection_id)
      end
    end

    defp send_sse_event(conn, event, data) do
      chunk = "event: #{event}\ndata: #{Jason.encode!(data)}\n\n"
      
      case chunk(conn, chunk) do
        {:ok, conn} -> {:ok, conn}
        {:error, reason} -> {:error, reason}
      end
    end

    defp parse_request(params) do
      case params do
        %{"jsonrpc" => "2.0", "method" => _method} = request ->
          {:ok, request}
        _ ->
          {:error, :invalid_request}
      end
    end
  end

  # GenServer implementation

  defstruct connections: %{}, handler_state: nil

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  # Client API

  def register_connection(conn) do
    GenServer.call(__MODULE__, {:register_connection, conn})
  end

  def unregister_connection(connection_id) do
    GenServer.cast(__MODULE__, {:unregister_connection, connection_id})
  end

  def process_message(request) do
    GenServer.call(__MODULE__, {:process_message, request})
  end

  def send_to_connection(connection_id, event, data) do
    GenServer.cast(__MODULE__, {:send_to_connection, connection_id, event, data})
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, 8080)
    
    Logger.info("Starting MCP SSE server on port #{port}")
    
    # Start the Plug router
    {:ok, _} = Plug.Cowboy.http(Router, [], port: port)
    
    # Initialize handler state
    {:ok, handler_state} = Handler.init(:sse)
    
    {:ok, %__MODULE__{handler_state: handler_state}}
  end

  @impl true
  def handle_call({:register_connection, conn}, _from, state) do
    connection_id = generate_connection_id()
    connections = Map.put(state.connections, connection_id, conn)
    
    {:reply, {:ok, connection_id}, %{state | connections: connections}}
  end

  @impl true
  def handle_call({:process_message, request}, _from, state) do
    response = case request do
      %{"method" => method, "params" => params, "id" => id} ->
        # Request with ID
        case Handler.handle_request(method, params || %{}, state.handler_state) do
          {:ok, result, new_handler_state} ->
            response = %{
              jsonrpc: "2.0",
              result: result,
              id: id
            }
            {:ok, response, %{state | handler_state: new_handler_state}}
          
          {:error, error, new_handler_state} ->
            response = %{
              jsonrpc: "2.0",
              error: error,
              id: id
            }
            {:ok, response, %{state | handler_state: new_handler_state}}
        end
      
      %{"method" => method, "params" => params} ->
        # Notification (no ID)
        case Handler.handle_notification(method, params || %{}, state.handler_state) do
          {:ok, new_handler_state} ->
            {:ok, %{jsonrpc: "2.0", result: "ok"}, %{state | handler_state: new_handler_state}}
          _ ->
            {:ok, %{jsonrpc: "2.0", result: "ok"}, state}
        end
      
      %{"method" => _method, "id" => _id} ->
        # Request with no params
        handle_call({:process_message, Map.put(request, "params", %{})}, nil, state)
    end
    
    case response do
      {:ok, resp, new_state} ->
        {:reply, {:ok, resp}, new_state}
      _ ->
        {:reply, {:error, :processing_failed}, state}
    end
  end

  @impl true
  def handle_cast({:unregister_connection, connection_id}, state) do
    connections = Map.delete(state.connections, connection_id)
    {:noreply, %{state | connections: connections}}
  end

  @impl true
  def handle_cast({:send_to_connection, connection_id, event, data}, state) do
    case Map.get(state.connections, connection_id) do
      nil ->
        Logger.warning("Connection #{connection_id} not found")
      
      conn ->
        chunk = "event: #{event}\ndata: #{Jason.encode!(data)}\n\n"
        case Plug.Conn.chunk(conn, chunk) do
          {:ok, _} -> :ok
          {:error, _} -> 
            # Connection is dead, remove it
            connections = Map.delete(state.connections, connection_id)
            {:noreply, %{state | connections: connections}}
        end
    end
    
    {:noreply, state}
  end

  # Private functions

  defp generate_connection_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end
end