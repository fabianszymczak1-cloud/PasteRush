#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:?usage: release.sh <version> e.g. 1.0.0}"
export PASTERUSH_VERSION="$VERSION"
export PASTERUSH_BUILD="${PASTERUSH_BUILD:-$VERSION}"
TAG="v$VERSION"

SIGN_UPDATE="$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update"
PRIVATE_KEY="${SPARKLE_PRIVATE_KEY_FILE:-$ROOT/Secrets/sparkle_eddsa_private.key}"
BMC="https://buymeacoffee.com/5r8nffw85nw"
REPO="fabianszymczak1-cloud/PasteRush"
DMG_NAME="PasteRush.dmg"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${DMG_NAME}"

if [[ ! -f "$PRIVATE_KEY" ]]; then
  echo "Missing private key at $PRIVATE_KEY"
  echo "Set SPARKLE_PRIVATE_KEY_FILE or create Secrets/sparkle_eddsa_private.key"
  exit 1
fi

"$ROOT/Scripts/make_dmg.sh" "$VERSION"
DMG="$ROOT/.build/dmg/PasteRush.dmg"

echo "==> Signing update with Sparkle"
SIGNATURE_LINE="$("$SIGN_UPDATE" -f "$PRIVATE_KEY" "$DMG")"
# sign_update prints: sparkle:edSignature="..." length="..."
ED_SIG="$(echo "$SIGNATURE_LINE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
LENGTH="$(echo "$SIGNATURE_LINE" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
if [[ -z "$ED_SIG" || -z "$LENGTH" ]]; then
  echo "Failed to parse sign_update output: $SIGNATURE_LINE"
  exit 1
fi

PUB_DATE="$(date -u +"%a, %d %b %Y %H:%M:%S +0000")"
APPCAST="$ROOT/.build/dmg/appcast.xml"
cat > "$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>PasteRush</title>
    <link>https://github.com/${REPO}/releases</link>
    <description>PasteRush updates</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure
        url="${DOWNLOAD_URL}"
        length="${LENGTH}"
        type="application/octet-stream"
        sparkle:edSignature="${ED_SIG}" />
      <description><![CDATA[
        <h2>PasteRush ${VERSION}</h2>
        <p>Local clipboard history for macOS.</p>
        <p><a href="${BMC}">Buy Me a Coffee</a></p>
      ]]></description>
    </item>
  </channel>
</rss>
XML

NOTES="$(cat <<EOF
## PasteRush ${VERSION}

Local, private clipboard history for macOS.

### Download
- [${DMG_NAME}](${DOWNLOAD_URL})

### Support
If PasteRush helps you: [Buy Me a Coffee](${BMC})

### Notes
- macOS 14+
- First launch may require **Privacy & Security → Open Anyway** (ad-hoc signed build)
- Or: \`xattr -dr com.apple.quarantine /Applications/PasteRush.app\`
EOF
)"

echo "==> Creating GitHub release $TAG"
gh release create "$TAG" \
  --repo "$REPO" \
  --title "PasteRush $VERSION" \
  --notes "$NOTES" \
  "$DMG" \
  "$APPCAST"

echo "==> Done: https://github.com/${REPO}/releases/tag/${TAG}"
