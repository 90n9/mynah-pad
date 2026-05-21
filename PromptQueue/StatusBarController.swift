import AppKit

/// Manages the NSStatusItem in the menu bar and its drop-down menu.
final class StatusBarController: NSObject {

    private let statusItem: NSStatusItem
    private let store: Store
    private weak var window: NoteListWindow?
    private var updateMenuItem: NSMenuItem?

    private static let version: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }()

    init(store: Store, window: NoteListWindow) {
        self.store = store
        self.window = window

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        configureButton()
        buildMenu()
    }

    // MARK: - Button

    private func configureButton() {
        guard let button = statusItem.button else { return }

        // SF Symbol template image — scales with menu bar appearance.
        if let image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "PromptQueue") {
            image.isTemplate = true
            button.image = image
        } else {
            // Fallback: draw a simple pencil square.
            button.image = makeFallbackIcon()
        }

        button.toolTip = "PromptQueue"
    }

    private func makeFallbackIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        let rect = NSRect(x: 2, y: 2, width: 14, height: 14)
        let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        path.fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        // Version label / update item placeholder.
        let versionItem = NSMenuItem(
            title: "PromptQueue v\(Self.version)",
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        updateMenuItem = versionItem   // will be replaced if update available

        menu.addItem(.separator())

        let showHide = NSMenuItem(
            title: "Show/Hide Window",
            action: #selector(toggleWindow),
            keyEquivalent: "p"
        )
        showHide.keyEquivalentModifierMask = [.command, .shift]
        showHide.target = self
        menu.addItem(showHide)

        menu.addItem(.separator())

        let about = NSMenuItem(
            title: "About PromptQueue",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Update badge

    /// Called from AppDelegate when UpdateChecker finds a newer release.
    func showUpdateAvailable(version: String) {
        guard let menu = statusItem.menu,
              let old = updateMenuItem,
              let idx = menu.items.firstIndex(of: old) else { return }

        let item = NSMenuItem(
            title: "⬆ Update available: v\(version)",
            action: #selector(openReleasePage),
            keyEquivalent: ""
        )
        item.target = self
        menu.removeItem(at: idx)
        menu.insertItem(item, at: idx)
        updateMenuItem = item
    }

    // MARK: - Actions

    @objc private func toggleWindow() {
        window?.toggleWindow()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func openReleasePage() {
        let url = URL(string: "https://github.com/90n9/prompt-queue-swift/releases")!
        NSWorkspace.shared.open(url)
    }
}
