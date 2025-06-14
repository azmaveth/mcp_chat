defmodule McpChat.MixProject do
  use Mix.Project

  def project do
    [
      app: :mcp_chat,
      version: "0.2.1",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      escript: [
        main_module: MCPChat,
        embed_elixir: true,
        applications: [:ex_llm, :ex_mcp, :ex_alias, :ex_readline, :owl, :toml]
      ],
      releases: [
        mcp_chat: [
          steps: [:assemble, &copy_launch_script/1],
          applications: [runtime_tools: :permanent]
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {MCPChat.Application, []}
    ]
  end

  # Specify compilation paths
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Copy launch script to release
  defp copy_launch_script(release) do
    launch_script = """
    #!/bin/sh
    cd "$(dirname "$0")"
    exec ./bin/mcp_chat eval "MCPChat.main()"
    """

    script_path = Path.join(release.path, "mcp_chat.sh")
    File.write!(script_path, launch_script)
    File.chmod!(script_path, 0o755)

    release
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Extracted libraries
      {:ex_mcp, path: "../ex_mcp"},
      {:ex_llm, path: "../ex_llm"},
      {:ex_alias, path: "../ex_alias"},
      {:ex_readline, path: "../ex_readline"},

      # CLI interface
      {:owl, "~> 0.12"},

      # Configuration
      {:toml, "~> 0.7"},

      # Development dependencies
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:meck, "~> 0.9", only: :test}
    ]
  end
end
