# PasteRush

**Local clipboard history for macOS** — fast search, image preview, and privacy by default. No account. No cloud. No telemetry.

<p align="center">
  <img src="docs/screenshots/popup.png" alt="PasteRush search popup" width="820" />
</p>

<p align="center">
  <a href="https://github.com/fabianszymczak1-cloud/PasteRush/releases/latest"><img alt="Download" src="https://img.shields.io/badge/download-DMG-0B5FFF?style=for-the-badge" /></a>
  <a href="https://buymeacoffee.com/5r8nffw85nw"><img alt="Buy Me a Coffee" src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-FFDD00?style=for-the-badge&logo=buymeacoffee&logoColor=black" /></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-black?style=for-the-badge" />
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.9-F05138?style=for-the-badge&logo=swift&logoColor=white" />
</p>

## Download

**[Download PasteRush.dmg](https://github.com/fabianszymczak1-cloud/PasteRush/releases/latest/download/PasteRush.dmg)** (latest release)

If PasteRush helps you, you can support development here:

**[Buy Me a Coffee](https://buymeacoffee.com/5r8nffw85nw)**

## Features

| | |
|---|---|
| **Clipboard history** | Text, RTF/HTML, images, and files — stored only on your Mac |
| **Instant search** | SQLite FTS5 with filters (`type:`, `app:`, `pinned:`, dates) |
| **Large preview** | Space / ⌥Space for a nearly fullscreen media viewer; ←→ navigate |
| **Smart paste** | Enter pastes into the previous app (Accessibility) |
| **Pins & groups** | Keep important clips forever; organize with groups |
| **Transforms** | Paste special: case changes, slug, UUID, join multiple clips… |
| **Private by design** | No telemetry, no account, optional private mode & excluded apps |
| **Auto-updates** | Sparkle checks GitHub Releases for new versions |
| **EN + PL** | Follows your macOS system language |

<p align="center">
  <img src="docs/screenshots/preview.png" alt="Large image preview" width="400" />
  &nbsp;
  <img src="docs/screenshots/settings.png" alt="Settings" width="400" />
</p>

## Install

1. Download the DMG and drag **PasteRush** to **Applications** (do not run it from the DMG).
2. Open the app (menu bar clipboard icon).
3. Grant **Accessibility** when onboarding asks (needed for auto-paste).
4. Copy something → press **⌃`** (Control + backtick) → type → **Enter**.

## macOS security warning (“malware” / “cannot be opened”)

PasteRush is **not malware**. Builds are currently **ad-hoc signed** (no paid Apple Developer ID / notarization yet), so Gatekeeper may show warnings such as:

- *“Apple could not verify PasteRush is free of malware”*
- *“PasteRush cannot be opened because it is from an unidentified developer”*
- *“PasteRush was blocked to protect your Mac”*

That is expected for open-source apps without notarization. You only need to allow it **once**.

### Option A — System Settings (recommended)

1. Try to open **PasteRush** once (from `/Applications`). If macOS blocks it, click **Done** / **OK**.
2. Open **System Settings → Privacy & Security**.
3. Scroll down to the security section. You should see a message about PasteRush being blocked.
4. Click **Open Anyway**.
5. Confirm again in the dialog (**Open**).
6. If prompted, enter your Mac password / Touch ID.

On some macOS versions the button appears only **after** the first blocked open attempt.

### Option B — Terminal (always works)

```bash
xattr -dr com.apple.quarantine /Applications/PasteRush.app
```

Then open PasteRush again from Applications.

### After that

- Menu bar icon should appear (clipboard).
- Complete onboarding and grant **Accessibility** if asked.
- Future updates via **Sparkle** (Check for Updates) usually do not need this step again.

If something still fails, make sure the app is in `/Applications` and not sitting on the Desktop or inside the mounted DMG.
## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| ⌃` (configurable) | Open history |
| ↵ | Paste |
| ⇧↵ | Paste as plain text |
| ⌘↵ | Copy only |
| ⌥↵ | Properties |
| ␣ / ⌥␣ | Large preview |
| ↑↓←→ | Navigate (also in preview) |
| Esc | Close preview / popup |
| ⌘P | Pin · ⌘E Edit · ⌘G Groups · ⌘⌫ Delete · ⌘, Settings |

## Support

PasteRush is free. Tips keep the project going:

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-FFDD00?style=for-the-badge&logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/5r8nffw85nw)

## Build from source

```bash
cd PasteRush
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
./Scripts/build_app.sh release
# optional DMG:
./Scripts/make_dmg.sh 1.0.0
cp -R .build/PasteRush.app /Applications/
```

Release (needs `gh` auth + Sparkle private key in `Secrets/`):

```bash
./Scripts/release.sh 1.0.0
```

## License

MIT — see source; contributions welcome.
