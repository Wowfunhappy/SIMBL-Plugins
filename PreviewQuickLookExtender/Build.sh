#!/bin/bash

set -e

# PreviewQuickLookExtender build script

PLUGIN_NAME="PreviewQuickLookExtender"
VERSION=$(date +%Y.%m.%d)
BUILD_DIR="./build"
BUNDLE_DIR="${BUILD_DIR}/${PLUGIN_NAME}.bundle"
INSTALL_DIR="/Library/Application Support/SIMBL/Plugins"

# Clean and create build directory
rm -rf "$BUILD_DIR"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"

# Copy Info.plist
cp Info.plist "${BUNDLE_DIR}/Contents/Info.plist"

# Update Info.plist with automatic values using defaults
defaults write "${BUNDLE_DIR}/Contents/Info" CFBundleVersion "$VERSION"
defaults write "${BUNDLE_DIR}/Contents/Info" CFBundleShortVersionString "$VERSION"

# Compile ZKSwizzle without ARC
clang -c -framework Cocoa \
      -framework Foundation \
      -fno-objc-arc \
      -Wno-deprecated-declarations \
      -o "$BUILD_DIR/ZKSwizzle.o" \
      ZKSwizzle/ZKSwizzle.m

# Compile the plugin with ARC
clang -c -framework Cocoa \
      -framework Foundation \
      -fobjc-arc \
      -Wno-deprecated-declarations \
      -o "$BUILD_DIR/PreviewQuickLookExtender.o" \
      PreviewQuickLookExtender.m

# Link everything together
clang -framework Cocoa \
      -framework Foundation \
      -bundle \
      -o "${BUNDLE_DIR}/Contents/MacOS/${PLUGIN_NAME}" \
      "$BUILD_DIR/PreviewQuickLookExtender.o" \
      "$BUILD_DIR/ZKSwizzle.o"

# Check if compilation was successful
if [ $? -eq 0 ]; then
    echo "Build successful!"
    
    # Install the plugin
    echo "Installing to ${INSTALL_DIR}..."
    osascript -e "tell application \"Finder\" to move (POSIX file \"${BUNDLE_DIR}\" as alias) to (POSIX file \"${INSTALL_DIR}\" as alias) replacing True"
    
    # Clean up the build directory
    rm -rf "${BUILD_DIR}"
    
    echo "Plugin installed at ${INSTALL_DIR}/${PLUGIN_NAME}.bundle"
    echo "Please restart Preview.app to load the plugin."
else
    echo "Build failed!"
    exit 1
fi