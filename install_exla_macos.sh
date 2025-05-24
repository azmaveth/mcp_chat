#!/bin/bash
# Script to install EXLA with proper compiler flags for macOS

echo "Installing EXLA with macOS-compatible compiler flags..."

# Clean any previous EXLA build artifacts
mix deps.clean exla

# Set compiler flags to work around the template syntax issue
export CXXFLAGS="-Wno-error=missing-template-arg-list-after-template-kw"

# For newer Xcode versions, we might need to use an older C++ standard
export CXXFLAGS="$CXXFLAGS -std=c++17"

# Try to compile EXLA
echo "Fetching and compiling EXLA..."
mix deps.get
mix deps.compile exla

echo "Done! EXLA should now be compiled."
echo ""
echo "If compilation still fails, you can:"
echo "1. Skip EXLA and use EMLX for Apple Silicon (recommended)"
echo "2. Use the binary backend (slower but works everywhere)"
echo "3. Try installing an older Xcode Command Line Tools version"