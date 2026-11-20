import Foundation

// mynahpad-mcp — a stdio MCP server that lets an agent (e.g. Claude Code) read
// and add MynahPad folders and notes.
//
// It edits notes.json under the same lock the app uses (NotesFile.withLock);
// the running app notices the change through its file watcher and reloads,
// so there's no need to quit and reopen MynahPad.
//
// Built by build.sh into MynahPad.app/Contents/MacOS/mynahpad-mcp. Uses the
// dev store (~/.config/mynahpad-dev) when it sits inside the dev bundle or is
// run with --dev.

let useDev = CommandLine.arguments.contains("--dev") || NotesFile.isDevBundle
let serverVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

// `--store-path` prints which notes.json this helper uses, then exits.
if CommandLine.arguments.contains("--store-path") {
    print(NotesFile.storageURL(dev: useDev).path)
    exit(0)
}

struct ToolError: Error { let message: String }

// MARK: - Store access

/// Locked read-modify-write of notes.json. `body` returns the tool result;
/// the document is written back only when it changed, so read-only tools
/// never create or touch the file.
func withDocument(_ body: (inout StorageDocument) throws -> Any) throws -> Any {
    try NotesFile.withLock(dev: useDev) {
        // The helper may run before the app's first launch.
        NotesFile.importLegacyIfNeeded(dev: useDev)
        var doc: StorageDocument
        if let data = NotesFile.readData(dev: useDev) {
            do {
                doc = try StorageDocument.decode(data)
            } catch {
                // Never overwrite a file we can't parse.
                throw ToolError(message: "notes.json could not be read: \(error.localizedDescription)")
            }
        } else {
            doc = .empty
        }
        doc.migrate()
        let before = doc
        let result = try body(&doc)
        if doc != before {
            try NotesFile.write(try doc.encoded(), dev: useDev)
        }
        return result
    }
}

func folderJSON(_ f: Folder, _ doc: StorageDocument) -> [String: Any] {
    var out: [String: Any] = [
        "id": f.id,
        "name": f.name,
        "note_count": doc.notes.filter { $0.folder_id == f.id }.count,
    ]
    out["parent_id"] = f.parent_id ?? NSNull()
    return out
}

func noteJSON(_ n: Note) -> [String: Any] {
    var out: [String: Any] = [
        "id": n.id,
        "folder_id": n.folder_id,
        "text": n.text,
        "used": n.used,
        "created_at": n.created_at,
    ]
    if n.isImage { out["image"] = true }
    return out
}

func requireFolder(_ id: String, in doc: StorageDocument) throws {
    guard doc.folders.contains(where: { $0.id == id }) else {
        throw ToolError(message: "No folder with id \"\(id)\". Call list_folders to see the ids.")
    }
}

// MARK: - Tools

let tools: [[String: Any]] = [
    [
        "name": "list_folders",
        "description": "List MynahPad folders in the order the app shows them. Nested folders have a parent_id; top-level folders have parent_id null. The \"general\" folder always exists.",
        "inputSchema": ["type": "object", "properties": [String: Any]()],
        "annotations": ["readOnlyHint": true],
    ],
    [
        "name": "create_folder",
        "description": "Create a folder, optionally nested inside another folder. Returns the new folder.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "Folder name"],
                "parent_id": ["type": "string", "description": "Id of the folder to nest it in; omit for top level"],
            ],
            "required": ["name"],
        ],
    ],
    [
        "name": "add_notes",
        "description": "Add one or more text notes to a folder in one call. The notes keep the order given: texts[0] appears above texts[1], and so on (top to bottom = the order to run them). By default the block goes above the folder's existing notes, like a note typed in the app.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "folder_id": ["type": "string", "description": "Target folder id (see list_folders)"],
                "texts": ["type": "array", "items": ["type": "string"], "minItems": 1,
                          "description": "Note texts, in display order"],
                "position": ["type": "string", "enum": ["top", "bottom"],
                             "description": "Put the block above (top, default) or below (bottom) the folder's existing notes"],
            ],
            "required": ["folder_id", "texts"],
        ],
    ],
    [
        "name": "list_notes",
        "description": "List notes in the order the app shows them, optionally only one folder's. Image notes have image: true and their text is the caption.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "folder_id": ["type": "string", "description": "Only notes in this folder; omit for all notes"],
            ],
        ],
        "annotations": ["readOnlyHint": true],
    ],
    [
        "name": "update_note",
        "description": "Replace the text of one note (for an image note, its caption). Returns the updated note.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "Note id (see list_notes)"],
                "text": ["type": "string", "description": "New text"],
            ],
            "required": ["id", "text"],
        ],
    ],
    [
        "name": "delete_notes",
        "description": "Move notes to MynahPad's trash, where the user can restore them for 30 days. Fails without deleting anything if an id is unknown.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "ids": ["type": "array", "items": ["type": "string"], "minItems": 1,
                        "description": "Ids of the notes to delete"],
            ],
            "required": ["ids"],
        ],
        "annotations": ["destructiveHint": true],
    ],
    [
        "name": "reset_folder",
        "description": "Clear the used mark on every note in a folder, so a set of prompts can be run again. Returns how many notes were reset.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "folder_id": ["type": "string", "description": "Folder id (see list_folders)"],
            ],
            "required": ["folder_id"],
        ],
    ],
]

func callTool(_ name: String, _ args: [String: Any]) throws -> Any {
    switch name {
    case "list_folders":
        return try withDocument { doc in
            ["folders": doc.folders.map { folderJSON($0, doc) }]
        }

    case "create_folder":
        let name = (args["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ToolError(message: "name must not be empty") }
        let parentID = args["parent_id"] as? String
        return try withDocument { doc in
            if let parentID { try requireFolder(parentID, in: doc) }
            let folder = Folder(name: name, parent_id: parentID)
            doc.folders.append(folder)
            return ["folder": folderJSON(folder, doc)]
        }

    case "add_notes":
        guard let folderID = args["folder_id"] as? String else {
            throw ToolError(message: "folder_id is required")
        }
        guard let rawTexts = args["texts"] as? [String] else {
            throw ToolError(message: "texts must be an array of strings")
        }
        let texts = rawTexts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !texts.isEmpty, !texts.contains(where: \.isEmpty) else {
            throw ToolError(message: "texts must contain at least one non-empty string, and no empty ones")
        }
        let position = args["position"] as? String ?? "top"
        guard position == "top" || position == "bottom" else {
            throw ToolError(message: "position must be \"top\" or \"bottom\"")
        }
        return try withDocument { doc in
            try requireFolder(folderID, in: doc)
            let now = Date().timeIntervalSince1970
            let added = texts.map { Note(text: $0, folder_id: folderID, created_at: now) }
            // The app shows a folder's notes in array order, so insert the
            // block before the folder's first note (top) or after its last.
            let indices = doc.notes.indices.filter { doc.notes[$0].folder_id == folderID }
            let at = position == "top" ? (indices.first ?? 0)
                                       : (indices.last.map { $0 + 1 } ?? doc.notes.count)
            doc.notes.insert(contentsOf: added, at: at)
            return ["added": added.map(noteJSON)]
        }

    case "list_notes":
        let folderID = args["folder_id"] as? String
        return try withDocument { doc in
            if let folderID { try requireFolder(folderID, in: doc) }
            let notes = doc.notes.filter { folderID == nil || $0.folder_id == folderID }
            return ["notes": notes.map(noteJSON)]
        }

    case "update_note":
        guard let id = args["id"] as? String else { throw ToolError(message: "id is required") }
        guard let rawText = args["text"] as? String else { throw ToolError(message: "text is required") }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return try withDocument { doc in
            guard let idx = doc.notes.firstIndex(where: { $0.id == id }) else {
                throw ToolError(message: "No note with id \"\(id)\". Call list_notes to see the ids.")
            }
            // A text note can't be empty; an image note's caption can.
            guard !text.isEmpty || doc.notes[idx].isImage else {
                throw ToolError(message: "text must not be empty")
            }
            doc.notes[idx].text = text
            return ["note": noteJSON(doc.notes[idx])]
        }

    case "delete_notes":
        guard let ids = args["ids"] as? [String], !ids.isEmpty else {
            throw ToolError(message: "ids must be a non-empty array of strings")
        }
        return try withDocument { doc in
            let wanted = Set(ids)
            let unknown = wanted.subtracting(doc.notes.map(\.id)).sorted()
            guard unknown.isEmpty else {
                throw ToolError(message: "No note with id: \(unknown.joined(separator: ", ")). Nothing was deleted.")
            }
            let removed = doc.notes.filter { wanted.contains($0.id) }
            var trash = doc.trash ?? []
            trash.insert(contentsOf: removed.map { DeletedNote(note: $0) }, at: 0)
            doc.trash = trash
            doc.notes.removeAll { wanted.contains($0.id) }
            return ["deleted": removed.map(\.id), "restorable_from_trash": true]
        }

    case "reset_folder":
        guard let folderID = args["folder_id"] as? String else {
            throw ToolError(message: "folder_id is required")
        }
        return try withDocument { doc in
            try requireFolder(folderID, in: doc)
            var count = 0
            for i in doc.notes.indices where doc.notes[i].folder_id == folderID && doc.notes[i].used {
                doc.notes[i].used = false
                count += 1
            }
            return ["reset": count]
        }

    default:
        throw ToolError(message: "Unknown tool \"\(name)\"")
    }
}

// MARK: - JSON-RPC over stdio

func send(_ message: [String: Any]) {
    guard var data = try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes]) else { return }
    data.append(0x0A)
    FileHandle.standardOutput.write(data)
}

func reply(_ id: Any, result: Any) {
    send(["jsonrpc": "2.0", "id": id, "result": result])
}

func replyError(_ id: Any, code: Int, message: String) {
    send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
}

func toolText(_ value: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: value,
                                                 options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
          let text = String(data: data, encoding: .utf8) else { return "\(value)" }
    return text
}

func handle(_ msg: [String: Any]) {
    let method = msg["method"] as? String ?? ""
    // Notifications carry no id and get no reply.
    guard let id = msg["id"], !(id is NSNull) else { return }
    let params = msg["params"] as? [String: Any] ?? [:]

    switch method {
    case "initialize":
        let requested = params["protocolVersion"] as? String
        reply(id, result: [
            // Answer with the client's version only when we speak it;
            // otherwise offer our latest and let the client decide.
            "protocolVersion": requested.flatMap { supportedProtocolVersions.contains($0) ? $0 : nil }
                ?? supportedProtocolVersions[0],
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": ["name": "mynahpad", "version": serverVersion],
            "instructions": "MynahPad stores text prompts in folders. Call list_folders for folder ids, then add_notes to add several notes in order. delete_notes moves notes to the trash; reset_folder clears used marks. The running app picks up changes on its own.",
        ])
    case "ping":
        reply(id, result: [String: Any]())
    case "tools/list":
        reply(id, result: ["tools": tools])
    case "tools/call":
        guard let name = params["name"] as? String else {
            replyError(id, code: -32602, message: "params.name is required")
            return
        }
        let args = params["arguments"] as? [String: Any] ?? [:]
        do {
            let result = try callTool(name, args)
            reply(id, result: [
                "content": [["type": "text", "text": toolText(result)]],
                "structuredContent": result,
            ])
        } catch {
            let message = (error as? ToolError)?.message ?? error.localizedDescription
            reply(id, result: ["content": [["type": "text", "text": message]], "isError": true])
        }
    default:
        replyError(id, code: -32601, message: "Method not found: \(method)")
    }
}

while let line = readLine(strippingNewline: true) {
    if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
    guard let data = line.data(using: .utf8),
          let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        replyError(NSNull(), code: -32700, message: "Parse error")
        continue
    }
    handle(msg)
}
