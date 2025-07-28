#!/bin/bash

set -e

PLUGIN_NAME="mySIMBLFixes"
VERSION=$(date +%Y.%m.%d)

BUILD_DIR="./build"
mkdir -p "${BUILD_DIR}"

BUNDLE_DIR="$(cd "${BUILD_DIR}" && pwd)/${PLUGIN_NAME}.bundle"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
mkdir -p "${BUNDLE_DIR}/Contents/Resources"

INSTALL_DIR="/Library/Application Support/SIMBL/Plugins"

# Compile the plugin
clang -dynamiclib -arch i386 -arch x86_64 -mmacosx-version-min=10.6 -framework Cocoa -I./ZKSwizzle -o "${BUILD_DIR}/${PLUGIN_NAME}" "${PLUGIN_NAME}.m" "ZKSwizzle/ZKSwizzle.m"

# Copy the compiled plugin to the bundle
cp "${BUILD_DIR}/${PLUGIN_NAME}" "${BUNDLE_DIR}/Contents/MacOS/"

# Copy Info.plist and update properties
cp "./Info.plist" "${BUNDLE_DIR}/Contents/Info.plist"

# Update Info.plist with automatic values using defaults
defaults write "${BUNDLE_DIR}/Contents/Info" CFBundleVersion "$VERSION"
defaults write "${BUNDLE_DIR}/Contents/Info" CFBundleName "$PLUGIN_NAME"
defaults write "${BUNDLE_DIR}/Contents/Info" CFBundleExecutable "$PLUGIN_NAME"

# Copy Resources directory contents if it exists
if [ -d "./Resources" ]; then
    echo "Copying Resources..."
    cp -R ./Resources/* "${BUNDLE_DIR}/Contents/Resources/"
fi

echo "Copying bundle to ${INSTALL_DIR}..."
osascript -e "tell application \"Finder\" to move (POSIX file \"${BUNDLE_DIR}\" as alias) to (POSIX file \"${INSTALL_DIR}\" as alias) replacing True"

# Clean up the build directory
rm -rf "${BUILD_DIR}"

echo "Build complete. Plugin installed at ${INSTALL_DIR}/${PLUGIN_NAME}.bundle"
