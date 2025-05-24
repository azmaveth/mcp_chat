# Agent Tools Example

This example shows how to create MCP tools that enable true agent-to-agent communication.

## Custom MCP Server for Agent Communication

Create `agent_bridge.js`:

```javascript
#!/usr/bin/env node
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import axios from 'axios';

const server = new Server({
  name: 'agent-bridge',
  version: '1.0.0',
}, {
  capabilities: {
    tools: {},
    prompts: {}
  }
});

// Tool to send tasks to other agents
server.setRequestHandler('tools/call', async (request) => {
  const { name, arguments: args } = request.params;
  
  if (name === 'delegate_to_analyst') {
    // Send task to analyst agent via their MCP endpoint
    const response = await axios.post('http://localhost:8081/sse', {
      jsonrpc: '2.0',
      method: 'prompts/get',
      params: {
        name: 'analyze',
        arguments: { task: args.task }
      }
    });
    
    return {
      content: [{
        type: 'text',
        text: `Analyst response: ${response.data.result}`
      }]
    };
  }
  
  if (name === 'delegate_to_writer') {
    const response = await axios.post('http://localhost:8082/sse', {
      jsonrpc: '2.0',
      method: 'prompts/get',
      params: {
        name: 'write',
        arguments: { 
          topic: args.topic,
          style: args.style || 'professional'
        }
      }
    });
    
    return {
      content: [{
        type: 'text',
        text: `Writer response: ${response.data.result}`
      }]
    };
  }
  
  if (name === 'coordinate_task') {
    // Complex coordination between multiple agents
    const { task_description } = args;
    
    // Step 1: Get analysis
    const analysisResponse = await axios.post('http://localhost:8081/sse', {
      jsonrpc: '2.0',
      method: 'prompts/get',
      params: {
        name: 'analyze',
        arguments: { task: task_description }
      }
    });
    
    // Step 2: Based on analysis, get writing
    const writingResponse = await axios.post('http://localhost:8082/sse', {
      jsonrpc: '2.0',
      method: 'prompts/get',
      params: {
        name: 'write',
        arguments: { 
          topic: task_description,
          context: analysisResponse.data.result
        }
      }
    });
    
    return {
      content: [{
        type: 'text',
        text: `Task completed:\n\nAnalysis:\n${analysisResponse.data.result}\n\nContent:\n${writingResponse.data.result}`
      }]
    };
  }
});

// List available tools
server.setRequestHandler('tools/list', async () => {
  return {
    tools: [
      {
        name: 'delegate_to_analyst',
        description: 'Send a task to the Analyst agent',
        inputSchema: {
          type: 'object',
          properties: {
            task: { 
              type: 'string', 
              description: 'Task description for analysis' 
            }
          },
          required: ['task']
        }
      },
      {
        name: 'delegate_to_writer',
        description: 'Send a writing task to the Writer agent',
        inputSchema: {
          type: 'object',
          properties: {
            topic: { 
              type: 'string', 
              description: 'Topic to write about' 
            },
            style: {
              type: 'string',
              description: 'Writing style (professional, casual, technical)',
              enum: ['professional', 'casual', 'technical']
            }
          },
          required: ['topic']
        }
      },
      {
        name: 'coordinate_task',
        description: 'Coordinate a complex task across multiple agents',
        inputSchema: {
          type: 'object',
          properties: {
            task_description: {
              type: 'string',
              description: 'Full description of the task to coordinate'
            }
          },
          required: ['task_description']
        }
      }
    ]
  };
});

// Prompts for agent identity
server.setRequestHandler('prompts/list', async () => {
  return {
    prompts: [
      {
        name: 'orchestrator_prompt',
        description: 'System prompt for the orchestrator agent'
      }
    ]
  };
});

server.setRequestHandler('prompts/get', async (request) => {
  if (request.params.name === 'orchestrator_prompt') {
    return {
      prompt: {
        name: 'orchestrator_prompt',
        arguments: [],
        template: `You are the Orchestrator Agent in a multi-agent system.

Your capabilities:
1. You can delegate analysis tasks to the Analyst agent
2. You can delegate writing tasks to the Writer agent  
3. You can coordinate complex tasks across multiple agents

Your role:
- Understand user requests and break them down
- Delegate appropriately to specialized agents
- Synthesize results from multiple agents
- Provide comprehensive solutions

Available tools:
- delegate_to_analyst: Send analysis tasks
- delegate_to_writer: Send writing tasks
- coordinate_task: Handle complex multi-step tasks

Always explain your delegation strategy before executing.`
      }
    };
  }
});

const transport = new StdioServerTransport();
server.connect(transport);
```

## Elixir-Based Agent Communication

For a pure Elixir solution, create a custom MCP server module:

```elixir
defmodule MCPChat.AgentBridge do
  @moduledoc """
  MCP server that enables agent-to-agent communication
  """
  use GenServer
  
  # MCP Server callbacks
  def handle_mcp_request("tools/list", _params, state) do
    tools = [
      %{
        name: "query_agent",
        description: "Query another MCP Chat agent",
        inputSchema: %{
          type: "object",
          properties: %{
            agent_port: %{type: "integer"},
            prompt: %{type: "string"}
          },
          required: ["agent_port", "prompt"]
        }
      },
      %{
        name: "broadcast_task",
        description: "Send task to all connected agents",
        inputSchema: %{
          type: "object", 
          properties: %{
            task: %{type: "string"}
          },
          required: ["task"]
        }
      }
    ]
    
    {:reply, %{tools: tools}, state}
  end
  
  def handle_mcp_request("tools/call", %{"name" => "query_agent", "arguments" => args}, state) do
    %{"agent_port" => port, "prompt" => prompt} = args
    
    # Connect to the other agent's SSE endpoint
    response = query_agent_sse(port, prompt)
    
    {:reply, %{
      content: [%{
        type: "text",
        text: "Agent response: #{response}"
      }]
    }, state}
  end
  
  defp query_agent_sse(port, prompt) do
    # This would make an HTTP request to the agent's SSE endpoint
    # For now, simulate the response
    "Analysis complete: #{prompt}"
  end
end
```

## Practical Multi-Agent Scenarios

### 1. Research Assistant Team

```bash
# Agent 1: Web Researcher (finds sources)
# Agent 2: Academic Analyst (evaluates credibility)  
# Agent 3: Report Writer (creates summaries)

# User request to Agent 1:
"Research recent breakthroughs in quantum computing"

# Agent 1 automatically:
# - Searches for sources
# - Sends to Agent 2 for credibility analysis
# - Agent 2 sends verified sources to Agent 3
# - Agent 3 writes comprehensive report
# - Result returned to user
```

### 2. Code Development Team

```bash
# Agent 1: Architect (designs system)
# Agent 2: Developer (writes code)
# Agent 3: Tester (writes and runs tests)

# User request to Agent 1:
"Create a REST API for user management"

# Automatic workflow:
# - Architect designs API structure
# - Developer implements based on design
# - Tester creates test suite
# - Iterative refinement between agents
```

### 3. Content Creation Pipeline

```bash
# Agent 1: Ideation (generates ideas)
# Agent 2: Writer (creates content)
# Agent 3: Editor (refines and polishes)

# User request:
"Create a blog post about AI safety"

# Pipeline:
# - Ideation agent brainstorms angles
# - Writer creates draft
# - Editor reviews and suggests improvements
# - Writer revises based on feedback
```

## Running the Examples

1. **Setup the bridge server:**
```bash
npm install @modelcontextprotocol/sdk axios
node agent_bridge.js
```

2. **Configure orchestrator to use bridge:**
```toml
[[mcp.servers]]
name = "bridge"
command = ["node", "/path/to/agent_bridge.js"]
auto_connect = true
```

3. **Start all agents:**
```bash
# Terminal 1
./mcp_chat --config orchestrator.toml

# Terminal 2  
./mcp_chat --config analyst.toml

# Terminal 3
./mcp_chat --config writer.toml
```

4. **Test coordination:**
```
Orchestrator> /tool bridge coordinate_task "Analyze AI trends and write article"
```

## Benefits of This Architecture

1. **Specialization**: Each agent optimized for specific tasks
2. **Cost Efficiency**: Use cheaper models for simple tasks
3. **Parallel Processing**: Agents work simultaneously
4. **Fault Isolation**: One agent failure doesn't affect others
5. **Scalability**: Add new specialized agents easily
6. **Auditability**: Track decision flow between agents