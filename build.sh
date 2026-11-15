#!/bin/bash
# Builds Islet.app from the Swift package and signs it ad hoc.
# Usage:  ./build.sh        build only
#         ./build.sh run    build and launch
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/Islet.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Islet" "$APP/Contents/MacOS/Islet"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Built $APP"
if [[ "${1:-}" == "run" ]]; then
    pkill -x Islet 2>/dev/null || true
    open "$APP"
fi
