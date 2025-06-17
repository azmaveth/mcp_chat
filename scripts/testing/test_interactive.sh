#!/bin/bash

# Test interactive commands with enhanced agent architecture
echo "Testing mcp_chat enhanced agent commands interactively..."
echo "This will test:"
echo "1. /help command (agent discovery)"
echo "2. Enhanced agent commands (/model recommend, /mcp discover)"
echo "3. Arrow keys and terminal behavior"
echo "4. Agent-based command routing"
echo ""

# Create a temporary file for output
OUTFILE=$(mktemp)

# Run mcp_chat with tmux to capture interactive session
tmux new-session -d -s test_mcp "MCP_DEBUG=1 bin/mcp_chat 2>&1 | tee $OUTFILE"

# Give it time to start and agents to initialize
sleep 3

echo "Testing basic /help command..."
# Send /help command
tmux send-keys -t test_mcp "/help" Enter

# Wait for command to process
sleep 3

echo "Testing agent discovery with /models command..."
# Test model listing (should route to LLM agent)
tmux send-keys -t test_mcp "/models" Enter

# Wait for command to process
sleep 2

echo "Testing enhanced model recommendations..."
# Test model recommendations (enhanced agent command)
tmux send-keys -t test_mcp "/model recommend" Enter

# Wait for processing
sleep 3

echo "Testing MCP server discovery..."
# Test MCP discovery (should route to MCP agent)
tmux send-keys -t test_mcp "/mcp discover" Enter

# Wait for discovery
sleep 3

echo "Testing statistics command (Analysis agent)..."
# Test stats command (should route to Analysis agent)
tmux send-keys -t test_mcp "/stats" Enter

# Wait for stats
sleep 2

echo "Testing arrow key functionality..."
# Send arrow key test
tmux send-keys -t test_mcp "test" Left Left "X" Enter

# Wait
sleep 1

echo "Testing Ctrl-A/Ctrl-E functionality..."
# Send Ctrl-A test
tmux send-keys -t test_mcp "hello" C-a "START-" Enter

# Wait
sleep 1

echo "Exiting test session..."
# Exit
tmux send-keys -t test_mcp "/exit" Enter

# Wait for exit
sleep 2

# Kill tmux session
tmux kill-session -t test_mcp 2>/dev/null

# Show results
echo ""
echo "=== Enhanced Agent Command Test Results ==="
echo ""

# Check if help was displayed
if grep -q "Available Commands" "$OUTFILE"; then
    echo "✓ /help command worked"
else
    echo "✗ /help command failed"
fi

# Check for agent command routing
if grep -q "LLM Agent\|MCP Agent\|Analysis Agent" "$OUTFILE"; then
    echo "✓ Agent command routing detected"
else
    echo "✗ Agent command routing not detected"
fi

# Check for enhanced commands
if grep -q "model.*recommend\|mcp.*discover" "$OUTFILE"; then
    echo "✓ Enhanced agent commands executed"
else
    echo "✗ Enhanced agent commands not found"
fi

# Check for model information
if grep -q "models\|backend\|provider" "$OUTFILE"; then
    echo "✓ Model information displayed"
else
    echo "✗ Model information not found"
fi

# Check for MCP functionality
if grep -q "MCP\|server\|discover" "$OUTFILE"; then
    echo "✓ MCP functionality detected"
else
    echo "✗ MCP functionality not found"
fi

# Show full output if there were failures
FAILURES=0
if ! grep -q "Available Commands" "$OUTFILE"; then
    ((FAILURES++))
fi
if ! grep -q "LLM Agent\|MCP Agent\|Analysis Agent" "$OUTFILE"; then
    ((FAILURES++))
fi

if [ $FAILURES -gt 0 ]; then
    echo ""
    echo "=== Full Output (for debugging) ==="
    cat "$OUTFILE"
fi

# Clean up
rm -f "$OUTFILE"

echo ""
echo "Enhanced agent command testing complete."