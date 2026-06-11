import Foundation

/// A single text prompt managed by MynahPad.
/// `id`, `folder_id`, and `created_at` use snake_case keys to match the
/// cross-app JSON schema produced by the Python version.
struct Note: Identifiable, Codable, Equatable {
    var id: String
    var text: String
    var folder_id: String
    var used: Bool
    var created_at: Double  // Unix timestamp (seconds)

    init(id: String = UUID().uuidString,
         text: String,
         folder_id: String = "general",
         used: Bool = false,
         created_at: Double = Date().timeIntervalSince1970) {
        self.id = id
        self.text = text
        self.folder_id = folder_id
        self.used = used
        self.created_at = created_at
    }
}

/// A note that was deleted by the user, retained in the trash for 30 days so it
/// can be restored. Wraps the original `Note` plus the moment it was deleted.
/// `deleted_at` uses a snake_case key to match the cross-app JSON schema.
struct DeletedNote: Identifiable, Codable, Equatable {
    var note: Note
    var deleted_at: Double  // Unix timestamp (seconds)

    var id: String { note.id }

    init(note: Note, deleted_at: Double = Date().timeIntervalSince1970) {
        self.note = note
        self.deleted_at = deleted_at
    }
}
