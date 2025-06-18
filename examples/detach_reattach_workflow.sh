#!/bin/bash

# MCP Chat CLI/Agent Detach/Reattach Workflow Demo
# Demonstrates starting an agent, disconnecting CLI, and reconnecting to see results

set -e

echo "🔄 MCP Chat CLI/Agent Detach/Reattach Workflow"
echo "=============================================="
echo
echo "This script demonstrates the full workflow of:"
echo "1. Starting an agent session via CLI"
echo "2. Starting a long-running task"
echo "3. Disconnecting the CLI while agent continues"
echo "4. Reconnecting to see results"
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if MCP Chat is built
if [ ! -f "./mcp_chat" ]; then
    echo -e "${RED}❌ mcp_chat executable not found${NC}"
    echo "Please run: mix escript.build"
    exit 1
fi

echo -e "${BLUE}📋 Step 1: Starting MCP Chat with Agent Backend${NC}"
echo "================================================"
echo

# Create a temporary script for the CLI session
TEMP_SESSION_FILE=$(mktemp)
cat > "$TEMP_SESSION_FILE" << 'EOF'
# Simulate a long-running task
echo "Starting repository analysis..."
echo "/mcp tool analyze_large_repository repo:my-project"

# Wait a bit to simulate task startup
sleep 3

echo ""
echo "📊 Analysis started. Task will continue in background."
echo "💡 You can now disconnect the CLI safely."
echo ""
echo "Press Ctrl+C to disconnect CLI (agent will continue)"
echo "Or wait 10 seconds for automatic disconnect..."

# Wait for user interrupt or timeout
timeout 10 cat > /dev/null || true
echo ""
echo "🔌 CLI disconnecting... (agent continues in background)"
EOF

echo "Starting MCP Chat session..."
echo -e "${YELLOW}💡 In a real scenario, you would:${NC}"
echo "   1. Run: ./mcp_chat"
echo "   2. Send command: /mcp tool analyze_large_repository"  
echo "   3. Press Ctrl+C to disconnect"
echo

# Simulate the CLI session
echo -e "${GREEN}🚀 CLI Session Started${NC}"
echo "   ✓ Agent session created: session_$(date +%s)"
echo "   ✓ Connected to agent backend"
echo "   ✓ Ready for commands"
echo

sleep 2

echo -e "${BLUE}📋 Step 2: Starting Long-Running Task${NC}"
echo "====================================="
echo
echo "User> /mcp tool analyze_large_repository repo:my-project"
echo
echo "Agent> 🔍 Starting repository analysis..."
echo "Agent> 📂 Scanning 15,000 files..."
echo "Agent> 🧠 Analyzing code patterns..."
echo "Agent> ⏱️  Estimated time: 10 minutes"
echo "Agent> 📊 Progress: [██░░░░░░░░░░░░░░░░░░] 10%"
echo

sleep 3

echo -e "${BLUE}📋 Step 3: Disconnecting CLI${NC}"
echo "============================"
echo
echo -e "${YELLOW}💡 Simulating Ctrl+C or terminal close...${NC}"
echo
echo "🔌 CLI process terminating..."
echo "   ✓ CLI session cleaned up"
echo "   ✓ Agent session remains active"
echo "   ✓ Background task continues"
echo "   ✓ State persisted to storage"
echo

sleep 2

echo -e "${BLUE}📋 Step 4: Agent Working in Background${NC}"
echo "======================================"
echo
echo "🌙 Agent continues work independently..."
echo

# Simulate background progress
PROGRESS_STEPS=(
    "20|Analyzing core modules..."
    "35|Processing dependencies..."
    "50|Generating complexity metrics..."
    "65|Scanning for patterns..."
    "80|Creating architecture diagram..."
    "95|Finalizing report..."
    "100|Analysis complete!"
)

for step in "${PROGRESS_STEPS[@]}"; do
    IFS='|' read -r progress message <<< "$step"
    
    # Create progress bar
    filled=$((progress / 5))
    empty=$((20 - filled))
    bar=$(printf "%*s" $filled | tr ' ' '█')$(printf "%*s" $empty | tr ' ' '░')
    
    echo "📊 Progress: [$bar] ${progress}% - $message"
    sleep 1
done

echo
echo "✅ Analysis completed successfully!"
echo "   📄 Report generated: 45 pages"
echo "   📊 Files analyzed: 15,000"
echo "   🐛 Issues found: 847"
echo "   💡 Recommendations: 23"
echo

sleep 2

echo -e "${BLUE}📋 Step 5: Reconnecting CLI${NC}"
echo "============================"
echo
echo -e "${YELLOW}💡 Starting new CLI instance...${NC}"
echo
echo "$ ./mcp_chat -c  # Continue most recent session"
echo
echo "🚀 MCP Chat reconnecting..."
echo "   🔍 Scanning for active sessions..."
echo "   ✅ Found session: session_$(date +%s)"
echo "   🔗 Reconnecting to agent..."
echo "   📡 Subscribing to events..."
echo "   💾 Loading session state..."
echo "   📜 Restoring conversation history..."
echo

sleep 3

echo -e "${GREEN}✅ CLI Reconnected Successfully!${NC}"
echo
echo "Agent> 🎉 Welcome back! Analysis completed while you were away."
echo "Agent> 📊 Repository analysis finished successfully."
echo "Agent> 📄 Generated comprehensive report with findings."
echo "Agent> 💾 All results preserved in session state."
echo
echo "User> /export report"
echo "Agent> ✅ Report exported to: analysis_report_$(date +%Y%m%d).md"
echo

echo -e "${BLUE}📋 Step 6: Session Management${NC}"
echo "============================"
echo
echo "Available session commands:"
echo "   ./mcp_chat -l              # List active sessions"
echo "   ./mcp_chat -r <session_id> # Resume specific session"
echo "   ./mcp_chat -c              # Continue most recent"
echo "   /session save <name>       # Save current session"
echo "   /session list              # List saved sessions"
echo

echo -e "${YELLOW}📊 Example session list:${NC}"
cat << 'EOF'
   Active Sessions:
   📍 session_1704123456  [ACTIVE]   Started: 14:30  CLI: connected
   🏃 session_1704123123  [WORKING]  Started: 13:15  CLI: detached  
   💤 session_1704122890  [IDLE]     Started: 12:00  CLI: detached

   Saved Sessions:
   💾 project_analysis    Saved: 2024-01-15  Messages: 89
   💾 code_review         Saved: 2024-01-14  Messages: 156
EOF

echo

echo -e "${GREEN}🎯 Demo Complete!${NC}"
echo "================="
echo
echo "This workflow demonstrated:"
echo "✅ Agent persistence independent of CLI"
echo "✅ Background task execution"
echo "✅ State preservation across disconnections"
echo "✅ Seamless CLI reconnection"
echo "✅ Session management capabilities"
echo

echo -e "${BLUE}💡 Try it yourself:${NC}"
echo "1. Build MCP Chat: mix escript.build"
echo "2. Start a session: ./mcp_chat"
echo "3. Run a long task (file analysis, etc.)"
echo "4. Disconnect with Ctrl+C"
echo "5. Reconnect with: ./mcp_chat -c"
echo "6. See your preserved results!"
echo

# Cleanup
rm -f "$TEMP_SESSION_FILE"

echo "✅ Workflow demo completed successfully!"