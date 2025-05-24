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

  @impl true
  def commands() do
    %{
      "backend" => "Switch LLM backend (usage: /backend <name>)",
      "model" => "Switch model (usage: /model <name>)",
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
    switch_model(args)
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

  # Command implementations

  defp switch_backend(args) do
    available_backends = ["anthropic", "openai", "ollama", "local", "bedrock", "gemini"]

    case args do
      [] ->
        # Show current backend and available options
        current = get_current_backend()
        show_info("Current backend: #{current}")
        show_info("Available backends: #{Enum.join(available_backends, ", ")}")

      [backend | _] ->
        if backend in available_backends do
          # Get the adapter module
          adapter = get_adapter_module(backend)

          # Check if it's configured
          if adapter && function_exported?(adapter, :configured?, 0) && adapter.configured?() do
            MCPChat.Session.update_session(%{llm_backend: backend})
            show_success("Switched to #{backend} backend")

            # Show available models for this backend
            case adapter && function_exported?(adapter, :list_models, 0) && adapter.list_models() do
              {:ok, models} when is_list(models) and length(models) > 0 ->
                show_info("Available models: #{format_model_list(models)}")

              _ ->
                :ok
            end
          else
            show_error("#{backend} backend is not configured. Please check your configuration.")
          end
        else
          show_error("Unknown backend: #{backend}")
          show_info("Available backends: #{Enum.join(available_backends, ", ")}")
        end
    end
  end

  defp switch_model(args) do
    with {:ok, args} <- require_arg(args, "/model <name>"),
         model <- parse_args(args) do
      MCPChat.Session.update_session(%{model: model})
      {backend, _} = get_current_model()
      show_success("Switched to model: #{model} (#{backend})")
    else
      {:error, msg} -> show_error(msg)
    end
  end

  defp list_models() do
    {backend, current_model} = get_current_model()
    adapter = get_adapter_module(backend)

    show_info("Current backend: #{backend}")
    show_info("Current model: #{current_model}")

    case adapter && function_exported?(adapter, :list_models, 0) && adapter.list_models() do
      {:ok, models} ->
        show_info("\nAvailable models:")
        display_models(models, backend)

      {:error, reason} ->
        show_error("Failed to list models: #{reason}")
    end
  end

  defp load_model(args) do
    case args do
      [] ->
        show_error("Usage: /loadmodel <model-id|path>")
        fetch_and_display_local_models()

      _ ->
        model_id = parse_args(args)

        show_info("Loading model: #{model_id}")
        show_info("This may take a while for first-time downloads...")

        case MCPChat.LLM.ModelLoader.load_model(model_id) do
          {:ok, info} ->
            show_success("Model loaded: #{info.name}")
            show_info("Parameters: #{format_number(info.parameters)}")

          {:error, reason} ->
            show_error("Failed to load model: #{inspect(reason)}")
        end
    end
  end

  defp unload_model(args) do
    case args do
      [] ->
        show_error("Usage: /unloadmodel <model-id>")
        models = MCPChat.LLM.ModelLoader.list_loaded_models()

        if Enum.empty?(models) do
          show_info("No models currently loaded")
        else
          show_info("Currently loaded models:")
          Enum.each(models, &IO.puts("  • #{&1}"))
        end

      _ ->
        model_id = parse_args(args)

        case MCPChat.LLM.ModelLoader.unload_model(model_id) do
          :ok ->
            show_success("Model unloaded: #{model_id}")

          {:error, reason} ->
            show_error("Failed to unload model: #{inspect(reason)}")
        end
    end
  end

  defp show_acceleration_info() do
    info = MCPChat.LLM.EXLAConfig.acceleration_info()

    MCPChat.CLI.Renderer.show_text("## Hardware Acceleration Info\n")

    IO.puts("Type: #{info.name}")
    IO.puts("Backend: #{info.backend}")

    case info.type do
      :cuda ->
        IO.puts("Devices: #{info.device_count}")
        IO.puts("Memory: #{info.memory.total_gb} GB")

      :metal ->
        IO.puts("Memory: #{info.memory.total_gb} GB (unified)")
        IO.puts("Optimizations: EMLX (Elixir Metal)")

      :cpu ->
        IO.puts("Cores: #{info.cores}")

      _ ->
        :ok
    end

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

      _ ->
        IO.puts("  ⚠ No hardware acceleration available")
        IO.puts("  Consider installing EXLA or EMLX for better performance")
    end

    :ok
  end

  # Helper functions

  defp get_adapter_module(backend) do
    case backend do
      "anthropic" -> MCPChat.LLM.Anthropic
      "openai" -> MCPChat.LLM.OpenAI
      "ollama" -> MCPChat.LLM.Ollama
      "local" -> MCPChat.LLM.Local
      "bedrock" -> MCPChat.LLM.Bedrock
      "gemini" -> MCPChat.LLM.Gemini
      _ -> nil
    end
  end

  defp format_model_list(models) when is_list(models) do
    case models do
      [] ->
        "none"

      [model] when is_binary(model) ->
        model

      models when length(models) <= 3 ->
        models
        |> Enum.map_join(&extract_model_name/1, ", ")

      models ->
        first_three =
          models
          |> Enum.take(3)
          |> Enum.map_join(&extract_model_name/1, ", ")

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

  defp fetch_and_display_local_models() do
    case MCPChat.LLM.Local.list_models() do
      {:ok, models} ->
        show_info("\nAvailable models to load:")

        models
        |> Enum.sort_by(& &1.id)
        |> Enum.each(fn model ->
          status = if model.status == "loaded", do: " (loaded)", else: ""
          IO.puts("  • #{model.id} - #{model.name}#{status}")
        end)

      {:error, reason} ->
        Logger.error("Failed to fetch local models: #{inspect(reason)}")
    end
  end

  defp format_number(n) when n >= 1_000_000_000 do
    "#{Float.round(n / 1_000_000_000, 1)}B"
  end

  defp format_number(n) when n >= 1_000_000 do
    "#{Float.round(n / 1_000_000, 1)}M"
  end

  defp format_number(n), do: "#{n}"
end
