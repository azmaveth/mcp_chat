#!/bin/bash

echo "Setting up MCP Chat Client..."

# Install dependencies
echo "Installing Elixir dependencies..."
mix deps.get

# Handle macOS-specific EXLA compilation issues
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Detected macOS. Checking for Apple Silicon..."
    if [[ $(uname -m) == "arm64" ]]; then
        echo "Apple Silicon detected. EMLX will be used for Metal acceleration."
        # Try to compile, but don't fail if EXLA has issues
        mix compile || {
            echo "Note: EXLA compilation failed. This is expected on macOS with newer Xcode."
            echo "EMLX will be used for local model acceleration instead."
            # Clean EXLA and compile without it
            mix deps.clean exla
            mix compile
        }
    else
        # Intel Mac
        echo "Intel Mac detected. Attempting to compile with EXLA..."
        export CXXFLAGS="-Wno-error=missing-template-arg-list-after-template-kw"
        mix compile || {
            echo "EXLA compilation failed. Continuing without GPU acceleration."
            mix deps.clean exla
            mix compile
        }
    fi
else
    # Non-macOS systems
    echo "Compiling..."
    mix compile
fi

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