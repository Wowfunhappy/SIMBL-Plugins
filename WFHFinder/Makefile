#@run: make install

PLUGIN_NAME = WFHFinder
VERSION = $(shell date +%Y.%m.%d)
BUILD_DIR = ./build
BUNDLE_DIR = $(BUILD_DIR)/$(PLUGIN_NAME).bundle
INSTALL_DIR = /Library/Application Support/SIMBL/Plugins

CC = clang
CFLAGS = -dynamiclib -arch i386 -arch x86_64 -mmacosx-version-min=10.6 -framework Cocoa -framework Carbon -O2 -I./ZKSwizzle
SOURCES = *.m ZKSwizzle/ZKSwizzle.m
OUTPUT = $(BUILD_DIR)/$(PLUGIN_NAME)

.PHONY: all clean install

all: $(OUTPUT)

$(OUTPUT): $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(BUNDLE_DIR)/Contents/MacOS
	@mkdir -p $(BUNDLE_DIR)/Contents/Resources
	$(CC) $(CFLAGS) -o $@ $(SOURCES)
	@cp $(OUTPUT) $(BUNDLE_DIR)/Contents/MacOS/
	@cp ./Info.plist $(BUNDLE_DIR)/Contents/Info.plist
	@defaults write $(BUNDLE_DIR)/Contents/Info CFBundleVersion "$(VERSION)"
	@defaults write $(BUNDLE_DIR)/Contents/Info CFBundleName "$(PLUGIN_NAME)"
	@defaults write $(BUNDLE_DIR)/Contents/Info CFBundleExecutable "$(PLUGIN_NAME)"

install: all
	@echo "Installing plugin to $(INSTALL_DIR)..."
	@osascript -e "tell application \"Finder\" to move (POSIX file \"$(shell cd $(BUILD_DIR) && pwd)/$(PLUGIN_NAME).bundle\" as alias) to (POSIX file \"$(INSTALL_DIR)\" as alias) replacing True"
	@rm -rf $(BUILD_DIR)
	@echo "Plugin installed. Restarting Finder..."
	@killall Finder

clean:
	@rm -rf $(BUILD_DIR)