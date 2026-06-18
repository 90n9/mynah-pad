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

    /// Base config dir for this build variant (`~/.config/mynahpad[-dev]`).
    /// Dev builds use a sibling directory so testing doesn't trample the
    /// user's production notes. Detection is bundle-id based: prod is
    /// `com.mynahpad.app`; dev is `com.mynahpad.app.dev` (see build.sh).
    private static var baseDirURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let bundleID = Bundle.main.bundleIdentifier ?? "com.mynahpad.app"
        let dirName = bundleID.hasSuffix(".dev") ? "mynahpad-dev" : "mynahpad"
        let base = home.appendingPathComponent(".config/\(dirName)", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Directory holding image-note files (`<uuid>.png`), created on demand.
    static var imagesDirURL: URL {
        let dir = baseDirURL.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// On-disk URL for an image note's file, or nil for a text note.
    static func imageURL(for note: Note) -> URL? {
        guard let name = note.image_path else { return nil }
        return imagesDirURL.appendingPathComponent(name)
    }

    private static var storageURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = baseDirURL.appendingPathComponent("notes.json")

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
        // Re-home child folders to the deleted folder's parent (or top level)
        // so they aren't orphaned.
        let removedParent = folders.first(where: { $0.id == id })?.parent_id
        for i in folders.indices where folders[i].parent_id == id {
            folders[i].parent_id = removedParent
        }
        // Reassign notes to general before removal.
        for i in notes.indices where notes[i].folder_id == id {
            notes[i].folder_id = "general"
        }
        folders.removeAll { $0.id == id }
        save()
    }

    /// Re-parents folder `id` under `parentID` (nil = top level). The "general"
    /// folder always stays at the root. Guards against cycles: a folder cannot
    /// be nested inside itself or any of its own descendants.
    func setFolderParent(id: String, parentID: String?) {
        guard id != "general",
              let idx = folders.firstIndex(where: { $0.id == id }),
              folders[idx].parent_id != parentID else { return }
        if let parentID {
            guard folders.contains(where: { $0.id == parentID }),
                  !isDescendant(parentID, of: id) else { return }
        }
        folders[idx].parent_id = parentID
        save()
    }

    /// True when `candidate` is `ancestor` itself or sits anywhere below it in
    /// the folder tree. Used to reject re-parent operations that would form a
    /// cycle. Bounded by `folders.count` against malformed (already-cyclic) data.
    func isDescendant(_ candidate: String, of ancestor: String) -> Bool {
        var current: String? = candidate
        var steps = 0
        while let c = current, steps <= folders.count {
            if c == ancestor { return true }
            current = folders.first(where: { $0.id == c })?.parent_id
            steps += 1
        }
        return false
    }

    func addNote(text: String, folderID: String) {
        let note = Note(text: text, folder_id: folderID)
        notes.insert(note, at: 0)  // newest first
        save()
    }

    /// Persists `pngData` to `images/<uuid>.png` and inserts an image note
    /// referencing it. Returns the created note, or nil if the write failed.
    @discardableResult
    func addImageNote(pngData: Data, caption: String = "", folderID: String) -> Note? {
        let filename = "\(UUID().uuidString).png"
        let url = Self.imagesDirURL.appendingPathComponent(filename)
        guard (try? pngData.write(to: url, options: .atomic)) != nil else {
            print("[Store] failed to write image note to \(url.path)")
            return nil
        }
        let note = Note(text: caption, folder_id: folderID, image_path: filename)
        notes.insert(note, at: 0)  // newest first
        save()
        return note
    }

    /// Removes the backing image file for a note, if any. Called when a note
    /// leaves the system permanently (trash purge / clear).
    private func deleteImageFile(for note: Note) {
        guard let url = Self.imageURL(for: note) else { return }
        try? FileManager.default.removeItem(at: url)
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

    /// Clears the `used` flag on every note in `folderID`, returning the whole
    /// folder to an unused state. No-op (no save) when nothing was used.
    func resetNotes(in folderID: String) {
        var changed = false
        for i in notes.indices where notes[i].folder_id == folderID && notes[i].used {
            notes[i].used = false
            changed = true
        }
        if changed { save() }
    }

    /// Duplicates a folder, its notes, and any nested subfolders (with their
    /// notes) into fresh copies. The top copy is named "<name> copy" and shares
    /// the original's parent. Image notes get independent PNG files so edits to
    /// one copy don't affect the other. Returns the new top-level folder.
    @discardableResult
    func duplicateFolder(id: String) -> Folder? {
        guard let original = folders.first(where: { $0.id == id }) else { return nil }

        // Copy the folder subtree, mapping each old folder ID to its new one so
        // child parent_ids and note folder_ids can be re-pointed.
        var idMap: [String: String] = [:]
        var newFolders: [Folder] = []

        let top = Folder(name: "\(original.name) copy", parent_id: original.parent_id)
        idMap[original.id] = top.id
        newFolders.append(top)

        var queue = [original.id]
        while !queue.isEmpty {
            let parentOld = queue.removeFirst()
            for child in folders where child.parent_id == parentOld {
                let copy = Folder(name: child.name, parent_id: idMap[parentOld])
                idMap[child.id] = copy.id
                newFolders.append(copy)
                queue.append(child.id)
            }
        }

        // Copy every note belonging to a folder in the subtree.
        var newNotes: [Note] = []
        for note in notes where idMap[note.folder_id] != nil {
            let imagePath = note.image_path.flatMap { copyImageFile(named: $0) }
            newNotes.append(Note(text: note.text,
                                 folder_id: idMap[note.folder_id]!,
                                 used: note.used,
                                 image_path: imagePath))
        }

        folders.append(contentsOf: newFolders)
        notes.append(contentsOf: newNotes)
        save()
        return top
    }

    /// Copies an image file to a fresh uuid-named file in the images dir.
    /// Returns the new filename, or nil if the source is missing / copy failed.
    private func copyImageFile(named name: String) -> String? {
        let src = Self.imagesDirURL.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: src.path) else { return nil }
        let newName = "\(UUID().uuidString).png"
        let dst = Self.imagesDirURL.appendingPathComponent(newName)
        guard (try? FileManager.default.copyItem(at: src, to: dst)) != nil else { return nil }
        return newName
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

    /// Drag-reorder: places folder `id` immediately before `targetID` in the
    /// sibling order, re-parenting it to share `targetID`'s parent so it becomes
    /// a true sibling. Cycle- and "general"-root-guarded like `setFolderParent`.
    func reorderFolder(id: String, before targetID: String) {
        guard id != targetID,
              let target = folders.first(where: { $0.id == targetID }),
              let from = folders.firstIndex(where: { $0.id == id }) else { return }
        let newParent = target.parent_id
        if let newParent, isDescendant(newParent, of: id) { return }   // would form a cycle
        if id == "general" && newParent != nil { return }              // general stays root
        var moved = folders.remove(at: from)
        moved.parent_id = newParent
        guard let to = folders.firstIndex(where: { $0.id == targetID }) else {
            folders.append(moved); save(); return
        }
        folders.insert(moved, at: to)
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
        if let entry = trash.first(where: { $0.id == id }) {
            deleteImageFile(for: entry.note)
        }
        trash.removeAll { $0.id == id }
        save()
    }

    /// Empties the entire trash.
    func clearTrash() {
        trash.forEach { deleteImageFile(for: $0.note) }
        trash.removeAll()
        save()
    }

    /// Drops trash entries older than `trashRetention` (30 days). Called on load.
    private func pruneTrash() {
        let cutoff = Date().timeIntervalSince1970 - Self.trashRetention
        let expired = trash.filter { $0.deleted_at < cutoff }
        guard !expired.isEmpty else { return }
        expired.forEach { deleteImageFile(for: $0.note) }
        trash.removeAll { $0.deleted_at < cutoff }
        save()
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

        // 3. Normalise folder nesting: "general" is always a root; any
        //    parent_id pointing at a missing folder falls back to top level.
        for i in doc.folders.indices {
            if doc.folders[i].id == "general" {
                doc.folders[i].parent_id = nil
            } else if let p = doc.folders[i].parent_id, !knownIDs.contains(p) {
                doc.folders[i].parent_id = nil
            }
        }

        // 4. `used` defaults to false — already set by Codable default init,
        //    but guard against any future schema that might omit the field.
        // (Nothing extra needed: Swift initialises Bool? as nil; struct defaults handle it.)
    }
}
