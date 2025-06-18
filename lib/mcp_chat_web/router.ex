defmodule MCPChatWeb.Router do
  use Phoenix.Router

  import Phoenix.LiveView.Router
  import Plug.Conn
  import Phoenix.Controller

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {MCPChatWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", MCPChatWeb do
    pipe_through(:browser)

    live("/", DashboardLive, :index)
    live("/sessions", SessionListLive, :index)
    live("/sessions/:session_id", SessionLive, :show)
    live("/sessions/:session_id/chat", ChatLive, :show)
    live("/agents", AgentMonitorLive, :index)
    live("/agents/:agent_id", AgentDetailLive, :show)
  end

  scope "/api", MCPChatWeb do
    pipe_through(:api)

    get("/sessions", SessionController, :index)
    post("/sessions", SessionController, :create)
    get("/sessions/:id", SessionController, :show)
    delete("/sessions/:id", SessionController, :delete)

    post("/sessions/:id/messages", MessageController, :create)
    post("/sessions/:id/commands", CommandController, :execute)

    get("/agents", AgentController, :index)
    get("/agents/:id", AgentController, :show)
    get("/agents/:id/status", AgentController, :status)
  end

  # Development routes
  scope "/dev" do
    pipe_through(:browser)

    # Simple health check for now
    get("/health", MCPChatWeb.HealthController, :index)
  end
end
