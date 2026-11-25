import Foundation

/// Reads the JSONL transcripts Claude Code keeps under
/// `~/.claude/projects/<encoded-path>/` and turns them into Gantry sessions.
/// Imported sessions keep Claude Code's session ID so they continue with
/// `--resume` instead of starting over.
public enum ClaudeTranscriptImporter {
    /// Claude Code honours `CLAUDE_CONFIG_DIR`; otherwise it uses `~/.claude`.
    public static func projectsDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let config = environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 }
        let root = config.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent(".claude", isDirectory: true)
        return root.appendingPathComponent("projects", isDirectory: true)
    }

    /// Claude Code names a project's folder by replacing every
    /// non-alphanumeric character of its absolute path with `-`.
    public static func encodedName(forProjectPath path: String) -> String {
        String(path.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }

    /// Transcripts for `projectPath` whose session is not in `knownSessionIDs`.
    public static func transcriptURLs(
        forProjectPath projectPath: String,
        excluding knownSessionIDs: Set<UUID>,
        projectsDirectory: URL = projectsDirectory()
    ) -> [URL] {
        let directory = projectsDirectory.appendingPathComponent(
            encodedName(forProjectPath: projectPath),
            isDirectory: true
        )
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return files.filter { url in
            guard url.pathExtension == "jsonl",
                  let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return false }
            return !knownSessionIDs.contains(id)
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Returns nil when the file is unreadable or holds no visible conversation.
    public static func session(
        fromTranscript url: URL,
        model: ModelChoice = .automatic,
        permissionMode: PermissionMode = .ask,
        providerID: UUID? = nil
    ) -> ChatSession? {
        guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
              let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let turns = turns(fromTranscript: contents)
        guard turns.contains(where: { $0.role == .user }) else { return nil }

        var session = ChatSession(
            claudeSessionID: id,
            createdAt: turns.first?.createdAt ?? .now,
            updatedAt: turns.last?.createdAt ?? .now,
            turns: turns,
            model: model,
            permissionMode: permissionMode,
            claudeStarted: true,
            providerID: providerID
        )
        if let prompt = session.firstUserPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
            session.title = String(prompt.split(separator: "\n").first?.prefix(80) ?? "Imported session")
        } else {
            session.title = "Imported session"
        }
        session.actualModelName = turns.last(where: { $0.role == .assistant })?.usage?.modelName
        return session
    }

    static func turns(fromTranscript contents: String) -> [ConversationTurn] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var turns: [ConversationTurn] = []

        for line in contents.split(whereSeparator: \.isNewline) {
            guard let data = line.data(using: .utf8),
                  let object = (try? JSONDecoder().decode(JSONValue.self, from: data))?.objectValue,
                  // Meta lines are injected context; sidechains are subagent runs.
                  object["isMeta"]?.boolValue != true,
                  object["isSidechain"]?.boolValue != true else { continue }
            let createdAt = object["timestamp"]?.stringValue.flatMap(formatter.date(from:)) ?? .now

            switch object["type"]?.stringValue {
            case "user":
                if let prompt = userPrompt(object["message"]?["content"]) {
                    turns.append(ConversationTurn(role: .user, createdAt: createdAt, blocks: [.makeText(prompt)]))
                    continue
                }
                for case .toolResults(let results) in ClaudeStreamParser.parse(line: String(line)) {
                    apply(results, to: &turns)
                }
            case "assistant":
                for case .assistant(let message) in ClaudeStreamParser.parse(line: String(line)) {
                    // Claude Code writes one line per content block; merge them into one turn.
                    if turns.last?.role != .assistant {
                        turns.append(ConversationTurn(role: .assistant, createdAt: createdAt))
                    }
                    let index = turns.count - 1
                    for content in message.content {
                        switch content {
                        case .text(let text):
                            turns[index].blocks.append(.makeText(text))
                        case .thinking(let text):
                            turns[index].blocks.append(.makeThinking(text))
                        case .toolUse(let id, let name, let input, let displayName):
                            turns[index].blocks.append(.makeTool(ToolActivity(
                                id: id,
                                name: name,
                                displayName: displayName,
                                input: input,
                                status: .interrupted,
                                startedAt: createdAt
                            )))
                        }
                    }
                    if let model = message.model, model != "<synthetic>" {
                        var usage = turns[index].usage ?? TurnUsage()
                        usage.modelName = model
                        turns[index].usage = usage
                    }
                }
            default:
                continue
            }
        }
        return turns.filter(\.hasVisibleContent)
    }

    /// A typed prompt is either a plain string or text blocks; tool results are not prompts.
    private static func userPrompt(_ content: JSONValue?) -> String? {
        let text: String
        if let string = content?.stringValue {
            text = string
        } else {
            let blocks = content?.arrayValue ?? []
            guard !blocks.contains(where: { $0["type"]?.stringValue == "tool_result" }) else { return nil }
            text = blocks.compactMap { $0["type"]?.stringValue == "text" ? $0["text"]?.stringValue : nil }
                .joined(separator: "\n\n")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Slash-command and local-command echoes are wrapped in XML-like tags.
        guard !trimmed.isEmpty, !trimmed.hasPrefix("<") else { return nil }
        return trimmed
    }

    private static func apply(_ results: [ClaudeToolResult], to turns: inout [ConversationTurn]) {
        for result in results {
            for turnIndex in turns.indices.reversed() {
                guard let blockIndex = turns[turnIndex].blocks.firstIndex(where: {
                    $0.tool?.id == result.toolUseID
                }) else { continue }
                turns[turnIndex].blocks[blockIndex].tool?.resultText = result.text
                turns[turnIndex].blocks[blockIndex].tool?.isError = result.isError
                turns[turnIndex].blocks[blockIndex].tool?.status = result.isError ? .failed : .completed
                break
            }
        }
    }
}
