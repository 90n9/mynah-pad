# PromptQueue (Swift)

A lightweight macOS menu-bar app that manages a list of text prompts and pastes them
into your active terminal with a double-click. Targets a ~2 MB binary — the Python/PyQt6
predecessor produced a ~200 MB DMG.

## Prerequisites

- **macOS 12 Monterey or later**
- **Xcode 14 or later** — install from the [Mac App Store](https://apps.apple.com/app/xcode/id497799835)
  (Command Line Tools alone are not sufficient to build a `.app` bundle)

## Build

```bash
git clone git@github.com:90n9/prompt-queue-swift.git
cd prompt-queue-swift
open PromptQueue.xcodeproj          # Opens Xcode
# Press ⌘R to run, or Product → Archive for a release build
```

Or from the command line once Xcode is installed:

```bash
xcodebuild -scheme PromptQueue -configuration Release build
```

## Accessibility Permission

PromptQueue needs **Accessibility access** to simulate Cmd+V and paste prompts into your
terminal. On first run (or when the Accessibility permission is missing) macOS will
prompt you. You can also grant it manually:

**System Settings → Privacy & Security → Accessibility → enable PromptQueue**

Without this permission the paste feature silently does nothing.

## Storage

Notes are stored at `~/.config/promptqueue/notes.json`. The schema is compatible with the
Python version of PromptQueue, so you can migrate by copying your existing file.

## Usage

1. Launch PromptQueue — a `📝` icon appears in the menu bar.
2. Click the icon → **Show Window** to open the note list.
3. Type a prompt in the **New idea…** field and press Return to add it.
4. Switch to your terminal, then **double-click** a note to paste it.
5. Used notes turn grey with a ✓ prefix. Right-click for Reset / Delete / Move to folder.

## Release

Tag with `v<MAJOR>.<MINOR>.<PATCH>` to trigger the GitHub Actions release workflow,
which builds an unsigned DMG and attaches it to a GitHub release.

## License

MIT
