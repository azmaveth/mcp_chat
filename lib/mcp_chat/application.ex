defmodule MCPChat.Application do
  @moduledoc """
  Main OTP application for MCP Chat client.
  """
  use Application

  alias MCPChat.Alias.ExAliasAdapter
  alias MCPChat.MCP.Handlers.{ProgressHandler, ToolChangeHandler}
  alias MCPChat.MCP.{HealthMonitor, NotificationRegistry, ProgressTracker}
  alias MCPChat.Memory.StoreSupervisor
  alias MCPChat.Session.Autosave
  alias MCPChat.{Config, StartupProfiler}

  @impl true
  def start(_type, _args) do
    # Start profiling if enabled
    StartupProfiler.start_profiling()
    StartupProfiler.start_phase(:total)

    # Load configuration first
    StartupProfiler.start_phase(:config_loading)
    config_mode = get_startup_mode()

    # ExLLM circuit breaker is automatically initialized by ExLLM.Application

    # Initialize telemetry for comprehensive monitoring
    MCPChat.Telemetry.attach_default_handlers()

    StartupProfiler.end_phase(:config_loading)

    StartupProfiler.start_phase(:supervision_tree)

    children =
      [
        # Configuration manager
        MCPChat.Config,
        # Session manager
        MCPChat.Session,
        # Session autosave
        {Autosave, autosave_config()},
        # MCP Health monitoring
        HealthMonitor,
        # ExLLM circuit breaker is auto-initialized
        # Connection pool supervisor
        {DynamicSupervisor, strategy: :one_for_one, name: MCPChat.ConnectionPoolSupervisor},
        # Memory store supervisor for message pagination
        StoreSupervisor,
        # Chat session supervisor
        MCPChat.ChatSupervisor,
        # ExAlias server (must be started before the adapter)
        ExAlias,
        # Alias manager adapter
        ExAliasAdapter,
        # Line editor for CLI input
        MCPChat.CLI.ExReadlineAdapter,
        # Lazy server manager (new)
        {MCPChat.MCP.LazyServerManager, connection_mode: config_mode},
        # MCP server manager (handles the dynamic supervisor internally)
        MCPChat.MCP.ServerManager,
        # New v0.2.0 MCP features
        MCPChat.MCP.NotificationRegistry,
        MCPChat.MCP.ProgressTracker,
        # TUI components
        MCPChat.UI.TUIManager,
        MCPChat.UI.ProgressDisplay,
        MCPChat.UI.ResourceCacheDisplay,
        # Resource cache
        MCPChat.MCP.ResourceCache
      ] ++ mcp_server_children()

    opts = [strategy: :one_for_one, name: MCPChat.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, _sup} = result ->
        StartupProfiler.end_phase(:supervision_tree)

        # Register core processes for health monitoring
        register_health_monitors()
        # Enable notifications by default
        enable_notifications()

        result

      error ->
        error
    end
  end

  defp get_startup_mode do
    case get_startup_mode_from_env() do
      nil -> get_startup_mode_from_config()
      mode -> mode
    end
  end

  defp get_startup_mode_from_env do
    case System.get_env("MCP_STARTUP_MODE") do
      "eager" -> :eager
      "background" -> :background
      "lazy" -> :lazy
      _ -> nil
    end
  end

  defp get_startup_mode_from_config do
    config_path = Path.expand("~/.config/mcp_chat/config.toml")

    if File.exists?(config_path) do
      read_startup_mode_from_file(config_path)
    else
      :lazy
    end
  end

  defp read_startup_mode_from_file(config_path) do
    case Toml.decode_file(config_path) do
      {:ok, config} -> parse_startup_mode_from_config(config)
      _ -> :lazy
    end
  end

  defp parse_startup_mode_from_config(config) do
    case get_in(config, ["startup", "mcp_connection_mode"]) do
      "eager" -> :eager
      "background" -> :background
      "lazy" -> :lazy
      _ -> :lazy
    end
  end

  defp register_health_monitors do
    # Give processes time to start
    Process.sleep(100)

    # Register core processes for monitoring
    processes_to_monitor = [
      {:config, MCPChat.Config},
      {:session, MCPChat.Session},
      {:server_manager, MCPChat.MCP.ServerManager},
      {:alias_adapter, MCPChat.Alias.ExAliasAdapter}
    ]

    Enum.each(processes_to_monitor, &register_process_for_monitoring/1)
  end

  defp register_process_for_monitoring({name, process_name}) do
    case Process.whereis(process_name) do
      nil ->
        :ok

      pid ->
        # Note: Using general health monitor, not MCP-specific one
        if Process.whereis(MCPChat.HealthMonitor) do
          MCPChat.HealthMonitor.register(name, pid)
        end
    end
  end

  defp mcp_server_children do
    # Wait a bit for Config to initialize
    Process.sleep(100)

    config =
      case Process.whereis(MCPChat.Config) do
        nil -> %{}
        _ -> MCPChat.Config.get(:mcp_server) || %{}
      end

    children = []

    # Add MCP server using ex_mcp if enabled
    children =
      if config[:stdio_enabled] do
        [
          %{
            id: MCPChat.MCPServer.Stdio,
            start:
              {ExMCP.Server, :start_link,
               [
                 [
                   handler: MCPChat.MCPServerHandler,
                   transport: :stdio,
                   name: {:local, MCPChat.MCPServer.Stdio}
                 ]
               ]}
          }
          | children
        ]
      else
        children
      end

    # Add SSE server if enabled
    children =
      if config[:sse_enabled] do
        port = config[:sse_port] || 8_080

        [
          %{
            id: MCPChat.MCPServer.SSE,
            start:
              {ExMCP.Server, :start_link,
               [
                 [
                   handler: MCPChat.MCPServerHandler,
                   transport: :sse,
                   transport_opts: [port: port],
                   name: {:local, MCPChat.MCPServer.SSE}
                 ]
               ]}
          }
          | children
        ]
      else
        children
      end

    children
  end

  defp enable_notifications do
    # Give registry time to start
    Process.sleep(200)

    # Register default notification handlers
    NotificationRegistry.register_handler(
      MCPChat.MCP.Handlers.ResourceChangeHandler,
      [:resources_list_changed, :resources_updated]
    )

    NotificationRegistry.register_handler(
      ToolChangeHandler,
      [:tools_list_changed]
    )

    NotificationRegistry.register_handler(
      ProgressHandler,
      [:progress],
      progress_tracker_pid: Process.whereis(ProgressTracker)
    )

    # Save preference
    if Process.whereis(MCPChat.Config) do
      MCPChat.Config.set_runtime("notifications.enabled", true)
    end
  rescue
    _ -> :ok
  end

  defp autosave_config do
    # Default configuration - actual config will be loaded after Config starts
    [
      enabled: true,
      # 5 minutes
      interval: 5 * 60 * 1_000,
      keep_count: 10,
      compress_large: true,
      session_name_prefix: "autosave"
    ]
  end
end
