import Foundation

/// A file or folder the user attaches to a prompt. Gantry passes the path to
/// Claude; it does not read or copy the contents.
public struct PromptAttachment: Hashable, Sendable, Identifiable {
    public var path: String
    public var name: String
    public var isDirectory: Bool

    public var id: String { path }

    public init(path: String, name: String, isDirectory: Bool = false) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
    }

    /// Standardizes, deduplicates, and drops URLs that no longer exist.
    public static func make(from urls: [URL]) -> [PromptAttachment] {
        var seen = Set<String>()
        var result: [PromptAttachment] = []
        for url in urls {
            let standardized = url.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: standardized.path,
                isDirectory: &isDirectory
            ) else { continue }
            guard seen.insert(standardized.path).inserted else { continue }
            let name = standardized.lastPathComponent.isEmpty
                ? standardized.path
                : standardized.lastPathComponent
            result.append(PromptAttachment(
                path: standardized.path,
                name: name,
                isDirectory: isDirectory.boolValue
            ))
        }
        return result
    }

    /// Appends only attachments whose path is not already present.
    public static func merging(
        _ existing: [PromptAttachment],
        with added: [PromptAttachment]
    ) -> [PromptAttachment] {
        var seen = Set(existing.map(\.id))
        var result = existing
        for attachment in added where seen.insert(attachment.id).inserted {
            result.append(attachment)
        }
        return result
    }
}

/// Turns the composer's text and attachments into the user turn Claude reads.
/// Paths are absolute so Claude can open them from the project directory.
public enum PromptAttachmentComposer {
    public static func compose(
        text: String,
        attachments: [PromptAttachment]
    ) -> String {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let unique = PromptAttachment.merging([], with: attachments)
        guard !unique.isEmpty else { return body }

        let lines = unique.map { "- \($0.path)" }.joined(separator: "\n")
        let heading = unique.count == 1
            ? "Use this path as context:"
            : "Use these paths as context:"

        if body.isEmpty {
            return "\(heading)\n\(lines)"
        }
        return "\(body)\n\n\(heading)\n\(lines)"
    }
}
