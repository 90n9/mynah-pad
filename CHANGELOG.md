# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial Swift/SwiftUI rewrite of MynahPad macOS menu-bar app (formerly PromptQueue)
- NSStatusItem menu bar icon with update check support
- Floating, frameless dark note list window
- Folder management and note CRUD operations
- Double-click to paste note into last focused app via CGEvent Cmd+V
- FocusTracker to remember the last active non-MynahPad application
- UpdateChecker fetching latest release from GitHub API
- JSON storage at `~/.config/mynahpad/notes.json` with auto-migration from the
  legacy `~/.config/promptqueue/notes.json` path (cross-app compatible schema)
- GitHub Actions release workflow building unsigned .app DMG on `v*.*.*` tags

### Changed
- Replaced the placeholder `UpdateChecker` (which only opened the GitHub
  Releases page in a browser) with **Sparkle 2.6.4** for in-app auto-updates.
  `SPUStandardUpdaterController` is wired in `AppDelegate`. A "Check for
  Updates…" menu item invokes it; a daily background check runs automatically
  via `SUScheduledCheckInterval` in Info.plist. When a newer version is found,
  Sparkle's native dialog handles download, EdDSA signature verification,
  installation, and relaunch — no browser detour, no manual DMG drag. The
  appcast URL points to `appcast.xml` at the repo root on `main`; the
  `SUPublicEDKey` for verifying releases is embedded in the bundle.
- `build.sh` downloads Sparkle 2.6.4 to `vendor/Sparkle/` on first build
  (gitignored), embeds `Sparkle.framework` in `Contents/Frameworks/`, and
  re-signs every nested Mach-O (the framework dylib, `Autoupdate`, `Updater.app`,
  and both XPC services) with the local self-signed `MynahPad Dev` cert before
  sealing the outer bundle. Hardened Runtime is deliberately off so Library
  Validation doesn't reject the framework over Team-ID mismatch (the self-signed
  cert has no Team ID).
- Renamed from **PromptQueue** to **MynahPad**. Bundle identifier
  `com.promptqueue.swift` → `com.mynahpad.app`. Signing cert
  `PromptQueue Dev` → `MynahPad Dev`. Accessibility permission must be re-granted
  once after the first build under the new identifier.
- Drag & drop overhauled with typed Transferable payloads (`FolderRef`, `NoteRef`)
  registered under custom UTIs (`com.mynahpad.folder-ref`, `com.mynahpad.note-ref`).
  Notes are sortable within a folder (drop on a note inserts before it). Folders
  are sortable (drop on a folder inserts before it). Folders cannot be dropped
  onto notes — they only reorder among folders. Visual cue is now distinct per
  drag kind: a thin accent line above the target row signals reorder/insertion,
  while a full-row accent fill on a folder signals "move note into folder".
- Window dragging fixed for drag-and-drop interactions. `isMovableByWindowBackground`
  re-enabled (so the window can be moved from any background area), with a
  `NoWindowDragRegion` (NSView wrapper exposing `mouseDownCanMoveWindow = false`)
  stamped behind note rows and folder rows so dragging a note or reordering a
  folder no longer drags the window itself.
- Used-note indicator collapsed to the green `checkmark.circle.fill` icon only;
  the redundant `"✓ "` text prefix was removed.

### Known Issues / TODO
- The release workflow uses `method: development` in ExportOptions.plist. For unsigned
  macOS archives the correct method is `mac-application`. Update once code signing
  strategy is decided (ad-hoc, Developer ID, or unsigned direct copy).
