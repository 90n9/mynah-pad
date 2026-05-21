import AppKit
import CoreGraphics

/// Pastes a text string into whatever application was last focused.
///
/// Steps:
///   1. Write `text` to the general pasteboard.
///   2. Re-activate the last focused application.
///   3. After a short delay (for app-switch animation), post Cmd+V via CGEvent.
///
/// **Requires Accessibility permission** (`NSAccessibilityUsageDescription` in Info.plist).
/// Without it, `CGEventPost` silently does nothing.
enum Paster {

    /// Virtual key code for V on a US-layout keyboard (carbon constant kVK_ANSI_V = 9).
    private static let kVK_ANSI_V: CGKeyCode = 9

    static func paste(text: String, focusTracker: FocusTracker) {
        // 1. Write to pasteboard.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        // 2. Re-activate the target application.
        guard let target = focusTracker.lastFocusedApp else {
            // No previous app recorded — nothing to paste into.
            return
        }
        target.activate(options: .activateIgnoringOtherApps)

        // 3. Post Cmd+V after giving the OS time to complete the app switch (~80 ms).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            sendCmdV()
        }
    }

    // MARK: - CGEvent helpers

    private static func sendCmdV() {
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: kVK_ANSI_V, keyDown: true),
            let keyUp   = CGEvent(keyboardEventSource: nil, virtualKey: kVK_ANSI_V, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags   = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
