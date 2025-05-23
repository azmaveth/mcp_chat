#!/bin/bash

echo "Setting up MCP Chat Client..."

# Install dependencies
echo "Installing Elixir dependencies..."
mix deps.get

# Compile the project
echo "Compiling..."
mix compile

# Build escript
echo "Building executable..."
mix escript.build

# Create config directory
CONFIG_DIR="$HOME/.config/mcp_chat"
if [ ! -d "$CONFIG_DIR" ]; then
    echo "Creating configuration directory..."
    mkdir -p "$CONFIG_DIR"
    
    # Copy example config if no config exists
    if [ ! -f "$CONFIG_DIR/config.toml" ]; then
        echo "Creating default configuration..."
        cp config/example.toml "$CONFIG_DIR/config.toml"
        echo ""
        echo "⚠️  Please edit $CONFIG_DIR/config.toml with your API keys"
    fi
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "To start the chat client, run:"
echo "  ./mcp_chat"
echo ""
echo "For help, run:"
echo "  ./mcp_chat --help"