import Foundation

// Shared by the app (`Store`) and the `mynahpad-mcp` helper, so both read and
// write `notes.json` the same way. Keep this file free of AppKit/SwiftUI.

// MARK: - Window geometry

struct WindowGeometry: Codable, Equatable {
    var x: Int
    var y: Int
    var w: Int
    var h: Int

    static let defaultValue = WindowGeometry(x: 0, y: 0, w: 320, h: 500)
}

// MARK: - Root JSON document

struct StorageDocument: Codable, Equatable {
    var folders: [Folder]
    var notes: [Note]
    var window: WindowGeometry
    /// Deleted-note history (30-day retention). Optional so older `notes.json`
    /// files without the key still decode; coalesced to `[]` on load.
    var trash: [DeletedNote]?

    static var empty: StorageDocument {
        StorageDocument(folders: [.general], notes: [], window: .defaultValue, trash: [])
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> StorageDocument {
        try JSONDecoder().decode(StorageDocument.self, from: data)
    }

    /// Forward-compatible fixes so older or hand-edited files keep working.
    mutating func migrate() {
        // 1. Ensure the "general" folder exists.
        if !folders.contains(where: { $0.id == "general" }) {
            folders.insert(.general, at: 0)
        }

        // 2. Reassign orphaned notes (folder_id references a deleted folder) to "general".
        let knownIDs = Set(folders.map { $0.id })
        for i in notes.indices where !knownIDs.contains(notes[i].folder_id) {
            notes[i].folder_id = "general"
        }

        // 3. Normalise folder nesting: "general" is always a root; any
        //    parent_id pointing at a missing folder falls back to top level.
        for i in folders.indices {
            if folders[i].id == "general" {
                folders[i].parent_id = nil
            } else if let p = folders[i].parent_id, !knownIDs.contains(p) {
                folders[i].parent_id = nil
            }
        }
    }
}

// MARK: - File location + locking

enum NotesFile {

    /// `~/.config/mynahpad` for the production app, `~/.config/mynahpad-dev`
    /// for the dev build (bundle id `com.mynahpad.app.dev`, see build.sh).
    static func baseDirURL(dev: Bool) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let base = home.appendingPathComponent(".config/\(dev ? "mynahpad-dev" : "mynahpad")",
                                               isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// True when running from the dev bundle. `Bundle.main` is the enclosing
    /// .app for both the app and the helper in `Contents/MacOS`.
    static var isDevBundle: Bool {
        (Bundle.main.bundleIdentifier ?? "com.mynahpad.app").hasSuffix(".dev")
    }

    static func storageURL(dev: Bool) -> URL {
        baseDirURL(dev: dev).appendingPathComponent("notes.json")
    }

    /// One-time import of notes from the pre-rename location
    /// (`~/.config/promptqueue`). Does nothing once `notes.json` exists. Call
    /// it only where the store is first opened (app launch, or the helper
    /// finding no file) — never from a file watcher, where a deleted file
    /// would bring the old notes back.
    static func importLegacyIfNeeded(dev: Bool) {
        let url = storageURL(dev: dev)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let legacy = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/promptqueue", isDirectory: true)
            .appendingPathComponent("notes.json")
        if FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.copyItem(at: legacy, to: url)
        }
    }

    /// Runs `body` while holding an exclusive `flock` on a sidecar lock file.
    /// Every read-modify-write of `notes.json` (app and helper) goes through
    /// this, so one writer never overwrites a change it hasn't seen.
    static func withLock<T>(dev: Bool, _ body: () throws -> T) rethrows -> T {
        let lockPath = baseDirURL(dev: dev).appendingPathComponent(".notes.json.lock").path
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        if fd >= 0 { flock(fd, LOCK_EX) }
        defer {
            if fd >= 0 {
                flock(fd, LOCK_UN)
                close(fd)
            }
        }
        return try body()
    }

    /// Raw file contents, or nil when the file doesn't exist yet.
    static func readData(dev: Bool) -> Data? {
        try? Data(contentsOf: storageURL(dev: dev))
    }

    static func write(_ data: Data, dev: Bool) throws {
        try data.write(to: storageURL(dev: dev), options: .atomic)
    }
}
