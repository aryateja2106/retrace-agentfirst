#!/bin/bash

# Build and package Retrace as a proper .app bundle
# This allows macOS to properly identify the app for permissions

set -e  # Exit on error

BUILD_CONFIG="release"
APP_VARIANT="${RETRACE_APP_VARIANT:-prod}"
INSTALL_TO_APPLICATIONS="${RETRACE_INSTALL_TO_APPLICATIONS:-}"
DEFAULT_CODESIGN_IDENTITY="Retrace Local Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$DEFAULT_CODESIGN_IDENTITY\""; then
    CODESIGN_IDENTITY="${RETRACE_CODESIGN_IDENTITY:-$DEFAULT_CODESIGN_IDENTITY}"
else
    CODESIGN_IDENTITY="${RETRACE_CODESIGN_IDENTITY:--}"
fi

usage() {
    echo "Usage: $0 [--prod|--dev] [--install|--no-install]"
    echo ""
    echo "  --prod        Build the production app identity: Retrace.app"
    echo "  --dev         Build the parallel dev app identity: Retrace Dev.app"
    echo "  --install     Copy/update the selected app in /Applications and install retrace-cli"
    echo "  --no-install  Leave the app only in the SwiftPM build directory"
    echo ""
    echo "Environment:"
    echo "  RETRACE_CODESIGN_IDENTITY   Code signing identity to use (default: ad-hoc '-')"
    echo "                              Example: RETRACE_CODESIGN_IDENTITY=\"$DEFAULT_CODESIGN_IDENTITY\" $0 --dev --install"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prod)
            APP_VARIANT="prod"
            ;;
        --dev)
            APP_VARIANT="dev"
            ;;
        --install)
            INSTALL_TO_APPLICATIONS="1"
            ;;
        --no-install)
            INSTALL_TO_APPLICATIONS="0"
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

case "$APP_VARIANT" in
    prod)
        APP_NAME="Retrace"
        BUNDLE_ID="io.retrace.app"
        EXECUTABLE_NAME="Retrace"
        URL_SCHEME="retrace"
        IS_DEV_BUILD="true"
        ;;
    dev)
        APP_NAME="Retrace Dev"
        BUNDLE_ID="io.retrace.app.dev"
        EXECUTABLE_NAME="Retrace Dev"
        URL_SCHEME="retrace-dev"
        IS_DEV_BUILD="true"
        ;;
    *)
        echo "Unknown RETRACE_APP_VARIANT: $APP_VARIANT"
        usage
        exit 1
        ;;
esac

BUILD_DIR="$(swift build -c "$BUILD_CONFIG" --show-bin-path)"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

# ---------------------------------------------------------------------------
# Parse version from project.yml (single source of truth)
# ---------------------------------------------------------------------------
MARKETING_VERSION=$(grep 'MARKETING_VERSION' project.yml | head -1 | sed 's/.*"\(.*\)".*/\1/')
BUILD_NUMBER=$(grep 'CURRENT_PROJECT_VERSION' project.yml | head -1 | sed 's/.*"\(.*\)".*/\1/')

if [ -z "$MARKETING_VERSION" ]; then
    echo "⚠️  Could not parse MARKETING_VERSION from project.yml, using default"
    MARKETING_VERSION="0.0.0"
fi
if [ -z "$BUILD_NUMBER" ]; then
    BUILD_NUMBER="0"
fi

# ---------------------------------------------------------------------------
# Require a clean working tree so the embedded commit hash is accurate
# ---------------------------------------------------------------------------
if [ -n "$(git diff --name-only HEAD 2>/dev/null)" ]; then
    echo "INFO: Building with local uncommitted changes."
    echo "      Build metadata will use HEAD commit (local diff is not encoded)."
    echo "      Local changes:"
    git diff --stat
fi

# ---------------------------------------------------------------------------
# Collect build metadata (embedded into generated Info.plist)
# ---------------------------------------------------------------------------
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_COMMIT_FULL=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
BUILD_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

# Detect fork name from the origin remote (e.g. "aculich/retrace")
REMOTE_URL=$(git remote get-url origin 2>/dev/null || true)
FORK_NAME=$(printf "%s" "$REMOTE_URL" | sed -E 's#^(git@github\.com:|ssh://git@github\.com/|https://github\.com/)##; s#\.git$##')

echo "🔨 Building $APP_NAME..."
./scripts/check_no_nanoseconds_sleep.sh
echo "🔨 Building $APP_NAME v${MARKETING_VERSION} (${BUILD_CONFIG})..."
echo "   commit: ${GIT_COMMIT} (${GIT_BRANCH})"
echo "   bundle: ${BUNDLE_ID}"
echo "   signing identity: ${CODESIGN_IDENTITY}"
./scripts/check_no_nanoseconds_sleep.sh
swift build -c release

if [ ! -f "$BUILD_DIR/Retrace" ]; then
    echo "❌ Expected release executable not found at $BUILD_DIR/Retrace"
    echo "   SwiftPM release bin path: $BUILD_DIR"
    exit 1
fi

if [ ! -f "$BUILD_DIR/retrace-cli" ]; then
    echo "❌ Expected release CLI not found at $BUILD_DIR/retrace-cli"
    echo "   SwiftPM release bin path: $BUILD_DIR"
    exit 1
fi

echo "📦 Creating app bundle..."

# Create app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$APP_BUNDLE/Contents/Library/Helpers"
mkdir -p "$APP_BUNDLE/Contents/Library/LaunchAgents"

# Copy executable. The dev bundle uses a distinct executable name so it can sit
# beside the production app in Activity Monitor and Finder.
cp "$BUILD_DIR/Retrace" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

# Copy bundled crash recovery helper assets used by the app's launch agent flow.
CRASH_RECOVERY_HELPER="$BUILD_DIR/RetraceCrashRecoveryHelper"
CRASH_RECOVERY_PLIST="UI/LaunchAgents/io.retrace.app.crash-recovery.plist"

if [ ! -f "$CRASH_RECOVERY_HELPER" ]; then
    echo "❌ Crash recovery helper not found at $CRASH_RECOVERY_HELPER"
    exit 1
fi

if [ ! -f "$CRASH_RECOVERY_PLIST" ]; then
    echo "❌ Crash recovery launch agent plist not found at $CRASH_RECOVERY_PLIST"
    exit 1
fi

cp "$CRASH_RECOVERY_HELPER" "$APP_BUNDLE/Contents/Library/Helpers/RetraceCrashRecoveryHelper"
cp "$CRASH_RECOVERY_PLIST" \
    "$APP_BUNDLE/Contents/Library/LaunchAgents/io.retrace.app.crash-recovery.plist"

# Add rpath so the app finds embedded frameworks when run from .app bundle
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true

# Copy embedded frameworks (Sparkle and any others the app links to)
for fw in Sparkle; do
    if [ -d "$BUILD_DIR/$fw.framework" ]; then
        cp -R "$BUILD_DIR/$fw.framework" "$APP_BUNDLE/Contents/Frameworks/"
    fi
done

# Copy app icon (CLT lacks actool to compile Assets.xcassets, so use repo's prebuilt .icns)
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Copy Info.plist with variable substitution (fixes $(MARKETING_VERSION) bug)
sed -e "s/\$(MARKETING_VERSION)/$MARKETING_VERSION/g" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD_NUMBER/g" \
    "UI/Info.plist" > "$APP_BUNDLE/Contents/Info.plist"

set_plist_string() {
    local key="$1"
    local value="$2"
    /usr/libexec/PlistBuddy -c "Set :$key \"$value\"" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :$key string \"$value\"" "$APP_BUNDLE/Contents/Info.plist"
}

set_plist_bool() {
    local key="$1"
    local value="$2"
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :$key bool $value" "$APP_BUNDLE/Contents/Info.plist"
}

set_plist_string "RetraceVersion" "$MARKETING_VERSION"
set_plist_string "RetraceBuildNumber" "$BUILD_NUMBER"
set_plist_string "RetraceGitCommit" "$GIT_COMMIT"
set_plist_string "RetraceGitCommitFull" "$GIT_COMMIT_FULL"
set_plist_string "RetraceGitBranch" "$GIT_BRANCH"
set_plist_string "RetraceBuildDate" "$BUILD_DATE"
set_plist_string "RetraceBuildConfig" "$BUILD_CONFIG"
set_plist_string "RetraceBuildVariant" "$APP_VARIANT"
set_plist_bool "RetraceIsDevBuild" "$IS_DEV_BUILD"
set_plist_string "RetraceForkName" "$FORK_NAME"
set_plist_string "CFBundleName" "$APP_NAME"
set_plist_string "CFBundleDisplayName" "$APP_NAME"
set_plist_string "CFBundleIdentifier" "$BUNDLE_ID"
set_plist_string "CFBundleExecutable" "$EXECUTABLE_NAME"
/usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 $URL_SCHEME" "$APP_BUNDLE/Contents/Info.plist"

if [ "$APP_VARIANT" = "dev" ]; then
    set_plist_bool "SUEnableAutomaticChecks" "false"
    set_plist_bool "SUAllowsAutomaticUpdates" "false"
    set_plist_bool "SUAutomaticallyUpdate" "false"
fi

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "✍️  Signing app bundle..."

CODESIGN_ARGS=(--force --sign "$CODESIGN_IDENTITY")
if [ "$CODESIGN_IDENTITY" != "-" ]; then
    CODESIGN_ARGS+=(--timestamp=none)
fi

# Sign frameworks first (required before signing the app)
for fw in "$APP_BUNDLE/Contents/Frameworks/"*.framework; do
    [ -d "$fw" ] && codesign "${CODESIGN_ARGS[@]}" "$fw"
done

# Sign nested helper executables before the containing app.
if [ -f "$APP_BUNDLE/Contents/Library/Helpers/RetraceCrashRecoveryHelper" ]; then
    codesign "${CODESIGN_ARGS[@]}" "$APP_BUNDLE/Contents/Library/Helpers/RetraceCrashRecoveryHelper"
fi

# Sign the app bundle with entitlements. Prefer a stable local identity so TCC
# permissions survive rebuilds; fall back to ad-hoc when no identity is present.
codesign "${CODESIGN_ARGS[@]}" --deep --entitlements "UI/Retrace.entitlements" "$APP_BUNDLE"

install_cli() {
    local cli_install_dir="${RETRACE_CLI_INSTALL_DIR:-$HOME/.local/bin}"
    mkdir -p "$cli_install_dir"
    cp "$BUILD_DIR/retrace-cli" "$cli_install_dir/retrace-cli"
    chmod +x "$cli_install_dir/retrace-cli"
    echo "✅ Installed retrace-cli to $cli_install_dir/retrace-cli"
}

echo "✅ Build complete!"
echo ""
echo "📍 App bundle location: $APP_BUNDLE"
echo "   Version: $MARKETING_VERSION ($BUILD_NUMBER) · $GIT_COMMIT"
echo "   Bundle ID: $BUNDLE_ID"
echo ""

if [ -z "$INSTALL_TO_APPLICATIONS" ]; then
    if [ -d "/Applications/$APP_NAME.app" ]; then
        INSTALL_TO_APPLICATIONS="1"
    else
        INSTALL_TO_APPLICATIONS="0"
    fi
fi

if [ "$INSTALL_TO_APPLICATIONS" = "1" ]; then
    if [ -d "/Applications/$APP_NAME.app" ]; then
        echo "📲 Found existing $APP_NAME in /Applications/, updating in place..."
        echo "   This preserves your permissions settings."
    else
        echo "📲 Installing $APP_NAME to /Applications/..."
    fi

    # Kill the app if running
    pkill -x "$EXECUTABLE_NAME" 2>/dev/null || true

    # Replace the selected app variant.
    rm -rf "/Applications/$APP_NAME.app"
    cp -r "$APP_BUNDLE" /Applications/
    install_cli

    echo "✅ Updated /Applications/$APP_NAME.app"
    echo ""
    echo "To run:"
    echo "  open /Applications/$APP_NAME.app"
else
    echo "💡 For persistent permissions during development, install to /Applications/:"
    echo "   $0 --$APP_VARIANT --install && open \"/Applications/$APP_NAME.app\""
    echo ""
    echo "Or run from build directory (permissions reset on each rebuild):"
    echo "   open $APP_BUNDLE"
fi
