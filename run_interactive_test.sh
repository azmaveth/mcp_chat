#!/bin/bash

# Run mcp_chat interactively and capture output
# This script uses script command to capture interactive session

echo "Running interactive test of /help command..."
echo "This will type '/help' followed by Enter, then '/exit'"
echo

# Use script command to capture interactive session
script -q /dev/null ./mcp_chat <<EOF
/help
/exit
EOF

echo
echo "Test complete."