#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP_NAME="PasteRush"
BUILD_DIR="$ROOT/.build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"
VERSION="${PASTERUSH_VERSION:-1.0.0}"
BUILD_NUMBER="${PASTERUSH_BUILD:-1}"
PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-x1EY7L2lr4TL3H28I7wEybGtaFq/0zDiVyrHE4CtoEA=}"
FEED_URL="${SPARKLE_FEED_URL:-https://github.com/fabianszymczak1-cloud/PasteRush/releases/latest/download/appcast.xml}"

echo "==> Building $APP_NAME ($CONFIG) v$VERSION ($BUILD_NUMBER)"
swift build -c "$CONFIG" --product PasteRush

TRIPLE_DIR=""
for d in "$BUILD_DIR/$CONFIG" "$BUILD_DIR"/arm64-apple-macosx/"$CONFIG" "$BUILD_DIR"/x86_64-apple-macosx/"$CONFIG"; do
  if [[ -f "$d/PasteRush" ]]; then
    TRIPLE_DIR="$d"
    break
  fi
done
if [[ -z "$TRIPLE_DIR" ]]; then
  echo "Binary not found"
  exit 1
fi
BIN="$TRIPLE_DIR/PasteRush"

echo "==> Assembling .app at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS"
cp "$BIN" "$MACOS/PasteRush"
chmod +x "$MACOS/PasteRush"

# SPM resource bundle — must live under Contents/Resources for codesign
if [[ -d "$TRIPLE_DIR/PasteRush_PasteRushCore.bundle" ]]; then
  cp -R "$TRIPLE_DIR/PasteRush_PasteRushCore.bundle" "$RESOURCES/PasteRush_PasteRushCore.bundle"
fi

# Sparkle framework
SPARKLE_SRC=""
for s in \
  "$TRIPLE_DIR/Sparkle.framework" \
  "$BUILD_DIR/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
do
  if [[ -d "$s" ]]; then SPARKLE_SRC="$s"; break; fi
done
if [[ -z "$SPARKLE_SRC" ]]; then
  echo "Sparkle.framework not found"
  exit 1
fi
cp -R "$SPARKLE_SRC" "$FRAMEWORKS/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/PasteRush" 2>/dev/null || true

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi
if [[ -f "$ROOT/Resources/Assets.car" ]]; then
  cp "$ROOT/Resources/Assets.car" "$RESOURCES/Assets.car"
fi
if [[ -d "$ROOT/Resources/Sounds" ]]; then
  mkdir -p "$RESOURCES/Sounds"
  cp -R "$ROOT/Resources/Sounds/." "$RESOURCES/Sounds/"
fi
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>pl</string>
  </array>
  <key>CFBundleExecutable</key>
  <string>PasteRush</string>
  <key>CFBundleIdentifier</key>
  <string>com.pasterush.app</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>PasteRush</string>
  <key>CFBundleDisplayName</key>
  <string>PasteRush</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticTermination</key>
  <false/>
  <key>NSSupportsSuddenTermination</key>
  <false/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © PasteRush</string>
  <key>SUFeedURL</key>
  <string>${FEED_URL}</string>
  <key>SUPublicEDKey</key>
  <string>${PUBLIC_ED_KEY}</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
</dict>
</plist>
PLIST

# Ad-hoc sign (deep) for local use / Gatekeeper bypass notes in README
codesign --force --deep --sign - --entitlements "$ROOT/Resources/PasteRush.entitlements" "$APP_DIR" 2>/dev/null \
  || codesign --force --deep --sign - "$APP_DIR"

echo "==> Built: $APP_DIR"
echo "$APP_DIR"
