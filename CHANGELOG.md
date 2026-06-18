# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.21] - 2026-06-18

- Duplicate a folder and all its notes (plus nested subfolders) with "Duplicate Folder" in the folder right-click menu.

## [1.0.20] - 2026-06-18

- Nest a folder inside another: drag a folder onto another folder's body, or use the right-click menu ("Move into…" / "Top Level").
- Drag a folder onto another folder's top edge to reorder it as a sibling.
- Drag a folder or note onto the "Add Folder" strip to move it to the top level / General.
- Reset every note in a folder to unused with "Reset All Notes" in the folder right-click menu.

## [1.0.19] - 2026-06-15

- Paste a screen capture (⌘⌃⇧4) into the window to save it as an image note with a thumbnail.
- Right-click an image note for Quick Look, Open in Preview, or Show in Finder.
- Image files are deleted from disk when their note is purged from Deleted History.

## [1.0.18] - 2026-06-11

- Deleted History: deleted notes kept 30 days, restore/delete/clear from the menu-bar item.

## [1.0.17] - 2026-05-28

### Added
- Selected notes expand to show their full text; unselected rows stay truncated.
- Input bar accepts multi-line text and preserves long pastes. Submit with **⌘⏎**.

## [1.0.16] - 2026-05-26

### Added
- Double-clicking the title bar toggles minimize/expand.

## [1.0.15] - 2026-05-22

### Fixed
- Edit-note sheet now opens with the note's text on first use.
- Single-click selects a note instantly (no more tap-disambiguation delay).

## [1.0.14] - 2026-05-22

### Added
- Rename folders from the right-click menu.
- Edit notes from the right-click menu (⌘⏎ saves, Esc cancels).

## [1.0.13] - 2026-05-22

### Changed
- Minimized strip uses a larger full-colour app icon for better visibility.
- Title-bar minimize/close buttons adopt the macOS yellow/red traffic-light colours.
- About panel uses the tight-cropped colourful icon.

## [1.0.12] - 2026-05-22

### Changed
- Minimized strip shrinks to a compact logo-only pill (~92×32pt).
- Smoother minimize/expand animation; icon toggles between `−` and `+`.

## [1.0.11] - 2026-05-22

### Added
- Title-bar minimize button collapses the panel to a slim floating strip.

## [1.0.10] - 2026-05-22

### Fixed
- "Restart now" waits for Sparkle to fully stage the update before relaunching.
- Update dialog release notes show the actual changelog entry instead of `[Unreleased]`.

## [1.0.9] - 2026-05-22

### Added
- Note panel opens automatically on launch.
- In-panel update banner with an **Update Now** button when a new version is available.

### Changed
- `build.sh` defaults to a separate "MynahPad Dev" bundle; pass `--release` for production.

## [1.0.8] - 2026-05-22

### Fixed
- Accessibility prompt no longer re-fires on launch when permission is granted; offers **Reset & Grant** if blocked.

### Changed
- Status bar and Sparkle dialogs show matching version strings.
- Update check interval reduced from 24h to 1h.

## [1.0.7] - 2026-05-22

### Fixed
- Folder rows can be drag-reordered again (gesture conflict with `Button` removed).

## [1.0.6] - 2026-05-22

### Added
- "View on GitHub" menu item in the status bar.

## [1.0.5] - 2026-05-22

### Fixed
- Auto-updates now install on relaunch (re-enabled Sparkle's installer service).

### Added
- "Restart Now" alert after a background download.

## [1.0.4] - 2026-05-22

### Fixed
- Paste-into-terminal now survives auto-updates (CI uses a stable signing cert).

## [1.0.3] - 2026-05-22

### Changed
- Updates install silently in the background; bundle swaps on next quit. EdDSA verification unchanged.

## [1.0.2] - 2026-05-21

### Changed
- About panel adds a one-line tagline describing the app.

### Build
- Ignore `.playwright-mcp/` working directory.

## [1.0.1] - 2026-05-21

### Fixed
- DMG ships with an `/Applications` symlink for drag-to-install.

## [1.0.0] - 2026-05-21

First public release.

### Added
- Swift/SwiftUI rewrite of MynahPad menu-bar app (formerly PromptQueue).
- Folder + note CRUD with right-click menus and drag-and-drop sorting.
- Double-click a note to paste it into the last focused app via Cmd+V.
- Sparkle 2.6.4 auto-updater with EdDSA-signed DMGs and daily background check.
- JSON storage with auto-migration from the legacy PromptQueue path.
- `build.sh` — Xcode-CLT-only build with a self-signed dev cert for TCC stability.
- GitHub Actions release workflow signs DMGs, patches `appcast.xml`, and publishes on tag push.

### Known Issues
- Self-signed only — first launch shows a Gatekeeper warning. Subsequent updates flow through Sparkle's signed channel.
