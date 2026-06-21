#!/usr/bin/env bash
# make-dmg.sh <App.app> <out.dmg> — 把 .app 包成拖放安裝的 DMG（含 /Applications 捷徑）。
set -euo pipefail

APP="$1"
DMG="$2"
NAME="$(basename "$APP" .app)"

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
mkdir -p "$(dirname "$DMG")"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "[OK] $DMG"
