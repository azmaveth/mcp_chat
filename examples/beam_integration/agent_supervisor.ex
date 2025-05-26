defmodule BeamIntegration.AgentSupervisor do
  @moduledoc """
  Supervises multiple MCP Chat agents for a multi-agent system.
  """
  use Supervisor
  
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def start_agent(name, config \\ []) do
    spec = %{
      id: name,
      start: {BeamIntegration.AgentServer, :start_link, [[name: name] ++ config]},
      restart: :permanent,
      type: :worker
    }
    
    Supervisor.start_child(__MODULE__, spec)
  end
  
  def stop_agent(name) do
    Supervisor.terminate_child(__MODULE__, name)
    Supervisor.delete_child(__MODULE__, name)
  end
  
  def list_agents() do
    __MODULE__
    |> Supervisor.which_children()
    |> Enum.map(fn {id, _pid, _type, _modules} -> id end)
  end
  
  @impl true
  def init(opts) do
    # Define initial agents to start
    initial_agents = Keyword.get(opts, :agents, [
      {:researcher, [backend: "anthropic", model: "claude-3-5-haiku-latest"]},
      {:coder, [backend: "anthropic", model: "claude-3-5-sonnet-latest"]},
      {:reviewer, [backend: "ollama", model: "llama3.2:3b"]}
    ])
    
    children = 
      Enum.map(initial_agents, fn {name, config} ->
        %{
          id: name,
          start: {BeamIntegration.AgentServer, :start_link, [[name: name] ++ config]}
        }
      end)
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end