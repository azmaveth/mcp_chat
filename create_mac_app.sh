#!/bin/bash
# Create a macOS app bundle for MCP Chat

APP_NAME="MCP Chat"
APP_DIR="$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Clean up any existing app
rm -rf "$APP_DIR"

# Create the app structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Create the executable script
cat > "$MACOS_DIR/mcp_chat" << 'EOF'
#!/bin/bash
# Get the directory of this script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Go to the project directory
cd "$DIR/../../../"
# Launch with Terminal
osascript -e "tell application \"Terminal\" to do script \"cd '$PWD' && ./mcp_chat_iex\""
EOF

chmod +x "$MACOS_DIR/mcp_chat"

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>MCP Chat</string>
    <key>CFBundleDisplayName</key>
    <string>MCP Chat</string>
    <key>CFBundleIdentifier</key>
    <string>com.mcp.chat</string>
    <key>CFBundleVersion</key>
    <string>0.2.1</string>
    <key>CFBundleExecutable</key>
    <string>mcp_chat</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.10</string>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
EOF

echo "Created $APP_DIR - you can now drag it to Applications folder"