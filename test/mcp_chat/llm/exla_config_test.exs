defmodule MCPChat.LLM.EXLAConfigTest do
  use ExUnit.Case
  alias MCPChat.LLM.EXLAConfig

  describe "configure_backend/0" do
    test "configures appropriate backend" do
      result = EXLAConfig.configure_backend()
      assert {:ok, backend} = result
      assert backend in [:emlx, :binary] or is_map(backend)
    end
  end

  describe "serving_options/0" do
    test "returns serving options with compiler settings" do
      options = EXLAConfig.serving_options()
      assert is_list(options)
      assert Keyword.has_key?(options, :compile)
      assert Keyword.has_key?(options, :defn_options)

      compile_opts = Keyword.get(options, :compile)
      assert Keyword.has_key?(compile_opts, :batch_size)
      assert Keyword.has_key?(compile_opts, :sequence_length)
    end
  end

  describe "determine_backend_options/0" do
    test "returns backend options map" do
      options = EXLAConfig.determine_backend_options()
      assert is_map(options)
      assert Map.has_key?(options, :client)

      # Should have appropriate client type
      assert options.client in [:cuda, :rocm, :metal, :host]
    end
  end

  describe "acceleration_info/0" do
    test "returns acceleration info map" do
      info = EXLAConfig.acceleration_info()
      assert is_map(info)
      assert Map.has_key?(info, :type)
      assert Map.has_key?(info, :name)
      assert Map.has_key?(info, :backend)

      assert info.type in [:cuda, :rocm, :metal, :cpu]
    end
  end

  describe "enable_mixed_precision/0" do
    test "enables mixed precision without error" do
      assert :ok = EXLAConfig.enable_mixed_precision()
    end
  end

  describe "optimize_memory/0" do
    test "optimizes memory settings without error" do
      assert :ok = EXLAConfig.optimize_memory()
    end
  end
end
