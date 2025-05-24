defmodule McpChat.MixProject do
  use Mix.Project

  def project do
    [
      app: :mcp_chat,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: [main_module: MCPChat]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {MCPChat.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # MCP and WebSocket support
      {:websockex, "~> 0.4.3"},
      {:jason, "~> 1.4"},

      # CLI interface
      {:owl, "~> 0.12"},

      # HTTP client for LLM APIs
      {:req, "~> 0.5"},

      # Configuration
      {:toml, "~> 0.7"},

      # HTTP server for SSE support
      {:plug, "~> 1.15"},
      {:plug_cowboy, "~> 2.7"},

      # Local model support with Bumblebee
      {:bumblebee, "~> 0.5"},
      {:nx, "~> 0.7"},
      {:exla, "~> 0.9", optional: true},
      {:emlx, "~> 0.1", optional: true},
      {:ortex, "~> 0.1", optional: true},

      # Development dependencies
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:meck, "~> 0.9", only: :test}
    ]
  end
end
