#!/bin/bash
# Builds "LG Remote.app". With `install`, copies it to /Applications (Dock & Launchpad)
# and links the `lgremote` CLI into a bin directory on your PATH.
#
#   scripts/build-app.sh            # build into ./build
#   scripts/build-app.sh install    # build + install
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="LG Remote"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "→ Compiling (release)…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/LGRemote"

if [[ ! -f "$BUILD_DIR/AppIcon.icns" || scripts/make-icon.swift -nt "$BUILD_DIR/AppIcon.icns" ]]; then
    echo "→ Rendering icon…"
    rm -rf "$BUILD_DIR/AppIcon.iconset"
    swift scripts/make-icon.swift "$BUILD_DIR/AppIcon.iconset"
    iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$BUILD_DIR/AppIcon.icns"
fi

echo "→ Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LGRemote"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BUILD_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null
echo "✓ Built $APP"

if [[ "${1:-}" == "install" ]]; then
    DEST="/Applications"
    [[ -w "$DEST" ]] || DEST="$HOME/Applications"
    mkdir -p "$DEST"
    TARGET="$DEST/$APP_NAME.app"

    # Quit a running copy so it can be replaced.
    osascript -e "tell application id \"dev.lgremote.LGRemote\" to quit" >/dev/null 2>&1 || true
    if [[ -d "$TARGET" ]]; then rm -rf "$TARGET"; fi
    cp -R "$APP" "$TARGET"
    echo "✓ Installed $TARGET"

    for dir in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
        if [[ -d "$dir" && -w "$dir" ]]; then
            ln -sf "$TARGET/Contents/MacOS/LGRemote" "$dir/lgremote"
            echo "✓ Linked CLI: $dir/lgremote"
            break
        fi
    done
fi
