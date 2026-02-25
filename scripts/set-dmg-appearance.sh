#!/usr/bin/env bash
# Usage: set-dmg-appearance.sh <VolumeName> <AppName>
# Runs AppleScript to position icons and set window size on a mounted DMG.

VOLUME_NAME="$1"
APP_NAME="$2"

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 200, 760, 480}
        set the icon size of the icon view options of container window to 100
        set the arrangement of the icon view options of container window to not arranged
        set position of item "${APP_NAME}.app" of container window to {160, 140}
        set position of item "Applications" of container window to {400, 140}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
APPLESCRIPT
