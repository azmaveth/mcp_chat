defmodule MCPChat.LLM.EXLAConfig do
  @moduledoc """
  Configuration module for EXLA backend optimization.
  Provides optimal settings for CPU and GPU inference.
  """

  require Logger

  @doc """
  Configure EXLA backend with optimal settings based on available hardware.
  """
  def configure_backend() do
    if Code.ensure_loaded?(EXLA) do
      backend_opts = determine_backend_options()

      Application.put_env(:nx, :default_backend, {EXLA.Backend, backend_opts})
      Application.put_env(:nx, :default_defn_options, compiler: EXLA, client: backend_opts[:client])

      Logger.info("EXLA backend configured: #{inspect(backend_opts)}")
      {:ok, backend_opts}
    else
      Logger.warn("EXLA not available, falling back to binary backend")
      {:ok, :binary}
    end
  end

  @doc """
  Get optimal compiler options for model serving.
  """
  def serving_options() do
    if Code.ensure_loaded?(EXLA) do
      backend_opts = determine_backend_options()

      [
        compile: [
          batch_size: get_optimal_batch_size(),
          sequence_length: get_optimal_sequence_length()
        ],
        defn_options: [
          compiler: EXLA,
          client: backend_opts[:client]
        ],
        # Enable memory optimization
        preallocate_params: true
      ]
    else
      [
        compile: [
          batch_size: 1,
          sequence_length: 512
        ],
        defn_options: [
          compiler: Nx.BinaryBackend
        ]
      ]
    end
  end

  @doc """
  Determine optimal backend options based on available hardware.
  """
  def determine_backend_options() do
    cond do
      cuda_available?() ->
        %{
          client: :cuda,
          device_id: 0,
          memory_fraction: 0.9,
          preallocate: true
        }

      rocm_available?() ->
        %{
          client: :rocm,
          device_id: 0,
          memory_fraction: 0.9
        }

      metal_available?() ->
        %{
          client: :metal,
          device_id: 0
        }

      true ->
        # CPU optimization
        %{
          client: :host,
          num_replicas: System.schedulers_online(),
          intra_op_parallelism: System.schedulers_online(),
          inter_op_parallelism: 2
        }
    end
  end

  @doc """
  Get information about available acceleration.
  """
  def acceleration_info() do
    cond do
      cuda_available?() ->
        %{
          type: :cuda,
          name: "NVIDIA CUDA",
          device_count: cuda_device_count(),
          memory: cuda_memory_info()
        }

      rocm_available?() ->
        %{
          type: :rocm,
          name: "AMD ROCm",
          device_count: 1
        }

      metal_available?() ->
        %{
          type: :metal,
          name: "Apple Metal",
          device_count: 1
        }

      true ->
        %{
          type: :cpu,
          name: "CPU",
          cores: System.schedulers_online()
        }
    end
  end

  # Private functions

  defp cuda_available? do
    Code.ensure_loaded?(EXLA) and
      System.get_env("CUDA_VISIBLE_DEVICES") != "-1" and
      check_cuda_runtime()
  end

  defp check_cuda_runtime() do
    try do
      {output, 0} = System.cmd("nvidia-smi", ["--query-gpu=name", "--format=csv,noheader"], stderr_to_stdout: true)
      String.trim(output) != ""
    rescue
      _ -> false
    end
  end

  defp cuda_device_count() do
    try do
      {output, 0} = System.cmd("nvidia-smi", ["--query-gpu=count", "--format=csv,noheader"], stderr_to_stdout: true)
      String.to_integer(String.trim(output))
    rescue
      _ -> 0
    end
  end

  defp cuda_memory_info() do
    try do
      {output, 0} =
        System.cmd("nvidia-smi", ["--query-gpu=memory.total", "--format=csv,noheader,nounits"], stderr_to_stdout: true)

      memory_mb = String.to_integer(String.trim(output))
      %{total_mb: memory_mb, total_gb: Float.round(memory_mb / 1_024, 2)}
    rescue
      _ -> %{total_mb: 0, total_gb: 0}
    end
  end

  defp rocm_available? do
    Code.ensure_loaded?(EXLA) and
      System.get_env("ROCM_PATH") != nil and
      File.exists?("/opt/rocm/bin/rocminfo")
  end

  defp metal_available? do
    Code.ensure_loaded?(EXLA) and
      :os.type() == {:unix, :darwin} and
      System.get_env("DISABLE_METAL") != "1"
  end

  defp get_optimal_batch_size() do
    # Adjust based on available memory
    case acceleration_info().type do
      :cuda ->
        memory_gb = cuda_memory_info().total_gb

        cond do
          memory_gb >= 24 -> 8
          memory_gb >= 16 -> 4
          memory_gb >= 8 -> 2
          true -> 1
        end

      :metal ->
        2

      _ ->
        1
    end
  end

  defp get_optimal_sequence_length() do
    # Adjust based on model and memory
    case acceleration_info().type do
      :cuda ->
        memory_gb = cuda_memory_info().total_gb

        cond do
          memory_gb >= 24 -> 2048
          memory_gb >= 16 -> 1_536
          memory_gb >= 8 -> 1_024
          true -> 512
        end

      :metal ->
        1_024

      _ ->
        512
    end
  end

  @doc """
  Enable mixed precision training/inference for better performance.
  """
  def enable_mixed_precision() do
    if Code.ensure_loaded?(EXLA) do
      # Enable automatic mixed precision
      Application.put_env(:exla, :mixed_precision, true)
      Application.put_env(:exla, :preferred_dtype, {:f, 16})
      Logger.info("Mixed precision enabled for better performance")
    end
  end

  @doc """
  Optimize memory usage for large models.
  """
  def optimize_memory() do
    if Code.ensure_loaded?(EXLA) do
      # Enable gradient checkpointing and memory optimizations
      Application.put_env(:exla, :allocator, :best_fit)
      Application.put_env(:exla, :memory_fraction, 0.9)
      Logger.info("Memory optimizations enabled")
    end
  end
end

