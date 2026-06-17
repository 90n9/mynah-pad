import Foundation

/// A named bucket that groups notes together.
struct Folder: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    /// ID of the folder this one is nested inside, or nil for a top-level
    /// folder. Optional (and snake_case to match the cross-app schema) so older
    /// `notes.json` files without the key still decode as top-level folders.
    var parent_id: String?

    init(id: String = UUID().uuidString, name: String, parent_id: String? = nil) {
        self.id = id
        self.name = name
        self.parent_id = parent_id
    }

    /// The default folder every installation starts with.
    static let general = Folder(id: "general", name: "General")
}
