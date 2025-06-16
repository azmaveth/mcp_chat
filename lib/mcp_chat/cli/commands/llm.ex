defmodule MCPChat.CLI.Commands.LLM do
  @moduledoc """
  LLM-related CLI commands.

  Handles commands for managing language models including:
  - Backend switching
  - Model selection
  - Model listing
  - Local model management
  - Hardware acceleration info
  """

  use MCPChat.CLI.Commands.Base

  require Logger

  alias MCPChat.CLI.Renderer
  alias MCPChat.LLM.ExLLMAdapter
  alias MCPChat.Session

  @impl true
  def commands do
    %{
      "backend" => "Switch LLM backend (usage: /backend <name>)",
      "model" => "Model management (usage: /model <subcommand> [args])",
      "models" => "List available models for current backend",
      "loadmodel" => "Load a local model (usage: /loadmodel <model-id|path>)",
      "unloadmodel" => "Unload a local model (usage: /unloadmodel <model-id>)",
      "acceleration" => "Show hardware acceleration info"
    }
  end

  @impl true
  def handle_command("backend", args) do
    switch_backend(args)
  end

  def handle_command("model", args) do
    handle_model_subcommand(args)
  end

  def handle_command("models", _args) do
    list_models()
  end

  def handle_command("loadmodel", args) do
    load_model(args)
  end

  def handle_command("unloadmodel", args) do
    unload_model(args)
  end

  def handle_command("acceleration", _args) do
    show_acceleration_info()
  end

  def handle_command(cmd, _args) do
    {:error, "Unknown LLM command: #{cmd}"}
  end

  # Model subcommand handling

  defp handle_model_subcommand([]) do
    show_model_help()
  end

  defp handle_model_subcommand([subcommand | args]) do
    subcommand_handlers = %{
      "switch" => fn -> switch_model(args) end,
      "list" => fn -> list_models() end,
      "capabilities" => fn -> show_capabilities(args) end,
      "recommend" => fn -> recommend_models(args) end,
      "features" => fn -> list_features() end,
      "compare" => fn -> compare_models(args) end,
      "info" => fn -> show_current_model_info() end,
      "help" => fn -> show_model_help() end
    }

    case Map.get(subcommand_handlers, subcommand) do
      nil ->
        # If no subcommand matches, treat as model name for backward compatibility
        switch_model([subcommand | args])

      handler ->
        handler.()
    end
  end

  defp show_model_help do
    show_info("Model management commands:")
    show_info("")
    show_info("  /model <name>           - Switch to a specific model")
    show_info("  /model switch <name>    - Switch to a specific model")
    show_info("  /model list             - List available models")
    show_info("  /model info             - Show current model information")
    show_info("  /model capabilities [model] - Show model capabilities")
    show_info("  /model recommend [features] - Get model recommendations")
    show_info("  /model features         - List all available features")
    show_info("  /model compare <model1> <model2> [...] - Compare models")
    show_info("  /model help             - Show this help")
    show_info("")
    show_info("Examples:")
    show_info("  /model gpt-4")
    show_info("  /model capabilities claude-3-opus-20240229")
    show_info("  /model recommend streaming vision")
    show_info("  /model compare gpt-4 claude-3-sonnet-20240229")
    :ok
  end

  # Command implementations

  defp switch_backend(args) do
    available_backends = ["anthropic", "openai", "ollama", "local", "bedrock", "gemini"]

    case args do
      [] -> show_current_backend_info(available_backends)
      [backend | _] -> attempt_backend_switch(backend, available_backends)
    end
  end

  defp show_current_backend_info(available_backends) do
    current = get_current_backend()
    show_info("Current backend: #{current}")
    show_info("Available backends: #{Enum.join(available_backends, ", ")}")
    :ok
  end

  defp attempt_backend_switch(backend, available_backends) do
    if backend in available_backends do
      execute_backend_switch(backend)
    else
      show_error("Unknown backend: #{backend}")
      show_info("Available backends: #{Enum.join(available_backends, ", ")}")
      :ok
    end
  end

  defp execute_backend_switch(backend) do
    adapter = get_adapter_module(backend)

    if adapter_configured?(adapter, backend) do
      complete_backend_switch(backend, adapter)
    else
      show_configuration_error(backend)
    end
  end

  defp adapter_configured?(adapter, backend) do
    adapter && function_exported?(adapter, :configured?, 1) && adapter.configured?(backend)
  end

  defp complete_backend_switch(backend, adapter) do
    Session.update_session(%{llm_backend: backend})
    show_success("Switched to #{backend} backend")
    show_available_models(adapter, backend)
  end

  defp show_available_models(adapter, backend) do
    case get_models_for_backend(adapter, backend) do
      {:ok, models} when is_list(models) and length(models) > 0 ->
        show_info("Available models: #{format_model_list(models)}")

      _ ->
        :ok
    end

    :ok
  end

  defp get_models_for_backend(adapter, backend) do
    if adapter && function_exported?(adapter, :list_models, 1) do
      adapter.list_models([{:provider, String.to_atom(backend)}])
    else
      {:error, :not_supported}
    end
  end

  defp show_configuration_error(backend) do
    show_error("#{backend} backend is not configured. Please check your configuration.")
    :ok
  end

  defp switch_model(args) do
    case args do
      [] ->
        show_error("Usage: /model switch <name> or /model <name>")
        show_info("Use '/model info' to see current model or '/model list' to see available models")
        :ok

      _ ->
        # Switch to specified model
        model = parse_args(args)
        Session.update_session(%{model: model})
        {backend, _} = get_current_model()
        show_success("Switched to model: #{model} (#{backend})")
        :ok
    end
  end

  defp list_models do
    {backend, current_model} = get_current_model()
    adapter = get_adapter_module(backend)

    show_info("Current backend: #{backend}")
    show_info("Current model: #{current_model}")

    # adapter is always ExLLMAdapter, so we just check if list_models is exported
    if function_exported?(adapter, :list_models, 1) do
      case adapter.list_models([{:provider, String.to_atom(backend)}]) do
        {:ok, models} ->
          show_info("\nAvailable models:")
          display_models(models, backend)

        {:error, reason} ->
          show_error("Failed to list models: #{reason}")
      end
    else
      show_error("Backend #{backend} does not support listing models")
    end
  end

  defp show_current_model_info do
    {backend, current_model} = get_current_model()
    show_info("Current backend: #{backend}")
    show_info("Current model: #{current_model}")
    show_available_models_for_backend(backend)
    :ok
  end

  defp show_available_models_for_backend(backend) do
    adapter = get_adapter_module(backend)

    if function_exported?(adapter, :list_models, 1) do
      try_display_backend_models(adapter, backend)
    end
  end

  defp try_display_backend_models(adapter, backend) do
    case adapter.list_models([{:provider, String.to_atom(backend)}]) do
      {:ok, models} ->
        show_info("\nAvailable models for #{backend}:")
        display_models(models, backend)

      _ ->
        :ok
    end
  end

  defp load_model(args) do
    case args do
      [] ->
        show_error("Usage: /loadmodel <model-id|path>")
        fetch_and_display_local_models()

      _ ->
        attempt_model_load(args)
    end
  end

  defp attempt_model_load(args) do
    if local_model_support_available?() do
      perform_model_load(args)
    else
      show_error("Local model support is not available.")
      show_info("To enable local models, add the required dependencies and rebuild.")
    end
  end

  defp perform_model_load(args) do
    model_id = parse_args(args)

    show_info("Loading model: #{model_id}")
    show_info("This may take a while for first-time downloads...")

    case ExLLMAdapter.load_model(model_id) do
      {:ok, info} ->
        show_success("Model loaded: #{info.name}")
        show_info("Parameters: #{format_number(info.parameters, :compact)}")

      {:error, reason} ->
        show_error("Failed to load model: #{inspect(reason)}")
    end
  end

  defp unload_model(args) do
    case args do
      [] ->
        show_unload_usage_and_models()

      _ ->
        attempt_model_unload(args)
    end
  end

  defp show_unload_usage_and_models do
    show_error("Usage: /unloadmodel <model-id>")

    if local_model_support_available?() do
      display_loaded_models()
    else
      show_info("\nLocal model support is not available.")
    end
  end

  defp display_loaded_models do
    models = ExLLMAdapter.list_loaded_models()

    if Enum.empty?(models) do
      show_info("No models currently loaded")
    else
      show_info("Currently loaded models:")
      Enum.each(models, &IO.puts("  • #{&1}"))
    end
  end

  defp attempt_model_unload(args) do
    if local_model_support_available?() do
      perform_model_unload(args)
    else
      show_error("Local model support is not available.")
    end
  end

  defp perform_model_unload(args) do
    model_id = parse_args(args)

    case ExLLMAdapter.unload_model(model_id) do
      :ok ->
        show_success("Model unloaded: #{model_id}")

      {:error, reason} ->
        show_error("Failed to unload model: #{inspect(reason)}")
    end
  end

  defp show_acceleration_info do
    info = ExLLMAdapter.acceleration_info()

    Renderer.show_text("## Hardware Acceleration Info\n")

    IO.puts("Type: #{info.name}")
    IO.puts("Backend: #{info.backend}")

    display_hardware_details(info)
    display_optimization_details(info)

    :ok
  end

  defp display_hardware_details(info) do
    case info.type do
      :cuda ->
        IO.puts("Devices: #{info.device_count}")
        IO.puts("Memory: #{info.memory.total_gb} GB")

      :metal ->
        IO.puts("Memory: #{info.memory.total_gb} GB (unified)")
        # Only show EMLX if it's actually available
        if info.backend == "EMLX" do
          IO.puts("Optimizations: EMLX (Elixir Metal)")
        else
          IO.puts("Hardware: Apple Metal (EMLX not loaded)")
        end

      :cpu ->
        if Map.has_key?(info, :cores) do
          IO.puts("Cores: #{info.cores}")
        else
          IO.puts("Hardware: CPU (no acceleration)")
        end

      _ ->
        :ok
    end
  end

  defp display_optimization_details(info) do
    # Show optimization tips
    IO.puts("\nOptimization Status:")

    case info.backend do
      "EMLX" ->
        IO.puts("  ✓ Apple Silicon optimizations enabled")
        IO.puts("  ✓ Unified memory architecture utilized")
        IO.puts("  ✓ Mixed precision inference available")

      "EXLA" ->
        IO.puts("  ✓ XLA JIT compilation enabled")

        if info.type == :cuda do
          IO.puts("  ✓ CUDA acceleration available")
        end

      "Not available" ->
        IO.puts("  ⚠ No hardware acceleration available")
        IO.puts("  ⚠ Local model support not configured")
        IO.puts("\nTo enable local model support:")
        IO.puts("  1. Add ex_llm local dependencies to your mix.exs")
        IO.puts("  2. Configure hardware acceleration (EMLX, EXLA)")
        IO.puts("  3. Rebuild the application")

      _ ->
        display_generic_optimization_tips(info)
    end
  end

  defp display_generic_optimization_tips(info) do
    # Show more specific guidance based on hardware
    case info.type do
      :metal ->
        IO.puts("  ⚠ Apple Metal detected but EMLX not loaded")
        IO.puts("  Consider adding {:emlx, \"~> 0.5\"} to your mix.exs dependencies")
        IO.puts("  Alternatively, add {:exla, \"~> 0.6\"} for XLA acceleration")

      :cuda ->
        IO.puts("  ⚠ CUDA capable GPU detected but EXLA not loaded")
        IO.puts("  Consider adding {:exla, \"~> 0.6\"} to your mix.exs dependencies")
        IO.puts("  Ensure CUDA toolkit is installed and XLA_TARGET=cuda120 is set")

      _ ->
        IO.puts("  ⚠ No hardware acceleration libraries loaded")
        IO.puts("  Binary backend will be used (slower performance)")
        IO.puts("  Consider installing EXLA for CPU optimizations")
    end
  end

  # Helper functions

  defp get_adapter_module(_backend) do
    # Always use ExLLMAdapter with the provider option
    ExLLMAdapter
  end

  defp format_model_list(models) when is_list(models) do
    case models do
      [] ->
        "none"

      [model] when is_binary(model) ->
        model

      models when length(models) <= 3 ->
        models
        |> Enum.map_join(", ", &extract_model_name/1)

      models ->
        first_three =
          models
          |> Enum.take(3)
          |> Enum.map_join(", ", &extract_model_name/1)

        "#{first_three}, and #{length(models) - 3} more"
    end
  end

  defp extract_model_name(model) when is_binary(model), do: model
  defp extract_model_name(%{name: name}), do: name
  defp extract_model_name(%{id: id}), do: id
  defp extract_model_name(%{"name" => name}), do: name
  defp extract_model_name(%{"id" => id}), do: id
  defp extract_model_name(_), do: "unknown"

  defp display_models(models, _backend) do
    models
    |> Enum.each(fn model ->
      case model do
        %{id: id, name: name} ->
          IO.puts("  • #{id} - #{name}")

        %{id: id} ->
          IO.puts("  • #{id}")

        model when is_binary(model) ->
          IO.puts("  • #{model}")

        _ ->
          :ok
      end
    end)
  end

  defp fetch_and_display_local_models do
    if local_model_support_available?() do
      fetch_and_display_available_models()
    else
      show_local_model_unavailable_message()
    end
  end

  defp show_local_model_unavailable_message do
    show_info("\nLocal model support is not available.")
    show_info("To enable local models:")
    show_info("  1. Add Bumblebee and EXLA/EMLX dependencies to your mix.exs")
    show_info("  2. Configure hardware acceleration")
    show_info("  3. Rebuild the application")
  end

  defp fetch_and_display_available_models do
    case ExLLMAdapter.list_models(provider: :bumblebee) do
      {:ok, models} ->
        display_available_models(models)

      {:error, reason} ->
        Logger.error("Failed to fetch local models: #{inspect(reason)}")
        show_error("Unable to list available models. Local model support may not be configured.")
    end
  end

  defp display_available_models(models) do
    show_info("\nAvailable models to load:")

    models
    |> Enum.sort_by(& &1.id)
    |> Enum.each(fn model ->
      status = if model.status == "loaded", do: " (loaded)", else: ""
      IO.puts("  • #{model.id} - #{model.name}#{status}")
    end)
  end

  defp local_model_support_available? do
    Code.ensure_loaded?(ExLLM.Local.ModelLoader) and
      Process.whereis(ExLLM.Local.ModelLoader) != nil
  end

  # Note: format_number now comes from Display helper

  # Model Capabilities Commands

  defp show_capabilities(args) do
    case args do
      [] ->
        # Show capabilities for current model
        {backend, model} = get_current_model()
        show_model_capabilities(String.to_atom(backend), model)

      [model | _] ->
        # Show capabilities for specified model
        {backend, _} = get_current_model()
        show_model_capabilities(String.to_atom(backend), model)
    end
  end

  defp show_model_capabilities(provider, model_id) do
    case ExLLMAdapter.get_model_capabilities(provider, model_id) do
      {:ok, capabilities} ->
        display_model_capabilities(capabilities, provider)

      {:error, :not_found} ->
        show_error("Model #{model_id} not found for provider #{provider}")

      {:error, reason} ->
        show_error("Failed to get capabilities: #{inspect(reason)}")
    end

    :ok
  end

  defp display_model_capabilities(capabilities, provider) do
    show_basic_model_info(capabilities, provider)
    show_supported_features(capabilities.capabilities)
    show_unsupported_count(capabilities.capabilities)
  end

  defp show_basic_model_info(capabilities, provider) do
    show_info("Model: #{capabilities.display_name} (#{provider})")
    show_info("Context Window: #{format_number(capabilities.context_window, :compact)} tokens")

    if capabilities.max_output_tokens do
      show_info("Max Output: #{format_number(capabilities.max_output_tokens, :compact)} tokens")
    end
  end

  defp show_supported_features(capabilities) do
    show_info("\nSupported Features:")

    capabilities
    |> Enum.filter(fn {_feature, cap} -> cap.supported end)
    |> Enum.sort_by(fn {feature, _cap} -> to_string(feature) end)
    |> Enum.each(&display_feature_capability/1)
  end

  defp display_feature_capability({feature, cap}) do
    feature_name = format_feature_name(feature)

    if cap.details && map_size(cap.details) > 0 do
      show_info("  ✓ #{feature_name} #{format_capability_details(cap.details)}")
    else
      show_info("  ✓ #{feature_name}")
    end
  end

  defp show_unsupported_count(capabilities) do
    unsupported_count =
      capabilities
      |> Enum.filter(fn {_feature, cap} -> not cap.supported end)
      |> length()

    if unsupported_count > 0 do
      show_info("\nUnsupported features: #{unsupported_count}")
    end
  end

  defp recommend_models(args) do
    requirements = parse_recommendation_args(args)

    case ExLLMAdapter.recommend_models(requirements) do
      recommendations when is_list(recommendations) and length(recommendations) > 0 ->
        display_recommendations(recommendations)

      [] ->
        show_no_recommendations()

      {:error, reason} ->
        show_error("Failed to get recommendations: #{inspect(reason)}")
    end

    :ok
  end

  defp display_recommendations(recommendations) do
    show_info("Recommended models based on your requirements:")
    show_info("")

    recommendations
    |> Enum.with_index(1)
    |> Enum.each(&display_single_recommendation/1)
  end

  defp display_single_recommendation({{provider, model_id, %{score: score, info: info}}, index}) do
    show_info("#{index}. #{info.display_name} (#{provider})")
    show_info("   Model: #{model_id}")
    show_info("   Context: #{format_number(info.context_window, :compact)} tokens")

    display_max_output_if_available(info.max_output_tokens)
    show_info("   Score: #{Float.round(score, 1)}")
    display_key_capabilities(info.capabilities)
    show_info("")
  end

  defp display_max_output_if_available(nil), do: :ok

  defp display_max_output_if_available(max_output) do
    show_info("   Max Output: #{format_number(max_output, :compact)} tokens")
  end

  defp display_key_capabilities(capabilities) do
    key_caps = get_key_capabilities(capabilities)

    if length(key_caps) > 0 do
      show_info("   Features: #{Enum.join(key_caps, ", ")}")
    end
  end

  defp show_no_recommendations do
    show_info("No models found matching your requirements.")
    show_info("Try relaxing your constraints or use /features to see available capabilities.")
  end

  defp list_features do
    case ExLLMAdapter.list_model_features() do
      features when is_list(features) ->
        show_info("Available model features:")
        show_info("")

        features
        |> Enum.sort_by(&to_string/1)
        |> Enum.each(fn feature ->
          feature_name = format_feature_name(feature)
          show_info("  • #{feature_name}")
        end)

      {:error, reason} ->
        show_error("Failed to list features: #{inspect(reason)}")
    end

    :ok
  end

  defp compare_models(args) do
    case args do
      [] ->
        show_error("Usage: /compare <model1> <model2> [model3...]")
        show_info("Example: /compare gpt-4 claude-3-opus-20240229")

      models when length(models) < 2 ->
        show_error("At least 2 models are required for comparison")

      models ->
        {backend, _} = get_current_model()
        provider = String.to_atom(backend)

        model_specs = Enum.map(models, fn model -> {provider, model} end)

        case ExLLMAdapter.compare_models(model_specs) do
          %{models: model_list, features: feature_comparison} ->
            show_model_comparison(model_list, feature_comparison)

          %{error: error} ->
            show_error("Comparison failed: #{error}")

          {:error, reason} ->
            show_error("Failed to compare models: #{inspect(reason)}")
        end
    end

    :ok
  end

  defp show_model_comparison(models, features) do
    show_info("Model Comparison:")
    show_info("")

    # Show basic model info
    models
    |> Enum.with_index(1)
    |> Enum.each(fn {model, index} ->
      show_info("#{index}. #{model.display_name} (#{model.provider})")
      show_info("   Context: #{format_number(model.context_window, :compact)} tokens")

      if model.max_output_tokens do
        show_info("   Max Output: #{format_number(model.max_output_tokens, :compact)} tokens")
      end
    end)

    show_info("")
    show_info("Feature Comparison:")

    # Create comparison table
    model_names = Enum.map(models, & &1.display_name)

    features
    |> Enum.filter(fn {_feature, support_list} ->
      # Only show features where at least one model supports it
      Enum.any?(support_list, & &1.supported)
    end)
    |> Enum.sort_by(fn {feature, _} -> to_string(feature) end)
    |> Enum.each(fn {feature, support_list} ->
      feature_name = format_feature_name(feature)

      support_icons =
        Enum.map(support_list, fn
          %{supported: true} -> "✓"
          %{supported: false} -> "✗"
        end)

      show_info("  #{String.pad_trailing(feature_name, 20)} #{Enum.join(support_icons, "  ")}")
    end)

    show_info("")
    show_info("Legend: ✓ = Supported, ✗ = Not supported")
  end

  # Helper functions for capabilities

  defp parse_recommendation_args(args) do
    # Parse args into recommendation requirements
    # For now, return empty requirements - could be extended to parse specific needs
    case args do
      [] -> []
      _ -> [features: parse_feature_list(args)]
    end
  end

  defp parse_feature_list(args) do
    # Convert string args to feature atoms
    args
    |> Enum.map(&String.to_atom/1)
    |> Enum.filter(fn feature ->
      # Only include valid features
      feature in [
        :streaming,
        :function_calling,
        :vision,
        :audio,
        :system_messages,
        :multi_turn,
        :json_mode,
        :structured_output,
        :context_caching
      ]
    end)
  end

  defp format_feature_name(feature) do
    feature
    |> to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(&String.capitalize/1, " ")
  end

  defp format_capability_details(details) when is_map(details) do
    details
    |> Map.to_list()
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{inspect(v)}" end)
    |> then(fn str -> "(#{str})" end)
  end

  defp format_capability_details(_), do: ""

  defp get_key_capabilities(capabilities) do
    key_features = [:streaming, :function_calling, :vision, :system_messages, :json_mode]

    capabilities
    |> Enum.filter(fn {feature, cap} ->
      feature in key_features and cap.supported
    end)
    |> Enum.map(fn {feature, _cap} -> format_feature_name(feature) end)
  end
end
