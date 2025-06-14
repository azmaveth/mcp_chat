#!/usr/bin/env elixir
# Portable MCP Chat launcher using Mix.install

Mix.install([
  {:mcp_chat, path: __DIR__},
  {:ex_mcp, path: Path.join(__DIR__, "../ex_mcp")},
  {:ex_llm, path: Path.join(__DIR__, "../ex_llm")},
  {:ex_alias, path: Path.join(__DIR__, "../ex_alias")},
  {:ex_readline, path: Path.join(__DIR__, "../ex_readline")},
  {:owl, "~> 0.12"},
  {:toml, "~> 0.7"}
])

# Start the application
Application.ensure_all_started(:mcp_chat)

# Run main
MCPChat.main()