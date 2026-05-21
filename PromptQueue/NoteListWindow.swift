import AppKit
import SwiftUI

// MARK: - Shared view state

/// Shared mutable state bridge between the NSWindow host and the SwiftUI view.
/// Allows `keyDown(with:)` in NoteListWindow to read which note is selected
/// without using `.onKeyPress` (macOS 14+).
final class NoteListViewState: ObservableObject {
    @Published var selectedNoteID: String? = nil
}

// MARK: - Window

/// A frameless, floating, dark window that hosts the SwiftUI NoteListView.
/// - Stays above other windows but doesn't force exclusive focus.
/// - Closing hides rather than deallocates.
/// - Draggable from anywhere in the titlebar region.
final class NoteListWindow: NSWindow, NSWindowDelegate {

    private let store: Store
    private let focusTracker: FocusTracker

    /// Shared selection state — the SwiftUI view writes here; keyDown reads it.
    private let viewState = NoteListViewState()

    init(store: Store, focusTracker: FocusTracker) {
        self.store = store
        self.focusTracker = focusTracker

        let initialRect: NSRect = {
            let geo = store.windowGeometry
            if geo.x == 0 && geo.y == 0 {
                // Centre on primary screen the first time.
                let screen = NSScreen.main ?? NSScreen.screens[0]
                let sw = screen.visibleFrame.width
                let sh = screen.visibleFrame.height
                let w: CGFloat = CGFloat(geo.w > 0 ? geo.w : 320)
                let h: CGFloat = CGFloat(geo.h > 0 ? geo.h : 500)
                return NSRect(
                    x: screen.visibleFrame.minX + (sw - w) / 2,
                    y: screen.visibleFrame.minY + (sh - h) / 2,
                    width: w,
                    height: h
                )
            }
            return NSRect(x: CGFloat(geo.x), y: CGFloat(geo.y),
                          width: CGFloat(geo.w > 0 ? geo.w : 320),
                          height: CGFloat(geo.h > 0 ? geo.h : 500))
        }()

        super.init(
            contentRect: initialRect,
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        configureWindow()
        embedSwiftUI()
        self.delegate = self
    }

    // MARK: - Configuration

    private func configureWindow() {
        // Appearance — use a fully opaque background colour + window alphaValue for
        // transparency. Setting both alpha in the colour AND alphaValue compounds
        // them (~0.92 effective), so we keep the colour opaque.
        backgroundColor = NSColor(calibratedRed: 0.102, green: 0.102, blue: 0.102, alpha: 1.0)
        isOpaque = false
        alphaValue = 0.96
        hasShadow = true

        // Corner radius via contentView layer
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 10
        contentView?.layer?.masksToBounds = true

        // Floating above regular windows, visible on all spaces
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Allow resizing
        minSize = NSSize(width: 280, height: 350)
        maxSize = NSSize(width: 600, height: 900)

        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden

        // Standard close/min/zoom buttons removed (borderless)
        // Esc and Delete key handling lives in keyDown(with:) below.
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:  // Esc
            hideWindow()
        case 51, 117:  // Delete (backspace=51) / Forward-Delete (117)
            if let noteID = viewState.selectedNoteID {
                store.deleteNote(id: noteID)
                viewState.selectedNoteID = nil
            }
        default:
            super.keyDown(with: event)
        }
    }

    private func embedSwiftUI() {
        let rootView = NoteListView(store: store, focusTracker: focusTracker, viewState: viewState) { [weak self] in
            self?.hideWindow()
        }
        let hosting = NSHostingView(rootView: rootView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        contentView?.addSubview(hosting)
        if let cv = contentView {
            NSLayoutConstraint.activate([
                hosting.topAnchor.constraint(equalTo: cv.topAnchor),
                hosting.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
                hosting.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            ])
        }
    }

    // MARK: - Show / Hide

    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func hideWindow() {
        orderOut(nil)
        saveGeometry()
    }

    func toggleWindow() {
        if isVisible {
            hideWindow()
        } else {
            showWindow()
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Intercept close — hide instead of destroy.
        hideWindow()
    }

    func windowDidMove(_ notification: Notification) {
        saveGeometry()
    }

    func windowDidResize(_ notification: Notification) {
        saveGeometry()
    }

    // MARK: - Geometry persistence

    private func saveGeometry() {
        let f = frame
        store.windowGeometry = WindowGeometry(
            x: Int(f.origin.x),
            y: Int(f.origin.y),
            w: Int(f.width),
            h: Int(f.height)
        )
        store.save()
    }
}
