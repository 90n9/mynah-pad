import AppKit
import ApplicationServices
import Sparkle

/// Coordinates all top-level objects. Holds strong references to everything that
/// NSApplication would otherwise release (status bar, window, trackers).
final class AppDelegate: NSObject, NSApplicationDelegate {

    var statusBarController: StatusBarController!
    var noteListWindow: NoteListWindow!
    var focusTracker: FocusTracker!
    var store: Store!
    var updaterController: SPUStandardUpdaterController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock — belt-and-suspenders alongside LSUIElement.
        NSApp.setActivationPolicy(.accessory)

        // Shared data store.
        store = Store()
        store.load()

        // Focus tracker must start before user can interact.
        focusTracker = FocusTracker()

        // Floating note list window.
        noteListWindow = NoteListWindow(store: store, focusTracker: focusTracker)

        // Sparkle auto-updater. `startingUpdater: true` schedules the first
        // background check using SUScheduledCheckInterval from Info.plist.
        // The user driver presents native dialogs for "new version available",
        // download progress, and the install-and-relaunch step.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Status bar icon + menu — needs the updater so the "Check for Updates…"
        // menu item can invoke it.
        statusBarController = StatusBarController(
            store: store,
            window: noteListWindow,
            updater: updaterController
        )

        // Accessibility trust — required for the Cmd+V paste to actually fire.
        // Without it, CGEventPost silently no-ops. Prompt the user once on launch
        // so they can grant it in System Settings → Privacy & Security.
        promptForAccessibilityIfNeeded()
    }

    /// First-responder action so any UI hooked to `Selector("checkForUpdates:")`
    /// (menu items, future buttons) routes through the same updater.
    @IBAction func checkForUpdates(_ sender: Any?) {
        updaterController.checkForUpdates(sender)
    }

    private func promptForAccessibilityIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        if !trusted {
            NSLog("[MynahPad] Accessibility not granted — paste will silently fail until granted.")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.save()
    }

    /// Window close button hides rather than destroys the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        noteListWindow.showWindow()
        return false
    }
}
