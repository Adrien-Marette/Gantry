import Foundation

/// One file mutation reported by a completed tool call.
public struct ReviewedChange: Hashable, Sendable, Identifiable {
    public var id: String
    public var toolName: String
    public var oldText: String?
    public var newText: String
    public var isCreation: Bool

    public init(
        id: String,
        toolName: String,
        oldText: String? = nil,
        newText: String,
        isCreation: Bool = false
    ) {
        self.id = id
        self.toolName = toolName
        self.oldText = oldText
        self.newText = newText
        self.isCreation = isCreation
    }

    public var addedLines: Int { Self.lineCount(newText) }
    public var removedLines: Int { Self.lineCount(oldText) }

    static func lineCount(_ text: String?) -> Int {
        guard let text, !text.isEmpty else { return 0 }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var count = normalized.components(separatedBy: "\n").count
        if normalized.hasSuffix("\n") { count -= 1 }
        return max(0, count)
    }
}

/// All changes to one file, in the order Claude made them.
public struct ReviewedFile: Hashable, Sendable, Identifiable {
    public var id: String
    public var path: String
    public var displayPath: String
    public var changes: [ReviewedChange]

    public init(path: String, displayPath: String, changes: [ReviewedChange]) {
        self.id = path
        self.path = path
        self.displayPath = displayPath
        self.changes = changes
    }

    public var addedLines: Int { changes.reduce(0) { $0 + $1.addedLines } }
    public var removedLines: Int { changes.reduce(0) { $0 + $1.removedLines } }
    public var wasCreated: Bool { changes.first?.isCreation == true }

    public var toolNames: [String] {
        var seen = Set<String>()
        return changes.compactMap { seen.insert($0.toolName).inserted ? $0.toolName : nil }
    }

    public var changeSummary: String {
        let count = changes.count
        let noun = count == 1 ? "change" : "changes"
        return "\(count) \(noun) · +\(addedLines) −\(removedLines)"
    }
}

/// A reviewable log of the file changes Claude made in one session.
///
/// It is built from completed `Edit`, `MultiEdit`, `Write`, and `NotebookEdit`
/// tool calls, so it reflects what Claude did even after the working tree has
/// moved on. It cannot see changes made by shell commands or by other tools.
/// `Write` replacements use the original file Claude Code reports when it is
/// available.
public struct SessionReview: Hashable, Sendable {
    public var projectPath: String
    public var files: [ReviewedFile]

    public init(projectPath: String, files: [ReviewedFile]) {
        self.projectPath = projectPath
        self.files = files
    }

    public var isEmpty: Bool { files.isEmpty }
    public var fileCount: Int { files.count }
    public var addedLines: Int { files.reduce(0) { $0 + $1.addedLines } }
    public var removedLines: Int { files.reduce(0) { $0 + $1.removedLines } }

    public var summaryLine: String {
        let noun = files.count == 1 ? "file" : "files"
        return "\(files.count) \(noun) · +\(addedLines) −\(removedLines)"
    }

    public static func build(session: ChatSession, projectPath: String) -> SessionReview {
        var files: [ReviewedFile] = []
        var indexByPath: [String: Int] = [:]

        for turn in session.turns {
            for block in turn.blocks {
                guard let tool = block.tool,
                      tool.status == .completed,
                      !tool.isError,
                      tool.isFileMutation else {
                    continue
                }
                for entry in changes(for: tool) {
                    let path = absolutePath(entry.path, projectPath: projectPath)
                    if let index = indexByPath[path] {
                        files[index].changes.append(entry.change)
                    } else {
                        indexByPath[path] = files.count
                        files.append(ReviewedFile(
                            path: path,
                            displayPath: displayPath(path, projectPath: projectPath),
                            changes: [entry.change]
                        ))
                    }
                }
            }
        }

        return SessionReview(projectPath: projectPath, files: files)
    }

    /// A message that asks Claude to address the notes the user wrote. Notes
    /// are keyed by `ReviewedFile.id`. Returns nil when every note is empty.
    public func reviewMessage(
        notes: [String: String],
        overallNote: String = ""
    ) -> String? {
        let overall = overallNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileNotes = files.compactMap { file -> String? in
            let note = notes[file.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !note.isEmpty else { return nil }
            return "\(file.displayPath):\n\(note)"
        }
        guard !overall.isEmpty || !fileNotes.isEmpty else { return nil }

        var message = "Please address these review notes on the current changes."
        if !overall.isEmpty {
            message += "\n\nOverall:\n\(overall)"
        }
        if !fileNotes.isEmpty {
            message += "\n\n" + fileNotes.joined(separator: "\n\n")
        }
        return message
    }

    /// A readable text copy of every change, suitable for a PR description or
    /// handing the review to another tool.
    public func plainText() -> String {
        guard !files.isEmpty else { return "No file changes." }
        var lines = ["Review summary — \(summaryLine)", ""]
        for file in files {
            lines.append(plainText(for: file))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    public func plainText(for file: ReviewedFile) -> String {
        var lines = ["\(file.displayPath)  (+\(file.addedLines) −\(file.removedLines))"]
        for change in file.changes {
            if change.isCreation {
                lines.append("[New file]")
            } else if change.toolName == "Write" {
                lines.append("[Wrote file]")
            } else {
                lines.append("[\(change.toolName)]")
            }
            if let oldText = change.oldText, !oldText.isEmpty {
                for line in oldText.components(separatedBy: "\n") {
                    lines.append("- \(line)")
                }
            }
            if change.newText.isEmpty {
                lines.append("+ (empty)")
            } else {
                for line in change.newText.components(separatedBy: "\n") {
                    lines.append("+ \(line)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Tool extraction

    private static func changes(
        for tool: ToolActivity
    ) -> [(path: String, change: ReviewedChange)] {
        let toolPath = tool.filePath

        switch tool.name {
        case "Write":
            guard let path = toolPath else { return [] }
            let resultType = tool.structuredResult?["type"]?.stringValue?.lowercased()
            let isCreation = resultType == "create"
            // Claude Code includes the file's previous contents in the tool
            // result, so a replacement can show a real before/after diff.
            let original = isCreation
                ? nil
                : tool.structuredResult?["originalFile"]?.stringValue
            return [(
                path,
                ReviewedChange(
                    id: "\(tool.id)-0",
                    toolName: tool.name,
                    oldText: original,
                    newText: tool.input["content"]?.stringValue ?? "",
                    isCreation: isCreation
                )
            )]

        case "Edit":
            guard let path = toolPath,
                  let newText = tool.input["new_string"]?.stringValue else {
                return []
            }
            return [(
                path,
                ReviewedChange(
                    id: "\(tool.id)-0",
                    toolName: tool.name,
                    oldText: tool.input["old_string"]?.stringValue,
                    newText: newText
                )
            )]

        case "MultiEdit":
            let edits = tool.input["edits"]?.arrayValue ?? []
            return edits.enumerated().compactMap { index, entry in
                guard let object = entry.objectValue,
                      let newText = object["new_string"]?.stringValue else {
                    return nil
                }
                let path = object["file_path"]?.stringValue ?? toolPath
                guard let path else { return nil }
                return (
                    path,
                    ReviewedChange(
                        id: "\(tool.id)-\(index)",
                        toolName: tool.name,
                        oldText: object["old_string"]?.stringValue,
                        newText: newText
                    )
                )
            }

        case "NotebookEdit":
            guard let path = toolPath,
                  let newText = tool.input["new_source"]?.stringValue else {
                return []
            }
            return [(
                path,
                ReviewedChange(
                    id: "\(tool.id)-0",
                    toolName: tool.name,
                    oldText: nil,
                    newText: newText
                )
            )]

        default:
            return []
        }
    }

    // MARK: - Paths

    static func absolutePath(_ raw: String, projectPath: String) -> String {
        let root = URL(fileURLWithPath: projectPath, isDirectory: true)
        let expanded = (raw as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL.path
        }
        return root.appendingPathComponent(expanded).standardizedFileURL.path
    }

    static func displayPath(_ absolutePath: String, projectPath: String) -> String {
        let root = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard absolutePath.hasPrefix(prefix) else { return absolutePath }
        return String(absolutePath.dropFirst(prefix.count))
    }
}
