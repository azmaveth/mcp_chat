# MCP Chat Examples

This directory contains examples demonstrating advanced uses of MCP Chat, particularly focusing on multi-agent architectures.

## Available Examples

### 1. Multi-Agent Setup (`multi_agent_setup.md`)
A comprehensive guide showing how to chain multiple MCP Chat instances together as specialized AI agents:
- **Orchestrator**: Coordinates tasks using Claude Opus 4
- **Researcher**: Handles information gathering with Claude 3.7
- **Developer**: Generates code with Claude 3.5

Features demonstrated:
- Agent-to-agent communication via MCP
- Task delegation and coordination
- Parallel processing
- Shared context management

### 2. Simple Agent Chain (`simple_agent_chain.sh`)
A ready-to-run bash script that sets up a three-agent system:
- Creates configuration files for each agent
- Demonstrates SSE transport connections
- Shows basic task delegation

To run:
```bash
./simple_agent_chain.sh
# Then follow the instructions to start each agent
```

### 3. Agent Tools Example (`agent_tools_example.md`)
Advanced example showing:
- Custom MCP server implementation for agent bridging
- JavaScript and Elixir implementations
- Real agent-to-agent communication protocols
- Practical multi-agent scenarios

## Key Concepts

### Agent Communication Patterns

1. **Direct Connection**: Agents connect to each other's MCP servers
2. **Bridge Pattern**: Central coordinator manages agent interactions  
3. **Pipeline Pattern**: Sequential processing through agent chain
4. **Mesh Pattern**: Agents can query any other agent

### Use Cases

- **Research Teams**: Multiple agents collaborating on information gathering
- **Development Teams**: Architect, developer, and tester agents
- **Content Creation**: Ideation, writing, and editing pipeline
- **Analysis Systems**: Data gathering, processing, and reporting

### Benefits

- **Specialization**: Each agent uses the most appropriate model
- **Cost Optimization**: Expensive models only for complex tasks
- **Fault Tolerance**: Agents fail independently
- **Scalability**: Add agents as needed
- **Auditability**: Track decision flow

## Getting Started

1. Ensure MCP Chat is built:
   ```bash
   mix escript.build
   ```

2. Install MCP server dependencies (if using JavaScript examples):
   ```bash
   npm install -g @modelcontextprotocol/server-filesystem
   ```

3. Set your API keys:
   ```bash
   export ANTHROPIC_API_KEY="your-key"
   ```

4. Choose an example and follow its instructions

## Future Enhancements

With the planned BEAM transport (Phase 9), agent communication will become even more powerful:
- Zero serialization overhead
- Native supervision trees
- Distributed agents across Erlang nodes
- Direct message passing between agents

## Contributing

Feel free to add your own multi-agent examples! Consider:
- Different agent specializations
- Novel communication patterns
- Integration with external tools
- Performance optimizations