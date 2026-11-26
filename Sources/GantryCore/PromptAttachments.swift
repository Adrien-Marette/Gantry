import Foundation

/// A file or folder the user attaches to a prompt. Gantry passes the path to
/// Claude; it does not read or copy the contents.
public struct PromptAttachment: Hashable, Sendable, Identifiable {
    public var path: String
    public var name: String
    public var isDirectory: Bool

    public var id: String { path }

    public var isImage: Bool { !isDirectory && PromptAttachment.isImagePath(path) }

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "tif", "bmp"]

    public static func isImagePath(_ path: String) -> Bool {
        imageExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// Writes pasted image bytes (PNG) to `directory` with user-only
    /// permissions so Claude can read them by path like any attachment.
    public static func savePastedImage(_ png: Data, in directory: URL) throws -> PromptAttachment {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let name = "Pasted \(UUID().uuidString.prefix(8)).png"
        let url = directory.appendingPathComponent(name)
        try png.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return PromptAttachment(path: url.standardizedFileURL.path, name: name)
    }

    /// Deletes pasted images older than `age` so the folder does not grow
    /// forever. Their thumbnails in old chats become placeholders.
    public static func removePastedImages(in directory: URL, olderThan age: TimeInterval, now: Date = .now) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, now.timeIntervalSince(modified) > age {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

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

    /// Image paths listed by `compose` in a sent prompt, so the transcript can
    /// show thumbnails without persisting extra state.
    public static func imagePaths(in prompt: String) -> [String] {
        prompt.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("- /") else { return nil }
            let path = String(line.dropFirst(2))
            return PromptAttachment.isImagePath(path) ? path : nil
        }
    }
}
