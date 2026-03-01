APP_NAME ?= AutoClawd
BUNDLE_ID ?= com.autoclawd.app
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CODESIGN_IDENTITY ?= -
CONTENTS = $(APP_BUNDLE)/Contents
MACOS_DIR = $(CONTENTS)/MacOS

SOURCES = $(wildcard Sources/*.swift)
RESOURCES = $(CONTENTS)/Resources
ARCH ?= $(shell uname -m)
ICON_SOURCE = Resources/AppIcon-Source.png
ICON_ICNS = Resources/AppIcon.icns

SDK = $(shell xcrun --show-sdk-path)
TARGET = $(ARCH)-apple-macosx13.0
VFS_OVERLAY = $(BUILD_DIR)/vfs-overlay.yaml
SWIFT_FLAGS = \
	-parse-as-library \
	-sdk $(SDK) \
	-target $(TARGET) \
	-lsqlite3 \
	-framework ShazamKit

VERSION ?= 0.1.0
DMG_NAME = $(APP_NAME)-$(VERSION).dmg
DMG_STAGING = $(BUILD_DIR)/dmg-staging
DMG_PATH = $(BUILD_DIR)/$(DMG_NAME)

# ── MCP Server ─────────────────────────────────────────────────────────────────
MCP_SOURCES = $(wildcard MCPServer/*.swift)
MCP_BINARY = $(BUILD_DIR)/autoclawd-mcp
MCP_SWIFT_FLAGS = \
	-sdk $(SDK) \
	-target $(TARGET) \
	-lsqlite3

# ── WhatsApp Sidecar ──────────────────────────────────────────────────────────
WHATSAPP_DIR = WhatsAppSidecar
WHATSAPP_DEST = $(RESOURCES)/WhatsAppSidecar

.PHONY: all clean run dmg mcp-server whatsapp-sidecar

all: $(MACOS_DIR)/$(APP_NAME) mcp-server whatsapp-sidecar

mcp-server: $(MCP_BINARY)

$(MCP_BINARY): $(MCP_SOURCES)
	@mkdir -p "$(BUILD_DIR)"
	swiftc $(MCP_SWIFT_FLAGS) \
		-o "$(MCP_BINARY)" \
		$(MCP_SOURCES)
	@echo "Built $(MCP_BINARY)"

$(MACOS_DIR)/$(APP_NAME): $(SOURCES) Info.plist $(ICON_ICNS) $(MCP_BINARY)
	@mkdir -p "$(MACOS_DIR)" "$(RESOURCES)"
	swiftc $(SWIFT_FLAGS) \
		-o "$(MACOS_DIR)/$(APP_NAME)" \
		$(SOURCES)
	@cp "$(MCP_BINARY)" "$(MACOS_DIR)/"
	@cp Info.plist "$(CONTENTS)/"
	@plutil -replace CFBundleName -string "$(APP_NAME)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleDisplayName -string "$(APP_NAME)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleExecutable -string "$(APP_NAME)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleIdentifier -string "$(BUNDLE_ID)" "$(CONTENTS)/Info.plist"
	@cp $(ICON_ICNS) "$(RESOURCES)/"
	@if [ -d "Resources/PixelWorld" ]; then \
		mkdir -p "$(RESOURCES)/PixelWorld"; \
		cp -r Resources/PixelWorld/. "$(RESOURCES)/PixelWorld/"; \
		echo "Bundled PixelWorld web app"; \
	fi
	@codesign --force --sign "$(CODESIGN_IDENTITY)" \
		--entitlements AutoClawd.entitlements "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"

whatsapp-sidecar: $(MACOS_DIR)/$(APP_NAME)
	@if [ -d "$(WHATSAPP_DIR)" ] && [ -f "$(WHATSAPP_DIR)/package.json" ]; then \
		echo "Bundling WhatsApp sidecar..."; \
		mkdir -p "$(WHATSAPP_DEST)"; \
		cp -r "$(WHATSAPP_DIR)/src" "$(WHATSAPP_DEST)/"; \
		cp "$(WHATSAPP_DIR)/package.json" "$(WHATSAPP_DEST)/"; \
		cp "$(WHATSAPP_DIR)/tsconfig.json" "$(WHATSAPP_DEST)/"; \
		if [ -d "$(WHATSAPP_DIR)/node_modules" ]; then \
			cp -r "$(WHATSAPP_DIR)/node_modules" "$(WHATSAPP_DEST)/"; \
		fi; \
		echo "WhatsApp sidecar bundled"; \
	fi

clean:
	rm -rf $(BUILD_DIR)

run: all
	@-pkill -x "$(APP_NAME)" 2>/dev/null; true
	@cp -r "$(APP_BUNDLE)" ~/Applications/ 2>/dev/null; true
	@osascript -e "tell application \"Finder\" to open POSIX file \"$$HOME/Applications/$(APP_NAME).app\"" 2>/dev/null || \
	 open ~/Applications/$(APP_NAME).app 2>/dev/null || \
	 echo "Build complete → open build/$(APP_NAME).app from Finder (first launch needs mic + speech permissions)"

# ── DMG ──────────────────────────────────────────────────────────────────────
# Produces build/AutoClawd-<VERSION>.dmg — standard drag-to-Applications UX.
# No external tools required; uses only hdiutil + AppleScript (built into macOS).

dmg: all
	@echo "Building DMG $(DMG_NAME)..."
	@rm -rf "$(DMG_STAGING)" "$(DMG_PATH)" "$(BUILD_DIR)/tmp-rw.dmg"
	@mkdir -p "$(DMG_STAGING)"
	@cp -r "$(APP_BUNDLE)" "$(DMG_STAGING)/"
	@ln -s /Applications "$(DMG_STAGING)/Applications"
	@hdiutil create -srcfolder "$(DMG_STAGING)" \
		-volname "$(APP_NAME)" -fs HFS+ -format UDRW \
		-o "$(BUILD_DIR)/tmp-rw.dmg" > /dev/null
	@hdiutil attach -readwrite -noverify "$(BUILD_DIR)/tmp-rw.dmg" > /dev/null
	@sleep 2
	@bash scripts/set-dmg-appearance.sh "$(APP_NAME)" "$(APP_NAME)"
	@hdiutil detach "/Volumes/$(APP_NAME)" > /dev/null
	@hdiutil convert "$(BUILD_DIR)/tmp-rw.dmg" \
		-format UDZO -imagekey zlib-level=9 \
		-o "$(DMG_PATH)" > /dev/null
	@rm -f "$(BUILD_DIR)/tmp-rw.dmg"
	@rm -rf "$(DMG_STAGING)"
	@echo "Done → $(DMG_PATH)"
