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
	-lsqlite3

.PHONY: all clean run

all: $(MACOS_DIR)/$(APP_NAME)

$(MACOS_DIR)/$(APP_NAME): $(SOURCES) Info.plist $(ICON_ICNS)
	@mkdir -p "$(MACOS_DIR)" "$(RESOURCES)"
	swiftc $(SWIFT_FLAGS) \
		-o "$(MACOS_DIR)/$(APP_NAME)" \
		$(SOURCES)
	@cp Info.plist "$(CONTENTS)/"
	@plutil -replace CFBundleName -string "$(APP_NAME)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleDisplayName -string "$(APP_NAME)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleExecutable -string "$(APP_NAME)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleIdentifier -string "$(BUNDLE_ID)" "$(CONTENTS)/Info.plist"
	@cp $(ICON_ICNS) "$(RESOURCES)/"
	@codesign --force --options runtime --sign "$(CODESIGN_IDENTITY)" \
		--entitlements AutoClawd.entitlements "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"

clean:
	rm -rf $(BUILD_DIR)

run: all
	open "$(APP_BUNDLE)"
