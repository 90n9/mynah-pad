import AppKit

/// Coordinates all top-level objects. Holds strong references to everything that
/// NSApplication would otherwise release (status bar, window, trackers).
final class AppDelegate: NSObject, NSApplicationDelegate {

    var statusBarController: StatusBarController!
    var noteListWindow: NoteListWindow!
    var focusTracker: FocusTracker!
    var store: Store!

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

        // Status bar icon + menu.
        statusBarController = StatusBarController(
            store: store,
            window: noteListWindow
        )

        // Start update check in the background.
        UpdateChecker.shared.check { [weak self] latestVersion in
            DispatchQueue.main.async {
                self?.statusBarController.showUpdateAvailable(version: latestVersion)
            }
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
