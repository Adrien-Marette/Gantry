import Foundation

/// One matching conversation title or turn, with a display-ready snippet.
public struct SessionSearchHit: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable {
        case title
        case user
        case assistant
        case tool
    }

    public var projectID: UUID
    public var projectName: String
    public var sessionID: UUID
    public var sessionTitle: String
    public var turnID: UUID?
    public var kind: Kind
    public var snippet: String
    public var createdAt: Date
    public var score: Int

    public var id: String {
        "\(sessionID.uuidString)-\(turnID?.uuidString ?? "title")"
    }

    public init(
        projectID: UUID,
        projectName: String,
        sessionID: UUID,
        sessionTitle: String,
        turnID: UUID?,
        kind: Kind,
        snippet: String,
        createdAt: Date,
        score: Int
    ) {
        self.projectID = projectID
        self.projectName = projectName
        self.sessionID = sessionID
        self.sessionTitle = sessionTitle
        self.turnID = turnID
        self.kind = kind
        self.snippet = snippet
        self.createdAt = createdAt
        self.score = score
    }
}

/// Full-text search over titles, user and assistant text, and tool commands
/// or file paths. It deliberately skips thinking blocks and tool output, which
/// are noisy and often hidden in the transcript.
public enum SessionSearch {
    private static let options: String.CompareOptions = [
        .caseInsensitive,
        .diacriticInsensitive
    ]

    public static func search(
        query: String,
        projects: [Project],
        limit: Int = 80
    ) -> [SessionSearchHit] {
        let normalized = normalizedQuery(query)
        guard !normalized.isEmpty else { return [] }

        var hits: [SessionSearchHit] = []
        for project in projects {
            for session in project.sessions {
                if normalizedQuery(session.title).range(of: normalized, options: options) != nil {
                    hits.append(SessionSearchHit(
                        projectID: project.id,
                        projectName: project.name,
                        sessionID: session.id,
                        sessionTitle: session.title,
                        turnID: nil,
                        kind: .title,
                        snippet: preview(session.firstUserPrompt ?? ""),
                        createdAt: session.updatedAt,
                        score: 100
                    ))
                }

                for turn in session.turns {
                    guard let best = bestMatch(in: turn, query: normalized) else {
                        continue
                    }
                    hits.append(SessionSearchHit(
                        projectID: project.id,
                        projectName: project.name,
                        sessionID: session.id,
                        sessionTitle: session.title,
                        turnID: turn.id,
                        kind: best.kind,
                        snippet: best.snippet,
                        createdAt: turn.createdAt,
                        score: best.score
                    ))
                }
            }
        }

        return hits
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.createdAt > $1.createdAt
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func bestMatch(
        in turn: ConversationTurn,
        query: String
    ) -> (kind: SessionSearchHit.Kind, snippet: String, score: Int)? {
        var best: (kind: SessionSearchHit.Kind, snippet: String, score: Int)?

        for block in turn.blocks {
            switch block.kind {
            case .text:
                guard let snippet = matchingSnippet(in: block.text, query: query) else {
                    continue
                }
                let kind: SessionSearchHit.Kind = turn.role == .user ? .user : .assistant
                let score = turn.role == .user ? 80 : 60
                if best == nil || score > best!.score {
                    best = (kind, snippet, score)
                }

            case .tool:
                guard let tool = block.tool else { continue }
                let candidates = [tool.command, tool.filePath, tool.displayName, tool.name]
                    .compactMap { $0 }
                var matchedSnippet: String?
                for candidate in candidates {
                    if let snippet = matchingSnippet(in: candidate, query: query) {
                        matchedSnippet = snippet
                        break
                    }
                }
                guard let snippet = matchedSnippet else { continue }
                let score = 50
                if best == nil || score > best!.score {
                    best = (.tool, snippet, score)
                }

            case .thinking:
                continue
            }
        }

        return best
    }

    /// Collapses whitespace, then keeps a window around the first match.
    static func matchingSnippet(
        in text: String,
        query: String,
        maxLength: Int = 180
    ) -> String? {
        let collapsed = collapseWhitespace(text)
        guard !collapsed.isEmpty,
              let range = collapsed.range(of: query, options: options) else {
            return nil
        }

        let window = max(maxLength, query.count + 80)
        let prefixLimit = 60
        let start = collapsed.index(
            range.lowerBound,
            offsetBy: -prefixLimit,
            limitedBy: collapsed.startIndex
        ) ?? collapsed.startIndex
        let end = collapsed.index(
            start,
            offsetBy: window,
            limitedBy: collapsed.endIndex
        ) ?? collapsed.endIndex

        var snippet = String(collapsed[start..<end])
        if start > collapsed.startIndex { snippet = "…" + snippet }
        if end < collapsed.endIndex { snippet += "…" }
        return snippet
    }

    static func preview(_ text: String, maxLength: Int = 160) -> String {
        let collapsed = collapseWhitespace(text)
        guard collapsed.count > maxLength else { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        return String(collapsed[..<end]).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Search and snippets both collapse whitespace, so a query with runs of
    /// spaces matches the same path or prose as a single space.
    public static func normalizedQuery(_ query: String) -> String {
        collapseWhitespace(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
