import SwiftUI
import GantryCore

struct EditDiff: Hashable {
    var path: String
    var oldText: String?
    var newText: String
}

enum ToolDetailContent {
    case command(String, output: String?)
    case code(path: String?, language: String?, code: String, output: String?)
    case edits([EditDiff], output: String?)
    case output(String)
    case todos([String])
    case json(String)
    case none
}

struct ToolPresentation {
    var title: String
    var subtitle: String
    var icon: String
    var tint: Color
    var detail: ToolDetailContent
    var showsStatusOnRow: Bool = true

    static func make(for tool: ToolActivity, projectPath: String) -> ToolPresentation {
        let name = tool.name
        let input = tool.input
        let path = tool.filePath.map { Format.abbreviatedPath($0, root: projectPath) }
        let result = (tool.resultText?.isEmpty == false) ? tool.resultText : nil
        let pretty = tool.displayName ?? Format.prettyToolName(name)

        switch name {
        case "Read":
            return ToolPresentation(
                title: "Read",
                subtitle: path ?? input["file_path"]?.stringValue ?? "file",
                icon: "doc.text.magnifyingglass",
                tint: Palette.info,
                detail: .code(
                    path: path,
                    language: language(for: path),
                    code: result ?? "",
                    output: nil
                )
            )

        case "Write":
            let content = input["content"]?.stringValue ?? ""
            return ToolPresentation(
                title: "Write",
                subtitle: path ?? "file",
                icon: "square.and.pencil",
                tint: Palette.accent,
                detail: .code(
                    path: path,
                    language: language(for: path),
                    code: content,
                    output: tool.status == .failed ? result : nil
                )
            )

        case "Edit", "MultiEdit", "NotebookEdit":
            var edits: [EditDiff] = []
            if let editArray = input["edits"]?.arrayValue {
                for edit in editArray {
                    guard let object = edit.objectValue else { continue }
                    let filePath = object["file_path"]?.stringValue ?? tool.filePath ?? ""
                    let newText = object["new_string"]?.stringValue ?? ""
                    edits.append(EditDiff(
                        path: Format.abbreviatedPath(filePath, root: projectPath),
                        oldText: object["old_string"]?.stringValue,
                        newText: newText
                    ))
                }
            } else {
                edits.append(EditDiff(
                    path: path ?? "file",
                    oldText: input["old_string"]?.stringValue,
                    newText: input["new_string"]?.stringValue ?? input["new_source"]?.stringValue ?? ""
                ))
            }
            return ToolPresentation(
                title: edits.count > 1 ? "Edit \(edits.count) files" : "Edit",
                subtitle: edits.first?.path ?? path ?? "file",
                icon: "pencil.line",
                tint: Palette.accent,
                detail: .edits(edits, output: tool.status == .failed ? result : nil)
            )

        case "Bash":
            let command = input["command"]?.stringValue ?? ""
            let description = input["description"]?.stringValue
            let subtitle = description?.nilIfEmpty
                ?? Format.truncated(command.replacingOccurrences(of: "\n", with: " "), limit: 90)
            return ToolPresentation(
                title: "Run",
                subtitle: subtitle,
                icon: "terminal",
                tint: Palette.warning,
                detail: .command(command, output: result)
            )

        case "Glob":
            let pattern = input["pattern"]?.stringValue ?? ""
            let searchPath = input["path"]?.stringValue.map {
                Format.abbreviatedPath($0, root: projectPath)
            }
            return ToolPresentation(
                title: "Find files",
                subtitle: searchPath.map { "\(pattern) in \($0)" } ?? pattern,
                icon: "folder.badge.magnifyingglass",
                tint: Palette.info,
                detail: result.map { .output($0) } ?? .none
            )

        case "Grep":
            let pattern = input["pattern"]?.stringValue ?? ""
            let searchPath = input["path"]?.stringValue.map {
                Format.abbreviatedPath($0, root: projectPath)
            }
            return ToolPresentation(
                title: "Search",
                subtitle: searchPath.map { "\(pattern) in \($0)" } ?? pattern,
                icon: "magnifyingglass",
                tint: Palette.info,
                detail: result.map { .output($0) } ?? .none
            )

        case "WebFetch":
            let url = input["url"]?.stringValue ?? ""
            return ToolPresentation(
                title: "Fetch page",
                subtitle: URL(string: url)?.host ?? url,
                icon: "globe",
                tint: Palette.info,
                detail: .code(path: nil, language: "markdown", code: url, output: result)
            )

        case "WebSearch":
            let query = input["query"]?.stringValue ?? ""
            return ToolPresentation(
                title: "Search web",
                subtitle: query,
                icon: "globe.europe.africa",
                tint: Palette.info,
                detail: result.map { .output($0) } ?? .none
            )

        case "Task", "Agent":
            let description = input["description"]?.stringValue
                ?? input["prompt"]?.stringValue.map { Format.truncated($0, limit: 80) }
                ?? "Subagent"
            let kind = input["subagent_type"]?.stringValue
            return ToolPresentation(
                title: kind.map { "Delegate · \($0)" } ?? "Delegate",
                subtitle: description,
                icon: "point.3.connected.trianglepath.dotted",
                tint: Palette.info,
                detail: result.map { .output($0) } ?? .none
            )

        case "TodoWrite":
            let todos = input["todos"]?.arrayValue?.compactMap { item -> String? in
                guard let object = item.objectValue,
                      let content = object["content"]?.stringValue else { return nil }
                let status = object["status"]?.stringValue ?? "pending"
                let marker = status == "completed" ? "✓" : (status == "in_progress" ? "◐" : "○")
                return "\(marker)  \(content)"
            } ?? []
            return ToolPresentation(
                title: "Update plan",
                subtitle: todos.isEmpty ? "Checklist" : "\(todos.count) steps",
                icon: "checklist",
                tint: Palette.success,
                detail: .todos(todos)
            )

        case "AskUserQuestion":
            let question = input["questions"]?.arrayValue?.first?["question"]?.stringValue
                ?? "Question for you"
            return ToolPresentation(
                title: "Ask you",
                subtitle: Format.truncated(question, limit: 100),
                icon: "bubble.left.and.bubble.right",
                tint: Palette.info,
                detail: .json(input.prettyJSON)
            )

        case "Skill":
            let skill = input["skill"]?.stringValue ?? input["name"]?.stringValue ?? "Skill"
            return ToolPresentation(
                title: "Use skill",
                subtitle: skill,
                icon: "wand.and.rays",
                tint: Palette.info,
                detail: result.map { .output($0) } ?? .none
            )

        case "ExitPlanMode":
            return ToolPresentation(
                title: "Ready to implement",
                subtitle: "Plan approval",
                icon: "checkmark.seal",
                tint: Palette.success,
                detail: .json(input.prettyJSON)
            )

        default:
            let subtitle = tool.command
                ?? path
                ?? input["query"]?.stringValue
                ?? input["description"]?.stringValue
                ?? input["prompt"]?.stringValue.map { Format.truncated($0, limit: 90) }
                ?? "Tool call"
            let hasDetails = !(input.objectValue?.isEmpty ?? true) || result != nil
            return ToolPresentation(
                title: pretty,
                subtitle: subtitle,
                icon: name.hasPrefix("mcp__") ? "puzzlepiece.extension" : "wrench.and.screwdriver",
                tint: name.hasPrefix("mcp__") ? Palette.success : Palette.secondaryInk,
                detail: hasDetails ? .json(input.prettyJSON + (result.map { "\n\n\($0)" } ?? "")) : .none
            )
        }
    }

    static func language(for path: String?) -> String? {
        guard let path else { return nil }
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        let map: [String: String] = [
            "swift": "swift", "m": "swift", "mm": "cpp",
            "js": "javascript", "jsx": "javascript", "mjs": "javascript",
            "ts": "typescript", "tsx": "typescript",
            "py": "python", "rb": "ruby",
            "sh": "shell", "zsh": "shell", "bash": "shell", "fish": "shell",
            "json": "json", "yaml": "yaml", "yml": "yaml", "toml": "yaml",
            "html": "html", "css": "css", "scss": "css",
            "c": "c", "h": "c", "cpp": "cpp", "hpp": "cpp", "cc": "cpp",
            "rs": "rust", "go": "go", "sql": "sql", "md": "markdown"
        ]
        return map[ext]
    }
}

struct PermissionPresentation {
    var icon: String
    var tint: Color
    var title: String
    var commandPreview: String?
    var pathPreview: String?
    var details: String

    static func make(from request: ClaudePermissionRequest, projectPath: String) -> PermissionPresentation {
        let tool = request.toolName
        let input = request.input

        switch tool {
        case "Bash":
            let command = input["command"]?.stringValue ?? ""
            return PermissionPresentation(
                icon: "terminal",
                tint: Palette.warning,
                title: "Run a command",
                commandPreview: command,
                pathPreview: nil,
                details: input.prettyJSON
            )
        case "Write":
            let path = input["file_path"]?.stringValue
            return PermissionPresentation(
                icon: "square.and.pencil",
                tint: Palette.accent,
                title: "Create or replace a file",
                commandPreview: input["content"]?.stringValue.map { Format.truncated($0, limit: 600) },
                pathPreview: path.map { Format.abbreviatedPath($0, root: projectPath) },
                details: input.prettyJSON
            )
        case "Edit", "MultiEdit", "NotebookEdit":
            let path = input["file_path"]?.stringValue
            return PermissionPresentation(
                icon: "pencil.line",
                tint: Palette.accent,
                title: "Edit a file",
                commandPreview: input["new_string"]?.stringValue.map { Format.truncated($0, limit: 500) },
                pathPreview: path.map { Format.abbreviatedPath($0, root: projectPath) },
                details: input.prettyJSON
            )
        case "Read":
            let path = input["file_path"]?.stringValue
            return PermissionPresentation(
                icon: "doc.text",
                tint: Palette.info,
                title: "Read a file",
                commandPreview: nil,
                pathPreview: path.map { Format.abbreviatedPath($0, root: projectPath) },
                details: input.prettyJSON
            )
        case "WebFetch", "WebSearch":
            let query = input["url"]?.stringValue ?? input["query"]?.stringValue ?? ""
            return PermissionPresentation(
                icon: "globe",
                tint: Palette.info,
                title: "Access the web",
                commandPreview: query,
                pathPreview: nil,
                details: input.prettyJSON
            )
        case "ExitPlanMode":
            return PermissionPresentation(
                icon: "map",
                tint: Palette.success,
                title: "Finish planning and start implementing",
                commandPreview: input["plan"]?.stringValue.map { Format.truncated($0, limit: 1_000) },
                pathPreview: nil,
                details: input.prettyJSON
            )
        default:
            return PermissionPresentation(
                icon: request.toolName.hasPrefix("mcp__") ? "puzzlepiece.extension" : "wrench.and.screwdriver",
                tint: Palette.warning,
                title: "Use \(request.displayName ?? Format.prettyToolName(request.toolName))",
                commandPreview: request.description,
                pathPreview: request.blockedPath.map { Format.abbreviatedPath($0, root: projectPath) },
                details: input.prettyJSON
            )
        }
    }
}
