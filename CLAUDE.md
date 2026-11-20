# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

MynahPad is a lightweight macOS menu-bar app (Swift / AppKit + SwiftUI) for storing text
prompts and pasting them into the previously-focused app with a double-click. Built from
the command line with `swiftc` — there is **no `.xcodeproj`**.

## Build & run

```bash
./build.sh                   # Dev build → dist/MynahPad Dev.app
./build.sh --release         # Optimised production build → dist/MynahPad.app
./build.sh --release --dmg   # Also wraps in dist/MynahPad-X.Y.Z.dmg
open "dist/MynahPad Dev.app"
```

There is no linter and no package manager. `build.sh` is the single source of truth for the
build: it lists sources explicitly, so **a new `.swift` file must be added there** or it won't
compile in — `SOURCES=(...)` for the app, `MCP_SOURCES=(...)` for the `mynahpad-mcp` helper
(files in both arrays must stay free of AppKit/SwiftUI).

```bash
scripts/test.sh              # Store.merge checks + mynahpad-mcp over stdio (throwaway home)
```

`scripts/test.sh` covers only the merge logic and the MCP helper. UI behaviour is verified
manually — launch the app and exercise it (see the `verify` / `run` skills).

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`); full Xcode is
not needed.

### Dev vs release variant
`build.sh` without `--release` produces a *separate* app: bundle id `com.mynahpad.app.dev`,
name "MynahPad Dev", Sparkle auto-update disabled. This is deliberate so a dev build coexists
with the installed production app — it gets its own TCC Accessibility entry and its own notes
store at `~/.config/mynahpad-dev/notes.json` (prod uses `~/.config/mynahpad/notes.json`). The
variant is detected at runtime via `Bundle.main.bundleIdentifier` (see `Store.storageURL` and
`build.sh`).

## Code-signing is load-bearing (don't "simplify" it)

`build.sh` generates and signs with a **self-signed `MynahPad Dev` certificate** in your
login keychain. This is NOT cosmetic: macOS TCC matches the Accessibility grant against the
binary's *designated requirement*. Ad-hoc signing (`codesign --sign -`) produces a `cdhash`-
based requirement that changes every rebuild, so TCC silently drops the grant and `CGEventPost`
(the paste) no-ops. A stable cert leaf hash keeps the grant alive across rebuilds. To confirm
a build is cert-signed, `codesign -d -r- dist/...app` must show `certificate leaf`, not `cdhash`.
Full rationale: CONTRIBUTING.md → "Why the self-signed cert".

In CI the cert comes from the `MACOS_SIGNING_CERT_P12_BASE64` secret rather than being
regenerated, so the leaf hash stays constant across releases (a fresh per-release cert would
break the grant on every Sparkle auto-update).

## Architecture

AppKit-driven, not SwiftUI-scene-driven. `MynahPadApp` exists only to satisfy `@main`; the
real app is run by `AppDelegate`, which owns every top-level object (status bar, window,
trackers, updater) so NSApplication doesn't release them.

- **`AppDelegate`** — wires everything in `applicationDidFinishLaunching`; sets
  `.accessory` activation policy (no Dock icon); prompts for Accessibility; is the Sparkle
  `SPUUpdaterDelegate`.
- **`Store`** (`Models/Store.swift`) — `ObservableObject` (not `@Observable`, for macOS 13
  compat) holding `folders` + `notes`, persisted to a single JSON document
  (`notes.json`). Every mutation calls `save()`. JSON keys are snake_case (`folder_id`,
  `created_at`) to match a cross-app schema from an earlier Python version. `migrate()` runs
  on load: ensures the `"general"` folder exists and re-homes orphaned notes. A file that
  fails to decode is copied to `notes.json.corrupt-<timestamp>` before defaults are written.
- **`NotesFile`** (`Models/NotesFile.swift`) — the file layer shared by the app and the MCP
  helper: `StorageDocument`, paths, and `withLock` (an `flock` on `.notes.json.lock`). Every
  read-modify-write of `notes.json`, in either binary, must go through `withLock`.
- **`NoteListWindow`** — a borderless, floating, dark-vibrancy `NSWindow` hosting the SwiftUI
  view via `NSHostingView`. Closing hides (doesn't dealloc). Window geometry persists to the
  Store. Handles minimize-to-titlebar-strip and global `keyDown` shortcuts (Esc to hide,
  Delete to remove the selected note, digits 1–9 to move it to folder N). `NoteListViewState`
  is the shared bridge letting `keyDown` read what the SwiftUI view has selected.
- **`NoteListView`** (`NoteListView.swift`, ~890 lines) — the entire UI: folder list, note
  rows, input bar, drag-and-drop reorder/move (`.draggable`/`.dropDestination` with
  `FolderRef`/`NoteRef` Transferables), context menus, and the modal note editor.
- **`Paster`** (`Services/Paster.swift`) — copies text to the pasteboard, re-activates the
  last-focused app, then posts ⌘V via `CGEvent` after a 120ms delay. Guards on
  `AXIsProcessTrusted()` and logs (rather than silently failing) when Accessibility is missing.
- **`FocusTracker`** — observes `NSWorkspace.didActivateApplicationNotification` to remember
  the last non-MynahPad frontmost app, so `Paster` knows where to paste.

### Paste flow (the core interaction)
Double-click a note → `pasteNote` → mark used → `Paster.paste`: clear pasteboard, set string,
`NSApp.deactivate()` (so our key window releases focus first), activate the target app, then
post ⌘V on a delay. Accessibility permission is mandatory for the keystroke to land.

### Other processes writing notes.json (live reload + MCP)
`notes.json` has two writers: the app and `mynahpad-mcp` (`MynahPadMCP/main.swift`), a stdio
MCP server built into `Contents/MacOS/` and signed on its own before the outer bundle. The
helper edits the file under `NotesFile.withLock`; it does not talk to the app.

`Store.startWatching()` watches the config dir and the file's inode and reloads when the
contents differ from `lastSyncedData` (what the app last loaded or wrote), so the app's own
saves never trigger a reload. If `save()` runs before the watcher has delivered an external
write, it three-way merges by id first (`Store.merge`: their adds, removes and edits are kept;
when both sides edited the same item, ours wins). Window geometry always stays the app's.
`NoteListWindow.saveGeometry` debounces its save by 0.5 s.

## Auto-update (Sparkle)

In-app updates via [Sparkle](https://sparkle-project.org/). The framework is downloaded by
`build.sh` to `vendor/Sparkle/` (gitignored) on first build and re-signed under the local cert.
On launch the app polls `appcast.xml` at the repo root; downloads are EdDSA-verified against
`SUPublicEDKey` in `Info.plist`. With `SUAutomaticallyUpdate=true`, installs apply silently on
next quit. `AppDelegate` deliberately does **not** hook `didDownloadUpdate` — that fires before
the package is staged, so quitting then would relaunch the old build; Sparkle's own driver
handles the install-and-relaunch step.

## Releasing

Releases are automated by `.github/workflows/release.yml`, triggered by pushing a `vX.Y.Z` tag.
Maintainer steps (see CONTRIBUTING.md → "Cutting a release"):

1. Bump `CFBundleShortVersionString` **and** `CFBundleVersion` in `MynahPad/Info.plist`.
2. Move the `## [Unreleased]` block in `CHANGELOG.md` under a new `## [X.Y.Z]` heading.
3. Commit/push to `main`, then `git tag vX.Y.Z && git push --tags`.

CI builds the DMG, signs it with the Sparkle EdDSA key (`SPARKLE_ED_PRIVATE_KEY` secret),
prepends a new `<item>` to `appcast.xml` and commits it back to `main`, and publishes the
GitHub Release. A tag with a `-` suffix (e.g. `v1.0.0-rc1`) is treated as a prerelease and
skips the appcast update.

**Never regenerate the Sparkle EdDSA key** — it's already provisioned (keychain + GitHub
secret + `SUPublicEDKey` in Info.plist). A new key invalidates the signature on every prior
release, so existing installs would reject all updates.

### CHANGELOG style
Bullets are short, one line each — no rationale or prior-behaviour context.
</content>
</invoke>
