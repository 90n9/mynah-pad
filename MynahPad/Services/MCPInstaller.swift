import AppKit

/// Registers this bundle's `mynahpad-mcp` helper with Claude Code, so the
/// user doesn't have to type `claude mcp add …` in a terminal.
enum MCPInstaller {

    /// Server name in Claude Code. The dev build registers under its own name
    /// so it can sit beside the production app's entry.
    static var serverName: String { NotesFile.isDevBundle ? "mynahpad-dev" : "mynahpad" }

    static var helperPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/mynahpad-mcp").path
    }

    /// The same registration as a command the user can paste into a terminal.
    static var manualCommand: String {
        let quoted = "'" + helperPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "claude mcp add -s user \(serverName) -- \(quoted)"
    }

    enum Outcome {
        case added
        case claudeNotFound
        case failed(String)
    }

    /// Runs in a login shell so `claude` (and `node`, when `claude` is a
    /// script) resolve as they do in the user's terminal: an app started from
    /// Finder gets a bare PATH. Common install dirs are added in case the
    /// user's PATH is set only in `.zshrc`. Name and path arrive as `$1`/`$2`,
    /// never spliced into the script. An existing entry is replaced, so the
    /// item also repairs a registration that points at an old app location.
    private static let script = """
        export PATH="$HOME/.claude/local:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
        command -v claude >/dev/null 2>&1 || exit 127
        claude mcp remove -s user "$1" >/dev/null 2>&1
        claude mcp add -s user "$1" -- "$2" 2>&1
        """

    private static let timeout: TimeInterval = 30

    static func install(completion: @escaping (Outcome) -> Void) {
        let name = serverName
        let path = helperPath
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = run(name: name, path: path)
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    private static func run(name: String, path: String) -> Outcome {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return .failed("The MCP helper is missing from this copy of the app:\n\(path)")
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-lc", script, "mynahpad-mcp-install", name, path]
        task.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
        } catch {
            return .failed(error.localizedDescription)
        }
        let watchdog = DispatchWorkItem { if task.isRunning { task.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        watchdog.cancel()

        let output = (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch task.terminationStatus {
        case 0: return .added
        case 127: return .claudeNotFound
        default: return .failed(output.isEmpty ? "claude exited with status \(task.terminationStatus)." : output)
        }
    }

    /// Runs the registration and reports the result in an alert. When it
    /// can't finish, the manual command is put on the clipboard.
    static func installAndReport() {
        install { outcome in
            let alert = NSAlert()
            switch outcome {
            case .added:
                alert.messageText = "MynahPad was added to Claude Code"
                alert.informativeText = "Start a new Claude Code session to use it. The server is named “\(serverName)”."
            case .claudeNotFound:
                copyManualCommand()
                alert.alertStyle = .warning
                alert.messageText = "Claude Code was not found"
                alert.informativeText = "The `claude` command isn't on your PATH. Once Claude Code is installed, paste this command in a terminal (it's on your clipboard):\n\n\(manualCommand)"
            case .failed(let detail):
                copyManualCommand()
                alert.alertStyle = .warning
                alert.messageText = "MynahPad could not be added to Claude Code"
                alert.informativeText = "\(detail)\n\nTo add it by hand, paste this command in a terminal (it's on your clipboard):\n\n\(manualCommand)"
            }
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private static func copyManualCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(manualCommand, forType: .string)
    }
}
