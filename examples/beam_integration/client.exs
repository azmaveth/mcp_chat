#!/usr/bin/env elixir
# Run with: iex -S mix run examples/beam_integration/client.exs

defmodule BeamIntegration.Client do
  @moduledoc """
  Example client that connects to the agent system via BEAM messages.
  """
  
  def connect_to_agent(agent_name) do
    case Process.whereis(agent_name) do
      nil ->
        IO.puts("Agent #{agent_name} not found. Available agents:")
        Node.list() |> IO.inspect()
        {:error, :not_found}
      
      pid ->
        IO.puts("Connected to agent #{inspect(agent_name)} at #{inspect(pid)}")
        {:ok, agent_name}
    end
  end
  
  def send_query(agent, prompt) do
    IO.puts("\n📤 Sending query to #{agent}...")
    BeamIntegration.AgentServer.query_async(agent, prompt, self())
    
    receive do
      {:mcp_response, _id, {:ok, response}} ->
        IO.puts("\n📥 Response received:")
        IO.puts(response)
        {:ok, response}
      
      {:mcp_response, _id, {:error, reason}} ->
        IO.puts("\n❌ Error: #{inspect(reason)}")
        {:error, reason}
    after
      30_000 ->
        IO.puts("\n⏱️  Timeout waiting for response")
        {:error, :timeout}
    end
  end
  
  def interactive_session(agent \\ :researcher) do
    IO.puts("""
    
    🤖 Interactive MCP Chat Client
    Agent: #{agent}
    Type 'exit' to quit, 'switch <agent>' to change agents
    
    """)
    
    loop(agent)
  end
  
  defp loop(agent) do
    prompt = IO.gets("You: ") |> String.trim()
    
    case prompt do
      "exit" ->
        IO.puts("Goodbye! 👋")
        :ok
      
      "switch " <> new_agent ->
        agent_atom = String.to_atom(new_agent)
        if Process.whereis(agent_atom) do
          IO.puts("Switched to agent: #{agent_atom}")
          loop(agent_atom)
        else
          IO.puts("Unknown agent: #{new_agent}")
          loop(agent)
        end
      
      "" ->
        loop(agent)
      
      _ ->
        case send_query(agent, prompt) do
          {:ok, _response} -> loop(agent)
          {:error, _reason} -> loop(agent)
        end
    end
  end
  
  def demo_parallel_queries() do
    IO.puts("\n🎯 Parallel Query Demo\n")
    
    queries = [
      {:researcher, "What are the SOLID principles in software design?"},
      {:coder, "Show me an example of the Single Responsibility Principle in Elixir"},
      {:reviewer, "What are common code smells to look for in functional programming?"}
    ]
    
    # Send all queries in parallel
    tasks = Enum.map(queries, fn {agent, prompt} ->
      Task.async(fn ->
        {agent, BeamIntegration.AgentServer.query(agent, prompt)}
      end)
    end)
    
    # Collect results
    results = Task.await_many(tasks, 60_000)
    
    # Display results
    Enum.each(results, fn {agent, result} ->
      case result do
        {:ok, response} ->
          IO.puts("\n#{agent} response:")
          IO.puts(response)
          IO.puts("\n" <> String.duplicate("-", 60))
        
        {:error, reason} ->
          IO.puts("\n#{agent} error: #{inspect(reason)}")
      end
    end)
  end
  
  def demo_context_sharing() do
    IO.puts("\n📚 Context Sharing Demo\n")
    
    # Add a file to the researcher's context
    file_content = """
    # Project Requirements
    - Build a real-time chat system
    - Support multiple users
    - Include message history
    - Add user authentication
    """
    
    # Create a temporary file
    tmp_file = Path.join(System.tmp_dir!(), "requirements.md")
    File.write!(tmp_file, file_content)
    
    # Add to context
    BeamIntegration.AgentServer.add_context_file(:researcher, tmp_file)
    IO.puts("✓ Added requirements.md to researcher's context")
    
    # Query with context
    response = BeamIntegration.AgentServer.query(
      :researcher, 
      "Based on the project requirements, what technologies would you recommend?"
    )
    
    case response do
      {:ok, text} ->
        IO.puts("\nResearcher's recommendation:")
        IO.puts(text)
      
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
    
    # Clean up
    File.rm(tmp_file)
  end
end

# Show available demos when loaded
if Code.ensure_loaded?(IEx) && IEx.started?() do
  IO.puts("""
  
  🎮 MCP Chat BEAM Client Loaded!
  
  Available functions:
  - BeamIntegration.Client.interactive_session()
  - BeamIntegration.Client.demo_parallel_queries()
  - BeamIntegration.Client.demo_context_sharing()
  - BeamIntegration.Client.send_query(:agent_name, "your question")
  
  """)
end