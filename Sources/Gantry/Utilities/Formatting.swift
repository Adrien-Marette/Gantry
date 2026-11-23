import Foundation

enum Format {
    static func relativeTime(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<45:
            return "now"
        case ..<3_600:
            return "\(max(1, Int(seconds / 60)))m"
        case ..<86_400:
            return "\(Int(seconds / 3_600))h"
        case ..<172_800:
            return "Yesterday"
        case ..<604_800:
            return "\(Int(seconds / 86_400))d"
        default:
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    static func dayLabel(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    static func duration(milliseconds: Int?) -> String? {
        guard let milliseconds, milliseconds >= 0 else { return nil }
        let seconds = Double(milliseconds) / 1_000
        if seconds < 1 { return "<1s" }
        if seconds < 60 { return String(format: "%.0fs", seconds) }
        let minutes = Int(seconds / 60)
        let remaining = Int(seconds.truncatingRemainder(dividingBy: 60))
        return remaining == 0 ? "\(minutes)m" : "\(minutes)m \(remaining)s"
    }

    static func cost(_ value: Double) -> String? {
        guard value > 0.000_001 else { return nil }
        if value < 0.01 { return "<$0.01" }
        if value < 1 { return String(format: "$%.2f", value) }
        return String(format: "$%.2f", value)
    }

    static func tokens(_ count: Int) -> String {
        if count < 1_000 { return "\(count)" }
        if count < 1_000_000 {
            let value = Double(count) / 1_000
            return value < 10 ? String(format: "%.1fk", value) : String(format: "%.0fk", value)
        }
        return String(format: "%.1fM", Double(count) / 1_000_000)
    }

    static func abbreviatedPath(_ path: String, root: String? = nil) -> String {
        if let root, path.hasPrefix(root) {
            let relative = String(path.dropFirst(root.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return relative.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : relative
        }
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    static func truncated(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let index = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    static func prettyToolName(_ name: String) -> String {
        if name.hasPrefix("mcp__") {
            let parts = name.components(separatedBy: "__")
            if parts.count >= 3 {
                return parts.dropFirst(2).joined(separator: " ")
                    .replacingOccurrences(of: "_", with: " ")
                    .capitalized
            }
        }
        switch name {
        case "WebFetch": return "Web Fetch"
        case "WebSearch": return "Web Search"
        case "TodoWrite": return "Update plan"
        case "NotebookEdit": return "Edit notebook"
        case "MultiEdit": return "Edit file"
        default: return name
        }
    }
}

struct GitContext {
    var branch: String?
    var repositoryName: String?
    var isRepository: Bool

    static func read(from projectURL: URL) -> GitContext {
        let dotGit = projectURL.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else {
            return GitContext(branch: nil, repositoryName: nil, isRepository: false)
        }

        var gitDirectory = dotGit
        if !isDirectory.boolValue,
           let contents = try? String(contentsOf: dotGit, encoding: .utf8),
           let line = contents.split(whereSeparator: \.isNewline)
            .first(where: { $0.hasPrefix("gitdir:") }) {
            let rawPath = line.dropFirst("gitdir:".count)
                .trimmingCharacters(in: .whitespaces)
            let path = rawPath.hasPrefix("/")
                ? rawPath
                : projectURL.appendingPathComponent(rawPath).standardizedFileURL.path
            gitDirectory = URL(fileURLWithPath: path, isDirectory: true)
        }

        guard let head = try? String(
            contentsOf: gitDirectory.appendingPathComponent("HEAD"),
            encoding: .utf8
        ) else {
            return GitContext(branch: nil, repositoryName: projectURL.lastPathComponent, isRepository: true)
        }

        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        let branch: String
        if trimmed.hasPrefix("ref: refs/heads/") {
            branch = String(trimmed.dropFirst("ref: refs/heads/".count))
        } else {
            branch = String(trimmed.prefix(7))
        }
        return GitContext(
            branch: branch.isEmpty ? nil : branch,
            repositoryName: projectURL.lastPathComponent,
            isRepository: true
        )
    }
}
