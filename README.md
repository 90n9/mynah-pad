<p align="center">
  <img src="assets/app-icon.png" alt="MynahPad" width="180" height="180" />
</p>

<h1 align="center">MynahPad <sub><sup>(Swift)</sup></sub></h1>

<p align="center">
  A lightweight macOS menu-bar app that manages a list of text prompts and pastes
  them into your active terminal with a double-click. Targets a ~2 MB binary —
  the Python/PyQt6 predecessor produced a ~200 MB DMG.
</p>

## Quick Install (no build needed)

Just want to try MynahPad? Grab the prebuilt DMG from the
[Releases page](https://github.com/90n9/mynah-pad/releases/latest) — no Xcode,
no clone, no compilation required.

1. Download the latest **`MynahPad-X.Y.Z.dmg`**.
2. Open the DMG and drag **MynahPad.app** into the **Applications** folder.
3. **The first launch will be blocked** with *"MynahPad cannot be opened because
   the developer cannot be verified"* (or *"MynahPad is damaged and can't be
   opened"*). This is macOS Gatekeeper reacting to the self-signed cert — the
   DMG is signed with a local `MynahPad Dev` cert, not an Apple Developer ID,
   so the bundle picks up a quarantine flag on mount. Strip it in Terminal:

   ```bash
   xattr -dr com.apple.quarantine /Applications/MynahPad.app
   ```

   Then double-click **MynahPad** in `/Applications`. You only need to do this
   once per machine — every future update flows through Sparkle's signed
   channel and won't re-prompt.
4. macOS will prompt for **Accessibility access** on first run. Grant it at
   **System Settings → Privacy & Security → Accessibility → enable MynahPad**.
   Without this permission, the paste feature silently does nothing.
5. A `📝` icon appears in the menu bar. You're done — see [Usage](#usage) below.

> If you'd rather build from source, read on. Otherwise skip to
> [Usage](#usage).

## Build from source

### Prerequisites

- **macOS 13 Ventura or later** (uses `.draggable` / `.dropDestination`)
- **Xcode Command Line Tools** — `xcode-select --install`. Full Xcode is not required;
  `build.sh` produces a `.app` bundle using `swiftc` and `codesign` from the CLT only.

### Build

`build.sh` is the only supported build path — there is no `.xcodeproj`.

```bash
git clone git@github.com:90n9/mynah-pad.git
cd mynah-pad
./build.sh                   # Debug build → dist/MynahPad.app
./build.sh --release         # Optimised build
./build.sh --release --dmg   # Also wrap in a DMG
```

The first build downloads the Sparkle framework (~13 MB) to `vendor/Sparkle/`,
which is gitignored.

On the first run, `build.sh` generates a self-signed code-signing certificate named
**MynahPad Dev** and installs it in your login keychain (see *Accessibility* below
for why). Subsequent builds reuse the same cert — no prompts.

## Accessibility Permission

MynahPad needs **Accessibility access** to simulate Cmd+V and paste prompts
into your terminal. On first run (or when the Accessibility permission is
missing) macOS will prompt you. You can also grant or revoke it manually at
**System Settings → Privacy & Security → Accessibility**. Without this
permission the paste feature silently does nothing.

### Why the self-signed cert

macOS TCC (the privacy database that gates Accessibility) matches grants against the
binary's **designated requirement**, not its bundle ID alone. With **ad-hoc** signing
(`codesign --sign -`) the designated requirement is literally `cdhash H"<binary hash>"` —
which changes every time you rebuild, so TCC silently invalidates the previous grant and
`CGEventPost` no-ops until you re-toggle Accessibility in System Settings.

Signing with a stable certificate makes the designated requirement
`identifier "com.mynahpad.app" and certificate leaf = H"<cert hash>"`. The cert
hash never changes between rebuilds, so the TCC grant persists. The cert is self-signed
(it shows up as `CSSMERR_TP_NOT_TRUSTED` in `security find-identity -v` — that's
expected; TCC matches by leaf-cert hash, not trust-chain validity).

If paste ever silently fails after a rebuild:

```bash
codesign -d -r- dist/MynahPad.app
# designated => identifier "com.mynahpad.app" and certificate leaf = H"..."
#                                              ^ must be `certificate leaf`,
#                                                not `cdhash`
```

If the line shows `cdhash` instead of `certificate leaf`, the cert bootstrap failed —
delete `dist/`, re-run `./build.sh`, and check its output for the cert-creation step.

## Storage

Notes are stored at `~/.config/mynahpad/notes.json`. On first launch, MynahPad
auto-migrates from the legacy `~/.config/promptqueue/notes.json` location if it
exists. The schema is compatible with the Python predecessor, so you can also seed
the file manually.

## Usage

1. Launch MynahPad — a `📝` icon appears in the menu bar.
2. Click the icon → **Show Window** to open the note list.
3. Type a prompt in the **New idea…** field and press Return to add it.
4. Switch to your terminal, then **double-click** a note to paste it.
5. Used notes turn grey with a ✓ prefix. Right-click for Reset / Delete / Move to folder.

## Updates

MynahPad **updates silently in the background** — you don't have to click
anything. Once a day Sparkle polls the appcast, downloads any newer release,
verifies its EdDSA signature against the public key baked into the bundle,
and swaps the bundle the next time you quit the app. On your next launch
MynahPad is already on the new version. No dialogs, no Install Update button,
no trip to the GitHub release page.

You can still trigger an on-demand check from the menu bar: click the `📝`
icon → **Check for Updates…**.

## Auto-update (Sparkle)

MynahPad uses **[Sparkle](https://sparkle-project.org/)** for in-app updates.
On launch it polls [`appcast.xml`](appcast.xml) at the repo root; a daily
background check is scheduled via `SUScheduledCheckInterval`. With
`SUAutomaticallyUpdate` enabled in `Info.plist`, downloads happen silently
and Sparkle installs them on the app's next quit — no native dialog, no user
interaction. Every download is EdDSA-verified against `SUPublicEDKey` in
`Info.plist` before it's installed, so silent updates don't loosen the
security posture.

The Sparkle framework is downloaded by `build.sh` to `vendor/Sparkle/`
(gitignored) on first build, embedded in `Contents/Frameworks/`, and re-signed
with the local `MynahPad Dev` cert so it loads under the same identity as the
host binary.

### Cutting a release

Releases are fully automated by GitHub Actions. Maintainer steps:

1. Bump `CFBundleShortVersionString` in `MynahPad/Info.plist`.
2. Move the `## [Unreleased]` section in `CHANGELOG.md` under a new version heading.
3. Commit and push to `main`.
4. Tag and push: `git tag v1.2.3 && git push --tags`.

The release workflow then builds the DMG, signs it with the Sparkle EdDSA key,
commits the updated `appcast.xml` back to `main`, and publishes the GitHub
Release. Existing installs pick up the new version on their next appcast check.

### Sparkle signing key

The Sparkle EdDSA private key is **already provisioned** — do not regenerate it.
Running `generate_keys` again would mint a new key and invalidate the signature
on every prior release, so Sparkle on existing installs would reject the update.

The key lives in three places:

- The maintainer's **macOS Keychain** (canonical — created by `generate_keys`).
- `~/.sparkle/mynah-pad-ed-key.pem` (local backup, kept out of the repo).
- The `SPARKLE_ED_PRIVATE_KEY` **GitHub Actions secret** (used by the release
  workflow to sign DMGs in CI).

The matching public key is embedded in the app as `SUPublicEDKey` in
`MynahPad/Info.plist` and is used by Sparkle to verify downloaded updates.

## License

MIT
