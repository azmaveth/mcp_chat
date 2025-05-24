# Multi-Agent MCP Chat Example

This example demonstrates how to chain multiple MCP Chat instances together to create a multi-agent AI system. Each instance can act as both an MCP client and server, enabling sophisticated agent interactions.

## Architecture Overview

```
┌─────────────────────┐
│   Orchestrator      │ (Port 8080)
│  (Claude Opus 4)    │ MCP Server: Coordination Tools
│ Primary Decision    │ - delegate_task
│      Maker          │ - collect_results
└──────────┬──────────┘ - make_decision
           │
      ┌────┴────┐
      │         │
┌─────▼───────┐ ┌─────▼───────┐
│ Researcher  │ │  Developer  │
│(Claude 3.7) │ │(Claude 3.5) │ 
│ Port 8081   │ │ Port 8082   │
│             │ │             │
│ MCP Tools:  │ │ MCP Tools:  │
│ - search    │ │ - code_gen  │
│ - analyze   │ │ - test      │
│ - summarize │ │ - refactor  │
└─────────────┘ └─────────────┘
```

## Setup Instructions

### 1. Orchestrator Agent (Terminal 1)

Create `~/.config/mcp_chat/orchestrator_config.toml`:

```toml
[llm]
default = "anthropic"

[llm.anthropic]
api_key = "your-key"
model = "claude-opus-4-20250514"
system_prompt = """
You are the Orchestrator Agent in a multi-agent system. Your role is to:
1. Understand user requests and break them down into subtasks
2. Delegate tasks to specialized agents (Researcher and Developer)
3. Collect and synthesize results from other agents
4. Make final decisions based on agent inputs

You have access to MCP tools for coordinating with other agents.
"""

[mcp_server]
sse_enabled = true
sse_port = 8080

[[mcp.servers]]
name = "researcher"
url = "http://localhost:8081/sse"
transport = "sse"

[[mcp.servers]]
name = "developer"  
url = "http://localhost:8082/sse"
transport = "sse"
```

Start the orchestrator:
```bash
cd /path/to/mcp_chat
./mcp_chat --config ~/.config/mcp_chat/orchestrator_config.toml
```

In the orchestrator chat:
```
/alias add research /tool researcher search $1 && /tool researcher analyze $1
/alias add develop /tool developer code_gen $1
/alias add review /tool developer test $1 && /tool developer refactor $1
```

### 2. Researcher Agent (Terminal 2)

Create `~/.config/mcp_chat/researcher_config.toml`:

```toml
[llm]
default = "anthropic"

[llm.anthropic]
api_key = "your-key"
model = "claude-3-7-sonnet-20250219"
system_prompt = """
You are the Researcher Agent. Your expertise includes:
1. Searching for relevant information
2. Analyzing data and documents
3. Summarizing findings
4. Providing research-backed recommendations

When called via MCP tools, provide thorough but concise responses.
Focus on accuracy and cite sources when possible.
"""

[mcp_server]
sse_enabled = true
sse_port = 8081

# Connect to filesystem for document access
[[mcp.servers]]
name = "filesystem"
command = ["npx", "-y", "@modelcontextprotocol/server-filesystem", "/tmp/research"]

# Connect to web search if available
[[mcp.servers]]
name = "websearch"
command = ["npx", "-y", "@modelcontextprotocol/server-websearch"]
```

Create custom MCP tools script `research_tools.js`:
```javascript
#!/usr/bin/env node
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';

const server = new Server({
  name: 'research-tools',
  version: '1.0.0',
}, {
  capabilities: {
    tools: {}
  }
});

// Search tool
server.setRequestHandler('tools/call', async (request) => {
  if (request.params.name === 'search') {
    const query = request.params.arguments.query;
    // Simulate search by delegating to the LLM
    return {
      content: [
        {
          type: 'text',
          text: `Search results for "${query}": [Delegated to LLM for processing]`
        }
      ]
    };
  }
  
  if (request.params.name === 'analyze') {
    const data = request.params.arguments.data;
    return {
      content: [
        {
          type: 'text', 
          text: `Analysis of data: [Delegated to LLM for deep analysis]`
        }
      ]
    };
  }

  if (request.params.name === 'summarize') {
    const content = request.params.arguments.content;
    return {
      content: [
        {
          type: 'text',
          text: `Summary: [Delegated to LLM for summarization]`
        }
      ]
    };
  }
});

// List available tools
server.setRequestHandler('tools/list', async () => {
  return {
    tools: [
      {
        name: 'search',
        description: 'Search for information on a topic',
        inputSchema: {
          type: 'object',
          properties: {
            query: { type: 'string', description: 'Search query' }
          },
          required: ['query']
        }
      },
      {
        name: 'analyze',
        description: 'Analyze data or documents',
        inputSchema: {
          type: 'object',
          properties: {
            data: { type: 'string', description: 'Data to analyze' }
          },
          required: ['data']
        }
      },
      {
        name: 'summarize',
        description: 'Summarize content',
        inputSchema: {
          type: 'object',
          properties: {
            content: { type: 'string', description: 'Content to summarize' }
          },
          required: ['content']
        }
      }
    ]
  };
});

const transport = new StdioServerTransport();
server.connect(transport);
```

Start the researcher:
```bash
./mcp_chat --config ~/.config/mcp_chat/researcher_config.toml
```

### 3. Developer Agent (Terminal 3)

Create `~/.config/mcp_chat/developer_config.toml`:

```toml
[llm]
default = "anthropic"

[llm.anthropic]
api_key = "your-key"
model = "claude-3-5-sonnet-20241022"
system_prompt = """
You are the Developer Agent. Your expertise includes:
1. Writing high-quality code in multiple languages
2. Creating comprehensive tests
3. Refactoring for clarity and performance
4. Debugging and error analysis

When called via MCP tools, provide working code with comments.
Follow best practices and consider edge cases.
"""

[mcp_server]
sse_enabled = true
sse_port = 8082

# Connect to filesystem for code management
[[mcp.servers]]
name = "workspace"
command = ["npx", "-y", "@modelcontextprotocol/server-filesystem", "/tmp/workspace"]
```

Create developer tools (similar structure to research_tools.js).

## Example Multi-Agent Workflow

### User Request to Orchestrator:
```
You: Create a Python web scraper that finds and analyzes climate change data from scientific websites.
```

### Orchestrator's Process:

1. **Break down the task:**
```
/think This requires both research and development. Let me coordinate both agents.
```

2. **Delegate to Researcher:**
```
/research climate change data sources scientific websites APIs
```

The Researcher agent receives this via MCP, searches for relevant sources, and returns:
- List of scientific climate databases
- API endpoints available
- Data formats and access methods

3. **Orchestrator processes research results and delegates to Developer:**
```
/develop Python web scraper for NOAA climate data API with rate limiting and data validation
```

The Developer agent receives this and generates:
- Complete Python scraper code
- Error handling
- Rate limiting implementation
- Basic tests

4. **Orchestrator requests testing:**
```
/review Generated Python climate scraper code
```

Developer agent runs tests and suggests improvements.

5. **Final synthesis by Orchestrator:**
The orchestrator combines insights from both agents and presents a complete solution to the user.

## Advanced Patterns

### 1. Feedback Loops
Agents can query each other for clarification:

```
Developer → Researcher: "What's the rate limit for the NOAA API?"
Researcher → Developer: "100 requests per hour with burst of 10"
```

### 2. Parallel Processing
Orchestrator can delegate simultaneously:

```elixir
# In orchestrator's task delegation
tasks = [
  Task.async(fn -> call_tool("researcher", "search", %{query: "climate APIs"}) end),
  Task.async(fn -> call_tool("developer", "code_gen", %{template: "web_scraper"}) end)
]

results = Task.await_many(tasks)
```

### 3. Agent Specialization
Create more specialized agents:
- **Security Agent**: Reviews code for vulnerabilities
- **Documentation Agent**: Generates docs from code
- **Testing Agent**: Creates comprehensive test suites
- **Deployment Agent**: Handles CI/CD

### 4. Shared Context
Use MCP resources to share context:

```toml
# In each agent config
[[mcp.servers]]
name = "shared_context"
command = ["npx", "-y", "@modelcontextprotocol/server-filesystem", "/tmp/shared"]
```

## Running as BEAM Nodes (Future)

With the planned BEAM transport, this becomes even more powerful:

```elixir
# Start nodes
iex --name orchestrator@localhost -S mix
iex --name researcher@localhost -S mix  
iex --name developer@localhost -S mix

# Connect them
Node.connect(:"researcher@localhost")
Node.connect(:"developer@localhost")

# Direct message passing
GenServer.call({MCPChat.Agent, :"researcher@localhost"}, 
  {:mcp_request, "search", %{query: "climate data"}})
```

## Benefits of This Architecture

1. **Separation of Concerns**: Each agent has specialized knowledge
2. **Scalability**: Add more agents as needed
3. **Fault Tolerance**: Agents can fail independently
4. **Cost Optimization**: Use appropriate models for each task
5. **Parallel Processing**: Multiple agents work simultaneously
6. **Auditability**: Track which agent made which decision

## Monitoring Dashboard

Create a simple Phoenix LiveView dashboard to monitor agent interactions:

```elixir
defmodule AgentDashboard do
  use Phoenix.LiveView

  def render(assigns) do
    ~H"""
    <div>
      <h1>Multi-Agent System Status</h1>
      <div class="agents">
        <%= for agent <- @agents do %>
          <div class="agent-card">
            <h3><%= agent.name %></h3>
            <p>Status: <%= agent.status %></p>
            <p>Current Task: <%= agent.current_task %></p>
            <p>Requests Handled: <%= agent.request_count %></p>
          </div>
        <% end %>
      </div>
      
      <div class="recent-interactions">
        <h2>Recent Agent Interactions</h2>
        <%= for interaction <- @interactions do %>
          <div class="interaction">
            <span><%= interaction.from %> → <%= interaction.to %></span>
            <span><%= interaction.tool %></span>
            <span><%= interaction.timestamp %></span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
```

## Conclusion

This multi-agent setup demonstrates how MCP Chat instances can work together as a sophisticated AI system. Each agent maintains its own context, expertise, and tools while collaborating through MCP protocols. The architecture is extensible, fault-tolerant, and can scale from local development to distributed production systems.