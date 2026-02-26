#!/usr/bin/env bash
# install.sh — AutoClawd installer for macOS
# Handles Gatekeeper on macOS 13+ (including macOS 26 Tahoe) without requiring
# a paid Apple Developer certificate.
#
# Usage:
#   chmod +x install.sh
#   ./install.sh          # builds from source then installs
#   ./install.sh --no-build   # installs pre-built bundle from build/

set -euo pipefail

# Always run from the directory containing this script,
# so it works regardless of where the user calls it from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="AutoClawd"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR="build"
BUILD_APP="${BUILD_DIR}/${APP_BUNDLE}"
INSTALL_DEST="/Applications/${APP_BUNDLE}"

# ── helpers ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}▶${RESET} $*"; }
success() { echo -e "${GREEN}✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET} $*"; }
die()     { echo -e "${RED}✗${RESET} $*" >&2; exit 1; }

# ── pre-flight ────────────────────────────────────────────────────────────────

NO_BUILD=false
for arg in "$@"; do [[ "$arg" == "--no-build" ]] && NO_BUILD=true; done

# ── step 1: build ─────────────────────────────────────────────────────────────

if [[ "$NO_BUILD" == false ]]; then
    info "Building ${APP_NAME}..."
    make all
    success "Build complete → ${BUILD_APP}"
else
    [[ -d "$BUILD_APP" ]] || die "No pre-built bundle found at ${BUILD_APP}. Run without --no-build."
    info "Skipping build (--no-build)"
fi

# ── step 2: kill running instance ─────────────────────────────────────────────

if pgrep -xq "$APP_NAME" 2>/dev/null; then
    info "Stopping running ${APP_NAME}..."
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 1
fi

# ── step 3: install to /Applications (needs sudo) ────────────────────────────

info "Installing to /Applications (may prompt for password)..."
sudo rm -rf "$INSTALL_DEST"
sudo cp -r "$BUILD_APP" "$INSTALL_DEST"
success "Copied to ${INSTALL_DEST}"

# ── step 4: strip Gatekeeper quarantine & re-sign ────────────────────────────
#
# On macOS 13–26 (Tahoe), the "application can't be opened" dialog is
# triggered by the com.apple.quarantine extended attribute. Removing it tells
# Gatekeeper not to run its notarization check.
#
# We also force an ad-hoc re-sign after the copy so macOS sees a clean,
# consistent signature on the installed path.

info "Clearing Gatekeeper quarantine..."
sudo xattr -cr "$INSTALL_DEST"
success "Quarantine attributes removed"

info "Ad-hoc re-signing installed bundle..."
# Use AutoClawd-adhoc.entitlements (NOT AutoClawd.entitlements):
# The main entitlements file includes com.apple.developer.networking.wifi-info,
# which is a RESTRICTED entitlement requiring an Apple Developer ID cert.
# Embedding it in an ad-hoc signed binary causes launchd Code=163 spawn failure.
sudo codesign --force --sign - \
    --entitlements AutoClawd-adhoc.entitlements \
    "$INSTALL_DEST" 2>/dev/null || \
sudo codesign --force --deep --sign - "$INSTALL_DEST"
success "Bundle signed"

# ── step 5: verify & launch ───────────────────────────────────────────────────

info "Verifying signature..."
codesign --verify --deep "$INSTALL_DEST" 2>/dev/null && \
    success "Signature valid" || \
    warn "Signature check returned non-zero (normal for ad-hoc; app should still run)"

info "Launching ${APP_NAME}..."
open "$INSTALL_DEST"

echo ""
echo -e "${BOLD}${GREEN}Installation complete!${RESET}"
echo -e "  ${CYAN}${APP_NAME}${RESET} is now in /Applications and running in your menu bar."
echo ""
echo -e "${YELLOW}First-run permissions:${RESET}"
echo "  macOS will ask for Microphone and Speech Recognition access."
echo "  Please grant both so ${APP_NAME} can transcribe your conversations."
echo ""
echo -e "${YELLOW}If the app still won't open:${RESET}"
echo "  1. Go to System Settings → Privacy & Security"
echo "  2. Scroll down to find '${APP_NAME} was blocked'"
echo "  3. Click 'Open Anyway'"
