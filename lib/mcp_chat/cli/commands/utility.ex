defmodule MCPChat.CLI.Commands.Utility do
  @moduledoc """
  Utility CLI commands.

  Handles general utility commands including:
  - Help and documentation
  - Screen clearing
  - Configuration display
  - Cost tracking
  - Session export
  """

  use MCPChat.CLI.Commands.Base

  alias MCPChat.CLI.Renderer
  alias MCPChat.LLM.ExLLMAdapter
  alias MCPChat.MCP.ServerManager
  alias MCPChat.{Cost, Persistence, Session}

  @impl true
  def commands do
    %{
      "help" => "Show available commands",
      "clear" => "Clear the screen",
      "config" => "Show current configuration",
      "cost" => "Show session cost (usage: /cost [detailed|compact|table|breakdown])",
      "stats" => "Show session statistics",
      "streaming" => "Show streaming metrics and configuration",
      "cache" => "Show cache statistics and management (usage: /cache [stats|clear|enable|disable])",
      "export" => "Export conversation (usage: /export [format] [path])",
      "resume" => "Resume the last interrupted response",
      "recovery" => "Manage recoverable streams (usage: /recovery list|clean|info [id])"
    }
  end

  @impl true
  def handle_command("help", _args) do
    show_help()
  end

  def handle_command("clear", _args) do
    clear_screen()
  end

  def handle_command("config", _args) do
    show_config()
  end

  def handle_command("cost", args) do
    show_cost(args)
  end

  def handle_command("stats", _args) do
    show_stats()
  end

  def handle_command("streaming", args) do
    show_streaming_info(args)
  end

  def handle_command("cache", args) do
    handle_cache_management(args)
  end

  def handle_command("export", args) do
    export_conversation(args)
  end

  def handle_command("resume", args) do
    resume_interrupted_response(args)
  end

  def handle_command("recovery", args) do
    handle_recovery_management(args)
  end

  def handle_command(cmd, _args) do
    {:error, "Unknown utility command: #{cmd}"}
  end

  # Command implementations

  defp show_help do
    # Collect commands from all modules
    all_commands = collect_all_commands()

    Renderer.show_text("## Available Commands\n")

    # Show table header
    IO.puts("Command          | Description")
    IO.puts("---------------- | -----------")

    # Sort and display all commands
    all_commands
    |> Enum.sort_by(fn {cmd, _desc} -> cmd end)
    |> Enum.each(fn {cmd, desc} ->
      IO.puts("/#{String.pad_trailing(cmd, 15)} | #{desc}")
    end)

    IO.puts("\nType /help <command> for detailed help on a specific command.")
    :ok
  end

  defp clear_screen do
    IO.write(IO.ANSI.clear())
    IO.write(IO.ANSI.cursor(0, 0))
    :ok
  end

  defp show_config do
    session = Session.get_current_session()

    Renderer.show_text("## Current Configuration\n")

    # Show configuration in table format
    IO.puts("Setting              | Value")
    IO.puts("-------------------- | -----")
    IO.puts("LLM Backend          | #{session.llm_backend || "Not set"}")
    IO.puts("Model                | #{session.context[:model] || "Not set"}")

    # Show MCP servers
    servers = ServerManager.list_servers()
    server_count = length(servers)
    IO.puts("MCP Servers          | #{server_count} connected")

    # Show context settings
    IO.puts("Max Tokens           | #{session.context[:max_tokens] || "4_096"}")
    IO.puts("Truncation Strategy  | #{session.context[:truncation_strategy] || "sliding_window"}")

    :ok
  end

  defp show_cost(args \\ []) do
    session = Session.get_current_session()

    case args do
      [] ->
        # Default detailed view
        show_cost_with_format(session, :detailed)

      ["detailed"] ->
        show_cost_with_format(session, :detailed)

      ["compact"] ->
        show_cost_with_format(session, :compact)

      ["table"] ->
        show_cost_with_format(session, :table)

      ["breakdown"] ->
        show_cost_breakdown(session)

      ["help"] ->
        show_cost_help()

      _ ->
        IO.puts("Invalid cost command. Use: /cost [detailed|compact|table|breakdown|help]")
    end

    :ok
  end

  defp show_cost_with_format(session, format) do
    # Use ExLLM's enhanced cost session if available
    if session.cost_session do
      show_enhanced_cost_summary(session.cost_session, format)
    else
      show_legacy_cost_summary(session)
    end
  end

  defp show_enhanced_cost_summary(cost_session, format \\ :detailed) do
    # Use ExLLM's enhanced formatting
    formatted_summary = ExLLM.Cost.Session.format_summary(cost_session, format: format)
    IO.puts(formatted_summary)
  end

  defp show_legacy_cost_summary(session) do
    Renderer.show_text("## Session Cost Summary\n")

    IO.puts("Backend: #{session.llm_backend || "Not set"}")
    IO.puts("Model: #{session.context[:model] || "Not set"}")
    IO.puts("")

    # Get accumulated cost from session (which now includes ExLLM cost data)
    total_cost = session.accumulated_cost || 0.0
    token_usage = session.token_usage || %{input_tokens: 0, output_tokens: 0}

    input_tokens = Map.get(token_usage, :input_tokens, 0)
    output_tokens = Map.get(token_usage, :output_tokens, 0)
    total_tokens = input_tokens + output_tokens

    if total_tokens > 0 do
      IO.puts("Token Usage:")
      IO.puts("  Input tokens:  #{format_number(input_tokens)}")
      IO.puts("  Output tokens: #{format_number(output_tokens)}")
      IO.puts("  Total tokens:  #{format_number(total_tokens)}")
      IO.puts("")

      if total_cost > 0 do
        IO.puts("Cost (calculated by ExLLM):")
        IO.puts("  Total cost:  #{ExLLM.Cost.format(total_cost)}")
      else
        IO.puts("Cost calculation not available for this provider/model.")
      end
    else
      IO.puts("No token usage recorded yet.")
    end
  end

  defp show_cost_breakdown(session) do
    if session.cost_session do
      IO.puts("💰 Session Cost Breakdown")
      IO.puts("========================")
      IO.puts("")

      # Provider breakdown
      provider_breakdown = ExLLM.Cost.Session.provider_breakdown(session.cost_session)

      if Enum.any?(provider_breakdown) do
        IO.puts("📊 By Provider:")

        Enum.each(provider_breakdown, fn provider_stats ->
          IO.puts(
            "  #{String.capitalize(provider_stats.provider)}: #{ExLLM.Cost.format(provider_stats.total_cost)} " <>
              "(#{provider_stats.message_count} msgs, #{format_number(provider_stats.total_tokens)} tokens)"
          )
        end)

        IO.puts("")
      end

      # Model breakdown
      model_breakdown = ExLLM.Cost.Session.model_breakdown(session.cost_session)

      if Enum.any?(model_breakdown) do
        IO.puts("🤖 By Model:")

        model_breakdown
        # Show top 10 models
        |> Enum.take(10)
        |> Enum.each(fn model_stats ->
          IO.puts(
            "  #{model_stats.model}: #{ExLLM.Cost.format(model_stats.total_cost)} " <>
              "(#{model_stats.message_count} msgs, #{format_number(model_stats.total_tokens)} tokens)"
          )
        end)

        if length(model_breakdown) > 10 do
          IO.puts("  ... and #{length(model_breakdown) - 10} more models")
        end
      end
    else
      IO.puts("❌ Enhanced cost breakdown not available. Start a new session to enable detailed cost tracking.")
    end
  end

  defp show_cost_help do
    IO.puts("## Cost Command Help")
    IO.puts("")
    IO.puts("Available cost commands:")
    IO.puts("  /cost                - Show detailed cost summary (default)")
    IO.puts("  /cost detailed       - Show comprehensive cost analysis")
    IO.puts("  /cost compact        - Show brief cost summary")
    IO.puts("  /cost table          - Show cost data in table format")
    IO.puts("  /cost breakdown      - Show detailed breakdown by provider and model")
    IO.puts("  /cost help           - Show this help")
    IO.puts("")
    IO.puts("The enhanced cost tracking provides:")
    IO.puts("  • Real-time cost calculation using ExLLM's pricing database")
    IO.puts("  • Provider and model breakdown analysis")
    IO.puts("  • Session duration and efficiency metrics")
    IO.puts("  • Cost per message and cost per 1K tokens")
  end

  defp show_stats do
    session = Session.get_current_session()

    IO.puts("## Session Statistics")
    IO.puts("")
    IO.puts("Session ID: #{session.id}")
    IO.puts("Messages: #{length(session.messages)}")
    IO.puts("Created: #{session.created_at}")

    show_token_usage(session)
    show_context_usage(session)
    :ok
  end

  defp show_token_usage(session) do
    if session.token_usage do
      input_tokens = Map.get(session.token_usage, :input_tokens, 0)
      output_tokens = Map.get(session.token_usage, :output_tokens, 0)
      total_tokens = input_tokens + output_tokens

      if total_tokens > 0 do
        show_token_details(input_tokens, output_tokens, total_tokens)
        show_cost_estimate(session.llm_backend, input_tokens, output_tokens)
      end
    end
  end

  defp show_token_details(input_tokens, output_tokens, total_tokens) do
    IO.puts("Input tokens: #{input_tokens}")
    IO.puts("Output tokens: #{output_tokens}")
    IO.puts("Total tokens: #{total_tokens}")
  end

  defp show_cost_estimate(nil, _input_tokens, _output_tokens), do: :ok

  defp show_cost_estimate(backend, input_tokens, output_tokens) do
    # Cost estimation is now handled by ExLLM, so we'll get it from the session's accumulated_cost
    session = Session.get_current_session()
    cost = session.accumulated_cost || 0.0

    if cost > 0 do
      IO.puts("Estimated cost: $#{:erlang.float_to_binary(cost, decimals: 4)}")
    end
  end

  defp show_context_usage(session) do
    # Get context stats using ExLLM's context management
    if session.llm_backend && session.llm_model do
      provider = String.to_atom(session.llm_backend)
      model = session.llm_model

      try do
        stats =
          ExLLMAdapter.get_context_stats(
            session.messages,
            provider,
            model
          )

        IO.puts("")
        IO.puts("## Context Usage")
        IO.puts("Context window: #{stats.context_window} tokens")
        IO.puts("Estimated usage: #{stats.estimated_tokens} tokens (#{stats.tokens_used_percentage}%)")
        IO.puts("Tokens remaining: #{stats.tokens_remaining}")

        if stats[:token_allocation] do
          alloc = stats.token_allocation
          IO.puts("")
          IO.puts("Token allocation:")
          IO.puts("  System: #{alloc.system} tokens")
          IO.puts("  Conversation: #{alloc.conversation} tokens")
          IO.puts("  Response: #{alloc.response} tokens")
        end
      rescue
        _ ->
          # Silently skip if context stats fail
          :ok
      end
    end
  end

  defp export_conversation(args) do
    format =
      case args do
        [] -> :markdown
        [f | _] -> String.to_atom(f)
      end

    session = Session.get_current_session()

    # Generate filename
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)

    extension =
      case format do
        :json -> "json"
        :text -> "txt"
        _ -> "md"
      end

    filename = "chat_export_#{timestamp}.#{extension}"

    case Persistence.export_session(session, format, filename) do
      {:ok, content} ->
        File.write!(filename, content)
        show_success("Conversation exported to: #{filename}")

      {:error, reason} ->
        show_error("Failed to export: #{reason}")
    end

    :ok
  end

  # Helper functions

  defp collect_all_commands do
    # Import commands from all command modules
    modules = [
      MCPChat.CLI.Commands.Session,
      MCPChat.CLI.Commands.Utility,
      MCPChat.CLI.Commands.LLM,
      MCPChat.CLI.Commands.MCP,
      MCPChat.CLI.Commands.Context,
      MCPChat.CLI.Commands.Alias
    ]

    # Merge all command maps
    modules
    |> Enum.filter(&Code.ensure_loaded?/1)
    |> Enum.flat_map(fn mod ->
      if function_exported?(mod, :commands, 0) do
        mod.commands() |> Map.to_list()
      else
        []
      end
    end)
    |> Map.new()
    |> Map.merge(%{
      "exit" => "Exit the application",
      "quit" => "Exit the application"
    })
  end

  # Note: format_number now comes from Display helper

  defp format_cost(cost) when cost < 0.01, do: "#{Float.round(cost, 4)}"
  defp format_cost(cost), do: "#{Float.round(cost, 2)}"

  defp resume_interrupted_response(_args) do
    alias MCPChat.CLI.Renderer
    alias MCPChat.LLM.ExLLMAdapter

    case Session.get_last_recovery_id() do
      nil ->
        Renderer.show_error("No interrupted response to resume")

      recovery_id ->
        handle_recovery(recovery_id, ExLLMAdapter, Renderer)
    end
  end

  defp handle_recovery(recovery_id, adapter, renderer) do
    recoverable = adapter.list_recoverable_streams()

    case Enum.find(recoverable, &(&1.id == recovery_id)) do
      nil ->
        handle_recovery_not_found(recovery_id, renderer)

      stream_info ->
        handle_recovery_found(recovery_id, stream_info, adapter, renderer)
    end
  end

  defp handle_recovery_not_found(recovery_id, renderer) do
    renderer.show_error("Previous response is no longer recoverable")
    Session.clear_last_recovery_id()
  end

  defp handle_recovery_found(recovery_id, stream_info, adapter, renderer) do
    show_recovery_info(stream_info, renderer)

    case adapter.get_partial_response(recovery_id) do
      {:ok, chunks} ->
        show_partial_content(chunks, renderer)
        attempt_resume_stream(recovery_id, adapter, renderer)

      {:error, reason} ->
        renderer.show_error("Failed to get partial response: #{inspect(reason)}")
    end
  end

  defp show_recovery_info(stream_info, renderer) do
    renderer.show_info("Resuming interrupted response...")
    renderer.show_text("• Provider: #{stream_info.provider}")
    renderer.show_text("• Model: #{stream_info.model}")
    renderer.show_text("• Chunks received: #{stream_info.chunks_received}")
    renderer.show_text("• Tokens processed: #{stream_info.token_count}")
  end

  defp show_partial_content(chunks, renderer) do
    partial_content = Enum.map_join(chunks, "", & &1.content)

    if String.length(partial_content) > 0 do
      renderer.show_text("\n--- Partial response ---")
      renderer.show_text(partial_content)
      renderer.show_text("--- Continuing... ---\n")
    end
  end

  defp attempt_resume_stream(recovery_id, adapter, renderer) do
    case adapter.resume_stream(recovery_id) do
      {:ok, stream} ->
        renderer.show_success("Response resumed successfully")
        Session.clear_last_recovery_id()
        {:resume_stream, stream}

      {:error, reason} ->
        renderer.show_error("Failed to resume: #{inspect(reason)}")
    end
  end

  defp handle_recovery_management(args) do
    alias MCPChat.CLI.Renderer
    alias MCPChat.LLM.ExLLMAdapter

    case args do
      [] ->
        show_recovery_help()

      ["list"] ->
        list_recoverable_streams()

      ["clean"] ->
        clean_expired_streams()

      ["info", recovery_id] ->
        show_recovery_info(recovery_id)

      ["resume", recovery_id] ->
        resume_specific_stream(recovery_id)

      _ ->
        Renderer.show_error("Invalid recovery command. Use: /recovery list|clean|info|resume [id]")
    end
  end

  defp show_recovery_help do
    IO.puts("## Recovery Management")
    IO.puts("Available commands:")
    IO.puts("  /recovery list       - List all recoverable streams")
    IO.puts("  /recovery clean      - Clean expired streams")
    IO.puts("  /recovery info <id>  - Show detailed info for a stream")
    IO.puts("  /recovery resume <id> - Resume a specific stream by ID")
    IO.puts("  /resume              - Resume the last interrupted stream")
  end

  defp list_recoverable_streams do
    alias MCPChat.CLI.Renderer
    alias MCPChat.LLM.ExLLMAdapter

    recoverable = ExLLMAdapter.list_recoverable_streams()

    if Enum.empty?(recoverable) do
      Renderer.show_info("No recoverable streams found")
    else
      Renderer.show_text("## Recoverable Streams")
      IO.puts("ID                    | Provider | Model            | Chunks | Tokens | Age")
      IO.puts("--------------------- | -------- | ---------------- | ------ | ------ | -------")

      Enum.each(recoverable, fn stream_info ->
        age = format_age(stream_info.created_at)

        IO.puts(
          "#{String.pad_trailing(stream_info.id, 21)} | #{String.pad_trailing(to_string(stream_info.provider), 8)} | #{String.pad_trailing(stream_info.model, 16)} | #{String.pad_leading(to_string(stream_info.chunks_received), 6)} | #{String.pad_leading(to_string(stream_info.token_count), 6)} | #{age}"
        )
      end)

      current_recovery_id = Session.get_last_recovery_id()

      if current_recovery_id do
        IO.puts("\\n* Current session recovery ID: #{current_recovery_id}")
      end
    end
  end

  defp clean_expired_streams do
    alias MCPChat.CLI.Renderer

    # This would call ExLLM to clean expired streams
    case ExLLM.StreamRecovery.cleanup_expired() do
      {:ok, count} ->
        Renderer.show_success("Cleaned #{count} expired stream(s)")

      {:error, reason} ->
        Renderer.show_error("Failed to clean streams: #{inspect(reason)}")
    end
  end

  defp show_recovery_info(recovery_id) do
    alias MCPChat.CLI.Renderer
    alias MCPChat.LLM.ExLLMAdapter

    recoverable = ExLLMAdapter.list_recoverable_streams()

    case Enum.find(recoverable, &(&1.id == recovery_id)) do
      nil ->
        Renderer.show_error("Recovery ID not found: #{recovery_id}")

      stream_info ->
        Renderer.show_text("## Stream Recovery Information")
        IO.puts("Recovery ID: #{stream_info.id}")
        IO.puts("Provider: #{stream_info.provider}")
        IO.puts("Model: #{stream_info.model}")
        IO.puts("Chunks received: #{stream_info.chunks_received}")
        IO.puts("Tokens processed: #{stream_info.token_count}")
        IO.puts("Created: #{format_timestamp(stream_info.created_at)}")
        IO.puts("Age: #{format_age(stream_info.created_at)}")

        # Show partial content preview
        case ExLLMAdapter.get_partial_response(recovery_id) do
          {:ok, chunks} ->
            partial_content = Enum.map_join(chunks, "", & &1.content)
            preview = String.slice(partial_content, 0, 200)
            IO.puts("\\nPartial content preview:")
            IO.puts("#{preview}#{if String.length(partial_content) > 200, do: "...", else: ""}")

          {:error, reason} ->
            IO.puts("\\nError retrieving partial content: #{inspect(reason)}")
        end
    end
  end

  defp resume_specific_stream(recovery_id) do
    alias MCPChat.CLI.Renderer
    alias MCPChat.LLM.ExLLMAdapter

    # Set the recovery ID as current and then resume
    Session.set_last_recovery_id(recovery_id)

    case handle_recovery(recovery_id, ExLLMAdapter, Renderer) do
      {:resume_stream, _stream} ->
        {:resume_stream_command, recovery_id}

      _ ->
        :ok
    end
  end

  defp format_age(timestamp) do
    now = :os.system_time(:second)
    diff = now - timestamp

    cond do
      diff < 60 -> "#{diff}s"
      diff < 3_600 -> "#{div(diff, 60)}m"
      diff < 86_400 -> "#{div(diff, 3_600)}h"
      true -> "#{div(diff, 86_400)}d"
    end
  end

  defp format_timestamp(timestamp) do
    timestamp
    |> DateTime.from_unix!()
    |> DateTime.to_string()
  end

  defp show_streaming_info(args) do
    case args do
      [] ->
        show_streaming_config()

      ["config"] ->
        show_streaming_config()

      ["metrics"] ->
        show_streaming_metrics()

      _ ->
        IO.puts("Usage: /streaming [config|metrics]")
        IO.puts("  config  - Show streaming configuration")
        IO.puts("  metrics - Show streaming performance metrics")
    end
  end

  defp show_streaming_config do
    alias MCPChat.Config

    IO.puts("## Streaming Configuration")
    IO.puts("")
    IO.puts("Enhanced streaming: #{Config.get([:streaming, :enhanced], true)}")
    IO.puts("Use ExLLM streaming: #{Config.get([:streaming, :use_ex_llm_streaming], true)}")
    IO.puts("")
    IO.puts("**ExLLM Flow Control:**")
    IO.puts("  Buffer capacity: #{Config.get([:streaming, :buffer_capacity], 100)}")
    IO.puts("  Backpressure threshold: #{Config.get([:streaming, :backpressure_threshold], 0.8)}")
    IO.puts("  Rate limit (ms): #{Config.get([:streaming, :rate_limit_ms], 0)}")
    IO.puts("")
    IO.puts("**ExLLM Chunk Batching:**")
    IO.puts("  Batch size: #{Config.get([:streaming, :batch_size], 5)}")
    IO.puts("  Batch timeout (ms): #{Config.get([:streaming, :batch_timeout_ms], 25)}")
    IO.puts("  Adaptive batching: #{Config.get([:streaming, :adaptive_batching], true)}")
    IO.puts("  Min batch size: #{Config.get([:streaming, :min_batch_size], 1)}")
    IO.puts("  Max batch size: #{Config.get([:streaming, :max_batch_size], 10)}")
    IO.puts("")
    IO.puts("**Recovery:**")
    IO.puts("  Enable recovery: #{Config.get([:streaming, :enable_recovery], true)}")
    IO.puts("  Recovery strategy: #{Config.get([:streaming, :recovery_strategy], :paragraph)}")
    IO.puts("  Recovery storage: #{Config.get([:streaming, :recovery_storage], :memory)}")
    IO.puts("  Recovery TTL: #{Config.get([:streaming, :recovery_ttl], 3_600)}s")
    IO.puts("  Checkpoint interval: #{Config.get([:streaming, :recovery_checkpoint_interval], 10)} chunks")
    IO.puts("")
    IO.puts("**Debug:**")
    IO.puts("  Track metrics: #{Config.get([:streaming, :track_metrics], false)}")
    IO.puts("  Log metrics: #{Config.get([:debug, :log_streaming_metrics], false)}")
  end

  defp show_streaming_metrics do
    IO.puts("## Streaming Metrics")
    IO.puts("")
    IO.puts("ExLLM provides comprehensive streaming metrics including:")
    IO.puts("- Chunks per second throughput")
    IO.puts("- Buffer utilization and backpressure events")
    IO.puts("- Batch efficiency and adaptive sizing")
    IO.puts("- Recovery checkpoint performance")
    IO.puts("- Consumer latency and error rates")
    IO.puts("")
    IO.puts("To enable metrics tracking, add to your config.toml:")
    IO.puts("  [streaming]")
    IO.puts("  track_metrics = true")
    IO.puts("")
    IO.puts("  [debug]")
    IO.puts("  log_streaming_metrics = true")
    IO.puts("")
    IO.puts("Metrics will be logged during streaming responses when enabled.")
  end

  defp handle_cache_management(args) do
    case args do
      [] ->
        show_cache_help()

      ["stats"] ->
        show_cache_stats()

      ["clear"] ->
        clear_cache()

      ["enable"] ->
        enable_cache()

      ["disable"] ->
        disable_cache()

      ["persist", "enable"] ->
        enable_disk_persistence()

      ["persist", "disable"] ->
        disable_disk_persistence()

      _ ->
        IO.puts("Invalid cache command. Use: /cache [stats|clear|enable|disable|persist enable|persist disable]")
    end
  end

  defp show_cache_help do
    IO.puts("## Cache Management")
    IO.puts("")
    IO.puts("Available commands:")
    IO.puts("  /cache stats            - Show cache statistics")
    IO.puts("  /cache clear            - Clear all cached responses")
    IO.puts("  /cache enable           - Enable response caching")
    IO.puts("  /cache disable          - Disable response caching")
    IO.puts("  /cache persist enable   - Enable disk persistence for cache")
    IO.puts("  /cache persist disable  - Disable disk persistence")
    IO.puts("")
    IO.puts("Response caching speeds up development by storing LLM responses")
    IO.puts("locally. Disk persistence saves responses for testing/debugging.")
  end

  defp show_cache_stats do
    IO.puts("## Cache Statistics")
    IO.puts("")

    # Get cache configuration
    caching_config = MCPChat.Config.get([:caching], %{})
    cache_enabled = ExLLMAdapter.get_cache_stats()

    IO.puts("**Configuration:**")
    IO.puts("  Caching enabled: #{Map.get(caching_config, :enabled, false)}")
    IO.puts("  Auto-enable in dev: #{Map.get(caching_config, :auto_enable_dev, true)}")
    IO.puts("  TTL minutes: #{Map.get(caching_config, :ttl_minutes, 15)}")
    IO.puts("  Disk persistence: #{Map.get(caching_config, :persist_disk, false)}")

    if cache_dir = Map.get(caching_config, :cache_dir) do
      IO.puts("  Cache directory: #{cache_dir}")
    end

    IO.puts("")
    IO.puts("**Runtime Statistics:**")

    case cache_enabled do
      %{} = stats ->
        IO.puts("  Cache hits: #{Map.get(stats, :hits, 0)}")
        IO.puts("  Cache misses: #{Map.get(stats, :misses, 0)}")
        IO.puts("  Cache evictions: #{Map.get(stats, :evictions, 0)}")
        IO.puts("  Cache errors: #{Map.get(stats, :errors, 0)}")

        total_requests = Map.get(stats, :hits, 0) + Map.get(stats, :misses, 0)

        if total_requests > 0 do
          hit_rate = Map.get(stats, :hits, 0) / total_requests * 100
          IO.puts("  Hit rate: #{Float.round(hit_rate, 1)}%")
        end

      _ ->
        IO.puts("  Cache not available or not running")
    end

    # Check if we're in development mode
    dev_mode =
      try do
        Mix.env() == :dev
      rescue
        _ -> false
      end

    if dev_mode do
      IO.puts("")
      IO.puts("**Development Mode Detected**")
      IO.puts("Consider enabling caching to speed up repeated requests:")
      IO.puts("  /cache enable")
    end
  end

  defp clear_cache do
    case ExLLMAdapter.clear_cache() do
      :ok ->
        IO.puts("✅ Cache cleared successfully")

      _ ->
        IO.puts("❌ Failed to clear cache")
    end
  end

  defp enable_cache do
    MCPChat.Config.put([:caching, :enabled], true)
    IO.puts("✅ Response caching enabled")
    IO.puts("Note: This setting is for the current session only.")
    IO.puts("To enable permanently, update your config.toml:")
    IO.puts("  [caching]")
    IO.puts("  enabled = true")
  end

  defp disable_cache do
    MCPChat.Config.put([:caching, :enabled], false)
    IO.puts("✅ Response caching disabled")
    IO.puts("Note: This setting is for the current session only.")
  end

  defp enable_disk_persistence do
    MCPChat.Config.put([:caching, :persist_disk], true)
    ExLLMAdapter.configure_cache_persistence(true)
    IO.puts("✅ Disk persistence enabled")
    IO.puts("Cached responses will be saved to disk for testing/debugging.")
    IO.puts("Note: This setting is for the current session only.")
  end

  defp disable_disk_persistence do
    MCPChat.Config.put([:caching, :persist_disk], false)
    ExLLMAdapter.configure_cache_persistence(false)
    IO.puts("✅ Disk persistence disabled")
    IO.puts("Note: This setting is for the current session only.")
  end

  # Cost calculation is now handled by ExLLM with accurate pricing data
end
