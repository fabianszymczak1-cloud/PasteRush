# Installation guide

PasteRush is a menu-bar clipboard history app for **macOS 14+**. This guide covers download, first launch, Gatekeeper, and **Accessibility** permission (required for auto-paste).

## 1. Download

Get the latest DMG from GitHub Releases:

**[Download PasteRush.dmg](https://github.com/fabianszymczak1-cloud/PasteRush/releases/latest/download/PasteRush.dmg)**

## 2. Install

1. Open the DMG.
2. Drag **PasteRush** into the **Applications** folder.
3. Eject the DMG.
4. Open **PasteRush** from `/Applications` (Finder → Applications, or Spotlight).

Do **not** run the app from inside the mounted DMG — always use the copy in Applications.

After a successful launch you should see a **clipboard** icon in the menu bar.

## 3. Allow the app (Gatekeeper)

Builds are currently **ad-hoc signed** (no Apple Developer ID / notarization yet), so macOS may block the first open with messages like:

- *“Apple could not verify PasteRush is free of malware”*
- *“PasteRush cannot be opened because it is from an unidentified developer”*
- *“PasteRush was blocked to protect your Mac”*

PasteRush is **not malware**. You only need to allow it **once**.

### Option A — System Settings (recommended)

1. Try to open **PasteRush** from `/Applications`. If macOS blocks it, click **Done** / **OK**.
2. Open **System Settings → Privacy & Security**.
3. Scroll to the security section — you should see that PasteRush was blocked.
4. Click **Open Anyway**.
5. Confirm **Open** in the dialog (password / Touch ID if asked).

On some macOS versions **Open Anyway** appears only after the first blocked attempt.

### Option B — Terminal

```bash
xattr -dr com.apple.quarantine /Applications/PasteRush.app
```

Then open PasteRush again from Applications.

Sparkle auto-updates from GitHub Releases usually do **not** require this step again.

## 4. Grant Accessibility permission

PasteRush needs **Accessibility** so **Enter** can paste into the previous app (it simulates ⌘V). Without it, history and search still work; auto-paste does not.

### During onboarding (easiest)

1. On first launch, complete onboarding until step **3. Accessibility permission**.
2. Click **Open Accessibility Settings**.
3. In the list, find **PasteRush** and turn the toggle **on**.
4. If prompted, unlock with your Mac password / Touch ID.
5. Return to PasteRush and click **Check again** — status should show **Accessibility: granted**.
6. Optional: **Run paste test** to verify.

### Manually (any time)

1. Open **System Settings → Privacy & Security → Accessibility**.
2. Click the **+** button if PasteRush is missing, then choose  
   `/Applications/PasteRush.app`.
3. Enable the toggle next to **PasteRush**.
4. Quit and reopen PasteRush if the status does not update.

**macOS paths (English):**

- System Settings → Privacy & Security → Accessibility  
- (older): System Preferences → Security & Privacy → Privacy → Accessibility

**macOS paths (Polish):**

- Ustawienia systemowe → Prywatność i ochrona → Dostępność  
- (starsze): Preferencje systemowe → Ochrona i prywatność → Prywatność → Dostępność

### Why this permission?

| Feature | Needs Accessibility? |
|---------|----------------------|
| Clipboard history & search | No |
| Copy only (⌘↵) | No |
| Auto-paste with Enter | **Yes** |
| Paste as plain text (⇧↵) | **Yes** |

Data stays on your Mac. Accessibility is used only to send paste keystrokes to the frontmost app.

## 5. First use

1. Copy any text (⌘C).
2. Press **⌃`** (Control + backtick) — opens the history popup.
3. Type to filter, then press **Enter** to paste into the previous app.
4. Optional: enable **Launch at login** in onboarding or later in Settings.

Change the hotkey anytime: menu bar icon → **Settings**.

## 6. Troubleshooting

| Problem | Fix |
|---------|-----|
| App won’t open / “malware” warning | See [§3 Allow the app](#3-allow-the-app-gatekeeper) |
| No menu bar icon | Confirm the app is in `/Applications`, not on the Desktop or inside the DMG; reopen PasteRush |
| Enter does not paste | Grant Accessibility ([§4](#4-grant-accessibility-permission)); quit and reopen the app |
| Toggle already on but paste fails | Turn **PasteRush** off and on again in Accessibility; or remove it (+) and re-add `/Applications/PasteRush.app` |
| Shortcut does nothing | Check Settings for the configured hotkey; another app may be capturing the same shortcut |

## Uninstall

1. Quit PasteRush (menu bar icon → Quit).
2. Move `/Applications/PasteRush.app` to Trash.
3. Optional data cleanup:  
   `~/Library/Application Support/PasteRush`

## Build from source

See the [README](../README.md#build-from-source) for building and packaging your own `.app` / DMG.
