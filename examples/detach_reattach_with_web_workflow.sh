#!/bin/bash

# MCP Chat CLI/Agent Detach/Reattach Workflow with Web Dashboard
# This script demonstrates the complete workflow with web UI integration

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Function to print colored output
print_status() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_header() {
    echo
    echo -e "${BOLD}$1${NC}"
    echo "================================================================"
}

# Function to show progress
show_progress() {
    local duration=$1
    local message=$2
    echo -n "$message "
    for i in $(seq 1 $duration); do
        echo -n "."
        sleep 1
    done
    echo " Done!"
}

# Function to open browser
open_browser() {
    local url=$1
    print_status "Opening $url in your default browser..."
    
    # Detect OS and open browser
    if [[ "$OSTYPE" == "darwin"* ]]; then
        open "$url"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        xdg-open "$url" 2>/dev/null || echo "Please open $url manually"
    else
        echo "Please open $url in your browser"
    fi
}

# Main workflow
clear
echo -e "${BOLD}🔄 MCP Chat CLI/Agent Detach/Reattach Workflow with Web Dashboard${NC}"
echo "================================================================"
echo

# Step 1: Start the application with web server
print_header "Step 1: Starting MCP Chat with Web Dashboard"
print_status "Starting MCP Chat application..."
echo

cat << 'EOF'
# In terminal 1, start the application:
iex -S mix

# The application will start with:
- Phoenix web server on http://localhost:4000
- Agent supervision tree
- Session management
- Real-time PubSub system
EOF

print_success "Application started with web server!"
sleep 2

# Step 2: Open web dashboard
print_header "Step 2: Opening Web Dashboard"
open_browser "http://localhost:4000"

echo
print_status "Web dashboard features:"
echo "  📊 System overview with real-time stats"
echo "  🤖 Agent monitoring and control"
echo "  💬 Web-based chat interface"
echo "  📝 Session management"

sleep 3

# Step 3: Create session via web
print_header "Step 3: Creating Session via Web UI"
print_status "Navigate to http://localhost:4000/sessions"
echo
echo "Click 'Create New Session' and give it a name like 'Demo Session'"
echo
show_progress 3 "Creating session"
print_success "Session created! Note the session ID (e.g., session_demo_1)"

# Step 4: Start CLI and connect
print_header "Step 4: Starting CLI and Connecting to Web Session"
echo
cat << 'EOF'
# In terminal 2 (or in IEx):
MCPChat.main()

# Connect to the web session:
/connect session_demo_1
EOF

print_status "CLI is now connected to the same session as web!"
print_status "Try sending messages from both CLI and web - they sync instantly!"
sleep 3

# Step 5: Start background task
print_header "Step 5: Starting Long-Running Task"
print_status "Starting analysis task that will continue after CLI disconnects..."
echo
echo "# In CLI, start a long task:"
echo "/analyze large_codebase --deep"
echo

show_progress 3 "Task started and running"
print_status "Monitor progress in web at http://localhost:4000/agents"

# Step 6: Disconnect CLI
print_header "Step 6: Disconnecting CLI (Agent Continues)"
print_warning "Disconnecting CLI in 3 seconds..."
sleep 3

echo
print_status "CLI disconnecting with Ctrl+C or /exit --keep-session"
print_success "CLI disconnected!"
echo
print_status "Check web dashboard - agent is still active! ✨"
print_status "Background task continues processing..."

# Show web monitoring
echo
echo "🌐 In Web Dashboard you can see:"
echo "  - Agent status: ${GREEN}● Active${NC}"
echo "  - Task progress: ${YELLOW}▓▓▓▓▓▓░░░░${NC} 60%"
echo "  - Live logs streaming"
echo "  - Performance metrics updating"

sleep 5

# Step 7: Background work simulation
print_header "Step 7: Agent Working in Background (Observable via Web)"

tasks=(
    "📁 Scanning project files..."
    "🔍 Analyzing code patterns..."
    "🛠️ Running static analysis..."
    "📊 Generating insights..."
    "💾 Saving results to session..."
)

for task in "${tasks[@]}"; do
    echo -n "$task"
    for i in {1..10}; do
        echo -n "█"
        sleep 0.2
    done
    print_success " Complete!"
    print_status "Progress visible at http://localhost:4000/sessions/session_demo_1/chat"
done

# Step 8: Reconnect CLI
print_header "Step 8: Reconnecting CLI with Full State"
echo
cat << 'EOF'
# Start CLI again:
MCPChat.main()

# Reconnect to session:
/resume session_demo_1
EOF

show_progress 2 "Reconnecting and syncing state"
print_success "CLI reconnected with full session history!"

echo
echo "📋 Synchronized state includes:"
echo "  - Complete message history from web interactions"
echo "  - Background task results"
echo "  - Current model and settings"
echo "  - All context files"

# Step 9: Multi-interface demo
print_header "Step 9: Multi-Interface Interaction Demo"
print_status "Both CLI and Web are now connected to the same session"
echo

echo "Try this:"
echo "1. Type a message in CLI - see it appear instantly in web"
echo "2. Type a message in web - see it appear instantly in CLI"
echo "3. Start generation in CLI - stop it from web interface"
echo "4. Upload files in web - access them from CLI"
echo

# Summary
print_header "Summary"
echo "✅ Started MCP Chat with web dashboard"
echo "✅ Created and monitored agents via web UI"
echo "✅ Disconnected CLI while agent continued working"
echo "✅ Observed background work through web dashboard"
echo "✅ Reconnected CLI with full state synchronization"
echo "✅ Demonstrated real-time multi-interface interaction"
echo

print_success "Workflow demonstration complete!"
echo
echo "🎯 Key Takeaways:"
echo "  - Agents run independently of interfaces"
echo "  - Web dashboard provides 24/7 monitoring"
echo "  - State persists and syncs across connections"
echo "  - Multiple users can collaborate on same session"
echo
echo "📚 Next Steps:"
echo "  - Explore http://localhost:4000/agents for detailed monitoring"
echo "  - Try mobile access to web UI"
echo "  - Set up team collaboration with shared sessions"
echo "  - Configure webhooks for agent events"
echo

# Cleanup reminder
print_warning "Remember to stop the application when done with Ctrl+C"