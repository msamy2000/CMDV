# CMDV (`CMDV.app`)

A lightweight, native macOS clipboard manager blending [Maccy](https://maccy.app/)'s background pasteboard engine with Windows 11's minimal `Win+V` card popup.

## Key Features
- **Global Shortcut (`⇧⌘V` / `Cmd+Shift+V`)**: Opens a non-activating floating card panel right at your active text caret or mouse cursor position.
- **Minimal Windows 11-Style Cards**: Clean scrollable cards displaying rich previews for **text**, **images/screenshots**, **files**, and **binary payloads**, along with source app name, relative timestamp, `⌘1`..`⌘9` badges, and a per-card `×` delete button.
- **Auto-Paste by Default**:
  - `Enter`, `Click`, or `⌘1..9`: Restores the item to the system clipboard and synthesizes `Cmd+V` into the active app.
  - `Option+Enter` or `Option+Click`: Copies the item to the clipboard without pasting.
  - `Option+Shift+Enter` or `Option+Shift+Click`: Pastes as plain text (strips formatting).
  - `Option+Delete` (`⌥⌫`) or `×` button: Deletes the item from history.
  - `Escape` or outside click: Dismisses the popup.
- **20-Item / 5-Day Rolling Buffer (Whichever Reached First)**:
  - Stores up to **20 items** and automatically expires any item older than **5 days** (`432,000` seconds).
  - Loop overwrite (MRU/FIFO): copying a 21st item automatically overwrites the oldest entry and cleans up its binary payload on disk.
  - Deduplication: copying or selecting an existing item moves it to the top and resets its 5-day expiration timer.
  - Privacy-aware: ignores concealed/transient clipboard items (`org.nspasteboard.ConcealedType`, `1Password`, etc.).
- **Embedded Menu Bar Agent & Startup**:
  - Runs embedded in the macOS menu bar (`LSUIElement = true`, no Dock icon).
  - **Left-click** the menu bar icon to toggle the clipboard cards below the menu bar; **right-click** (or `Option-click`) for system controls (*Clear All History*, *Start with macOS*, *Accessibility Permission*, *Quit*).
  - Automatically configures Launch at Login and prompts for macOS Accessibility permission on startup.

## Build, Test & Install

```bash
./scripts/build_app.sh
```

This runs the unit test suite (`swift run CMDVTestRunner`), builds the release binary, generates `AppIcon.icns`, bundles and signs `build/CMDV.app`, installs it to `/Applications/CMDV.app`, and configures `~/Library/LaunchAgents/com.cmdv.app.plist`.
