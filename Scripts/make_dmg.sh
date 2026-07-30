#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-${PASTERUSH_VERSION:-1.0.0}}"
export PASTERUSH_VERSION="$VERSION"
export PASTERUSH_BUILD="${PASTERUSH_BUILD:-$VERSION}"

"$ROOT/Scripts/build_app.sh" release

APP="$ROOT/.build/PasteRush.app"
STAGE="$ROOT/.build/dmg-stage"
DMG_DIR="$ROOT/.build/dmg"
DMG="$DMG_DIR/PasteRush.dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE" "$DMG_DIR"
cp -R "$APP" "$STAGE/PasteRush.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "PasteRush" -srcfolder "$STAGE" -ov -format UDZO -imagekey zlib-level=9 "$DMG"
echo "==> DMG: $DMG"
echo "$DMG"
