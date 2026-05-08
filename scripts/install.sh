#!/bin/bash
# Install Retrace Agentfirst from a hosted DMG URL.
# Usage:
#   curl -fsSL https://example.com/install.sh | bash -s -- --url https://example.com/Retrace-Agentfirst.dmg

set -euo pipefail

APP_NAME="Retrace Agentfirst.app"
URL=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --url)
            URL="${2:-}"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 64
            ;;
    esac
done

if [ -z "$URL" ]; then
    echo "Usage: install.sh --url https://.../Retrace-Agentfirst.dmg" >&2
    exit 64
fi

TMPDIR="$(mktemp -d)"
DMG_PATH="${TMPDIR}/Retrace-Agentfirst.dmg"
MOUNT_OUTPUT="${TMPDIR}/mount.txt"

cleanup() {
    if [ -f "$MOUNT_OUTPUT" ]; then
        MOUNT_POINT="$(awk '/\\/Volumes\\// {print substr($0, index($0, "/Volumes/"))}' "$MOUNT_OUTPUT" | tail -n 1)"
        if [ -n "${MOUNT_POINT:-}" ]; then
            hdiutil detach "$MOUNT_POINT" -quiet || true
        fi
    fi
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

curl -fL "$URL" -o "$DMG_PATH"
hdiutil attach "$DMG_PATH" -nobrowse -quiet | tee "$MOUNT_OUTPUT" >/dev/null
MOUNT_POINT="$(awk '/\\/Volumes\\// {print substr($0, index($0, "/Volumes/"))}' "$MOUNT_OUTPUT" | tail -n 1)"

if [ -z "$MOUNT_POINT" ] || [ ! -d "${MOUNT_POINT}/${APP_NAME}" ]; then
    echo "ERROR: ${APP_NAME} not found in mounted DMG" >&2
    exit 66
fi

ditto "${MOUNT_POINT}/${APP_NAME}" "/Applications/${APP_NAME}"

echo "Installed /Applications/${APP_NAME}"
