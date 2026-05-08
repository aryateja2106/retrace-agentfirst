#!/bin/bash
# =============================================================================
# Retrace Agentfirst DMG Packager
# =============================================================================
# Usage: ./scripts/create-dmg.sh <version>
# Expects scripts/create-release.sh to have exported:
#   build/Build/Products/Release/Retrace Agentfirst.app
# =============================================================================

set -euo pipefail

APP_NAME="Retrace Agentfirst"
VERSION="${1:-}"
RELEASES_DIR="releases"
BUILD_PRODUCTS_DIR="build/Build/Products/Release"
APP_PATH="${BUILD_PRODUCTS_DIR}/${APP_NAME}.app"
DMG_STAGING_DIR="build/dmg-staging"
DMG_NAME="Retrace-Agentfirst-${VERSION}-aarch64.dmg"
DMG_PATH="${RELEASES_DIR}/${DMG_NAME}"
VOLUME_NAME="${APP_NAME} ${VERSION}"

if [ -z "$VERSION" ]; then
    echo "Usage: ./scripts/create-dmg.sh <version>" >&2
    exit 64
fi

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: App not found at ${APP_PATH}" >&2
    echo "Run ./scripts/create-release.sh ${VERSION} first." >&2
    exit 66
fi

mkdir -p "$RELEASES_DIR"
rm -rf "$DMG_STAGING_DIR" "$DMG_PATH"
mkdir -p "$DMG_STAGING_DIR"

cp -R "$APP_PATH" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

codesign --verify --deep --strict "$APP_PATH"
shasum -a 256 "$DMG_PATH" > "${DMG_PATH}.sha256"

echo "DMG: ${DMG_PATH}"
echo "SHA256: ${DMG_PATH}.sha256"
