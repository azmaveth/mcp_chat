#!/bin/bash

# Simple script to test the web UI without Phoenix

echo "🌐 Starting MCP Chat Web UI Test Server"
echo "========================================"
echo
echo "This will start a simple HTTP server to demonstrate the web UI"
echo "without dealing with Phoenix configuration issues."
echo
echo "Opening test interface at: http://localhost:4000/test.html"
echo

# Change to static directory
cd priv/static

# Check if Python is available
if command -v python3 &> /dev/null; then
    echo "Starting Python HTTP server..."
    python3 -m http.server 4000
elif command -v python &> /dev/null; then
    echo "Starting Python HTTP server..."
    python -m SimpleHTTPServer 4000
else
    echo "❌ Python not found. Please install Python to run the test server."
    echo "   Alternatively, you can use any HTTP server to serve the priv/static directory."
    exit 1
fi