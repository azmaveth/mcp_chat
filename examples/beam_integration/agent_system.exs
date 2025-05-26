#!/usr/bin/env elixir
# Run with: iex -S mix run examples/beam_integration/agent_system.exs

# Load the modules
Code.require_file("agent_server.ex", __DIR__)
Code.require_file("agent_supervisor.ex", __DIR__)
Code.require_file("orchestrator.ex", __DIR__)

defmodule BeamIntegration.Demo do
  @moduledoc """
  Demo module showing BEAM integration with MCP Chat.
  """
  
  def start() do
    IO.puts("\n🚀 Starting MCP Chat Multi-Agent System...\n")
    
    # Start the supervision tree
    {:ok, _sup} = BeamIntegration.AgentSupervisor.start_link()
    {:ok, _orch} = BeamIntegration.Orchestrator.start_link()
    
    IO.puts("✓ Agent Supervisor started")
    IO.puts("✓ Orchestrator started")
    IO.puts("✓ Default agents started: #{inspect(BeamIntegration.AgentSupervisor.list_agents())}\n")
    
    show_menu()
  end
  
  def show_menu() do
    IO.puts("""
    Available Commands:
    
    1. demo_simple()       - Simple agent query
    2. demo_async()        - Async queries with multiple agents  
    3. demo_workflow()     - Execute a multi-agent workflow
    4. demo_broadcast()    - Broadcast query to all agents
    5. add_agent(name)     - Add a new agent
    6. list_agents()       - List all active agents
    7. agent_info(name)    - Get agent information
    
    Example: BeamIntegration.Demo.demo_simple()
    """)
  end
  
  def demo_simple() do
    IO.puts("\n📝 Simple Query Demo\n")
    
    case BeamIntegration.AgentServer.query(:researcher, "What are the key principles of functional programming?") do
      {:ok, response} ->
        IO.puts("Researcher says:\n#{response}\n")
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
  end
  
  def demo_async() do
    IO.puts("\n⚡ Async Query Demo\n")
    
    # Send queries to multiple agents
    agents = [:researcher, :coder, :reviewer]
    prompt = "What makes Elixir great for building concurrent systems?"
    
    Enum.each(agents, fn agent ->
      BeamIntegration.AgentServer.query_async(agent, prompt, self())
      IO.puts("✓ Query sent to #{agent}")
    end)
    
    IO.puts("\nWaiting for responses...\n")
    
    # Collect responses
    collect_responses(length(agents), [])
  end
  
  def demo_workflow() do
    IO.puts("\n🔄 Workflow Demo: Code Review\n")
    
    code = """
    def calculate_total(items) do
      total = 0
      for item <- items do
        total = total + item.price * item.quantity
      end
      total
    end
    """
    
    IO.puts("Code to review:")
    IO.puts(code)
    IO.puts("\nExecuting workflow...\n")
    
    case BeamIntegration.Orchestrator.execute_workflow(:code_review, %{code: code}) do
      {:ok, results} ->
        IO.puts("Workflow completed!\n")
        Enum.with_index(results, 1) |> Enum.each(fn {result, i} ->
          IO.puts("Step #{i}:\n#{result}\n#{String.duplicate("-", 60)}\n")
        end)
      
      {:error, reason} ->
        IO.puts("Workflow failed: #{inspect(reason)}")
    end
  end
  
  def demo_broadcast() do
    IO.puts("\n📢 Broadcast Demo\n")
    
    prompt = "In one sentence, what is your primary strength as an AI assistant?"
    agents = BeamIntegration.AgentSupervisor.list_agents()
    
    IO.puts("Broadcasting to #{length(agents)} agents: #{prompt}\n")
    
    # Send to all agents
    Enum.each(agents, fn agent ->
      BeamIntegration.AgentServer.query_async(agent, prompt, self())
    end)
    
    # Collect and display responses
    collect_responses(length(agents), [])
  end
  
  def add_agent(name, opts \\ []) do
    backend = Keyword.get(opts, :backend, "ollama")
    model = Keyword.get(opts, :model, "llama3.2:3b")
    
    case BeamIntegration.AgentSupervisor.start_agent(name, backend: backend, model: model) do
      {:ok, _pid} ->
        IO.puts("✓ Agent #{name} started with #{backend}/#{model}")
      {:error, reason} ->
        IO.puts("✗ Failed to start agent: #{inspect(reason)}")
    end
  end
  
  def list_agents() do
    agents = BeamIntegration.AgentSupervisor.list_agents()
    IO.puts("\nActive Agents: #{inspect(agents)}")
    agents
  end
  
  def agent_info(name) do
    case BeamIntegration.AgentServer.get_state(name) do
      info when is_map(info) ->
        IO.puts("""
        
        Agent: #{name}
        Backend: #{info.backend}
        Model: #{info.model}
        Messages: #{info.message_count}
        Pending: #{info.pending_queries}
        """)
      
      error ->
        IO.puts("Error getting agent info: #{inspect(error)}")
    end
  end
  
  # Private helpers
  
  defp collect_responses(0, results) do
    IO.puts("\nAll responses received!\n")
    Enum.reverse(results)
  end
  
  defp collect_responses(remaining, results) do
    receive do
      {:mcp_response, _id, {:ok, response}} ->
        IO.puts("Response received:\n#{response}\n#{String.duplicate("-", 60)}\n")
        collect_responses(remaining - 1, [response | results])
      
      {:mcp_response, _id, {:error, reason}} ->
        IO.puts("Error received: #{inspect(reason)}\n")
        collect_responses(remaining - 1, results)
    after
      30_000 ->
        IO.puts("Timeout waiting for responses")
        Enum.reverse(results)
    end
  end
end

# Auto-start if running in IEx
if Code.ensure_loaded?(IEx) && IEx.started?() do
  BeamIntegration.Demo.start()
end