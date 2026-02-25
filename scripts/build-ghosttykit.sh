#!/usr/bin/env bash
# build-ghosttykit.sh — Build GhosttyKit.xcframework from Ghostty source.
#
# Prerequisites:
#   - Zig 0.14+ (brew install zig@0.14  OR  https://ziglang.org/download/)
#   - Xcode Command Line Tools
#
# The script clones Ghostty into .build-deps/, builds the static library,
# and copies the resulting xcframework into AgentOS/Frameworks/.
#
# After running this script:
#   1. Ensure AgentOS/Package.swift uses the GhosttyKit binaryTarget
#   2. Run: cd AgentOS && swift build

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DEPS_DIR="$ROOT_DIR/.build-deps"
GHOSTTY_DIR="$BUILD_DEPS_DIR/ghostty"
LOCAL_GHOSTTY_DIR="$ROOT_DIR/ghostty"
FRAMEWORK_DEST="$ROOT_DIR/AgentOS/Frameworks"

# -----------------------------------------------------------------------
# 1. Check Zig version
# -----------------------------------------------------------------------
# .app runtime may not inherit Homebrew PATH
if ! command -v zig &>/dev/null && [[ -x /opt/homebrew/bin/zig ]]; then
    export PATH="/opt/homebrew/bin:$PATH"
fi

if ! command -v zig &>/dev/null; then
    echo "Error: Zig not found. Install Zig 0.14+:"
    echo "  brew install zig@0.14"
    echo "  OR download from https://ziglang.org/download/"
    exit 1
fi

ZIG_VERSION=$(zig version 2>/dev/null || echo "0.0.0")
ZIG_MAJOR=$(echo "$ZIG_VERSION" | cut -d. -f1)
ZIG_MINOR=$(echo "$ZIG_VERSION" | cut -d. -f2)

if [[ "$ZIG_MAJOR" -lt 0 ]] || { [[ "$ZIG_MAJOR" -eq 0 ]] && [[ "$ZIG_MINOR" -lt 14 ]]; }; then
    echo "Error: Zig 0.14+ required, found $ZIG_VERSION"
    exit 1
fi

echo "Using Zig $ZIG_VERSION"

# -----------------------------------------------------------------------
# 2. Resolve Ghostty source
# -----------------------------------------------------------------------
mkdir -p "$BUILD_DEPS_DIR"

if [[ -d "$LOCAL_GHOSTTY_DIR/.git" ]]; then
    echo "Using local Ghostty source: $LOCAL_GHOSTTY_DIR"
    GHOSTTY_DIR="$LOCAL_GHOSTTY_DIR"
elif [[ -d "$GHOSTTY_DIR/.git" ]]; then
    echo "Updating Ghostty source..."
    git -C "$GHOSTTY_DIR" fetch --depth=1 origin main
    git -C "$GHOSTTY_DIR" checkout FETCH_HEAD
else
    echo "Cloning Ghostty source..."
    git clone --depth=1 https://github.com/ghostty-org/ghostty.git "$GHOSTTY_DIR"
fi

# -----------------------------------------------------------------------
# 3. Build GhosttyKit
# -----------------------------------------------------------------------
echo "Building GhosttyKit (ReleaseFast)..."
cd "$GHOSTTY_DIR"

# Build only xcframework to avoid xcodebuild app packaging side effects
# (e.g. Sparkle dependency fetch) and keep CI/local build deterministic.
zig build -Doptimize=ReleaseFast -Demit-xcframework=true -Demit-macos-app=false

# Locate the built xcframework
XCFRAMEWORK=""
for candidate in \
    "$GHOSTTY_DIR/macos/GhosttyKit.xcframework" \
    "$GHOSTTY_DIR/zig-out/frameworks/GhosttyKit.xcframework" \
    "$GHOSTTY_DIR/zig-out/GhosttyKit.xcframework"; do
    if [[ -d "$candidate" ]]; then
        XCFRAMEWORK="$candidate"
        break
    fi
done

if [[ -z "$XCFRAMEWORK" ]]; then
    echo "Error: GhosttyKit.xcframework not found after build."
    echo "Searched:"
    echo "  $GHOSTTY_DIR/macos/GhosttyKit.xcframework"
    echo "  $GHOSTTY_DIR/zig-out/frameworks/GhosttyKit.xcframework"
    echo "  $GHOSTTY_DIR/zig-out/GhosttyKit.xcframework"
    exit 1
fi

echo "Found xcframework at: $XCFRAMEWORK"

# -----------------------------------------------------------------------
# 4. Copy to project
# -----------------------------------------------------------------------
mkdir -p "$FRAMEWORK_DEST"
rm -rf "$FRAMEWORK_DEST/GhosttyKit.xcframework"
cp -R "$XCFRAMEWORK" "$FRAMEWORK_DEST/GhosttyKit.xcframework"

echo ""
echo "GhosttyKit.xcframework installed to:"
echo "  $FRAMEWORK_DEST/GhosttyKit.xcframework"
echo ""
echo "Next steps:"
echo "  1. Ensure AgentOS/Package.swift uses:"
echo "     .binaryTarget(name: \"GhosttyKit\", path: \"Frameworks/GhosttyKit.xcframework\")"
echo "  2. cd AgentOS && swift build"
echo ""
echo "Done."
