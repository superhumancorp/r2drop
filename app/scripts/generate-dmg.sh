#!/usr/bin/env bash
# scripts/generate-dmg.sh
# Packages a signed R2Drop.app into a .dmg with drag-to-Applications layout.
#
# Usage:
#   ./scripts/generate-dmg.sh                           # Uses default build output
#   ./scripts/generate-dmg.sh --app /path/to/R2Drop.app # Use a specific .app bundle
#   ./scripts/generate-dmg.sh --sign "Developer ID Application: ..." # Code sign
#
# The .dmg is written to: build/R2Drop-<version>.dmg
#
# Requirements:
#   - macOS (uses hdiutil, which is macOS-only)
#   - The .app bundle must already be built and (optionally) code-signed

set -euo pipefail

# --- Configuration -----------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$APP_DIR/build"
DMG_NAME="R2Drop"
VOLUME_NAME="R2Drop"

# Default: look for the .app in the Xcode DerivedData or build directory
APP_PATH=""
SIGN_IDENTITY=""

# --- Parse arguments ----------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)
            APP_PATH="$2"
            shift 2
            ;;
        --app=*)
            APP_PATH="${1#--app=}"
            shift
            ;;
        --sign)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        --sign=*)
            SIGN_IDENTITY="${1#--sign=}"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--app <path>] [--sign <identity>]"
            echo ""
            echo "  --app <path>       Path to R2Drop.app bundle"
            echo "  --sign <identity>  Code signing identity (e.g. 'Developer ID Application: ...')"
            echo "  --help             Show this help message"
            echo ""
            echo "If --app is not specified, searches common build output locations."
            exit 0
            ;;
        *)
            echo "Error: Unknown argument '$1'"
            echo "Run '$0 --help' for usage."
            exit 1
            ;;
    esac
done

# --- Locate .app bundle -------------------------------------------------------

if [[ -z "$APP_PATH" ]]; then
    # Search common locations for the built .app
    CANDIDATES=(
        "$BUILD_DIR/Build/Products/Release/R2Drop.app"
        "$BUILD_DIR/Release/R2Drop.app"
        "$APP_DIR/R2Drop/build/Release/R2Drop.app"
    )
    for candidate in "${CANDIDATES[@]}"; do
        if [[ -d "$candidate" ]]; then
            APP_PATH="$candidate"
            break
        fi
    done
fi

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
    echo "Error: R2Drop.app not found."
    echo ""
    echo "Either build the app first or specify its location:"
    echo "  $0 --app /path/to/R2Drop.app"
    echo ""
    echo "Searched:"
    for candidate in "${CANDIDATES[@]:-}"; do
        echo "  $candidate"
    done
    exit 1
fi

echo "Using app bundle: $APP_PATH"

# --- Extract version ----------------------------------------------------------

# Read version from the app's Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "0.1.0")

DMG_FILENAME="${DMG_NAME}-${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_FILENAME"

echo "Version: $VERSION"
echo "Output:  $DMG_PATH"

# --- Optional code signing ----------------------------------------------------

if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "Signing app with identity: $SIGN_IDENTITY"
    codesign --force --deep --options runtime \
        --sign "$SIGN_IDENTITY" "$APP_PATH"
    echo "  Signature verified:"
    codesign --verify --verbose=2 "$APP_PATH" 2>&1 | head -3
fi

# --- Create DMG ---------------------------------------------------------------

mkdir -p "$BUILD_DIR"

# Clean up any previous DMG
rm -f "$DMG_PATH"

# Create a temporary directory for the DMG contents
STAGING_DIR=$(mktemp -d)
trap 'rm -rf "$STAGING_DIR"' EXIT

# Copy the .app and create Applications symlink
cp -a "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "Creating DMG..."

# Create the DMG using hdiutil
# -volname: name shown when mounted
# -srcfolder: directory containing the DMG contents
# -ov: overwrite existing
# -format UDZO: compressed read-only image
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# --- Summary ------------------------------------------------------------------

echo ""
echo "DMG created successfully."
echo "  Path: $DMG_PATH"
echo "  Size: $(du -h "$DMG_PATH" | cut -f1)"
echo ""
echo "To notarize (requires Apple Developer credentials):"
echo "  xcrun notarytool submit '$DMG_PATH' \\"
echo "    --apple-id \"\$APPLE_ID\" \\"
echo "    --password \"\$APPLE_APP_SPECIFIC_PASSWORD\" \\"
echo "    --team-id \"\$APPLE_TEAM_ID\" \\"
echo "    --wait"
