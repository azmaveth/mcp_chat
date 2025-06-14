#!/bin/bash

# Test interactive commands
echo "Testing mcp_chat interactively..."
echo "This will test:"
echo "1. /help command"
echo "2. Arrow keys"
echo "3. Ctrl-A/Ctrl-E"
echo ""

# Create a temporary file for output
OUTFILE=$(mktemp)

# Run mcp_chat with tmux to capture interactive session
tmux new-session -d -s test_mcp "MCP_DEBUG=1 ./mcp_chat 2>&1 | tee $OUTFILE"

# Give it time to start
sleep 2

# Send /help command
tmux send-keys -t test_mcp "/help" Enter

# Wait for command to process
sleep 2

# Send arrow key test
tmux send-keys -t test_mcp "test" Left Left "X" Enter

# Wait
sleep 1

# Send Ctrl-A test
tmux send-keys -t test_mcp "hello" C-a "START-" Enter

# Wait
sleep 1

# Exit
tmux send-keys -t test_mcp "/exit" Enter

# Wait for exit
sleep 1

# Kill tmux session
tmux kill-session -t test_mcp 2>/dev/null

# Show results
echo ""
echo "=== Test Results ==="
echo ""

# Check if help was displayed
if grep -q "Available Commands" "$OUTFILE"; then
    echo "✓ /help command worked"
else
    echo "✗ /help command failed"
    echo "Output:"
    cat "$OUTFILE"
fi

# Clean up
rm -f "$OUTFILE"