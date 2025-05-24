#!/bin/bash
# Simple Multi-Agent MCP Chat Setup
# This script demonstrates chaining 3 MCP Chat instances

echo "=== MCP Chat Multi-Agent Example ==="
echo "This will start 3 connected agents:"
echo "1. Orchestrator (port 8080) - Coordinates tasks"
echo "2. Analyst (port 8081) - Analyzes data" 
echo "3. Writer (port 8082) - Creates content"
echo ""
echo "Press Ctrl+C in each terminal to stop"
echo ""

# Create config directory
mkdir -p ~/.config/mcp_chat/agents

# Create Orchestrator config
cat > ~/.config/mcp_chat/agents/orchestrator.toml << 'EOF'
[llm]
default = "anthropic"

[llm.anthropic]
model = "claude-sonnet-4-20250514"

[mcp_server]
sse_enabled = true
sse_port = 8080

# Connect to other agents
[[mcp.servers]]
name = "analyst"
url = "http://localhost:8081/sse"
transport = "sse"
auto_connect = true

[[mcp.servers]]
name = "writer"  
url = "http://localhost:8082/sse"
transport = "sse"
auto_connect = true
EOF

# Create Analyst config
cat > ~/.config/mcp_chat/agents/analyst.toml << 'EOF'
[llm]
default = "anthropic"

[llm.anthropic]
model = "claude-3-haiku-20240307"  # Use a faster model for analysis

[mcp_server]
sse_enabled = true
sse_port = 8081

# Analyst can use filesystem tools
[[mcp.servers]]
name = "filesystem"
command = ["npx", "-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
auto_connect = true
EOF

# Create Writer config
cat > ~/.config/mcp_chat/agents/writer.toml << 'EOF'
[llm]
default = "anthropic"

[llm.anthropic]
model = "claude-3-5-sonnet-20241022"  # Good for creative writing

[mcp_server]
sse_enabled = true
sse_port = 8082

# Writer can save outputs
[[mcp.servers]]
name = "output"
command = ["npx", "-y", "@modelcontextprotocol/server-filesystem", "/tmp/output"]
auto_connect = true
EOF

echo "Configs created. To start the agents:"
echo ""
echo "Terminal 1 - Orchestrator:"
echo "  ./mcp_chat --config ~/.config/mcp_chat/agents/orchestrator.toml"
echo ""
echo "Terminal 2 - Analyst:"
echo "  ./mcp_chat --config ~/.config/mcp_chat/agents/analyst.toml"
echo ""
echo "Terminal 3 - Writer:"
echo "  ./mcp_chat --config ~/.config/mcp_chat/agents/writer.toml"
echo ""
echo "Example workflow in Orchestrator:"
echo "  /tools                    # See all available tools from connected agents"
echo "  /prompt analyst analyze   # Get analysis prompt from analyst"
echo "  /prompt writer create     # Get writing prompt from writer"
echo ""
echo "Example task delegation:"
echo "  You: Analyze the latest tech trends and write a blog post about AI"
echo "  [Orchestrator coordinates between Analyst and Writer agents]"