defmodule MCPChat.CLI.Commands.MCPExtended do
  @moduledoc """
  Extended MCP commands that leverage new ex_mcp v0.2.0 features:
  - /mcp sample - Server-side LLM generation
  - /mcp progress - Show active operations
  - /mcp notify - Control notifications
  - /mcp capabilities - Detailed server capabilities
  """

  alias MCPChat.{Config, CLI.Renderer}
  alias MCPChat.MCP.{ServerManager, ProgressTracker, NotificationRegistry}

  @doc """
  Handles the /mcp sample command for server-side LLM generation.
  """
  def handle_sample(args) do
    case args do
      [] ->
        show_sample_usage()

      [server_name | rest] ->
        handle_server_sample(server_name, rest)
    end
  end

  defp show_sample_usage() do
    Renderer.show_error("Usage: /mcp sample <server> <prompt> [--temperature 0.7] [--max-tokens 1_000]")
  end

  defp handle_server_sample(server_name, rest) do
    prompt = parse_prompt_and_options(rest)

    case get_server_client(server_name) do
      {:ok, client} ->
        handle_client_sampling(client, server_name, prompt)

      {:error, reason} ->
        Renderer.show_error("Failed to connect to server: #{reason}")
    end
  end

  defp handle_client_sampling(client, server_name, prompt) do
    case check_sampling_capability(client) do
      :ok ->
        execute_sampling(client, server_name, prompt)

      {:error, reason} ->
        Renderer.show_error(reason)
    end
  end

  @doc """
  Handles the /mcp progress command to show active operations.
  """
  def handle_progress(_args) do
    operations = ProgressTracker.list_operations()

    if operations == [] do
      Renderer.show_info("No active operations")
    else
      Renderer.show_info("Active Operations:")
      Renderer.show_divider()

      Enum.each(operations, fn op ->
        show_operation_status(op)
      end)
    end
  end

  @doc """
  Handles the /mcp notify command to control notifications.
  """
  def handle_notify(args) do
    case args do
      ["on"] ->
        enable_notifications()
        Renderer.show_success("Notifications enabled")

      ["off"] ->
        disable_notifications()
        Renderer.show_success("Notifications disabled")

      ["status"] ->
        show_notification_status()

      _ ->
        Renderer.show_error("Usage: /mcp notify <on|off|status>")
    end
  end

  @doc """
  Handles the /mcp capabilities command for detailed server info.
  """
  def handle_capabilities(args) do
    case args do
      [] ->
        show_all_server_capabilities()

      [server_name] ->
        show_server_capabilities(server_name)

      _ ->
        Renderer.show_error("Usage: /mcp capabilities [server_name]")
    end
  end

  defp show_all_server_capabilities() do
    case ServerManager.list_servers() do
      [] ->
        Renderer.show_info("No connected servers")

      servers ->
        Enum.each(servers, &show_capabilities_for_server/1)
    end
  end

  defp show_capabilities_for_server(server) do
    case extract_server_name(server) do
      {:ok, server_name} ->
        show_server_capabilities(server_name)

      {:error, _reason} ->
        Renderer.show_info("Capabilities not available for server: #{inspect(server)}")
    end
  end

  defp extract_server_name(server) do
    cond do
      is_binary(server) ->
        {:ok, server}

      is_map(server) ->
        extract_server_name_from_map(server)

      true ->
        {:error, :invalid_server_format}
    end
  end

  defp extract_server_name_from_map(server) do
    name =
      Map.get(server, :name) || Map.get(server, "name") ||
        Map.get(server, :server_name) || Map.get(server, "server_name")

    if name && is_binary(name) do
      {:ok, name}
    else
      {:error, :no_valid_name}
    end
  end

  # Private Functions

  defp parse_prompt_and_options(args) do
    # Simple parser - could be enhanced
    {options, prompt_parts} =
      Enum.split_with(args, fn arg ->
        String.starts_with?(arg, "--")
      end)

    prompt = Enum.join(prompt_parts, " ")

    params = %{
      messages: [
        %{
          role: "user",
          content: %{
            type: "text",
            text: prompt
          }
        }
      ],
      includeContext: "none"
    }

    # Parse options
    params =
      options
      |> Enum.chunk_every(2)
      |> Enum.reduce(params, fn
        ["--temperature", value], acc ->
          Map.put(acc, :temperature, String.to_float(value))

        ["--max-tokens", value], acc ->
          Map.put(acc, :maxTokens, String.to_integer(value))

        ["--model", value], acc ->
          Map.put(acc, :modelPreferences, %{hints: [%{name: value}]})

        _, acc ->
          acc
      end)

    params
  end

  defp get_server_client(server_name) do
    case ServerManager.get_server(server_name) do
      {:ok, %{client: client}} -> {:ok, client}
      error -> error
    end
  end

  defp check_sampling_capability(client) do
    case MCPChat.MCP.NotificationClient.server_capabilities(client) do
      {:ok, %{"sampling" => _}} -> :ok
      _ -> {:error, "Server does not support sampling/createMessage"}
    end
  end

  defp execute_sampling(client, server_name, params) do
    Renderer.show_info("🤖 Requesting generation from #{server_name}...")

    case MCPChat.MCP.NotificationClient.create_message(client, params) do
      {:ok, result} ->
        show_sampling_result(result, server_name)

      {:error, reason} ->
        Renderer.show_error("Sampling failed: #{inspect(reason)}")
    end
  end

  defp show_sampling_result(result, server_name) do
    Renderer.show_divider()
    Renderer.show_info("Response from #{server_name}:")

    content = get_in(result, ["content", "text"]) || "No content"
    Renderer.show_markdown(content)

    # Show model info if available
    if model = get_in(result, ["model"]) do
      Renderer.show_info("Model: #{model}")
    end

    # Show stop reason if available
    if reason = get_in(result, ["stopReason"]) do
      Renderer.show_info("Stop reason: #{reason}")
    end
  end

  defp show_operation_status(op) do
    progress_bar =
      if op.total do
        percentage = round(op.progress / op.total * 100)
        bar_width = 20
        filled = round(bar_width * op.progress / op.total)
        empty = bar_width - filled

        bar = String.duplicate("█", filled) <> String.duplicate("░", empty)
        "[#{bar}] #{percentage}%"
      else
        "#{op.progress} items processed"
      end

    duration = DateTime.diff(DateTime.utc_now(), op.started_at)

    Renderer.show_info("""
    📊 #{op.server}/#{op.tool} (#{op.token})
       Progress: #{progress_bar}
       Duration: #{format_duration(duration)}
    """)
  end

  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}m #{secs}s"
  end

  defp enable_notifications() do
    # Register default handlers
    NotificationRegistry.register_handler(
      MCPChat.MCP.Handlers.ResourceChangeHandler,
      [:resources_list_changed, :resources_updated]
    )

    NotificationRegistry.register_handler(
      MCPChat.MCP.Handlers.ToolChangeHandler,
      [:tools_list_changed]
    )

    NotificationRegistry.register_handler(
      MCPChat.MCP.Handlers.ProgressHandler,
      [:progress],
      progress_tracker_pid: Process.whereis(ProgressTracker)
    )

    # Save preference
    Config.set_runtime("notifications.enabled", true)
  end

  defp disable_notifications() do
    # Unregister all handlers
    NotificationRegistry.unregister_handler(MCPChat.MCP.Handlers.ResourceChangeHandler)
    NotificationRegistry.unregister_handler(MCPChat.MCP.Handlers.ToolChangeHandler)
    NotificationRegistry.unregister_handler(MCPChat.MCP.Handlers.ProgressHandler)

    # Save preference
    Config.set_runtime("notifications.enabled", false)
  end

  defp show_notification_status() do
    handlers = NotificationRegistry.list_handlers()
    enabled = Config.get_runtime("notifications.enabled", false)

    Renderer.show_info("Notification Status: #{if enabled, do: "ON", else: "OFF"}")

    if map_size(handlers) > 0 do
      Renderer.show_info("Active handlers:")

      Enum.each(handlers, fn {type, handler_list} ->
        Renderer.show_info("  #{type}: #{Enum.join(handler_list, ", ")}")
      end)
    end
  end

  defp show_server_capabilities(server_name) do
    if builtin_server?(server_name) do
      show_builtin_server_message(server_name)
    else
      show_external_server_capabilities(server_name)
    end
  end

  defp builtin_server?(server_name) do
    server_name =~ ~r/built.?in/i or server_name =~ ~r/internal/i
  end

  defp show_builtin_server_message(server_name) do
    Renderer.show_info("Server: #{server_name} (capabilities not available for built-in servers)")
    :ok
  end

  defp show_external_server_capabilities(server_name) do
    case get_server_client(server_name) do
      {:ok, client} ->
        fetch_and_display_capabilities(client, server_name)

      {:error, reason} ->
        Renderer.show_error("Server #{server_name}: #{inspect(reason)}")
    end
  end

  defp fetch_and_display_capabilities(client, server_name) do
    case MCPChat.MCP.NotificationClient.server_capabilities(client) do
      {:ok, capabilities} ->
        display_server_capabilities(server_name, capabilities)

      {:error, reason} ->
        Renderer.show_error("Failed to get capabilities: #{inspect(reason)}")
    end
  end

  defp display_server_capabilities(server_name, capabilities) do
    Renderer.show_divider()
    Renderer.show_info("Server: #{server_name}")
    show_capability_details(capabilities)
  end

  defp show_capability_details(capabilities) do
    show_tools_capability(capabilities)
    show_resources_capability(capabilities)
    show_prompts_capability(capabilities)
    show_logging_capability(capabilities)
    show_sampling_capability(capabilities)
    show_experimental_capabilities(capabilities)
  end

  defp show_tools_capability(capabilities) do
    if Map.get(capabilities, "tools") do
      Renderer.show_info("  Tools: supported")
    end
  end

  defp show_resources_capability(capabilities) do
    if resources = Map.get(capabilities, "resources") do
      features = build_resource_features(resources)
      feature_str = if features != [], do: " (#{Enum.join(features, ", ")})", else: ""
      Renderer.show_info("  Resources: supported#{feature_str}")
    end
  end

  defp build_resource_features(resources) do
    []
    |> maybe_add_feature(get_in(resources, ["subscribe"]), "subscribe")
    |> maybe_add_feature(get_in(resources, ["listChanged"]), "list notifications")
  end

  defp maybe_add_feature(features, true, feature_name), do: [feature_name | features]
  defp maybe_add_feature(features, _, _), do: features

  defp show_prompts_capability(capabilities) do
    if prompts = Map.get(capabilities, "prompts") do
      list_changed = get_in(prompts, ["listChanged"])
      feature_str = if list_changed, do: " (list notifications)", else: ""
      Renderer.show_info("  Prompts: supported#{feature_str}")
    end
  end

  defp show_logging_capability(capabilities) do
    if Map.get(capabilities, "logging") do
      Renderer.show_info("  Logging: supported")
    end
  end

  defp show_sampling_capability(capabilities) do
    if Map.get(capabilities, "sampling") do
      Renderer.show_info("  Sampling/LLM: supported ✨")
    end
  end

  defp show_experimental_capabilities(capabilities) do
    if experimental = Map.get(capabilities, "experimental") do
      Renderer.show_info("  Experimental features:")

      Enum.each(experimental, fn {feature, _details} ->
        Renderer.show_info("    - #{feature}")
      end)
    end
  end
end
