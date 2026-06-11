import Foundation
import Combine

// MARK: - Window geometry

struct WindowGeometry: Codable {
    var x: Int
    var y: Int
    var w: Int
    var h: Int

    static let defaultValue = WindowGeometry(x: 0, y: 0, w: 320, h: 500)
}

// MARK: - Root JSON document

private struct StorageDocument: Codable {
    var folders: [Folder]
    var notes: [Note]
    var window: WindowGeometry
    /// Deleted-note history (30-day retention). Optional so older `notes.json`
    /// files without the key still decode; coalesced to `[]` on load.
    var trash: [DeletedNote]?
}

// MARK: - Store

/// Observed data store backed by `~/.config/mynahpad/notes.json`.
/// Uses `ObservableObject` + `@Published` for macOS 12 compatibility
/// (`@Observable` macro requires macOS 14+).
final class Store: ObservableObject {

    @Published var folders: [Folder] = []
    @Published var notes: [Note] = []
    @Published var trash: [DeletedNote] = []
    var windowGeometry: WindowGeometry = .defaultValue

    /// Deleted notes are retained this long before being permanently dropped.
    static let trashRetention: TimeInterval = 30 * 24 * 60 * 60  // 30 days

    // MARK: File path

    private static var storageURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Dev builds use a sibling directory so testing doesn't trample the
        // user's production notes. Detection is bundle-id based: prod is
        // `com.mynahpad.app`; dev is `com.mynahpad.app.dev` (see build.sh).
        let bundleID = Bundle.main.bundleIdentifier ?? "com.mynahpad.app"
        let dirName = bundleID.hasSuffix(".dev") ? "mynahpad-dev" : "mynahpad"
        let base = home.appendingPathComponent(".config/\(dirName)", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let url = base.appendingPathComponent("notes.json")

        // One-shot migration from the pre-rename location.
        if !FileManager.default.fileExists(atPath: url.path) {
            let legacy = home
                .appendingPathComponent(".config/promptqueue", isDirectory: true)
                .appendingPathComponent("notes.json")
            if FileManager.default.fileExists(atPath: legacy.path) {
                try? FileManager.default.copyItem(at: legacy, to: url)
            }
        }
        return url
    }

    // MARK: Load

    func load() {
        let url = Self.storageURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            applyDefaults()
            return
        }

        do {
            var doc = try JSONDecoder().decode(StorageDocument.self, from: data)
            migrate(&doc)
            folders = doc.folders
            notes = doc.notes
            trash = doc.trash ?? []
            windowGeometry = doc.window
            pruneTrash()
        } catch {
            print("[Store] Decode error: \(error) — seeding defaults")
            applyDefaults()
        }
    }

    // MARK: Save

    func save() {
        let doc = StorageDocument(folders: folders, notes: notes, window: windowGeometry, trash: trash)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(doc) else { return }
        try? data.write(to: Self.storageURL, options: .atomicWrite)
    }

    // MARK: - CRUD

    @discardableResult
    func addFolder(name: String) -> Folder {
        let folder = Folder(name: name)
        folders.append(folder)
        save()
        return folder
    }

    func renameFolder(id: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[idx].name = trimmed
        save()
    }

    func deleteFolder(id: String) {
        // Reassign notes to general before removal.
        for i in notes.indices where notes[i].folder_id == id {
            notes[i].folder_id = "general"
        }
        folders.removeAll { $0.id == id }
        save()
    }

    func addNote(text: String, folderID: String) {
        let note = Note(text: text, folder_id: folderID)
        notes.insert(note, at: 0)  // newest first
        save()
    }

    func deleteNote(id: String) {
        if let note = notes.first(where: { $0.id == id }) {
            trash.insert(DeletedNote(note: note), at: 0)  // newest first
        }
        notes.removeAll { $0.id == id }
        save()
    }

    func updateNoteText(id: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].text = trimmed
        save()
    }

    func deleteUsedNotes(in folderID: String) {
        let removed = notes.filter { $0.folder_id == folderID && $0.used }
        trash.insert(contentsOf: removed.map { DeletedNote(note: $0) }, at: 0)
        notes.removeAll { $0.folder_id == folderID && $0.used }
        save()
    }

    func markUsed(id: String) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].used = true
        save()
    }

    func resetNote(id: String) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].used = false
        save()
    }

    func moveNote(id: String, toFolder folderID: String) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].folder_id = folderID
        save()
    }

    /// Reorders `folders` so that the folder with `id` lands immediately
    /// before the folder with `targetID`. If `targetID` is nil, moves to end.
    func moveFolder(id: String, before targetID: String?) {
        guard let from = folders.firstIndex(where: { $0.id == id }) else { return }
        let moved = folders.remove(at: from)
        if let targetID,
           let to = folders.firstIndex(where: { $0.id == targetID }) {
            folders.insert(moved, at: to)
        } else {
            folders.append(moved)
        }
        save()
    }

    /// Moves note `id` into `folderID` and places it immediately before the
    /// note with `targetID`. If `targetID` is nil, places at end of that folder.
    /// Same-folder calls reorder; cross-folder calls move + insert.
    func moveNote(id: String, before targetID: String?, in folderID: String) {
        guard let from = notes.firstIndex(where: { $0.id == id }) else { return }
        var moved = notes.remove(at: from)
        moved.folder_id = folderID
        if let targetID,
           let to = notes.firstIndex(where: { $0.id == targetID }) {
            notes.insert(moved, at: to)
        } else {
            notes.append(moved)
        }
        save()
    }

    // MARK: - Trash (delete history)

    /// Restores a deleted note back into the active list. If its original
    /// folder no longer exists it lands in "general" (matches `migrate()`).
    func restoreNote(id: String) {
        guard let idx = trash.firstIndex(where: { $0.id == id }) else { return }
        var note = trash[idx].note
        if !folders.contains(where: { $0.id == note.folder_id }) {
            note.folder_id = "general"
        }
        trash.remove(at: idx)
        notes.insert(note, at: 0)  // newest first
        save()
    }

    /// Permanently removes a single entry from the trash.
    func purgeNote(id: String) {
        trash.removeAll { $0.id == id }
        save()
    }

    /// Empties the entire trash.
    func clearTrash() {
        trash.removeAll()
        save()
    }

    /// Drops trash entries older than `trashRetention` (30 days). Called on load.
    private func pruneTrash() {
        let cutoff = Date().timeIntervalSince1970 - Self.trashRetention
        let before = trash.count
        trash.removeAll { $0.deleted_at < cutoff }
        if trash.count != before { save() }
    }

    // MARK: - Helpers

    private func applyDefaults() {
        folders = [.general]
        notes = []
        windowGeometry = .defaultValue
        save()
    }

    /// Applies forward-compatible migrations so older JSON files continue to work.
    private func migrate(_ doc: inout StorageDocument) {
        // 1. Ensure the "general" folder exists.
        if !doc.folders.contains(where: { $0.id == "general" }) {
            doc.folders.insert(.general, at: 0)
        }

        // 2. Reassign orphaned notes (folder_id references a deleted folder) to "general".
        let knownIDs = Set(doc.folders.map { $0.id })
        for i in doc.notes.indices where !knownIDs.contains(doc.notes[i].folder_id) {
            doc.notes[i].folder_id = "general"
        }

        // 3. `used` defaults to false — already set by Codable default init,
        //    but guard against any future schema that might omit the field.
        // (Nothing extra needed: Swift initialises Bool? as nil; struct defaults handle it.)
    }
}
